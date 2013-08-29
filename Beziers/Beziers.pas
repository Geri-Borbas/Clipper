unit Beziers;

(*******************************************************************************
*                                                                              *
* Author    :  Angus Johnson                                                   *
* Version   :  1.0                                                             *
* Date      :  27 August 2013                                                  *
* Website   :  http://www.angusj.com                                           *
* Copyright :  Angus Johnson 2010-2013                                         *
*                                                                              *
* License:                                                                     *
* Use, modification & distribution is subject to Boost Software License Ver 1. *
* http://www.boost.org/LICENSE_1_0.txt                                         *
*                                                                              *
*******************************************************************************)

interface

uses
  Windows, Messages, SysUtils, Classes, Math, clipper;

const
  DefaultPrecision = 0.5;

type
  //TBezierType: a parameter of TBezier's constructor
  TBezierType = (CubicBezier, QuadBezier);

  //The TPath structure is defined in Clipper.pas ...
  //TPath = Array of TIntPoint;
  //TIntPoint = record X,Y,Z: Int64; end;

  TBezierList = class
  private
    FList: TList;
    FPrecision: Double;
  public
    constructor Create(Precision: Double = DefaultPrecision);
    destructor Destroy; override;

    procedure AddPath(const CtrlPts: TPath; BezType: TBezierType);
    procedure AddPaths(const CtrlPts: TPaths; BezType: TBezierType);
    procedure Clear;

    function GetCtrlPts(index: Integer): TPath;
    function GetBezierType(index: Integer): TBezierType;
    function GetFlattenedPath(index: Integer): TPath;
    function GetFlattenedPaths(): TPaths;

    class function Flatten(path: TPath; BezType: TBezierType;
      Precision: Double = DefaultPrecision): TPath; overload;
    class function Flatten(paths: TPaths; BezType: TBezierType;
      Precision: Double = DefaultPrecision): TPaths; overload;

    class function CSplineToCBezier(CubicSpline: TPath): TPath;
    class function QSplineToQBezier(QuadSpline: TPath): TPath;

    function Reconstruct(Z1, Z2: Int64): TPath; //Control points again.
    property Precision: Double read FPrecision write FPrecision;
  end;

implementation

{$IF CompilerVersion >= 20}
  {$DEFINE INLINING}
{$IFEND}

resourcestring
  rsInvalidBezierPointCount = 'TBezier: invalid number of control points.';
  rsInvalidBezierType       = 'TBezier: invalid type.';
  rsIndexRange              = 'TBezierList: index out of range';
  rsZMemberDisabled         = 'TBezierList: Z member of TIntPoint is disabled.';

const
  half = 0.5;

type

  //IntNode: used internally only
  PIntNode = ^TIntNode;
  TIntNode = record
    Val: Integer;
    Next: PIntNode;
    Prev: PIntNode;
  end;

  //TBezier: Flattens poly-bezier curves, and later reconstructs them.
  //The FlattenedPath method stores data in the Z members of the returned
  //TPath structure and this is used for bezier reconstruction.
  //Any two Z values (of the IntPoints returned by the FlattenedPath method)
  //are sufficient to allow reconstruction of part or all of the original curve.

  TBezier = class
  private
    Reference : Integer;
    FBezierType: TBezierType;
    FCtrlPoints: TPath;
    //supports poly-beziers (ie before flattening) with up to 16,383 segments
    SegmentList: TList;
    procedure ReconstructInternal(SegIdx: Integer;
      StartIdx, EndIdx: Int64; IntCurrent: PIntNode);
  public
    constructor Create; overload;
    constructor Create(
      const CtrlPts: TPath;     //CtrlPts: Bezier control points
      BezType: TBezierType;     //CubicBezier or QuadBezier ...
      Ref: Word;                //Ref: user supplied identifier;
      Precision: Double         //Precision of flattened path
      ); overload;
    destructor Destroy; override;
    procedure Clear;
    procedure SetCtrlPoints(const CtrlPts: TPath;
      BezType: TBezierType; Ref: Word; Precision: Double = 0.25);
    function FlattenedPath: TPath;
    //Reconstruct: returns a list of Bezier control points using the
    //information provided in the startZ and endZ parameters (together with
    //the object's stored data) ...
    function Reconstruct(startZ, endZ: Int64): TPath; //Control points again.
    property BezierType: TBezierType read FBezierType write FBezierType;
    property CtrlPoints: TPath read FCtrlPoints;
  end;

  TSegment = class
  protected
    BezierType: TBezierType;
    RefID, SegID: Word;
    Index: Cardinal;
    Ctrls: array [0..3] of TDoublePoint;
    Childs: array [0..1] of TSegment;
    procedure GetFlattenedPath(var Path: TPath;
      var Cnt: Integer; Init: Boolean); overload;
    procedure AddCtrlPtsToPath(var path: TPath; var currCnt: Integer);
  public
    constructor Create(Ref, Seg, Idx: Cardinal); overload; virtual;
    destructor Destroy; override;
  end;

  TCubicBez = class(TSegment)
  public
    constructor Create(const Pt1, Pt2, Pt3, Pt4: TDoublePoint;
      Ref, Seg, Idx: Cardinal; Precision: Double); overload; virtual;
  end;

  TQuadBez = class(TSegment)
  public
    constructor Create(const Pt1, Pt2, Pt3: TDoublePoint;
      Ref, Seg, Idx: Cardinal; Precision: Double); overload;
  end;

//------------------------------------------------------------------------------
// Miscellaneous helper functions ...
//------------------------------------------------------------------------------

//nb. The format (high to low) of the 64bit Z value returned in the path ...
//Flg  (2): Flags StartOfPath and BezierType (CubicBezier, QuadBezier)
//Seg (14): segment index since a bezier may consist of multiple segments
//Ref (16): reference value passed to TBezier owner object
//Idx (32): binary index to sub-segment containing control points

function MakeZ(BezierType: TBezierType;
  Seg, Ref, Idx: Integer): Int64; //{$IFDEF INLINING} inline; {$ENDIF}
begin
  //nb: StartOfPath flag (bit63) is set separately
  Int64Rec(Result).Lo := Idx;
  Int64Rec(Result).Hi := Byte(BezierType) shl 30 or (Seg shl 16) or (Ref +1);
end;
//------------------------------------------------------------------------------

function UnMakeZ(ZVal: Int64;
  out BezierType: TBezierType; out Seg, Ref: Integer): Integer;
begin
  Result := Integer(Int64Rec(ZVal).Lo);
  BezierType := TBezierType((ZVal shr 62) and $1);
  Ref := (Int64Rec(ZVal).Hi and $FFFF) -1;
  Seg := Int64Rec(ZVal).Hi shr 16 and $3FFF;
end;
//------------------------------------------------------------------------------

function InsertInt(InsertAfter: PIntNode; Val: Integer): PIntNode;
begin
  new(Result);
  Result.Val := Val;
  Result.Next := InsertAfter.Next;
  Result.Prev := InsertAfter;
  if assigned(InsertAfter.Next) then
    InsertAfter.Next.Prev := Result;
  InsertAfter.Next := Result;
end;
//------------------------------------------------------------------------------

function GetFirstIntNode(Current: PIntNode): PIntNode;
begin
  Result := Current;
  if not assigned(Result) then Exit;
  while assigned(Result.Prev) do
    Result := Result.Prev;
  //now skip the very first (dummy) node ...
  Result := Result.Next;
end;
//------------------------------------------------------------------------------

procedure DisposeIntNodes(IntNodes: PIntNode);
var
  IntNode: PIntNode;
begin
  if not assigned(IntNodes) then Exit;
  while assigned(IntNodes.Prev) do
    IntNodes := IntNodes.Prev;

  repeat
    IntNode := IntNodes;
    IntNodes := IntNodes.Next;
    Dispose(IntNode);
  until not assigned(IntNodes);
end;
//------------------------------------------------------------------------------

procedure AppendToPath(var Path: TPath;
  var Cnt: Integer; const Pt: TIntPoint); overload;
const
  buffSize = 128;
begin
  if Cnt mod buffSize = 0 then
    SetLength(Path, Length(Path) +  buffSize);
  Path[Cnt] := Pt;
  Inc(Cnt);
end;
//------------------------------------------------------------------------------

function DoublePoint(const Ip: TIntPoint): TDoublePoint; {$IFDEF INLINING} inline; {$ENDIF}
begin
  Result.X := Ip.X;
  Result.Y := Ip.Y;
end;
//------------------------------------------------------------------------------

function GetMostSignificantBit(v: cardinal): cardinal; //index is zero based
var
  i: cardinal;
const
  b: array [0..4] of cardinal = ($2, $C, $F0, $FF00, $FFFF0000);
  s: array [0..4] of cardinal = (1, 2, 4, 8, 16);
begin
  result := 0;
  for i := 4 downto 0 do
    if (v and b[i] <> 0) then
    begin
      v := v shr s[i];
      result := result or s[i];
    end;
end;
//------------------------------------------------------------------------------

function IsBitSet(val, index: cardinal): boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  result := val and (1 shl index) <> 0;
end;

//------------------------------------------------------------------------------

function MidPoint(const Pt1, Pt2: TIntPoint): TIntPoint; {$IFDEF INLINING} inline; {$ENDIF}
begin
  Result.X := (Pt1.X + Pt2.X) div 2;
  Result.Y := (Pt1.Y + Pt2.Y) div 2;
  Result.Z := 0;
end;

//------------------------------------------------------------------------------
// TBezierList methods ...
//------------------------------------------------------------------------------

constructor TBezierList.Create(Precision: Double);
begin
  if (sizeof(TIntPoint) <> sizeof(cInt) * 3) then
    raise Exception.Create(rsZMemberDisabled);

  if Precision <= 0 then Precision := DefaultPrecision;
  FPrecision := Precision;
  FList := TList.Create;
end;
//------------------------------------------------------------------------------

destructor TBezierList.Destroy;
begin
  Clear;
  FList.Free;
end;
//------------------------------------------------------------------------------

procedure TBezierList.AddPath(const CtrlPts: TPath; BezType: TBezierType);
var
  NewBez: TBezier;
begin
  NewBez := TBezier.Create(CtrlPts, BezType, FList.Count, FPrecision);
  FList.Add(NewBez);
end;
//------------------------------------------------------------------------------

procedure TBezierList.AddPaths(const CtrlPts: TPaths; BezType: TBezierType);
var
  I, MinLen: Integer;
  NewBez: TBezier;
begin
  if (bezType = CubicBezier) then MinLen := 4  else MinLen := 3;
  for I := 0 to high(ctrlPts) do
  begin
    if length(CtrlPts[I]) < MinLen then continue;
    NewBez := TBezier.Create(CtrlPts[I], BezType, FList.Count, FPrecision);
    FList.Add(NewBez);
  end;
end;
//------------------------------------------------------------------------------

procedure TBezierList.Clear;
var
  i: Integer;
begin
  for i := 0 to FList.Count -1 do
    TBezier(FList[i]).Free;
  FList.Clear;
end;
//------------------------------------------------------------------------------

function TBezierList.GetCtrlPts(index: Integer): TPath;
begin
  if (index < 0) or (index >= FList.Count) then
    raise Exception.Create(rsIndexRange);
  result := TBezier(FList[index]).CtrlPoints;
end;
//------------------------------------------------------------------------------

function TBezierList.GetBezierType(index: Integer): TBezierType;
begin
  if (index < 0) or (index >= FList.Count) then
    raise Exception.Create(rsIndexRange);
  result := TBezier(FList[index]).BezierType;
end;
//------------------------------------------------------------------------------

function TBezierList.GetFlattenedPath(index: Integer): TPath;
begin
  if (index < 0) or (index >= FList.Count) then
    raise Exception.Create(rsIndexRange);
  result := TBezier(FList[index]).FlattenedPath;
end;
//------------------------------------------------------------------------------

function TBezierList.GetFlattenedPaths(): TPaths;
var
  I: Integer;
begin
  SetLength(result, FList.Count);
  for I := 0  to FList.Count -1 do
    result[I] := TBezier(FList[I]).FlattenedPath;
end;
//------------------------------------------------------------------------------

function TBezierList.Reconstruct(Z1, Z2: Int64): TPath;
var
  Seg, Ref: Integer;
  BezType: TBezierType;
begin
  UnMakeZ(Z1, BezType, Seg, Ref); //UnMakeZ() here just for Ref
  if (Ref >= 0) and (Ref < FList.Count) then
    result := TBezier(FList[Ref]).Reconstruct(Z1, Z2) else
    result := nil;
end;
//------------------------------------------------------------------------------

class function TBezierList.Flatten(path: TPath;
  BezType: TBezierType; Precision: Double): TPath;
begin
    with TBezier.Create(path, BezType, 0, Precision) do
    try
      Result := FlattenedPath;
    finally
      Free;
    end;
end;
//------------------------------------------------------------------------------

class function TBezierList.Flatten(paths: TPaths;
  BezType: TBezierType; Precision: Double = DefaultPrecision): TPaths;
var
  I, MinLen: Integer;
begin
  if (bezType = CubicBezier) then MinLen := 4  else MinLen := 3;
  SetLength(Result, length(paths));
  for I := 0 to high(paths) do
  begin
    if Length(paths[I]) < MinLen then
      result[I] := nil
    else
      with TBezier.Create(paths[I], BezType, I, Precision) do
      try
        Result[I] := FlattenedPath;
      finally
        Free;
      end;
  end;
end;
//------------------------------------------------------------------------------

class function TBezierList.CSplineToCBezier(CubicSpline: TPath): TPath;
var
  I, J, Len, LenMin1: Integer;
begin
  Result := nil;
  Len := Length(CubicSpline);
  if Len < 4 then Exit;
  if Odd(Len) then Dec(Len);
  I := (Len div 2) - 1;
  SetLength(Result, I * 3 + 1);
  Result[0] := CubicSpline[0];
  Result[1] := CubicSpline[1];
  Result[2] := CubicSpline[2];
  I := 3; J := 3;
  LenMin1 := Len - 1;
  while I < LenMin1 do
  begin
    Result[J] := MidPoint(CubicSpline[I-1], CubicSpline[I]);
    Result[J+1] := CubicSpline[I];
    Result[J+2] := CubicSpline[I+1];
    Inc(I, 2); Inc(J, 3);
  end;
  Result[J] := CubicSpline[LenMin1];
end;
//------------------------------------------------------------------------------

class function TBezierList.QSplineToQBezier(QuadSpline: TPath): TPath;
var
  I, J, Len, LenMin1: Integer;
begin
  Result := nil;
  Len := Length(QuadSpline);
  if Len < 3 then Exit;
  if not Odd(Len) then Dec(Len);
  I := Len - 2;
  SetLength(Result, I * 2 + 1);
  Result[0] := QuadSpline[0];
  Result[1] := QuadSpline[1];
  I := 2; J := 2;
  LenMin1 := Len - 1;
  while I < LenMin1 do
  begin
    Result[J] := MidPoint(QuadSpline[I-1], QuadSpline[I]);
    Result[J+1] := QuadSpline[I];
    Inc(I); Inc(J, 2);
  end;
  Result[J] := QuadSpline[LenMin1];
end;

//------------------------------------------------------------------------------
// TSegment methods ...
//------------------------------------------------------------------------------

constructor TSegment.Create(Ref, Seg, Idx: Cardinal);
begin
  RefID := Ref; SegID := Seg; Index := Idx;
  childs[0] := nil;
  childs[1] := nil;
end;
//------------------------------------------------------------------------------

destructor TSegment.Destroy;
begin
  FreeAndNil(childs[0]);
  FreeAndNil(childs[1]);
  inherited;
end;
//------------------------------------------------------------------------------

procedure TSegment.GetFlattenedPath(var Path: TPath;
  var Cnt: Integer; Init: Boolean);
var
  Z: Int64;
  CtrlIdx: Integer;
begin
  if Init then
  begin
    Z := MakeZ(BezierType, SegID, RefID, Index);
    AppendToPath(Path, Cnt, IntPoint(Round(ctrls[0].X), Round(ctrls[0].Y), Z));
  end;

  if not assigned(childs[0]) then
  begin
    case BezierType of
      CubicBezier: CtrlIdx := 3;
      else CtrlIdx := 2;
    end;
    Z := MakeZ(BezierType, SegID, RefID, Index);
    AppendToPath(Path, Cnt,
      IntPoint(Round(ctrls[CtrlIdx].X), Round(ctrls[CtrlIdx].Y), Z));
  end else
  begin
    childs[0].GetFlattenedPath(Path, Cnt, False);
    childs[1].GetFlattenedPath(Path, Cnt, False);
  end;
end;
//------------------------------------------------------------------------------

procedure TSegment.AddCtrlPtsToPath(var path: TPath; var currCnt: Integer);
var
  I, Len, FirstDelta: Integer;
const
  buffSize = 128;
begin
  Len := Length(path);
  if currCnt + 4 >= Len then
    SetLength(path, Len + buffSize);

  if currCnt = 0 then
    FirstDelta := 0 else
    FirstDelta := 1;

  case BezierType of
    CubicBezier:
      for I := FirstDelta to 3 do
      begin
        path[currCnt].X := Round(ctrls[I].X);
        path[currCnt].Y := Round(ctrls[I].Y);
        Inc(currCnt);
      end;
    QuadBezier:
      for I := FirstDelta to 2 do
      begin
        path[currCnt].X := Round(ctrls[I].X);
        path[currCnt].Y := Round(ctrls[I].Y);
        Inc(currCnt);
      end;
  end;
end;

//------------------------------------------------------------------------------
// TQuadBez methods ...
//------------------------------------------------------------------------------

constructor TQuadBez.Create(const Pt1, Pt2, Pt3: TDoublePoint;
  Ref, Seg, Idx: Cardinal; Precision: Double);
var
  p12, p23, p123: TDoublePoint;
begin
  inherited Create(Ref, Seg, Idx);
  BezierType := QuadBezier;
  ctrls[0] := Pt1; ctrls[1] := Pt2; ctrls[2] := Pt3;
  //assess curve flatness:
  if abs(pt1.x + pt3.x - 2*pt2.x) + abs(pt1.y + pt3.y - 2*pt2.y) < Precision then
    Exit;

  //if not at maximum precision then (recursively) create sub-segments ...
  p12.X := (Pt1.X + Pt2.X) * half;
  p12.Y := (Pt1.Y + Pt2.Y) * half;
  p23.X := (Pt2.X + Pt3.X) * half;
  p23.Y := (Pt2.Y + Pt3.Y) * half;
  p123.X := (p12.X + p23.X) * half;
  p123.Y := (p12.Y + p23.Y) * half;
  Idx := Idx shl 1;
  Childs[0] := TQuadBez.Create(Pt1, p12, p123, Ref, Seg, Idx, Precision);
  Childs[1] := TQuadBez.Create(p123, p23, pt3, Ref, Seg, Idx +1, Precision);
end;

//------------------------------------------------------------------------------
// TCubicBez methods ...
//------------------------------------------------------------------------------

constructor TCubicBez.Create(const Pt1, Pt2, Pt3, Pt4: TDoublePoint;
  Ref, Seg, Idx: Cardinal; Precision: Double);
var
  p12, p23, p34, p123, p234, p1234: TDoublePoint;
begin
  inherited Create(Ref, Seg, Idx);
  BezierType := CubicBezier;
  ctrls[0] := Pt1; ctrls[1] := Pt2; ctrls[2] := Pt3; ctrls[3] := Pt4;
  //assess curve flatness:
  //http://groups.google.com/group/comp.graphics.algorithms/tree/browse_frm/thread/d85ca902fdbd746e
  if abs(Pt1.x + Pt3.x - 2*Pt2.x) + abs(Pt2.x + Pt4.x - 2*Pt3.x) +
    abs(Pt1.y + Pt3.y - 2*Pt2.y) + abs(Pt2.y + Pt4.y - 2*Pt3.y) < Precision then
      Exit;

  //if not at maximum precision then (recursively) create sub-segments ...
  p12.X := (Pt1.X + Pt2.X) * half;
  p12.Y := (Pt1.Y + Pt2.Y) * half;
  p23.X := (Pt2.X + Pt3.X) * half;
  p23.Y := (Pt2.Y + Pt3.Y) * half;
  p34.X := (Pt3.X + Pt4.X) * half;
  p34.Y := (Pt3.Y + Pt4.Y) * half;
  p123.X := (p12.X + p23.X) * half;
  p123.Y := (p12.Y + p23.Y) * half;
  p234.X := (p23.X + p34.X) * half;
  p234.Y := (p23.Y + p34.Y) * half;
  p1234.X := (p123.X + p234.X) * half;
  p1234.Y := (p123.Y + p234.Y) * half;
  Idx := Idx shl 1;
  Childs[0] := TCubicBez.Create(Pt1, p12, p123, p1234, Ref, Seg, Idx, Precision);
  Childs[1] := TCubicBez.Create(p1234, p234, p34, Pt4, Ref, Seg, Idx +1, Precision);
end;

//------------------------------------------------------------------------------
// TBezier methods ...
//------------------------------------------------------------------------------

constructor TBezier.Create;
begin
  SegmentList := TList.Create;
end;
//------------------------------------------------------------------------------

constructor TBezier.Create(const CtrlPts: TPath;
  BezType: TBezierType; Ref: Word; Precision: Double);
begin
  Create;
  SetCtrlPoints(CtrlPts, BezType, Ref, Precision);
end;
//------------------------------------------------------------------------------

procedure TBezier.SetCtrlPoints(const CtrlPts: TPath;
  BezType: TBezierType; Ref: Word; Precision: Double);
var
  I, HighPts: Integer;
  Segment: TSegment;
begin
  //clean up any existing data ...
  Clear;
  HighPts := High(CtrlPts);

  BezierType := BezType;
  case BezType of
    CubicBezier:
      if (HighPts < 3) then raise Exception.Create(rsInvalidBezierPointCount)
      else Dec(HighPts, HighPts mod 3);
    QuadBezier:
      if (HighPts < 2) then raise Exception.Create(rsInvalidBezierPointCount)
      else Dec(HighPts, HighPts mod 2);

    else raise Exception.Create(rsInvalidBezierType);
  end;

  FCtrlPoints := CtrlPts;
  Reference  := Ref;
  if Precision <= 0 then Precision := DefaultPrecision;

  //now for each segment in the poly-bezier create a binary tree structure
  //and add it to SegmentList ...
  case BezType of
    CubicBezier:
      for I := 0 to (HighPts div 3) -1 do
      begin
        Segment := TCubicBez.Create(
                    DoublePoint(CtrlPts[I*3]),
                    DoublePoint(CtrlPts[I*3+1]),
                    DoublePoint(CtrlPts[I*3+2]),
                    DoublePoint(CtrlPts[I*3+3]),
                    Ref, I, 1, Precision);
        SegmentList.Add(Segment);
      end;
    QuadBezier:
      for I := 0 to (HighPts div 2) -1 do
      begin
        Segment := TQuadBez.Create(
                    DoublePoint(CtrlPts[I*2]),
                    DoublePoint(CtrlPts[I*2+1]),
                    DoublePoint(CtrlPts[I*2+2]),
                    Ref, I, 1, Precision);
        SegmentList.Add(Segment);
      end;
  end;
end;
//------------------------------------------------------------------------------

procedure TBezier.Clear;
var
  I: Integer;
begin
  FCtrlPoints := nil;
  for I := 0 to SegmentList.Count -1 do
    TObject(SegmentList[I]).Free;
  SegmentList.Clear;
end;
//------------------------------------------------------------------------------

destructor TBezier.Destroy;
begin
  Clear;
  SegmentList.Free;
  inherited;
end;
//------------------------------------------------------------------------------

function TBezier.FlattenedPath: TPath;
var
  I, Cnt: Integer;
begin
  Result := Nil;
  if SegmentList.Count = 0 then Exit;
  Cnt := 0;
  for I := 0 to SegmentList.Count -1 do
    TSegment(SegmentList[I]).GetFlattenedPath(Result, Cnt, Cnt = 0);
  Result[0].Z := Result[0].Z or $8000000000000000; //StartOfPath flag
  SetLength(Result, Cnt);
end;
//------------------------------------------------------------------------------

function TBezier.Reconstruct(startZ, endZ: Int64): TPath;
var
  I, J, K, Seg1, Seg2, Cnt: Integer;
  I64: Int64;
  BezType1, BezType2: TBezierType;
  IntList, IntCurrent: PIntNode;
  Segment: TSegment;
  Reversed: Boolean;
begin
  //precondition: startZ <> endZ
  result := nil;
  if startZ = endZ then Exit;

  //StartOfPath subSegID is converted to +1 once any reversal has been sorted.
  //if endZ has the StartOfPath flag then reverse path ...
  if endZ < 0 then
  begin
    I64 := startZ;
    startZ := endZ;
    endZ := I64;
    Reversed := true;
  end
  else
    Reversed := false;

  //'startZ' and 'endZ' are now converted into subSegIDs ...
  startZ := UnMakeZ(startZ, BezType1, Seg1, I);
  endZ   := UnMakeZ(endZ,   BezType2, Seg2, J);

  if (BezType1 <> BezierType) or (BezType1 <> BezType2) or
    (Reference <> I) or (I <> J) or
    (Seg1 < 0) or (Seg1 >= SegmentList.Count) or
    (Seg2 < 0) or (Seg2 >= SegmentList.Count) then
  begin
    Exit;
  end;

  //check orientation because it's much simpler to temporarily unreverse when
  //the startIdx and endIdx are reversed ...
  if (Seg1 > Seg2) then
  begin
    I := Seg1;
    Seg1 := Seg2;
    Seg2 := I;
    I := startZ;
    startZ := endZ;
    endZ := I;
    Reversed := true;
  end;

  //do further checks for reversal, in case reversal within a single segment.
  //nb: when endZ == 1 or startZ == 1 then reversal managed above.
  if not Reversed and (Seg1 = Seg2) and
    (startZ <> 1) and (endZ <> 1) then
  begin
    I := GetMostSignificantBit(startZ);
    J := GetMostSignificantBit(endZ);
    K := Max(I, J);
    //nb: we must compare Node indexes at the same level ...
    I := startZ shl (K - I);
    J := endZ shl (K - J);
    if I > J then
    begin
      K := startZ;
      startZ := endZ;
      endZ := K;
      Reversed := True;
    end;
  end;

  Cnt := 0;
  while Seg1 <= Seg2 do
  begin
    IntList := nil;
    try
      //create a dummy first IntNode for the Int List ...
      New(IntList);
      IntList.Val := 0;
      IntList.Next := nil;
      IntList.Prev := nil;
      IntCurrent := IntList;

      if Seg1 <> Seg2 then
        ReconstructInternal(Seg1, startZ, 1, IntCurrent) else
        ReconstructInternal(Seg1, startZ, endZ, IntCurrent);

      //IntList now contains the indexes of one or a series of sub-segments
      //that together define part of or the whole of the original segment.
      //We now append these sub-segments to the new list of control points ...

      IntCurrent := IntList.Next; //nb: skips the dummy IntNode
      while assigned(IntCurrent) do
      begin
        Segment := TSegment(SegmentList[Seg1]);
        J := IntCurrent.Val;
        K := GetMostSignificantBit(J);
        Dec(K);
        while K >= 0 do
        begin
          if not assigned(Segment.childs[0]) then break;
          if IsBitSet(J, K) then
            Segment := Segment.childs[1] else
            Segment := Segment.childs[0];
          Dec(K);
        end;
        Segment.AddCtrlPtsToPath(Result, Cnt);
        IntCurrent := IntCurrent.Next;
      end; //while assigned(IntCurrent);

    finally
      DisposeIntNodes(IntList);
    end;
    inc(Seg1);
    startZ := 1;
  end;
  SetLength(Result, Cnt);
  if Reversed then
    Result := Clipper.ReversePolygon(Result);
end;
//------------------------------------------------------------------------------

procedure TBezier.ReconstructInternal(SegIdx: Integer;
  StartIdx, EndIdx: Int64; IntCurrent: PIntNode);
var
  Level, L1, L2, L, R, J: Cardinal;
begin
  //get the maximum level ...
  L1 := GetMostSignificantBit(StartIdx);
  L2 := GetMostSignificantBit(EndIdx);
  Level := Max(L1, L2);

  if Level = 0 then
  begin
    InsertInt(IntCurrent, 1);
    Exit;
  end;

  //Right marker (R): EndIdx projected onto the bottom level ...
  if (EndIdx = 1) then
  begin
    R := 1 shl (Level +1) - 1;
  end else
  begin
    J := (Level - L2);
    R := (EndIdx shl J) + (1 shl J) -1;
  end;

  if (StartIdx = 1) then //special case
  begin
    //Left marker (L) is bottom left of the binary tree ...
    L := 1 shl Level;
    L1 := Level;
  end else
  begin
    //For any given Z value, its corresponding X & Y coords (created by
    //FlattenPath using De Casteljau's algorithm) refered to the ctrl[3] coords
    //of many tiny polybezier segments. Since ctrl[3] coords are identical to
    //ctrl[0] coords in the following node, we can safely increment StartIdx ...
    L := StartIdx +1;
    if L = 1 shl (Level +1) then Exit; //loops around tree so already at the end
  end;

  //L ====> R; at Level = Max(L1, L2)

  //now get blocks of nodes from the LEFT ...
  J := Level - L1;
  repeat
    //while next level up then down-right doesn't exceed L2 do ...
    while not Odd(L) and ((L shl J) + (1 shl (J + 1)) - 1 <= R) do
    begin
      L := L shr 1; //go up a level
      Inc(J);
    end;
    IntCurrent := InsertInt(IntCurrent, L); //nb: updates IntCurrent
    Inc(L);
  until (L = 3 shl (Level - J - 1)) or //ie crosses the ditch in the middle
    ((L shl J) + (1 shl J) >= R);      //or L is now over or to the right of R

  L := (L shl J);

  //now get blocks of nodes from the RIGHT ...
  J := 0;
  if R >= L then
    repeat
      while Odd(R) and ((R - 1) shl J >= L) do
      begin
        R := R shr 1; //go up a level
        Inc(J);
      end;
      InsertInt(IntCurrent, R); //nb: doesn't update IntCurrent
      Dec(R);
    until (Integer(R) = (3 shl (Level - J)) -1) or //ie crosses the ditch
      (R shl J <= L);
end;
//------------------------------------------------------------------------------

end.
