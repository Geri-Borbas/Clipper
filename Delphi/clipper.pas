unit clipper;

(*******************************************************************************
*                                                                              *
* Author    :  Angus Johnson                                                   *
* Version   :  5.1.6                                                           *
* Date      :  23 May 2013                                                     *
* Website   :  http://www.angusj.com                                           *
* Copyright :  Angus Johnson 2010-2013                                         *
*                                                                              *
* License:                                                                     *
* Use, modification & distribution is subject to Boost Software License Ver 1. *
* http://www.boost.org/LICENSE_1_0.txt                                         *
*                                                                              *
* Attributions:                                                                *
* The code in this library is an extension of Bala Vatti's clipping algorithm: *
* "A generic solution to polygon clipping"                                     *
* Communications of the ACM, Vol 35, Issue 7 (July 1992) PP 56-63.             *
* http://portal.acm.org/citation.cfm?id=129906                                 *
*                                                                              *
* Computer graphics and geometric modeling: implementation and algorithms      *
* By Max K. Agoston                                                            *
* Springer; 1 edition (January 4, 2005)                                        *
* http://books.google.com/books?q=vatti+clipping+agoston                       *
*                                                                              *
* See also:                                                                    *
* "Polygon Offsetting by Computing Winding Numbers"                            *
* Paper no. DETC2005-85513 PP. 565-575                                         *
* ASME 2005 International Design Engineering Technical Conferences             *
* and Computers and Information in Engineering Conference (IDETC/CIE2005)      *
* September 24-28, 2005 , Long Beach, California, USA                          *
* http://www.me.berkeley.edu/~mcmains/pubs/DAC05OffsetPolygon.pdf              *
*                                                                              *
*******************************************************************************)

interface

uses
  SysUtils, Types, Classes, Math;

type
  PIntPoint = ^TIntPoint;
  TIntPoint = record X, Y: Int64; end;
  TIntRect = record Left, Top, Right, Bottom: Int64; end;

  TClipType = (ctIntersection, ctUnion, ctDifference, ctXor);
  TPolyType = (ptSubject, ptClip);
  //By far the most widely used winding rules for polygon filling are
  //EvenOdd & NonZero (GDI, GDI+, XLib, OpenGL, Cairo, AGG, Quartz, SVG, Gr32)
  //Others rules include Positive, Negative and ABS_GTR_EQ_TWO (only in OpenGL)
  //see http://glprogramming.com/red/chapter11.html
  TPolyFillType = (pftEvenOdd, pftNonZero, pftPositive, pftNegative);

  //TJoinType & TEndType are used by OffsetPolygons()
  TJoinType = (jtSquare, jtRound, jtMiter);
  TEndType = (etClosed, etButt, etSquare, etRound);

  TPolygon = array of TIntPoint;
  TPolygons = array of TPolygon;

  TPolyNode = class;
  TArrayOfPolyNode = array of TPolyNode;

  TPolyNode = class
  private
    FPolygon: TPolygon;
    FParent  : TPolyNode;
    FIndex: Integer;
    FCount   : Integer;
    FBuffLen : Integer;
    FChilds: TArrayOfPolyNode;
    function GetChild(Index: Integer): TPolyNode;
    function IsHoleNode: boolean;
    procedure AddChild(PolyNode: TPolyNode);
    function GetNextSiblingUp: TPolyNode;
  public
    function GetNext: TPolyNode;
    property ChildCount: Integer read FCount;
    property Childs[index: Integer]: TPolyNode read GetChild;
    property Parent: TPolyNode read FParent;
    property IsHole: Boolean read IsHoleNode;
    property Contour: TPolygon read FPolygon;
  end;

  TPolyTree = class(TPolyNode)
  private
    FAllNodes: TArrayOfPolyNode; //container for ALL PolyNodes
    function GetTotal: Integer;
  public
    procedure Clear;
    function GetFirst: TPolyNode;
    destructor Destroy; override;
    property Total: Integer read GetTotal;
  end;


  //the definitions below are used internally ...
  TEdgeSide = (esLeft, esRight);
  TIntersectProtect = (ipLeft, ipRight);
  TIntersectProtects = set of TIntersectProtect;
  TDirection = (dRightToLeft, dLeftToRight);

  PEdge = ^TEdge;
  TEdge = record
    XBot : Int64;         //bottom
    YBot : Int64;
    XCurr: Int64;         //current (ie relative to bottom of current scanbeam)
    YCurr: Int64;
    XTop : Int64;         //top
    YTop : Int64;
    Dx   : Double;        //the inverse of slope
    DeltaX: Int64;
    DeltaY: Int64;
    PolyType : TPolyType;
    Side     : TEdgeSide;
    WindDelta: Integer;   //1 or -1 depending on winding direction
    WindCnt  : Integer;
    WindCnt2 : Integer;   //winding count of the opposite PolyType
    OutIdx   : Integer;
    Next     : PEdge;
    Prev     : PEdge;
    NextInLML: PEdge;
    PrevInAEL: PEdge;
    NextInAEL: PEdge;
    PrevInSEL: PEdge;
    NextInSEL: PEdge;
  end;

  PEdgeArray = ^TEdgeArray;
  TEdgeArray = array[0.. MaxInt div sizeof(TEdge) -1] of TEdge;

  PScanbeam = ^TScanbeam;
  TScanbeam = record
    Y   : Int64;
    Next: PScanbeam;
  end;

  PIntersectNode = ^TIntersectNode;
  TIntersectNode = record
    Edge1: PEdge;
    Edge2: PEdge;
    Pt   : TIntPoint;
    Next : PIntersectNode;
  end;

  PLocalMinima = ^TLocalMinima;
  TLocalMinima = record
    Y         : Int64;
    LeftBound : PEdge;
    RightBound: PEdge;
    Next      : PLocalMinima;
  end;

  POutPt = ^TOutPt;

  POutRec = ^TOutRec;
  TOutRec = record
    Idx         : Integer;
    BottomPt    : POutPt;
    IsHole      : Boolean;
    //The 'FirstLeft' field points to the OutRec representing the polygon
    //immediately to the left of the current OutRec's polygon. When a polygon is
    //contained within another polygon, the polygon immediately to its left will
    //either be its owner polygon or a sibling also contained by the same outer
    //polygon. By storing  this field, it's easy to sort polygons into a tree
    //structure which reflects the parent/child relationships of all polygons.
    FirstLeft   : POutRec;
    Pts         : POutPt;
    PolyNode    : TPolyNode;
  end;

  TOutPt = record
    Idx      : Integer;
    Pt       : TIntPoint;
    Next     : POutPt;
    Prev     : POutPt;
  end;

  PJoinRec = ^TJoinRec;
  TJoinRec = record
    Pt1a     : TIntPoint;
    Pt1b     : TIntPoint;
    Poly1Idx : Integer;
    Pt2a     : TIntPoint;
    Pt2b     : TIntPoint;
    Poly2Idx : Integer;
  end;

  PHorzRec = ^THorzRec;
  THorzRec = record
    Edge     : PEdge;
    SavedIdx : Integer;
    Next     : PHorzRec;
    Prev     : PHorzRec;
  end;

  TClipperBase = class
  private
    FEdgeList      : TList;
    FLmList        : PLocalMinima; //localMinima list
    FCurrLm        : PLocalMinima; //current localMinima node
    FUse64BitRange : Boolean;      //see LoRange and HiRange consts notes below
    procedure DisposeLocalMinimaList;
  protected
    procedure Reset; virtual;
    procedure PopLocalMinima;
    property CurrentLm: PLocalMinima read FCurrLm;
  public
    constructor Create; virtual;
    destructor Destroy; override;
    function AddPolygon(const Polygon: TPolygon; PolyType: TPolyType): Boolean;
    function AddPolygons(const Polygons: TPolygons; PolyType: TPolyType): Boolean;
    procedure Clear; virtual;
  end;

  TClipper = class(TClipperBase)
  private
    FPolyOutList    : TList;
    FJoinList       : TList;
    FClipType       : TClipType;
    FScanbeam       : PScanbeam; //scanbeam list
    FActiveEdges    : PEdge;     //active Edge list
    FSortedEdges    : PEdge;     //used for temporary sorting
    FIntersectNodes : PIntersectNode;
    FClipFillType   : TPolyFillType;
    FSubjFillType   : TPolyFillType;
    FExecuteLocked  : Boolean;
    FHorizJoins     : PHorzRec;
    FReverseOutput  : Boolean;
    FForceSimple    : Boolean;
    FUsingPolyTree: Boolean;
    procedure DisposeScanbeamList;
    procedure InsertScanbeam(const Y: Int64);
    function PopScanbeam: Int64;
    procedure SetWindingCount(Edge: PEdge);
    function IsEvenOddFillType(Edge: PEdge): Boolean;
    function IsEvenOddAltFillType(Edge: PEdge): Boolean;
    procedure AddEdgeToSEL(Edge: PEdge);
    procedure CopyAELToSEL;
    procedure InsertLocalMinimaIntoAEL(const BotY: Int64);
    procedure SwapPositionsInAEL(E1, E2: PEdge);
    procedure SwapPositionsInSEL(E1, E2: PEdge);
    function IsTopHorz(const XPos: Int64): Boolean;
    procedure ProcessHorizontal(HorzEdge: PEdge);
    procedure ProcessHorizontals;
    procedure InsertIntersectNode(E1, E2: PEdge; const Pt: TIntPoint);
    function ProcessIntersections(const BotY, TopY: Int64): Boolean;
    procedure BuildIntersectList(const BotY, TopY: Int64);
    procedure ProcessIntersectList;
    procedure DeleteFromAEL(E: PEdge);
    procedure DeleteFromSEL(E: PEdge);
    procedure IntersectEdges(E1,E2: PEdge;
      const Pt: TIntPoint; protects: TIntersectProtects = []);
    procedure DoMaxima(E: PEdge; const TopY: Int64);
    procedure UpdateEdgeIntoAEL(var E: PEdge);
    function FixupIntersectionOrder: Boolean;
    procedure ProcessEdgesAtTopOfScanbeam(const TopY: Int64);
    function IsContributing(Edge: PEdge): Boolean;
    function CreateOutRec: POutRec;
    procedure AddOutPt(E: PEdge; const Pt: TIntPoint);
    procedure AddLocalMaxPoly(E1, E2: PEdge; const Pt: TIntPoint);
    procedure AddLocalMinPoly(E1, E2: PEdge; const Pt: TIntPoint);
    function GetOutRec(Idx: integer): POutRec;
    procedure AppendPolygon(E1, E2: PEdge);
    procedure DisposePolyPts(PP: POutPt);
    procedure DisposeAllPolyPts;
    procedure DisposeOutRec(Index: Integer);
    procedure DisposeIntersectNodes;
    function GetResult: TPolygons;
    function GetResult2(PolyTree: TPolyTree): Boolean;
    procedure FixupOutPolygon(OutRec: POutRec);
    procedure SetHoleState(E: PEdge; OutRec: POutRec);
    procedure AddJoin(E1, E2: PEdge;
      E1OutIdx: Integer = -1; E2OutIdx: Integer = -1);
    procedure ClearJoins;
    procedure AddHorzJoin(E: PEdge; Idx: Integer);
    procedure ClearHorzJoins;
    function JoinPoints(JR: PJoinRec; out P1, P2: POutPt): Boolean;
    procedure FixupJoinRecs(JR: PJoinRec; Pt: POutPt; StartIdx: Integer);
    procedure FixupFirstLefts1(OldOutRec, NewOutRec: POutRec);
    procedure FixupFirstLefts2(OldOutRec, NewOutRec: POutRec);
    procedure DoSimplePolygons;
    procedure JoinCommonEdges;
    procedure FixHoleLinkage(OutRec: POutRec);
  protected
    procedure Reset; override;
    function ExecuteInternal: Boolean; virtual;
  public
    function Execute(clipType: TClipType;
      out solution: TPolygons;
      subjFillType: TPolyFillType = pftEvenOdd;
      clipFillType: TPolyFillType = pftEvenOdd): Boolean; overload;
    function Execute(clipType: TClipType;
      var PolyTree: TPolyTree;
      subjFillType: TPolyFillType = pftEvenOdd;
      clipFillType: TPolyFillType = pftEvenOdd): Boolean; overload;
    constructor Create; override;
    destructor Destroy; override;
    procedure Clear; override;
    //ReverseSolution: reverses the default orientation
    property ReverseSolution: Boolean read FReverseOutput write FReverseOutput;
    property ForceSimple: Boolean
      read FForceSimple write FForceSimple;
  end;

function Orientation(const Pts: TPolygon): Boolean; overload;
function Area(const Pts: TPolygon): Double; overload;
function IntPoint(const X, Y: Int64): TIntPoint;
function ReversePolygon(const Pts: TPolygon): TPolygon;
function ReversePolygons(const Pts: TPolygons): TPolygons;

//OffsetPolygons precondition: outer polygons MUST be oriented clockwise,
//and inner 'hole' polygons must be oriented counter-clockwise ...
function OffsetPolygons(const Polys: TPolygons; const Delta: Double;
  JoinType: TJoinType = jtSquare; Limit: Double = 0;
  AutoFix: Boolean = True): TPolygons;

function OffsetPolyLines(const Lines: TPolygons; Delta: Double;
  JoinType: TJoinType = jtSquare; EndType: TEndType = etSquare;
  Limit: Double = 0): TPolygons;

//SimplifyPolygon converts a self-intersecting polygon into a simple polygon.
function SimplifyPolygon(const Poly: TPolygon; FillType: TPolyFillType = pftEvenOdd): TPolygons;
function SimplifyPolygons(const Polys: TPolygons; FillType: TPolyFillType = pftEvenOdd): TPolygons;

//CleanPolygon removes adjacent vertices closer than the specified distance.
function CleanPolygon(const Poly: TPolygon; Distance: double = 1.415): TPolygon;
function CleanPolygons(const Polys: TPolygons; Distance: double = 1.415): TPolygons;

function PolyTreeToPolygons(PolyTree: TPolyTree): TPolygons;

implementation

type
  TDoublePoint = record X, Y: Double; end;
  TArrayOfDoublePoint = array of TDoublePoint;

const
  Horizontal: Double = -3.4e+38;
  //The Area function places the most limits on coordinate values
  //So, to avoid overflow errors, they must not exceed the following values...
  LoRange: Int64 = $3FFFFFFF;          //1.0e+9
  HiRange: Int64 = $3FFFFFFFFFFFFFFF;  //4.6e+18
  //Also, if all coordinates are within +/-LoRange, then calculations will be
  //faster. Otherwise using Int128 math will render the library ~10-15% slower.

resourcestring
  rsMissingRightbound = 'InsertLocalMinimaIntoAEL: missing RightBound';
  rsDoMaxima = 'DoMaxima error';
  rsUpdateEdgeIntoAEL = 'UpdateEdgeIntoAEL error';
  rsHorizontal = 'ProcessHorizontal error';
  rsInvalidInt = 'Coordinate exceeds range bounds';
  rsJoinError = 'Join Output polygons error';
  rsIntersect = 'Intersection error';

{$IF CompilerVersion >= 20}
  {$DEFINE INLINING}
{$IFEND}

//------------------------------------------------------------------------------
// TPolyNode methods ...
//------------------------------------------------------------------------------

function TPolyNode.GetChild(Index: Integer): TPolyNode;
begin
  if (Index < 0) or (Index >= FCount) then
    raise Exception.Create('TPolyNode range error: ' + inttostr(Index));
  Result := FChilds[Index];
end;
//------------------------------------------------------------------------------

procedure TPolyNode.AddChild(PolyNode: TPolyNode);
begin
  if FCount = FBuffLen then
  begin
    Inc(FBuffLen, 16);
    SetLength(FChilds, FBuffLen);
  end;
  PolyNode.FParent := self;
  PolyNode.FIndex := FCount;
  FChilds[FCount] := PolyNode;
  Inc(FCount);
end;
//------------------------------------------------------------------------------

function TPolyNode.IsHoleNode: boolean;
var
  Node: TPolyNode;
begin
  Result := True;
  Node := FParent;
  while Assigned(Node) do
  begin
    Result := not Result;
    Node := Node.FParent;
  end;
end;
//------------------------------------------------------------------------------

function TPolyNode.GetNext: TPolyNode;
begin
  if FCount > 0 then
    Result := FChilds[0] else
    Result := GetNextSiblingUp;
end;
//------------------------------------------------------------------------------

function TPolyNode.GetNextSiblingUp: TPolyNode;
begin
  if not Assigned(FParent) then //protects against TPolyTree.GetNextSiblingUp()
    Result := nil
  else if FIndex = FParent.FCount -1 then
      Result := FParent.GetNextSiblingUp
  else
      Result := FParent.Childs[FIndex +1];
end;

//------------------------------------------------------------------------------
// TPolyTree methods ...
//------------------------------------------------------------------------------

destructor TPolyTree.Destroy;
begin
  Clear;
  inherited;
end;
//------------------------------------------------------------------------------

procedure TPolyTree.Clear;
var
  I: Integer;
begin
  for I := 0 to high(FAllNodes) do FAllNodes[I].Free;
  FAllNodes := nil;
  FBuffLen := 16;
  SetLength(FChilds, FBuffLen);
  FCount := 0;
end;
//------------------------------------------------------------------------------

function TPolyTree.GetFirst: TPolyNode;
begin
  if FCount > 0 then
    Result := FChilds[0] else
    Result := nil;
end;
//------------------------------------------------------------------------------

function TPolyTree.GetTotal: Integer;
begin
  Result := length(FAllNodes);
end;

//------------------------------------------------------------------------------
// Int128 Functions ...
//------------------------------------------------------------------------------

const
  Mask32Bits = $FFFFFFFF;

type

  //nb: TInt128.Lo is typed Int64 instead of UInt64 to provide Delphi 7
  //compatability. However while UInt64 isn't a recognised type in
  //Delphi 7, it can still be used in typecasts.
  TInt128 = record
    Hi   : Int64;
    Lo   : Int64;
  end;

{$OVERFLOWCHECKS OFF}
procedure Int128Negate(var Val: TInt128);
begin
  if Val.Lo = 0 then
  begin
    Val.Hi := -Val.Hi;
  end else
  begin
    Val.Lo := -Val.Lo;
    Val.Hi := not Val.Hi;
  end;
end;
//------------------------------------------------------------------------------

function Int128(const val: Int64): TInt128; overload;
begin
  Result.Lo := val;
  if val < 0 then
    Result.Hi := -1 else
    Result.Hi := 0;
end;
//------------------------------------------------------------------------------

function Int128Equal(const Int1, Int2: TInt128): Boolean;
begin
  Result := (Int1.Lo = Int2.Lo) and (Int1.Hi = Int2.Hi);
end;
//------------------------------------------------------------------------------

function Int128LessThan(const Int1, Int2: TInt128): Boolean;
begin
  if (Int1.Hi <> Int2.Hi) then Result := Int1.Hi < Int2.Hi
  else Result := UInt64(Int1.Lo) < UInt64(Int2.Lo);
end;
//------------------------------------------------------------------------------

function Int128Add(const Int1, Int2: TInt128): TInt128;
begin
  Result.Lo := Int1.Lo + Int2.Lo;
  Result.Hi := Int1.Hi + Int2.Hi;
  if UInt64(Result.Lo) < UInt64(Int1.Lo) then Inc(Result.Hi);
end;
//------------------------------------------------------------------------------

function Int128Sub(const Int1, Int2: TInt128): TInt128;
begin
  Result.Hi := Int1.Hi - Int2.Hi;
  Result.Lo := Int1.Lo - Int2.Lo;
  if UInt64(Result.Lo) > UInt64(Int1.Lo) then Dec(Result.Hi);
end;
//------------------------------------------------------------------------------

function Int128Mul(Int1, Int2: Int64): TInt128;
var
  A, B, C: Int64;
  Int1Hi, Int1Lo, Int2Hi, Int2Lo: Int64;
  Negate: Boolean;
begin
  //save the Result's sign before clearing both sign bits ...
  Negate := (Int1 < 0) <> (Int2 < 0);
  if Int1 < 0 then Int1 := -Int1;
  if Int2 < 0 then Int2 := -Int2;

  Int1Hi := Int1 shr 32;
  Int1Lo := Int1 and Mask32Bits;
  Int2Hi := Int2 shr 32;
  Int2Lo := Int2 and Mask32Bits;

  A := Int1Hi * Int2Hi;
  B := Int1Lo * Int2Lo;
  //because the high (sign) bits in both int1Hi & int2Hi have been zeroed,
  //there's no risk of 64 bit overflow in the following assignment
  //(ie: $7FFFFFFF*$FFFFFFFF + $7FFFFFFF*$FFFFFFFF < 64bits)
  C := Int1Hi*Int2Lo + Int2Hi*Int1Lo;
  //Result = A shl 64 + C shl 32 + B ...
  Result.Hi := A + (C shr 32);
  A := C shl 32;

  Result.Lo := A + B;
  if UInt64(Result.Lo) < UInt64(A) then
    Inc(Result.Hi);

  if Negate then Int128Negate(Result);
end;
//------------------------------------------------------------------------------

function Int128Div(Dividend, Divisor: TInt128{; out Remainder: TInt128}): TInt128;
var
  Cntr: TInt128;
  Negate: Boolean;
begin
  if (Divisor.Lo = 0) and (Divisor.Hi = 0) then
    raise Exception.create('int128Div error: divide by zero');

  Negate := (Divisor.Hi < 0) <> (Dividend.Hi < 0);
  if Dividend.Hi < 0 then Int128Negate(Dividend);
  if Divisor.Hi < 0 then Int128Negate(Divisor);

  if Int128LessThan(Divisor, Dividend) then
  begin
    Result.Hi := 0;
    Result.Lo := 0;
    Cntr.Lo := 1;
    Cntr.Hi := 0;
    //while (Dividend >= Divisor) do
    while not Int128LessThan(Dividend, Divisor) do
    begin
      //divisor := divisor shl 1;
      Divisor.Hi := Divisor.Hi shl 1;
      if Divisor.Lo < 0 then Inc(Divisor.Hi);
      Divisor.Lo := Divisor.Lo shl 1;

      //Cntr := Cntr shl 1;
      Cntr.Hi := Cntr.Hi shl 1;
      if Cntr.Lo < 0 then Inc(Cntr.Hi);
      Cntr.Lo := Cntr.Lo shl 1;
    end;
    //Divisor := Divisor shr 1;
    Divisor.Lo := Divisor.Lo shr 1;
    if Divisor.Hi and $1 = $1 then
      Int64Rec(Divisor.Lo).Hi := Cardinal(Int64Rec(Divisor.Lo).Hi) or $80000000;
    Divisor.Hi := Divisor.Hi shr 1;

    //Cntr := Cntr shr 1;
    Cntr.Lo := Cntr.Lo shr 1;
    if Cntr.Hi and $1 = $1 then
      Int64Rec(Cntr.Lo).Hi := Cardinal(Int64Rec(Cntr.Lo).Hi) or $80000000;
    Cntr.Hi := Cntr.Hi shr 1;

    //while (Cntr > 0) do
    while not ((Cntr.Hi = 0) and (Cntr.Lo = 0)) do
    begin
      //if ( Dividend >= Divisor) then
      if not Int128LessThan(Dividend, Divisor) then
      begin
        //Dividend := Dividend - Divisor;
        Dividend := Int128Sub(Dividend, Divisor);

        //Result := Result or Cntr;
        Result.Hi := Result.Hi or Cntr.Hi;
        Result.Lo := Result.Lo or Cntr.Lo;
      end;
      //Divisor := Divisor shr 1;
      Divisor.Lo := Divisor.Lo shr 1;
      if Divisor.Hi and $1 = $1 then
        Int64Rec(Divisor.Lo).Hi := Cardinal(Int64Rec(Divisor.Lo).Hi) or $80000000;
      Divisor.Hi := Divisor.Hi shr 1;

      //Cntr := Cntr shr 1;
      Cntr.Lo := Cntr.Lo shr 1;
      if Cntr.Hi and $1 = $1 then
        Int64Rec(Cntr.Lo).Hi := Cardinal(Int64Rec(Cntr.Lo).Hi) or $80000000;
      Cntr.Hi := Cntr.Hi shr 1;
    end;
    if Negate then Int128Negate(Result);
    //Remainder := Dividend;
  end
  else if (Divisor.Hi = Dividend.Hi) and (Divisor.Lo = Dividend.Lo) then
  begin
    Result := Int128(1);
  end else
  begin
    Result := Int128(0);
  end;
end;
//------------------------------------------------------------------------------

function Int128AsDouble(val: TInt128): Double;
const
  shift64: Double = 18446744073709551616.0;
var
  lo: Int64;
begin
  if (val.Hi < 0) then
  begin
    lo := -val.Lo;
    if lo = 0 then
      Result := val.Hi * shift64 else
      Result := -(not val.Hi * shift64 + UInt64(lo));
  end else
    Result := val.Hi * shift64 + UInt64(val.Lo);
end;
//------------------------------------------------------------------------------

{$OVERFLOWCHECKS ON}

//------------------------------------------------------------------------------
// Miscellaneous Functions ...
//------------------------------------------------------------------------------

function FullRangeNeeded(const Pts: TPolygon): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to high(Pts) do
  begin
    if (abs(Pts[I].X) > HiRange) or (abs(Pts[I].Y) > HiRange) then
      raise exception.Create(rsInvalidInt)
    else if (abs(Pts[I].X) > LoRange) or (abs(Pts[I].Y) > LoRange) then
      Result := True;
  end;
end;
//------------------------------------------------------------------------------

function PointCount(Pts: POutPt): Integer;
var
  P: POutPt;
begin
  Result := 0;
  if not Assigned(Pts) then Exit;
  P := Pts;
  repeat
    Inc(Result);
    P := P.Next;
  until P = Pts;
end;
//------------------------------------------------------------------------------

function PointsEqual(const P1, P2: TIntPoint): Boolean;
begin
  Result := (P1.X = P2.X) and (P1.Y = P2.Y);
end;
//------------------------------------------------------------------------------

function IntPoint(const X, Y: Int64): TIntPoint;
begin
  Result.X := X;
  Result.Y := Y;
end;
//------------------------------------------------------------------------------

function Area(const Pts: TPolygon): Double;
var
  I, HighI: Integer;
  A: TInt128;
  D: Double;
begin
  Result := 0;
  HighI := high(Pts);
  if HighI < 2 then Exit;
  if FullRangeNeeded(Pts) then
  begin
    A := Int128Sub(Int128Mul(Pts[HighI].X, Pts[0].Y),
      Int128Mul(Pts[0].X, Pts[HighI].Y));
    for I := 0 to HighI-1 do
      A := Int128Add(A, Int128Sub(Int128Mul(Pts[I].X, Pts[I+1].Y),
    Int128Mul(Pts[I+1].X, Pts[I].Y)));
    Result := Int128AsDouble(A) / 2;
  end else
  begin
    //see http://www.mathopenref.com/coordpolygonarea2.html
    D := (Pts[HighI].X + Pts[0].X) * (Pts[0].Y - Pts[HighI].Y);
    for I := 1 to HighI do
      D := D + (Pts[I-1].X + Pts[I].X) * (Pts[I].Y - Pts[I-1].Y);
    Result := D / 2;
  end;
end;
//------------------------------------------------------------------------------

function Area(OutRec: POutRec; UseFullInt64Range: Boolean): Double; overload;
var
  Op: POutPt;
  D: Double;
  A: TInt128;
begin
  Op := OutRec.Pts;
  if not Assigned(Op) then
  begin
    Result := 0;
    Exit;
  end;
  if UseFullInt64Range then
  begin
    A := Int128(0);
    repeat
      A := Int128Add(A,
        Int128Mul(Op.Pt.X + Op.Prev.Pt.X, Op.Prev.Pt.Y - Op.Pt.Y));
      Op := Op.Next;
    until Op = OutRec.Pts;
    Result := Int128AsDouble(A) / 2;
  end else
  begin
    D := 0;
    repeat
      //nb: subtraction reversed since vertices are stored in reverse order ...
      D := D + (Op.Pt.X + Op.Prev.Pt.X) * (Op.Prev.Pt.Y - Op.Pt.Y);
      Op := Op.Next;
    until Op = OutRec.Pts;
    Result := D / 2;
  end;
end;
//------------------------------------------------------------------------------

function Orientation(const Pts: TPolygon): Boolean; overload;
begin
  Result := Area(Pts) >= 0;
end;
//------------------------------------------------------------------------------

function ReversePolygon(const Pts: TPolygon): TPolygon;
var
  I, HighI: Integer;
begin
  HighI := high(Pts);
  SetLength(Result, HighI +1);
  for I := 0 to HighI do
    Result[I] := Pts[HighI - I];
end;
//------------------------------------------------------------------------------

function ReversePolygons(const Pts: TPolygons): TPolygons;
var
  I, J, highJ: Integer;
begin
  I := length(Pts);
  SetLength(Result, I);
  for I := 0 to I -1 do
  begin
    highJ := high(Pts[I]);
    SetLength(Result[I], highJ+1);
    for J := 0 to highJ do
      Result[I][J] := Pts[I][highJ - J];
  end;
end;
//------------------------------------------------------------------------------

function PointIsVertex(const Pt: TIntPoint; PP: POutPt): Boolean;
var
  Pp2: POutPt;
begin
  Result := True;
  Pp2 := PP;
  repeat
    if PointsEqual(Pp2.Pt, Pt) then Exit;
    Pp2 := Pp2.Next;
  until Pp2 = PP;
  Result := False;
end;
//------------------------------------------------------------------------------

function PointOnLineSegment(const Pt, LinePt1, LinePt2: TIntPoint;
  UseFullInt64Range: Boolean): Boolean;
begin
  if UseFullInt64Range then
    Result :=
      ((Pt.X = LinePt1.X) and (Pt.Y = LinePt1.Y)) or
      ((Pt.X = LinePt2.X) and (Pt.Y = LinePt2.Y)) or
      (((Pt.X > LinePt1.X) = (Pt.X < LinePt2.X)) and
      ((Pt.Y > LinePt1.Y) = (Pt.Y < LinePt2.Y)) and
      Int128Equal(Int128Mul((Pt.X - LinePt1.X), (LinePt2.Y - LinePt1.Y)),
      Int128Mul((LinePt2.X - LinePt1.X), (Pt.Y - LinePt1.Y))))
  else
    Result :=
      ((Pt.X = LinePt1.X) and (Pt.Y = LinePt1.Y)) or
      ((Pt.X = LinePt2.X) and (Pt.Y = LinePt2.Y)) or
      (((Pt.X > LinePt1.X) = (Pt.X < LinePt2.X)) and
      ((Pt.Y > LinePt1.Y) = (Pt.Y < LinePt2.Y)) and
      ((Pt.X - LinePt1.X) * (LinePt2.Y - LinePt1.Y) =
        (LinePt2.X - LinePt1.X) * (Pt.Y - LinePt1.Y)));
end;
//------------------------------------------------------------------------------

function PointOnPolygon(const Pt: TIntPoint;
  PP: POutPt; UseFullInt64Range: Boolean): Boolean;
var
  Pp2: POutPt;
begin
  Pp2 := PP;
  repeat
    if PointOnLineSegment(Pt, Pp2.Pt, Pp2.Next.Pt, UseFullInt64Range) then
    begin
      Result := True;
      Exit;
    end;
    Pp2 := Pp2.Next;
  until (Pp2 = PP);
  Result := False;
end;
//------------------------------------------------------------------------------

function PointInPolygon(const Pt: TIntPoint;
  PP: POutPt; UseFullInt64Range: Boolean): Boolean;
var
  Pp2: POutPt;
  A, B: TInt128;
begin
  Result := False;
  Pp2 := PP;
  if UseFullInt64Range then
  begin
    repeat
      if (((Pp2.Pt.Y <= Pt.Y) and (Pt.Y < Pp2.Prev.Pt.Y)) or
        ((Pp2.Prev.Pt.Y <= Pt.Y) and (Pt.Y < Pp2.Pt.Y))) then
      begin
        A := Int128(Pt.X - Pp2.Pt.X);
        B := Int128Div( Int128Mul(Pp2.Prev.Pt.X - Pp2.Pt.X,
          Pt.Y - Pp2.Pt.Y), Int128(Pp2.Prev.Pt.Y - Pp2.Pt.Y) );
        if Int128LessThan(A, B) then Result := not Result;
      end;
      Pp2 := Pp2.Next;
    until Pp2 = PP;
  end else
  begin
    repeat
      if ((((Pp2.Pt.Y <= Pt.Y) and (Pt.Y < Pp2.Prev.Pt.Y)) or
        ((Pp2.Prev.Pt.Y <= Pt.Y) and (Pt.Y < Pp2.Pt.Y))) and
        (Pt.X < (Pp2.Prev.Pt.X - Pp2.Pt.X) * (Pt.Y - Pp2.Pt.Y) /
        (Pp2.Prev.Pt.Y - Pp2.Pt.Y) + Pp2.Pt.X)) then Result := not Result;
      Pp2 := Pp2.Next;
    until Pp2 = PP;
  end;
end;
//------------------------------------------------------------------------------

function SlopesEqual(E1, E2: PEdge;
  UseFullInt64Range: Boolean): Boolean; overload;
begin
  if UseFullInt64Range then
    Result := Int128Equal(Int128Mul(E1.DeltaY, E2.DeltaX),
      Int128Mul(E1.DeltaX, E2.DeltaY))
  else
    Result := E1.DeltaY * E2.DeltaX = E1.DeltaX * E2.DeltaY;
end;
//---------------------------------------------------------------------------

function SlopesEqual(const Pt1, Pt2, Pt3: TIntPoint;
  UseFullInt64Range: Boolean): Boolean; overload;
begin
  if UseFullInt64Range then
    Result := Int128Equal(
      Int128Mul(Pt1.Y-Pt2.Y, Pt2.X-Pt3.X), Int128Mul(Pt1.X-Pt2.X, Pt2.Y-Pt3.Y))
  else
    Result := (Pt1.Y-Pt2.Y)*(Pt2.X-Pt3.X) = (Pt1.X-Pt2.X)*(Pt2.Y-Pt3.Y);
end;
//---------------------------------------------------------------------------

function SlopesEqual(const Pt1, Pt2, Pt3, Pt4: TIntPoint;
  UseFullInt64Range: Boolean): Boolean; overload;
begin
  if UseFullInt64Range then
    Result := Int128Equal( Int128Mul(Pt1.Y-Pt2.Y, Pt3.X-Pt4.X),
      Int128Mul(Pt1.X-Pt2.X, Pt3.Y-Pt4.Y))
  else
    Result := (Pt1.Y-Pt2.Y)*(Pt3.X-Pt4.X) = (Pt1.X-Pt2.X)*(Pt3.Y-Pt4.Y);
end;
//---------------------------------------------------------------------------

//                 0(90º)                                                  //
//                 |                                                       //
// +inf (180º) --- o --- -inf (0º)                                         //
function GetDx(const Pt1, Pt2: TIntPoint): Double;
begin
  if (Pt1.Y = Pt2.Y) then Result := Horizontal
  else Result := (Pt2.X - Pt1.X)/(Pt2.Y - Pt1.Y);
end;
//---------------------------------------------------------------------------

procedure SetDx(E: PEdge); {$IFDEF INLINING} inline; {$ENDIF}
begin
  E.DeltaX := (E.XTop - E.XBot);
  E.DeltaY := (E.YTop - E.YBot);
  if E.DeltaY = 0 then E.Dx := Horizontal
  else E.Dx := E.DeltaX/E.DeltaY;
end;
//---------------------------------------------------------------------------

procedure SwapSides(Edge1, Edge2: PEdge);
var
  Side: TEdgeSide;
begin
  Side :=  Edge1.Side;
  Edge1.Side := Edge2.Side;
  Edge2.Side := Side;
end;
//------------------------------------------------------------------------------

procedure SwapPolyIndexes(Edge1, Edge2: PEdge);
var
  OutIdx: Integer;
begin
  OutIdx :=  Edge1.OutIdx;
  Edge1.OutIdx := Edge2.OutIdx;
  Edge2.OutIdx := OutIdx;
end;
//------------------------------------------------------------------------------

function TopX(Edge: PEdge; const currentY: Int64): Int64;
begin
  if currentY = Edge.YTop then Result := Edge.XTop
  else if Edge.XTop = Edge.XBot then Result := Edge.XBot
  else Result := Edge.XBot + round(Edge.Dx*(currentY - Edge.YBot));
end;
//------------------------------------------------------------------------------

function IntersectPoint(Edge1, Edge2: PEdge;
  out ip: TIntPoint; UseFullInt64Range: Boolean): Boolean; overload;
var
  B1,B2,M: Double;
begin
  if SlopesEqual(Edge1, Edge2, UseFullInt64Range) then
  begin
    //parallel edges, but nevertheless prepare to force the intersection
    //since Edge2.XCurr < Edge1.XCurr ...
    if Edge2.YBot > Edge1.YBot then
      ip.Y := Edge2.YBot else
      ip.Y := Edge1.YBot;
    Result := False;
    Exit;
  end;
  if Edge1.Dx = 0 then
  begin
    ip.X := Edge1.XBot;
    if Edge2.Dx = Horizontal then
      ip.Y := Edge2.YBot
    else
    begin
      with Edge2^ do B2 := YBot - (XBot/Dx);
      ip.Y := round(ip.X/Edge2.Dx + B2);
    end;
  end
  else if Edge2.Dx = 0 then
  begin
    ip.X := Edge2.XBot;
    if Edge1.Dx = Horizontal then
      ip.Y := Edge1.YBot
    else
    begin
      with Edge1^ do B1 := YBot - (XBot/Dx);
      ip.Y := round(ip.X/Edge1.Dx + B1);
    end;
  end else
  begin
    with Edge1^ do B1 := XBot - YBot * Dx;
    with Edge2^ do B2 := XBot - YBot * Dx;
    M := (B2-B1)/(Edge1.Dx - Edge2.Dx);
    ip.Y := round(M);
    if Abs(Edge1.Dx) < Abs(Edge2.Dx) then
      ip.X := round(Edge1.Dx * M + B1)
    else
      ip.X := round(Edge2.Dx * M + B2);
  end;

  //The precondition - E.XCurr > eNext.XCurr - indicates that the two edges do
  //intersect below TopY (and hence below the tops of either Edge). However,
  //when edges are almost parallel, rounding errors may cause False positives -
  //indicating intersections when there really aren't any. Also, floating point
  //imprecision can incorrectly place an intersect point beyond/above an Edge.
  //Therfore, further validation of the IP is warranted ...
  if (ip.Y < Edge1.YTop) or (ip.Y < Edge2.YTop) then
  begin
    //Find the lower top of the two edges and compare X's at this Y.
    //If Edge1's X is greater than Edge2's X then it's fair to assume an
    //intersection really has occurred...
    if (Edge1.YTop > Edge2.YTop) then
    begin
      Result := TopX(Edge2, Edge1.YTop) < Edge1.XTop;
      ip.X := Edge1.XTop;
      ip.Y := Edge1.YTop;
    end else
    begin
      Result := TopX(Edge1, Edge2.YTop) > Edge2.XTop;
      ip.X := Edge2.XTop;
      ip.Y := Edge2.YTop;
    end;
  end else
    Result := True;
end;
//------------------------------------------------------------------------------

procedure ReversePolyPtLinks(PP: POutPt);
var
  Pp1,Pp2: POutPt;
begin
  if not Assigned(PP) then Exit;
  Pp1 := PP;
  repeat
    Pp2:= Pp1.Next;
    Pp1.Next := Pp1.Prev;
    Pp1.Prev := Pp2;
    Pp1 := Pp2;
  until Pp1 = PP;
end;

//------------------------------------------------------------------------------
// TClipperBase methods ...
//------------------------------------------------------------------------------

constructor TClipperBase.Create;
begin
  FEdgeList := TList.Create;
  FLmList := nil;
  FCurrLm := nil;
  FUse64BitRange := False; //ie default is False
end;
//------------------------------------------------------------------------------

destructor TClipperBase.Destroy;
begin
  Clear;
  FEdgeList.Free;
  inherited;
end;
//------------------------------------------------------------------------------

procedure RangeTest(const Pt: TIntPoint;
  var MaxRange: Int64); {$IFDEF INLINING} inline; {$ENDIF}
begin
  if Pt.X > MaxRange then
    if Pt.X > HiRange then
      raise exception.Create(rsInvalidInt)
    else MaxRange := HiRange;
  if Pt.Y > MaxRange then
    if Pt.Y > HiRange then
      raise exception.Create(rsInvalidInt)
    else MaxRange := HiRange;
end;
//------------------------------------------------------------------------------

procedure SwapX(E: PEdge);
begin
  //swap horizontal edges' top and bottom x's so they follow the natural
  //progression of the bounds - ie so their xbots will align with the
  //adjoining lower Edge. [Helpful in the ProcessHorizontal() method.]
  E.XCurr := E.XTop;
  E.XTop := E.XBot;
  E.XBot := E.XCurr;
end;
//------------------------------------------------------------------------------

function TClipperBase.AddPolygon(const Polygon: TPolygon;
  PolyType: TPolyType): Boolean;

  //----------------------------------------------------------------------

  procedure InitEdge(E, eNext, ePrev: PEdge; const Pt: TIntPoint);
  begin
    E.Next := eNext;
    E.Prev := ePrev;
    E.XCurr := Pt.X;
    E.YCurr := Pt.Y;
    if E.YCurr >= E.Next.YCurr then
    begin
      E.XBot := E.XCurr;
      E.YBot := E.YCurr;
      E.XTop := E.Next.XCurr;
      E.YTop := E.Next.YCurr;
      E.WindDelta := 1;
    end else
    begin
      E.XTop := E.XCurr;
      E.YTop := E.YCurr;
      E.XBot := E.Next.XCurr;
      E.YBot := E.Next.YCurr;
      E.WindDelta := -1;
    end;
    SetDx(E);
    E.PolyType := PolyType;
    E.OutIdx := -1;
  end;
  //----------------------------------------------------------------------

  procedure InsertLocalMinima(Lm: PLocalMinima);
  var
    TmpLm: PLocalMinima;
  begin
    if not Assigned(FLmList) then
    begin
      FLmList := Lm;
    end
    else if (Lm.Y >= FLmList.Y) then
    begin
      Lm.Next := FLmList;
      FLmList := Lm;
    end else
    begin
      TmpLm := FLmList;
      while Assigned(TmpLm.Next) and (Lm.Y < TmpLm.Next.Y) do
          TmpLm := TmpLm.Next;
      Lm.Next := TmpLm.Next;
      TmpLm.Next := Lm;
    end;
  end;
  //----------------------------------------------------------------------

  function AddBoundsToLML(E: PEdge): PEdge;
  var
    NewLm: PLocalMinima;
  begin
    //Starting at the top of one bound we progress to the bottom where there's
    //A local minima. We then go to the top of the Next bound. These two bounds
    //form the left and right (or right and left) bounds of the local minima.
    E.NextInLML := nil;
    E := E.Next;
    while True do
    begin
      if E.Dx = Horizontal then
      begin
        //nb: proceed through horizontals when approaching from their right,
        //    but break on horizontal minima if approaching from their left.
        //    This ensures 'local minima' are always on the left of horizontals.
        if (E.Next.YTop < E.YTop) and (E.Next.XBot > E.Prev.XBot) then Break;
        if (E.XTop <> E.Prev.XBot) then SwapX(E);
        //E.WindDelta := 0; safe option to consider when redesigning
        E.NextInLML := E.Prev;
      end
      else if (E.YBot = E.Prev.YBot) then Break
      else E.NextInLML := E.Prev;
      E := E.Next;
    end;

    //E and E.Prev are now at a local minima ...
    new(NewLm);
    NewLm.Y := E.Prev.YBot;
    NewLm.Next := nil;
    if E.Dx = Horizontal then //Horizontal edges never start a left bound
    begin
      if (E.XBot <> E.Prev.XBot) then SwapX(E);
      NewLm.LeftBound := E.Prev;
      NewLm.RightBound := E;
    end else if (E.Dx < E.Prev.Dx) then
    begin
      NewLm.LeftBound := E.Prev;
      NewLm.RightBound := E;
    end else
    begin
      NewLm.LeftBound := E;
      NewLm.RightBound := E.Prev;
    end;
    NewLm.LeftBound.Side := esLeft;
    NewLm.RightBound.Side := esRight;

    InsertLocalMinima(NewLm);
    //now process the ascending bound ....
    while True do
    begin
      if (E.Next.YTop = E.YTop) and not (E.Next.Dx = Horizontal) then Break;
      E.NextInLML := E.Next;
      E := E.Next;
      if (E.Dx = Horizontal) and (E.XBot <> E.Prev.XTop) then SwapX(E);
    end;
    Result := E.Next;
  end;
  //----------------------------------------------------------------------

var
  I, J, len: Integer;
  Edges: PEdgeArray;
  E, EHighest: PEdge;
  Pg: TPolygon;
  MaxVal: Int64;
begin
  {AddPolygon}
  Result := False; //ie assume nothing added
  len := length(Polygon);
  if len < 3 then Exit;
  SetLength(Pg, len);

  //1. check that coordinate values are within the valid range, and
  //2. remove duplicate points and co-linear points
  if FUse64BitRange then MaxVal := HiRange else MaxVal := LoRange;
  RangeTest(Polygon[0], MaxVal);
  Pg[0] := Polygon[0];
  J := 0;
  for I := 1 to len-1 do
  begin
    if PointsEqual(Pg[J], Polygon[I]) then Continue;
    RangeTest(Polygon[I], MaxVal);
    if (J > 0) and SlopesEqual(Pg[J-1], Pg[J], Polygon[I], MaxVal = HiRange) then
    begin
      if PointsEqual(Pg[J-1], Polygon[I]) then Dec(J);
    end else
      Inc(J);
    Pg[J] := Polygon[I];
  end;
  if (J < 2) then Exit;
  FUse64BitRange := MaxVal = HiRange;

  //now remove duplicate points and co-linear edges at the loop around of the
  //start and end coordinates ...
  len := J+1;
  while len > 2 do
  begin
    //nb: test for point equality before testing slopes ...
    if PointsEqual(Pg[J], Pg[0]) then Dec(J)
    else if PointsEqual(Pg[0], Pg[1]) or
      SlopesEqual(Pg[J], Pg[0], Pg[1], FUse64BitRange) then
    begin
      Pg[0] := Pg[J];
      Dec(J);
    end
    else if SlopesEqual(Pg[J-1], Pg[J], Pg[0], FUse64BitRange) then Dec(J)
    else if SlopesEqual(Pg[0], Pg[1], Pg[2], FUse64BitRange) then
    begin
      for I := 2 to J do Pg[I-1] := Pg[I];
      Dec(J);
    end
    else
      Break;
    Dec(len);
  end;
  if len < 3 then Exit;
  Result := True;

  GetMem(Edges, sizeof(TEdge)*len);
  FillChar(Edges^, sizeof(TEdge)*len, 0);
  FEdgeList.Add(Edges);

  //convert vertices to a Double-linked-list of edges and initialize ...
  Edges[0].XCurr := Pg[0].X;
  Edges[0].YCurr := Pg[0].Y;
  InitEdge(@Edges[len-1], @Edges[0], @Edges[len-2], Pg[len-1]);
  for I := len-2 downto 1 do
    InitEdge(@Edges[I], @Edges[I+1], @Edges[I-1], Pg[I]);
  InitEdge(@Edges[0], @Edges[1], @Edges[len-1], Pg[0]);
  //reset XCurr & YCurr and find the 'highest' Edge. (nb: since I'm much more
  //familiar with positive downwards Y axes, 'highest' here will be the Edge
  //with the *smallest* YTop.)
  E := @Edges[0];
  EHighest := E;
  repeat
    E.XCurr := E.XBot;
    E.YCurr := E.YBot;
    if E.YTop < EHighest.YTop then EHighest := E;
    E := E.Next;
  until E = @Edges[0];

  //make sure eHighest is positioned so the following loop works safely ...
  if EHighest.WindDelta > 0 then EHighest := EHighest.Next;
  if (EHighest.Dx = Horizontal) then EHighest := EHighest.Next;

  //finally insert each local minima ...
  E := EHighest;
  repeat
    E := AddBoundsToLML(E);
  until (E = EHighest);
end;
//------------------------------------------------------------------------------

function TClipperBase.AddPolygons(const Polygons: TPolygons;
  PolyType: TPolyType): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to high(Polygons) do
    if AddPolygon(Polygons[I], PolyType) then Result := True;
end;
//------------------------------------------------------------------------------

procedure TClipperBase.Clear;
var
  I: Integer;
begin
  DisposeLocalMinimaList;
  for I := 0 to FEdgeList.Count -1 do dispose(PEdgeArray(fEdgeList[I]));
  FEdgeList.Clear;
  FUse64BitRange := False;
end;
//------------------------------------------------------------------------------

procedure TClipperBase.Reset;
var
  E: PEdge;
  Lm: PLocalMinima;
begin
  //Reset() allows various clipping operations to be executed
  //multiple times on the same polygon sets.

  FCurrLm := FLmList;
  //reset all edges ...
  Lm := FCurrLm;
  while Assigned(Lm) do
  begin
    E := Lm.LeftBound;
    while Assigned(E) do
    begin
      E.XCurr := E.XBot;
      E.YCurr := E.YBot;
      E.Side := esLeft;
      E.OutIdx := -1;
      E := E.NextInLML;
    end;
    E := Lm.RightBound;
    while Assigned(E) do
    begin
      E.XCurr := E.XBot;
      E.YCurr := E.YBot;
      E.Side := esRight;
      E.OutIdx := -1;
      E := E.NextInLML;
    end;
    Lm := Lm.Next;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipperBase.DisposeLocalMinimaList;
begin
  while Assigned(FLmList) do
  begin
    FCurrLm := FLmList.Next;
    Dispose(FLmList);
    FLmList := FCurrLm;
  end;
  FCurrLm := nil;
end;
//------------------------------------------------------------------------------

procedure TClipperBase.PopLocalMinima;
begin
  if not Assigned(fCurrLM) then Exit;
  FCurrLM := FCurrLM.Next;
end;

//------------------------------------------------------------------------------
// TClipper methods ...
//------------------------------------------------------------------------------

constructor TClipper.Create;
begin
  inherited Create;
  FJoinList := TList.Create;
  FPolyOutList := TList.Create;
end;
//------------------------------------------------------------------------------

destructor TClipper.Destroy;
begin
  inherited; //this must be first since inherited Destroy calls Clear.
  DisposeScanbeamList;
  FJoinList.Free;
  FPolyOutList.Free;
end;
//------------------------------------------------------------------------------

procedure TClipper.Clear;
begin
  DisposeAllPolyPts;
  inherited;
end;
//------------------------------------------------------------------------------

procedure TClipper.DisposeScanbeamList;
var
  SB: PScanbeam;
begin
  while Assigned(fScanbeam) do
  begin
    SB := FScanbeam.Next;
    Dispose(fScanbeam);
    FScanbeam := SB;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.Reset;
var
  Lm: PLocalMinima;
begin
  inherited Reset;
  FScanbeam := nil;
  DisposeAllPolyPts;
  Lm := FLmList;
  while Assigned(Lm) do
  begin
    InsertScanbeam(Lm.Y);
    Lm := Lm.Next;
  end;
end;
//------------------------------------------------------------------------------

function TClipper.Execute(clipType: TClipType;
  out solution: TPolygons;
  subjFillType: TPolyFillType = pftEvenOdd;
  clipFillType: TPolyFillType = pftEvenOdd): Boolean;
begin
  Result := False;
  solution := nil;
  if FExecuteLocked then Exit;
  try
    FExecuteLocked := True;
    FSubjFillType := subjFillType;
    FClipFillType := clipFillType;
    FClipType := clipType;
    FUsingPolyTree := False;
    Result := ExecuteInternal;
    if Result then solution := GetResult;
  finally
    FExecuteLocked := False;
  end;
end;
//------------------------------------------------------------------------------

function TClipper.Execute(clipType: TClipType;
  var PolyTree: TPolyTree;
  subjFillType: TPolyFillType = pftEvenOdd;
  clipFillType: TPolyFillType = pftEvenOdd): Boolean;
begin
  Result := False;
  if FExecuteLocked or not Assigned(PolyTree) then Exit;
  try
    FExecuteLocked := True;
    FSubjFillType := subjFillType;
    FClipFillType := clipFillType;
    FClipType := clipType;
    FUsingPolyTree := True;
    Result := ExecuteInternal and GetResult2(PolyTree);
  finally
    FExecuteLocked := False;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.FixHoleLinkage(OutRec: POutRec);
var
  orfl: POutRec;
begin
  //skip if it's an outermost polygon or if FirstLeft
  //already points to the outer/owner polygon ...
  if not Assigned(OutRec.FirstLeft) or
    ((OutRec.IsHole <> OutRec.FirstLeft.IsHole) and
      Assigned(OutRec.FirstLeft.Pts)) then Exit;
  orfl := OutRec.FirstLeft;
  while Assigned(orfl) and
    ((orfl.IsHole = OutRec.IsHole) or not Assigned(orfl.Pts)) do
      orfl := orfl.FirstLeft;
  OutRec.FirstLeft := orfl;
end;
//------------------------------------------------------------------------------

function TClipper.ExecuteInternal: Boolean;
var
  I: Integer;
  OutRec: POutRec;
  BotY, TopY: Int64;
begin
  Result := False;
  try try
    Reset;
    if not Assigned(fScanbeam) then
    begin
      Result := True;
      Exit;
    end;

    BotY := PopScanbeam;
    repeat
      InsertLocalMinimaIntoAEL(BotY);
      ClearHorzJoins;
      ProcessHorizontals;
      TopY := PopScanbeam;
      if not ProcessIntersections(BotY, TopY) then Exit;
      ProcessEdgesAtTopOfScanbeam(TopY);
      BotY := TopY;
    until not assigned(FScanbeam) and not assigned(CurrentLm);

    //tidy up output polygons and fix orientations where necessary ...
    for I := 0 to FPolyOutList.Count -1 do
    begin
      OutRec := FPolyOutList[I];
      if not Assigned(OutRec.Pts) then Continue;
      FixupOutPolygon(OutRec);
      if not Assigned(OutRec.Pts) then Continue;
      if (OutRec.IsHole xor FReverseOutput) = (Area(OutRec, FUse64BitRange) > 0) then
        ReversePolyPtLinks(OutRec.Pts);
    end;
    if FJoinList.count > 0 then JoinCommonEdges;
    if FForceSimple then DoSimplePolygons;

    Result := True;
  except
    Result := False;
  end;
  finally
    ClearJoins;
    ClearHorzJoins;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.InsertScanbeam(const Y: Int64);
var
  Sb, Sb2: PScanbeam;
begin
  new(Sb);
  Sb.Y := Y;
  if not Assigned(fScanbeam) then
  begin
    FScanbeam := Sb;
    Sb.Next := nil;
  end else if Y > FScanbeam.Y then
  begin
    Sb.Next := FScanbeam;
    FScanbeam := Sb;
  end else
  begin
    Sb2 := FScanbeam;
    while Assigned(Sb2.Next) and (Y <= Sb2.Next.Y) do Sb2 := Sb2.Next;
    if Y <> Sb2.Y then
    begin
      Sb.Next := Sb2.Next;
      Sb2.Next := Sb;
    end
    else dispose(Sb); //ie ignores duplicates
  end;
end;
//------------------------------------------------------------------------------

function TClipper.PopScanbeam: Int64;
var
  Sb: PScanbeam;
begin
  Result := FScanbeam.Y;
  Sb := FScanbeam;
  FScanbeam := FScanbeam.Next;
  dispose(Sb);
end;
//------------------------------------------------------------------------------

procedure TClipper.DisposePolyPts(PP: POutPt);
var
  TmpPp: POutPt;
begin
  PP.Prev.Next := nil;
  while Assigned(PP) do
  begin
    TmpPp := PP;
    PP := PP.Next;
    dispose(TmpPp);
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.DisposeAllPolyPts;
var
  I: Integer;
begin
  for I := 0 to FPolyOutList.Count -1 do DisposeOutRec(I);
  FPolyOutList.Clear;
end;
//------------------------------------------------------------------------------

procedure TClipper.DisposeOutRec(Index: Integer);
var
  OutRec: POutRec;
begin
  OutRec := FPolyOutList[Index];
  if Assigned(OutRec.Pts) then DisposePolyPts(OutRec.Pts);
  Dispose(OutRec);
  FPolyOutList[Index] := nil;
end;
//------------------------------------------------------------------------------

procedure TClipper.SetWindingCount(Edge: PEdge);
var
  E: PEdge;
begin
  E := Edge.PrevInAEL;
  //find the Edge of the same PolyType that immediately preceeds 'Edge' in AEL
  while Assigned(E) and (E.PolyType <> Edge.PolyType) do E := E.PrevInAEL;
  if not Assigned(E) then
  begin
    Edge.WindCnt := Edge.WindDelta;
    Edge.WindCnt2 := 0;
    E := FActiveEdges; //ie get ready to calc WindCnt2
  end else if IsEvenOddFillType(Edge) then
  begin
    //even-odd filling ...
    Edge.WindCnt := 1;
    Edge.WindCnt2 := E.WindCnt2;
    E := E.NextInAEL; //ie get ready to calc WindCnt2
  end else
  begin
    //NonZero, Positive, or Negative filling ...
    if E.WindCnt * E.WindDelta < 0 then
    begin
      if (abs(E.WindCnt) > 1) then
      begin
        if (E.WindDelta * Edge.WindDelta < 0) then Edge.WindCnt := E.WindCnt
        else Edge.WindCnt := E.WindCnt + Edge.WindDelta;
      end else
        Edge.WindCnt := E.WindCnt + E.WindDelta + Edge.WindDelta;
    end else
    begin
      if (abs(E.WindCnt) > 1) and (E.WindDelta * Edge.WindDelta < 0) then
        Edge.WindCnt := E.WindCnt
      else if E.WindCnt + Edge.WindDelta = 0 then
        Edge.WindCnt := E.WindCnt
      else Edge.WindCnt := E.WindCnt + Edge.WindDelta;
    end;
    Edge.WindCnt2 := E.WindCnt2;
    E := E.NextInAEL; //ie get ready to calc WindCnt2
  end;

  //update WindCnt2 ...
  if IsEvenOddAltFillType(Edge) then
  begin
    //even-odd filling ...
    while (E <> Edge) do
    begin
      if Edge.WindCnt2 = 0 then Edge.WindCnt2 := 1 else Edge.WindCnt2 := 0;
      E := E.NextInAEL;
    end;
  end else
  begin
    //NonZero, Positive, or Negative filling ...
    while (E <> Edge) do
    begin
      Inc(Edge.WindCnt2, E.WindDelta);
      E := E.NextInAEL;
    end;
  end;
end;
//------------------------------------------------------------------------------

function TClipper.IsEvenOddFillType(Edge: PEdge): Boolean;
begin
  if Edge.PolyType = ptSubject then
    Result := FSubjFillType = pftEvenOdd else
    Result := FClipFillType = pftEvenOdd;
end;
//------------------------------------------------------------------------------

function TClipper.IsEvenOddAltFillType(Edge: PEdge): Boolean;
begin
  if Edge.PolyType = ptSubject then
    Result := FClipFillType = pftEvenOdd else
    Result := FSubjFillType = pftEvenOdd;
end;
//------------------------------------------------------------------------------

function TClipper.IsContributing(Edge: PEdge): Boolean;
var
  Pft, Pft2: TPolyFillType;
begin
  if Edge.PolyType = ptSubject then
  begin
    Pft := FSubjFillType;
    Pft2 := FClipFillType;
  end else
  begin
    Pft := FClipFillType;
    Pft2 := FSubjFillType
  end;
  case Pft of
    pftEvenOdd, pftNonZero: Result := abs(Edge.WindCnt) = 1;
    pftPositive: Result := (Edge.WindCnt = 1);
    else Result := (Edge.WindCnt = -1);
  end;
  if not Result then Exit;

  case FClipType of
    ctIntersection:
      case Pft2 of
        pftEvenOdd, pftNonZero: Result := (Edge.WindCnt2 <> 0);
        pftPositive: Result := (Edge.WindCnt2 > 0);
        pftNegative: Result := (Edge.WindCnt2 < 0);
      end;
    ctUnion:
      case Pft2 of
        pftEvenOdd, pftNonZero: Result := (Edge.WindCnt2 = 0);
        pftPositive: Result := (Edge.WindCnt2 <= 0);
        pftNegative: Result := (Edge.WindCnt2 >= 0);
      end;
    ctDifference:
      if Edge.PolyType = ptSubject then
        case Pft2 of
          pftEvenOdd, pftNonZero: Result := (Edge.WindCnt2 = 0);
          pftPositive: Result := (Edge.WindCnt2 <= 0);
          pftNegative: Result := (Edge.WindCnt2 >= 0);
        end
      else
        case Pft2 of
          pftEvenOdd, pftNonZero: Result := (Edge.WindCnt2 <> 0);
          pftPositive: Result := (Edge.WindCnt2 > 0);
          pftNegative: Result := (Edge.WindCnt2 < 0);
        end;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.AddLocalMinPoly(E1, E2: PEdge; const Pt: TIntPoint);
var
  E, prevE: PEdge;
begin
  if (E2.Dx = Horizontal) or (E1.Dx > E2.Dx) then
  begin
    AddOutPt(E1, Pt);
    E2.OutIdx := E1.OutIdx;
    E1.Side := esLeft;
    E2.Side := esRight;
    E := E1;
    if E.PrevInAEL = E2 then
      prevE := E2.PrevInAEL
    else
      prevE := E.PrevInAEL;
  end else
  begin
    AddOutPt(E2, Pt);
    E1.OutIdx := E2.OutIdx;
    E1.Side := esRight;
    E2.Side := esLeft;
    E := E2;
    if E.PrevInAEL = E1 then
      prevE := E1.PrevInAEL
    else
      prevE := E.PrevInAEL;
  end;

  if Assigned(prevE) and (prevE.OutIdx >= 0) and
    (TopX(prevE, Pt.Y) = TopX(E, Pt.Y)) and
     SlopesEqual(E, prevE, FUse64BitRange) then
       AddJoin(E, prevE);
end;
//------------------------------------------------------------------------------

procedure TClipper.AddLocalMaxPoly(E1, E2: PEdge; const Pt: TIntPoint);
begin
  AddOutPt(E1, Pt);
  if (E1.OutIdx = E2.OutIdx) then
  begin
    E1.OutIdx := -1;
    E2.OutIdx := -1;
  end
  else if E1.OutIdx < E2.OutIdx then
    AppendPolygon(E1, E2)
  else
    AppendPolygon(E2, E1);
end;
//------------------------------------------------------------------------------

procedure TClipper.AddEdgeToSEL(Edge: PEdge);
begin
  //SEL pointers in PEdge are reused to build a list of horizontal edges.
  //However, we don't need to worry about order with horizontal Edge processing.
  if not Assigned(fSortedEdges) then
  begin
    FSortedEdges := Edge;
    Edge.PrevInSEL := nil;
    Edge.NextInSEL := nil;
  end else
  begin
    Edge.NextInSEL := FSortedEdges;
    Edge.PrevInSEL := nil;
    FSortedEdges.PrevInSEL := Edge;
    FSortedEdges := Edge;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.CopyAELToSEL;
var
  E: PEdge;
begin
  E := FActiveEdges;
  FSortedEdges := E;
  while Assigned(E) do
  begin
    E.PrevInSEL := E.PrevInAEL;
    E.NextInSEL := E.NextInAEL;
    E := E.NextInAEL;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.AddJoin(E1, E2: PEdge;
  E1OutIdx: Integer = -1; E2OutIdx: Integer = -1);
var
  Jr: PJoinRec;
begin
  new(Jr);
  if E1OutIdx >= 0 then
    Jr.Poly1Idx := E1OutIdx else
    Jr.Poly1Idx := E1.OutIdx;
  with E1^ do
  begin
    Jr.Pt1a := IntPoint(XCurr, YCurr);
    Jr.Pt1b := IntPoint(XTop, YTop);
  end;
  if E2OutIdx >= 0 then
    Jr.Poly2Idx := E2OutIdx else
    Jr.Poly2Idx := E2.OutIdx;
  with E2^ do
  begin
    Jr.Pt2a := IntPoint(XCurr, YCurr);
    Jr.Pt2b := IntPoint(XTop, YTop);
  end;
  FJoinList.add(Jr);
end;
//------------------------------------------------------------------------------

procedure TClipper.ClearJoins;
var
  I: Integer;
begin
  for I := 0 to FJoinList.count -1 do
    Dispose(PJoinRec(fJoinList[I]));
  FJoinList.Clear;
end;
//------------------------------------------------------------------------------

procedure TClipper.AddHorzJoin(E: PEdge; Idx: Integer);
var
  Hr: PHorzRec;
begin
  new(Hr);
  Hr.Edge := E;
  Hr.SavedIdx := Idx;
  if FHorizJoins = nil then
  begin
    FHorizJoins := Hr;
    Hr.Next := Hr;
    Hr.Prev := Hr;
  end else
  begin
    Hr.Next := FHorizJoins;
    Hr.Prev := FHorizJoins.Prev;
    FHorizJoins.Prev.Next := Hr;
    FHorizJoins.Prev := Hr;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.ClearHorzJoins;
var
  M, M2: PHorzRec;
begin
  if not Assigned(fHorizJoins) then Exit;
  M := FHorizJoins;
  M.Prev.Next := nil;
  while Assigned(M) do
  begin
    M2 := M.Next;
    dispose(M);
    M := M2;
  end;
  FHorizJoins := nil;
end;
//------------------------------------------------------------------------------

procedure SwapPoints(var Pt1, Pt2: TIntPoint);
var
  Tmp: TIntPoint;
begin
  Tmp := Pt1;
  Pt1 := Pt2;
  Pt2 := Tmp;
end;
//------------------------------------------------------------------------------

function GetOverlapSegment(Pt1a, Pt1b, Pt2a, Pt2b: TIntPoint;
  out Pt1, Pt2: TIntPoint): Boolean;
begin
  //precondition: segments are colinear
  if abs(Pt1a.X - Pt1b.X) > abs(Pt1a.Y - Pt1b.Y) then
  begin
    if Pt1a.X > Pt1b.X then SwapPoints(Pt1a, Pt1b);
    if Pt2a.X > Pt2b.X then SwapPoints(Pt2a, Pt2b);
    if (Pt1a.X > Pt2a.X) then Pt1 := Pt1a else Pt1 := Pt2a;
    if (Pt1b.X < Pt2b.X) then Pt2 := Pt1b else Pt2 := Pt2b;
    Result := Pt1.X < Pt2.X;
  end else
  begin
    if Pt1a.Y < Pt1b.Y then SwapPoints(Pt1a, Pt1b);
    if Pt2a.Y < Pt2b.Y then SwapPoints(Pt2a, Pt2b);
    if (Pt1a.Y < Pt2a.Y) then Pt1 := Pt1a else Pt1 := Pt2a;
    if (Pt1b.Y > Pt2b.Y) then Pt2 := Pt1b else Pt2 := Pt2b;
    Result := Pt1.Y > Pt2.Y;
  end;
end;
//------------------------------------------------------------------------------

function E2InsertsBeforeE1(E1, E2: PEdge): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  if E2.XCurr = E1.XCurr then
  begin
    if E2.YTop > E1.YTop then
      Result := E2.XTop < TopX(E1, E2.YTop) else
      Result := E1.XTop > TopX(E2, E1.YTop);
  end else
    Result := E2.XCurr < E1.XCurr;
end;
//----------------------------------------------------------------------


procedure TClipper.InsertLocalMinimaIntoAEL(const BotY: Int64);

  procedure InsertEdgeIntoAEL(Edge: PEdge);
  var
    E: PEdge;
  begin
    Edge.PrevInAEL := nil;
    Edge.NextInAEL := nil;
    if not Assigned(fActiveEdges) then
    begin
      FActiveEdges := Edge;
    end else if E2InsertsBeforeE1(fActiveEdges, Edge) then
    begin
      Edge.NextInAEL := FActiveEdges;
      FActiveEdges.PrevInAEL := Edge;
      FActiveEdges := Edge;
    end else
    begin
      E := FActiveEdges;
      while Assigned(E.NextInAEL) and
        not E2InsertsBeforeE1(E.NextInAEL, Edge) do
          E := E.NextInAEL;
      Edge.NextInAEL := E.NextInAEL;
      if Assigned(E.NextInAEL) then E.NextInAEL.PrevInAEL := Edge;
      Edge.PrevInAEL := E;
      E.NextInAEL := Edge;
    end;
  end;
  //----------------------------------------------------------------------

var
  E: PEdge;
  Pt, Pt2: TIntPoint;
  Lb, Rb: PEdge;
  Hj: PHorzRec;
begin
  while Assigned(CurrentLm) and (CurrentLm.Y = BotY) do
  begin
    Lb := CurrentLm.LeftBound;
    Rb := CurrentLm.RightBound;

    InsertEdgeIntoAEL(Lb);
    InsertScanbeam(Lb.YTop);
    InsertEdgeIntoAEL(Rb);

    //set Edge winding states ...
    if IsEvenOddFillType(Lb) then
    begin
      Lb.WindDelta := 1;
      Rb.WindDelta := 1;
    end else
    begin
      Rb.WindDelta := -Lb.WindDelta
    end;
    SetWindingCount(Lb);
    Rb.WindCnt := Lb.WindCnt;
    Rb.WindCnt2 := Lb.WindCnt2;

    if Rb.Dx = Horizontal then
    begin
      AddEdgeToSEL(Rb);
      InsertScanbeam(Rb.NextInLML.YTop);
    end else
      InsertScanbeam(Rb.YTop);

    if IsContributing(Lb) then
      AddLocalMinPoly(Lb, Rb, IntPoint(Lb.XCurr, CurrentLm.Y));

    //if output polygons share an Edge with rb, they'll need joining later ...
    if (Rb.OutIdx >= 0) and (Rb.Dx = Horizontal) and Assigned(fHorizJoins) then
    begin
      Hj := FHorizJoins;
      repeat
        //if horizontals rb & hj.Edge overlap, flag for joining later ...
        if GetOverlapSegment(IntPoint(Hj.Edge.XBot, Hj.Edge.YBot),
          IntPoint(Hj.Edge.XTop, Hj.Edge.YTop), IntPoint(Rb.XBot, Rb.YBot),
          IntPoint(Rb.XTop, Rb.YTop), Pt, Pt2) then
            AddJoin(Hj.Edge, Rb, Hj.SavedIdx);
        Hj := Hj.Next;
      until Hj = FHorizJoins;
    end;

    if (Lb.NextInAEL <> Rb) then
    begin
      if (Rb.OutIdx >= 0) and (Rb.PrevInAEL.OutIdx >= 0) and
        SlopesEqual(Rb.PrevInAEL, Rb, FUse64BitRange) then
          AddJoin(Rb, Rb.PrevInAEL);

      E := Lb.NextInAEL;
      Pt := IntPoint(Lb.XCurr,Lb.YCurr);
      while E <> Rb do
      begin
        if not Assigned(E) then raise exception.Create(rsMissingRightbound);
        //nb: For calculating winding counts etc, IntersectEdges() assumes
        //that param1 will be to the right of param2 ABOVE the intersection ...
        IntersectEdges(Rb, E, Pt);
        E := E.NextInAEL;
      end;
    end;
    PopLocalMinima;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.DeleteFromAEL(E: PEdge);
var
  AelPrev, AelNext: PEdge;
begin
  AelPrev := E.PrevInAEL;
  AelNext := E.NextInAEL;
  if not Assigned(AelPrev) and not Assigned(AelNext) and
    (E <> FActiveEdges) then Exit; //already deleted
  if Assigned(AelPrev) then AelPrev.NextInAEL := AelNext
  else FActiveEdges := AelNext;
  if Assigned(AelNext) then AelNext.PrevInAEL := AelPrev;
  E.NextInAEL := nil;
  E.PrevInAEL := nil;
end;
//------------------------------------------------------------------------------

procedure TClipper.DeleteFromSEL(E: PEdge);
var
  SelPrev, SelNext: PEdge;
begin
  SelPrev := E.PrevInSEL;
  SelNext := E.NextInSEL;
  if not Assigned(SelPrev) and not Assigned(SelNext) and
    (E <> FSortedEdges) then Exit; //already deleted
  if Assigned(SelPrev) then SelPrev.NextInSEL := SelNext
  else FSortedEdges := SelNext;
  if Assigned(SelNext) then SelNext.PrevInSEL := SelPrev;
  E.NextInSEL := nil;
  E.PrevInSEL := nil;
end;
//------------------------------------------------------------------------------

procedure TClipper.IntersectEdges(E1,E2: PEdge;
  const Pt: TIntPoint; protects: TIntersectProtects = []);
var
  E1stops, E2stops: Boolean;
  E1Contributing, E2contributing: Boolean;
  E1FillType, E2FillType, E1FillType2, E2FillType2: TPolyFillType;
  E1Wc, E2Wc, E1Wc2, E2Wc2: Integer;
begin
  {IntersectEdges}

  //E1 will be to the left of E2 BELOW the intersection. Therefore E1 is before
  //E2 in AEL except when E1 is being inserted at the intersection point ...

  E1stops := not (ipLeft in protects) and not Assigned(E1.NextInLML) and
    (E1.XTop = Pt.x) and (E1.YTop = Pt.Y);
  E2stops := not (ipRight in protects) and not Assigned(E2.NextInLML) and
    (E2.XTop = Pt.x) and (E2.YTop = Pt.Y);
  E1Contributing := (E1.OutIdx >= 0);
  E2contributing := (E2.OutIdx >= 0);

  //update winding counts...
  //assumes that E1 will be to the right of E2 ABOVE the intersection
  if E1.PolyType = E2.PolyType then
  begin
    if IsEvenOddFillType(E1) then
    begin
      E1Wc := E1.WindCnt;
      E1.WindCnt := E2.WindCnt;
      E2.WindCnt := E1Wc;
    end else
    begin
      if E1.WindCnt + E2.WindDelta = 0 then
        E1.WindCnt := -E1.WindCnt else
        Inc(E1.WindCnt, E2.WindDelta);
      if E2.WindCnt - E1.WindDelta = 0 then
        E2.WindCnt := -E2.WindCnt else
        Dec(E2.WindCnt, E1.WindDelta);
    end;
  end else
  begin
    if not IsEvenOddFillType(E2) then Inc(E1.WindCnt2, E2.WindDelta)
    else if E1.WindCnt2 = 0 then E1.WindCnt2 := 1
    else E1.WindCnt2 := 0;
    if not IsEvenOddFillType(E1) then Dec(E2.WindCnt2, E1.WindDelta)
    else if E2.WindCnt2 = 0 then E2.WindCnt2 := 1
    else E2.WindCnt2 := 0;
  end;

  if E1.PolyType = ptSubject then
  begin
    E1FillType := FSubjFillType;
    E1FillType2 := FClipFillType;
  end else
  begin
    E1FillType := FClipFillType;
    E1FillType2 := FSubjFillType;
  end;
  if E2.PolyType = ptSubject then
  begin
    E2FillType := FSubjFillType;
    E2FillType2 := FClipFillType;
  end else
  begin
    E2FillType := FClipFillType;
    E2FillType2 := FSubjFillType;
  end;

  case E1FillType of
    pftPositive: E1Wc := E1.WindCnt;
    pftNegative : E1Wc := -E1.WindCnt;
    else E1Wc := abs(E1.WindCnt);
  end;
  case E2FillType of
    pftPositive: E2Wc := E2.WindCnt;
    pftNegative : E2Wc := -E2.WindCnt;
    else E2Wc := abs(E2.WindCnt);
  end;

  if E1Contributing and E2contributing then
  begin
    if E1stops or E2stops or not (E1Wc in [0,1]) or not (E2Wc in [0,1]) or
      ((E1.PolyType <> E2.PolyType) and (fClipType <> ctXor)) then
        AddLocalMaxPoly(E1, E2, Pt)
    else
    begin
      AddOutPt(E1, Pt);
      AddOutPt(E2, Pt);
      SwapSides(E1, E2);
      SwapPolyIndexes(E1, E2);
    end;
  end else if E1Contributing then
  begin
    if (E2Wc = 0) or (E2Wc = 1) then
    begin
      AddOutPt(E1, Pt);
      SwapSides(E1, E2);
      SwapPolyIndexes(E1, E2);
    end;
  end
  else if E2contributing then
  begin
    if (E1Wc = 0) or (E1Wc = 1) then
    begin
      AddOutPt(E2, Pt);
      SwapSides(E1, E2);
      SwapPolyIndexes(E1, E2);
    end;
  end
  else if  ((E1Wc = 0) or (E1Wc = 1)) and ((E2Wc = 0) or (E2Wc = 1)) and
    not E1stops and not E2stops then
  begin
    //neither Edge is currently contributing ...

    case E1FillType2 of
      pftPositive: E1Wc2 := E1.WindCnt2;
      pftNegative : E1Wc2 := -E1.WindCnt2;
      else E1Wc2 := abs(E1.WindCnt2);
    end;
    case E2FillType2 of
      pftPositive: E2Wc2 := E2.WindCnt2;
      pftNegative : E2Wc2 := -E2.WindCnt2;
      else E2Wc2 := abs(E2.WindCnt2);
    end;

    if (E1.PolyType <> E2.PolyType) then
      AddLocalMinPoly(E1, E2, Pt)
    else if (E1Wc = 1) and (E2Wc = 1) then
      case FClipType of
        ctIntersection:
          if (E1Wc2 > 0) and (E2Wc2 > 0) then
            AddLocalMinPoly(E1, E2, Pt);
        ctUnion:
          if (E1Wc2 <= 0) and (E2Wc2 <= 0) then
            AddLocalMinPoly(E1, E2, Pt);
        ctDifference:
          if ((E1.PolyType = ptClip) and (E1Wc2 > 0) and (E2Wc2 > 0)) or
            ((E1.PolyType = ptSubject) and (E1Wc2 <= 0) and (E2Wc2 <= 0)) then
              AddLocalMinPoly(E1, E2, Pt);
        ctXor:
          AddLocalMinPoly(E1, E2, Pt);
      end
    else
      swapsides(E1,E2);
  end;

  if (E1stops <> E2stops) and
    ((E1stops and (E1.OutIdx >= 0)) or (E2stops and (E2.OutIdx >= 0))) then
  begin
    swapsides(E1,E2);
    SwapPolyIndexes(E1, E2);
  end;

  //finally, delete any non-contributing maxima edges  ...
  if E1stops then deleteFromAEL(E1);
  if E2stops then deleteFromAEL(E2);
end;
//------------------------------------------------------------------------------

function FirstParamIsBottomPt(btmPt1, btmPt2: POutPt): Boolean;
var
  Dx1n, Dx1p, Dx2n, Dx2p: Double;
  P: POutPt;
begin
  //Precondition: bottom-points share the same vertex.
  //Use inverse slopes of adjacent edges (ie dx/dy) to determine the outer
  //polygon and hence the 'real' bottompoint.
  //nb: Slope is vertical when dx == 0. If the greater abs(dx) of param1
  //is greater than or equal both abs(dx) in param2 then param1 is outer.
  P := btmPt1.Prev;
  while PointsEqual(P.Pt, btmPt1.Pt) and (P <> btmPt1) do P := P.Prev;
  Dx1p := abs(GetDx(btmPt1.Pt, P.Pt));
  P := btmPt1.Next;
  while PointsEqual(P.Pt, btmPt1.Pt) and (P <> btmPt1) do P := P.Next;
  Dx1n := abs(GetDx(btmPt1.Pt, P.Pt));

  P := btmPt2.Prev;
  while PointsEqual(P.Pt, btmPt2.Pt) and (P <> btmPt2) do P := P.Prev;
  Dx2p := abs(GetDx(btmPt2.Pt, P.Pt));
  P := btmPt2.Next;
  while PointsEqual(P.Pt, btmPt2.Pt) and (P <> btmPt2) do P := P.Next;
  Dx2n := abs(GetDx(btmPt2.Pt, P.Pt));
  Result := ((Dx1p >= Dx2p) and (Dx1p >= Dx2n)) or
    ((Dx1n >= Dx2p) and (Dx1n >= Dx2n));
end;
//------------------------------------------------------------------------------

function GetBottomPt(PP: POutPt): POutPt;
var
  P, Dups: POutPt;
begin
  Dups := nil;
  P := PP.Next;
  while P <> PP do
  begin
    if P.Pt.Y > PP.Pt.Y then
    begin
      PP := P;
      Dups := nil;
    end
    else if (P.Pt.Y = PP.Pt.Y) and (P.Pt.X <= PP.Pt.X) then
    begin
      if (P.Pt.X < PP.Pt.X) then
      begin
        Dups := nil;
        PP := P;
      end else
      begin
        if (P.Next <> PP) and (P.Prev <> PP) then Dups := P;
      end;
    end;
    P := P.Next;
  end;
  if Assigned(Dups) then
  begin
    //there appears to be at least 2 vertices at bottom-most point so ...
    while Dups <> P do
    begin
      if not FirstParamIsBottomPt(P, Dups) then PP := Dups;
      Dups := Dups.Next;
      while not PointsEqual(Dups.Pt, PP.Pt) do Dups := Dups.Next;
    end;
  end;
  Result := PP;
end;
//------------------------------------------------------------------------------

procedure TClipper.SetHoleState(E: PEdge; OutRec: POutRec);
var
  E2: PEdge;
  IsHole: Boolean;
begin
  IsHole := False;
  E2 := E.PrevInAEL;
  while Assigned(E2) do
  begin
    if (E2.OutIdx >= 0) then
    begin
      IsHole := not IsHole;
      if not Assigned(OutRec.FirstLeft) then
        OutRec.FirstLeft := POutRec(fPolyOutList[E2.OutIdx]);
    end;
    E2 := E2.PrevInAEL;
  end;
  if IsHole then
    OutRec.IsHole := True;
end;
//------------------------------------------------------------------------------

function GetLowermostRec(OutRec1, OutRec2: POutRec): POutRec;
var
  OutPt1, OutPt2: POutPt;
begin
  if not assigned(OutRec1.BottomPt) then
    OutRec1.BottomPt := GetBottomPt(OutRec1.Pts);
  if not assigned(OutRec2.BottomPt) then
    OutRec2.BottomPt := GetBottomPt(OutRec2.Pts);
  OutPt1 := OutRec1.BottomPt;
  OutPt2 := OutRec2.BottomPt;
  if (OutPt1.Pt.Y > OutPt2.Pt.Y) then Result := OutRec1
  else if (OutPt1.Pt.Y < OutPt2.Pt.Y) then Result := OutRec2
  else if (OutPt1.Pt.X < OutPt2.Pt.X) then Result := OutRec1
  else if (OutPt1.Pt.X > OutPt2.Pt.X) then Result := OutRec2
  else if (OutPt1.Next = OutPt1) then Result := OutRec2
  else if (OutPt2.Next = OutPt2) then Result := OutRec1
  else if FirstParamIsBottomPt(OutPt1, OutPt2) then Result := OutRec1
  else Result := OutRec2;
end;
//------------------------------------------------------------------------------

function Param1RightOfParam2(OutRec1, OutRec2: POutRec): Boolean;
begin
  Result := True;
  repeat
    OutRec1 := OutRec1.FirstLeft;
    if OutRec1 = OutRec2 then Exit;
  until not Assigned(OutRec1);
  Result := False;
end;
//------------------------------------------------------------------------------

function TClipper.GetOutRec(Idx: integer): POutRec;
begin
  Result := FPolyOutList[Idx];
  while Result <> FPolyOutList[Result.Idx] do
    Result := FPolyOutList[Result.Idx];
end;
//------------------------------------------------------------------------------

procedure TClipper.AppendPolygon(E1, E2: PEdge);
var
  HoleStateRec, OutRec1, OutRec2: POutRec;
  P1_lft, P1_rt, P2_lft, P2_rt: POutPt;
  NewSide: TEdgeSide;
  OKIdx, ObsoleteIdx: Integer;
  E: PEdge;
begin
  OutRec1 := FPolyOutList[E1.OutIdx];
  OutRec2 := FPolyOutList[E2.OutIdx];

  //First work out which polygon fragment has the correct hole state.
  //Since we're working from the bottom upward and left to right, the left most
  //and lowermost polygon is outermost and must have the correct hole state ...
  if Param1RightOfParam2(OutRec1, OutRec2) then HoleStateRec := OutRec2
  else if Param1RightOfParam2(OutRec2, OutRec1) then HoleStateRec := OutRec1
  else HoleStateRec := GetLowermostRec(OutRec1, OutRec2);

  //get the start and ends of both output polygons ...
  P1_lft := OutRec1.Pts;
  P2_lft := OutRec2.Pts;
  P1_rt := P1_lft.Prev;
  P2_rt := P2_lft.Prev;

  //join E2 poly onto E1 poly and delete pointers to E2 ...
  if E1.Side = esLeft then
  begin
    if E2.Side = esLeft then
    begin
      //z y x a b c
      ReversePolyPtLinks(P2_lft);
      P2_lft.Next := P1_lft;
      P1_lft.Prev := P2_lft;
      P1_rt.Next := P2_rt;
      P2_rt.Prev := P1_rt;
      OutRec1.Pts := P2_rt;
    end else
    begin
      //x y z a b c
      P2_rt.Next := P1_lft;
      P1_lft.Prev := P2_rt;
      P2_lft.Prev := P1_rt;
      P1_rt.Next := P2_lft;
      OutRec1.Pts := P2_lft;
    end;
    NewSide := esLeft;
  end else
  begin
    if E2.Side = esRight then
    begin
      //a b c z y x
      ReversePolyPtLinks(P2_lft);
      P1_rt.Next := P2_rt;
      P2_rt.Prev := P1_rt;
      P2_lft.Next := P1_lft;
      P1_lft.Prev := P2_lft;
    end else
    begin
      //a b c x y z
      P1_rt.Next := P2_lft;
      P2_lft.Prev := P1_rt;
      P1_lft.Prev := P2_rt;
      P2_rt.Next := P1_lft;
    end;
    NewSide := esRight;
  end;

  OutRec1.BottomPt := nil;
  if HoleStateRec = OutRec2 then
  begin
    if OutRec2.FirstLeft <> OutRec1 then
      OutRec1.FirstLeft := OutRec2.FirstLeft;
    OutRec1.IsHole := OutRec2.IsHole;
  end;

  OutRec2.Pts := nil;
  OutRec2.BottomPt := nil;
  OutRec2.FirstLeft := OutRec1;

  OKIdx := OutRec1.Idx;
  ObsoleteIdx := OutRec2.Idx;

  E1.OutIdx := -1; //nb: safe because we only get here via AddLocalMaxPoly
  E2.OutIdx := -1;

  E := FActiveEdges;
  while Assigned(E) do
  begin
    if (E.OutIdx = ObsoleteIdx) then
    begin
      E.OutIdx := OKIdx;
      E.Side := NewSide;
      Break;
    end;
    E := E.NextInAEL;
  end;

  OutRec2.Idx := OutRec1.Idx;
end;
//------------------------------------------------------------------------------

function TClipper.CreateOutRec: POutRec;
begin
  new(Result);
  Result.IsHole := False;
  Result.FirstLeft := nil;
  Result.Pts := nil;
  Result.BottomPt := nil;
  Result.PolyNode := nil;
  Result.Idx := FPolyOutList.Add(Result);
end;
//------------------------------------------------------------------------------

procedure TClipper.AddOutPt(E: PEdge; const Pt: TIntPoint);
var
  OutRec: POutRec;
  NewOp, Op: POutPt;
  ToFront: Boolean;
begin
  ToFront := E.Side = esLeft;
  if E.OutIdx < 0 then
  begin
    OutRec := CreateOutRec;
    E.OutIdx := OutRec.Idx;
    new(NewOp);
    OutRec.Pts := NewOp;
    NewOp.Next := NewOp;
    NewOp.Prev := NewOp;
    NewOp.Idx := OutRec.Idx;
    SetHoleState(E, OutRec);
  end else
  begin
    OutRec := FPolyOutList[E.OutIdx];
    Op := OutRec.Pts;
    if (ToFront and PointsEqual(Pt, Op.Pt)) or
      (not ToFront and PointsEqual(Pt, Op.Prev.Pt)) then Exit;
    new(NewOp);
    NewOp.Idx := OutRec.Idx;
    NewOp.Next := Op;
    NewOp.Prev := Op.Prev;
    Op.Prev.Next := NewOp;
    Op.Prev := NewOp;
    if ToFront then OutRec.Pts := NewOp;
  end;
  NewOp.Pt := Pt;
end;
//------------------------------------------------------------------------------

procedure TClipper.ProcessHorizontals;
var
  E: PEdge;
begin
  while Assigned(fSortedEdges) do
  begin
    E := FSortedEdges;
    DeleteFromSEL(E);
    ProcessHorizontal(E);
  end;
end;
//------------------------------------------------------------------------------

function TClipper.IsTopHorz(const XPos: Int64): Boolean;
var
  E: PEdge;
begin
  Result := False;
  E := FSortedEdges;
  while Assigned(E) do
  begin
    if (XPos >= min(E.XCurr,E.XTop)) and (XPos <= max(E.XCurr,E.XTop)) then Exit;
    E := E.NextInSEL;
  end;
  Result := True;
end;
//------------------------------------------------------------------------------

function IsMinima(E: PEdge): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  Result := Assigned(E) and (E.Prev.NextInLML <> E) and (E.Next.NextInLML <> E);
end;
//------------------------------------------------------------------------------

function IsMaxima(E: PEdge; const Y: Int64): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  Result := Assigned(E) and (E.YTop = Y) and not Assigned(E.NextInLML);
end;
//------------------------------------------------------------------------------

function IsIntermediate(E: PEdge; const Y: Int64): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  Result := (E.YTop = Y) and Assigned(E.NextInLML);
end;
//------------------------------------------------------------------------------

function GetMaximaPair(E: PEdge): PEdge;
begin
  Result := E.Next;
  if not IsMaxima(Result, E.YTop) or (Result.XTop <> E.XTop) then
    Result := E.Prev;
end;
//------------------------------------------------------------------------------

procedure TClipper.SwapPositionsInAEL(E1, E2: PEdge);
var
  Prev,Next: PEdge;
begin
  if E1.NextInAEL = E2 then
  begin
    Next := E2.NextInAEL;
    if Assigned(Next) then Next.PrevInAEL := E1;
    Prev := E1.PrevInAEL;
    if Assigned(Prev) then Prev.NextInAEL := E2;
    E2.PrevInAEL := Prev;
    E2.NextInAEL := E1;
    E1.PrevInAEL := E2;
    E1.NextInAEL := Next;
  end
  else if E2.NextInAEL = E1 then
  begin
    Next := E1.NextInAEL;
    if Assigned(Next) then Next.PrevInAEL := E2;
    Prev := E2.PrevInAEL;
    if Assigned(Prev) then Prev.NextInAEL := E1;
    E1.PrevInAEL := Prev;
    E1.NextInAEL := E2;
    E2.PrevInAEL := E1;
    E2.NextInAEL := Next;
  end else
  begin
    Next := E1.NextInAEL;
    Prev := E1.PrevInAEL;
    E1.NextInAEL := E2.NextInAEL;
    if Assigned(E1.NextInAEL) then E1.NextInAEL.PrevInAEL := E1;
    E1.PrevInAEL := E2.PrevInAEL;
    if Assigned(E1.PrevInAEL) then E1.PrevInAEL.NextInAEL := E1;
    E2.NextInAEL := Next;
    if Assigned(E2.NextInAEL) then E2.NextInAEL.PrevInAEL := E2;
    E2.PrevInAEL := Prev;
    if Assigned(E2.PrevInAEL) then E2.PrevInAEL.NextInAEL := E2;
  end;
  if not Assigned(E1.PrevInAEL) then FActiveEdges := E1
  else if not Assigned(E2.PrevInAEL) then FActiveEdges := E2;
end;
//------------------------------------------------------------------------------

procedure TClipper.SwapPositionsInSEL(E1, E2: PEdge);
var
  Prev,Next: PEdge;
begin
  if E1.NextInSEL = E2 then
  begin
    Next    := E2.NextInSEL;
    if Assigned(Next) then Next.PrevInSEL := E1;
    Prev    := E1.PrevInSEL;
    if Assigned(Prev) then Prev.NextInSEL := E2;
    E2.PrevInSEL := Prev;
    E2.NextInSEL := E1;
    E1.PrevInSEL := E2;
    E1.NextInSEL := Next;
  end
  else if E2.NextInSEL = E1 then
  begin
    Next    := E1.NextInSEL;
    if Assigned(Next) then Next.PrevInSEL := E2;
    Prev    := E2.PrevInSEL;
    if Assigned(Prev) then Prev.NextInSEL := E1;
    E1.PrevInSEL := Prev;
    E1.NextInSEL := E2;
    E2.PrevInSEL := E1;
    E2.NextInSEL := Next;
  end else
  begin
    Next    := E1.NextInSEL;
    Prev    := E1.PrevInSEL;
    E1.NextInSEL := E2.NextInSEL;
    if Assigned(E1.NextInSEL) then E1.NextInSEL.PrevInSEL := E1;
    E1.PrevInSEL := E2.PrevInSEL;
    if Assigned(E1.PrevInSEL) then E1.PrevInSEL.NextInSEL := E1;
    E2.NextInSEL := Next;
    if Assigned(E2.NextInSEL) then E2.NextInSEL.PrevInSEL := E2;
    E2.PrevInSEL := Prev;
    if Assigned(E2.PrevInSEL) then E2.PrevInSEL.NextInSEL := E2;
  end;
  if not Assigned(E1.PrevInSEL) then FSortedEdges := E1
  else if not Assigned(E2.PrevInSEL) then FSortedEdges := E2;
end;
//------------------------------------------------------------------------------

procedure TClipper.ProcessHorizontal(HorzEdge: PEdge);

  function GetNextInAEL(E: PEdge; Direction: TDirection): PEdge;
  begin
    if Direction = dLeftToRight then
      Result := E.NextInAEL else
      Result := E.PrevInAEL;
  end;
  //------------------------------------------------------------------------

var
  E, eNext, eMaxPair: PEdge;
  HorzLeft, HorzRight: Int64;
  Direction: TDirection;
const
  ProtectLeft: array[Boolean] of TIntersectProtects = ([ipRight], [ipLeft,ipRight]);
  ProtectRight: array[Boolean] of TIntersectProtects = ([ipLeft], [ipLeft,ipRight]);
begin
(*******************************************************************************
* Notes: Horizontal edges (HEs) at scanline intersections (ie at the top or    *
* bottom of a scanbeam) are processed as if layered. The order in which HEs    *
* are processed doesn't matter. HEs intersect with other HE xbots only [#],    *
* and with other non-horizontal edges [*]. Once these intersections are        *
* processed, intermediate HEs then 'promote' the Edge above (NextInLML) into   *
* the AEL. These 'promoted' edges may in turn intersect [%] with other HEs.    *
*******************************************************************************)

(*******************************************************************************
*           \   nb: HE processing order doesn't matter         /          /    *
*            \                                                /          /     *
* { --------  \  -------------------  /  \  - (3) o==========%==========o  - } *
* {            o==========o (2)      /    \       .          .               } *
* {                       .         /      \      .          .               } *
* { ----  o===============#========*========*=====#==========o  (1)  ------- } *
*        /                 \      /          \   /                             *
*******************************************************************************)

  if HorzEdge.XCurr < HorzEdge.XTop then
  begin
    HorzLeft := HorzEdge.XCurr;
    HorzRight := HorzEdge.XTop;
    Direction := dLeftToRight;
  end else
  begin
    HorzLeft := HorzEdge.XTop;
    HorzRight := HorzEdge.XCurr;
    Direction := dRightToLeft;
  end;

  if Assigned(HorzEdge.NextInLML) then
    eMaxPair := nil else
    eMaxPair := GetMaximaPair(HorzEdge);

  E := GetNextInAEL(HorzEdge, Direction);
  while Assigned(E) do
  begin
    if (E.XCurr = HorzEdge.XTop) and not Assigned(eMaxPair) then
    begin
      if SlopesEqual(E, HorzEdge.NextInLML, FUse64BitRange) then
      begin
        //if output polygons share an Edge, they'll need joining later ...
        if (HorzEdge.OutIdx >= 0) and (E.OutIdx >= 0) then
          AddJoin(HorzEdge.NextInLML, E, HorzEdge.OutIdx);
        Break; //we've reached the end of the horizontal line
      end
      else if (E.Dx < HorzEdge.NextInLML.Dx) then
      //we really have got to the end of the intermediate horz Edge so quit.
      //nb: More -ve slopes follow more +ve slopes ABOVE the horizontal.
        Break;
    end;

    eNext := GetNextInAEL(E, Direction);
    if Assigned(eMaxPair) or
       ((Direction = dLeftToRight) and (E.XCurr < HorzRight)) or
      ((Direction = dRightToLeft) and (E.XCurr > HorzLeft)) then
    begin
      //so far we're still in range of the horizontal Edge
      if (E = eMaxPair) then
      begin
        //HorzEdge is evidently a maxima horizontal and we've arrived at its end.
        if Direction = dLeftToRight then
          IntersectEdges(HorzEdge, E, IntPoint(E.XCurr, HorzEdge.YCurr)) else
          IntersectEdges(E, HorzEdge, IntPoint(E.XCurr, HorzEdge.YCurr));

        if (eMaxPair.OutIdx >= 0) then raise exception.Create(rsHorizontal);
        Exit;
      end
      else if (E.Dx = Horizontal) and not IsMinima(E) and not (E.XCurr > E.XTop) then
      begin
        //An overlapping horizontal Edge. Overlapping horizontal edges are
        //processed as if layered with the current horizontal Edge (horizEdge)
        //being infinitesimally lower that the Next (E). Therfore, we
        //intersect with E only if E.XCurr is within the bounds of HorzEdge ...
        if Direction = dLeftToRight then
          IntersectEdges(HorzEdge, E, IntPoint(E.XCurr, HorzEdge.YCurr),
            ProtectRight[not IsTopHorz(E.XCurr)])
        else
          IntersectEdges(E, HorzEdge, IntPoint(E.XCurr, HorzEdge.YCurr),
            ProtectLeft[not IsTopHorz(E.XCurr)]);
      end
      else if (Direction = dLeftToRight) then
        IntersectEdges(HorzEdge, E, IntPoint(E.XCurr, HorzEdge.YCurr),
          ProtectRight[not IsTopHorz(E.XCurr)])
      else
        IntersectEdges(E, HorzEdge, IntPoint(E.XCurr, HorzEdge.YCurr),
          ProtectLeft[not IsTopHorz(E.XCurr)]);
      SwapPositionsInAEL(HorzEdge, E);
    end
    else if ((Direction = dLeftToRight) and (E.XCurr >= HorzRight)) or
      ((Direction = dRightToLeft) and (E.XCurr <= HorzLeft)) then
        Break;
    E := eNext;
  end;

  if Assigned(HorzEdge.NextInLML) then
  begin
    if (HorzEdge.OutIdx >= 0) then
      AddOutPt(HorzEdge, IntPoint(HorzEdge.XTop, HorzEdge.YTop));
    UpdateEdgeIntoAEL(HorzEdge);
  end else
  begin
    if HorzEdge.OutIdx >= 0 then
      IntersectEdges(HorzEdge, eMaxPair,
        IntPoint(HorzEdge.XTop, HorzEdge.YCurr), [ipLeft,ipRight]);

    if eMaxPair.OutIdx >= 0 then raise exception.Create(rsHorizontal);
    DeleteFromAEL(eMaxPair);
    DeleteFromAEL(HorzEdge);
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.UpdateEdgeIntoAEL(var E: PEdge);
var
  AelPrev, AelNext: PEdge;
begin
  if not Assigned(E.NextInLML) then raise exception.Create(rsUpdateEdgeIntoAEL);
  AelPrev := E.PrevInAEL;
  AelNext := E.NextInAEL;
  E.NextInLML.OutIdx := E.OutIdx;
  if Assigned(AelPrev) then
    AelPrev.NextInAEL := E.NextInLML else
    FActiveEdges := E.NextInLML;
  if Assigned(AelNext) then
    AelNext.PrevInAEL := E.NextInLML;
  E.NextInLML.Side := E.Side;
  E.NextInLML.WindDelta := E.WindDelta;
  E.NextInLML.WindCnt := E.WindCnt;
  E.NextInLML.WindCnt2 := E.WindCnt2;
  E := E.NextInLML;
  E.PrevInAEL := AelPrev;
  E.NextInAEL := AelNext;
  if E.Dx <> Horizontal then
    InsertScanbeam(E.YTop);
end;
//------------------------------------------------------------------------------

function TClipper.ProcessIntersections(const BotY, TopY: Int64): Boolean;
begin
  Result := True;
  try
    BuildIntersectList(BotY, TopY);
    if (FIntersectNodes = nil) then Exit;
    if (FIntersectNodes.Next = nil) or FixupIntersectionOrder then
      ProcessIntersectList
    else
      Result := False;
  finally
    DisposeIntersectNodes; //clean up if there's been an error
    FSortedEdges := nil;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.DisposeIntersectNodes;
var
  N: PIntersectNode;
begin
  while Assigned(fIntersectNodes) do
  begin
    N := FIntersectNodes.Next;
    dispose(fIntersectNodes);
    FIntersectNodes := N;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.BuildIntersectList(const BotY, TopY: Int64);
var
  E, eNext: PEdge;
  Pt: TIntPoint;
  IsModified: Boolean;
begin
  if not Assigned(fActiveEdges) then Exit;

  //prepare for sorting ...
  E := FActiveEdges;
  FSortedEdges := E;
  while Assigned(E) do
  begin
    E.PrevInSEL := E.PrevInAEL;
    E.NextInSEL := E.NextInAEL;
    E.XCurr := TopX(E, TopY);
    E := E.NextInAEL;
  end;

  //bubblesort ...
  repeat
    IsModified := False;
    E := FSortedEdges;
    while Assigned(E.NextInSEL) do
    begin
      eNext := E.NextInSEL;
      if (E.XCurr > eNext.XCurr) then
      begin
        if not IntersectPoint(E, eNext, Pt, FUse64BitRange) and
          (E.XCurr > eNext.XCurr +1) then
            raise Exception.Create(rsIntersect);
        if Pt.Y > BotY then
        begin
          Pt.Y := BotY;
          Pt.X := TopX(E, Pt.Y);
        end;
        InsertIntersectNode(E, eNext, Pt);
        SwapPositionsInSEL(E, eNext);
        IsModified := True;
      end else
        E := eNext;
    end;
    if Assigned(E.PrevInSEL) then
      E.PrevInSEL.NextInSEL := nil
    else Break;
  until not IsModified;
end;
//------------------------------------------------------------------------------

procedure TClipper.InsertIntersectNode(E1, E2: PEdge; const Pt: TIntPoint);
var
  Node, NewNode: PIntersectNode;
begin
  new(NewNode);
  NewNode.Edge1 := E1;
  NewNode.Edge2 := E2;
  NewNode.Pt := Pt;
  NewNode.Next := nil;
  if not Assigned(fIntersectNodes) then
    FIntersectNodes := NewNode
  else if NewNode.Pt.Y > FIntersectNodes.Pt.Y then
  begin
    NewNode.Next := FIntersectNodes;
    FIntersectNodes := NewNode;
  end else
  begin
    Node := FIntersectNodes;
    while Assigned(Node.Next) and (NewNode.Pt.Y <= Node.Next.Pt.Y) do
      Node := Node.Next;
    NewNode.Next := Node.Next;
    Node.Next := NewNode;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.ProcessIntersectList;
var
  Node: PIntersectNode;
begin
  while Assigned(fIntersectNodes) do
  begin
    Node := FIntersectNodes.Next;
    with FIntersectNodes^ do
    begin
      IntersectEdges(Edge1, Edge2, Pt, [ipLeft,ipRight]);
      SwapPositionsInAEL(Edge1, Edge2);
    end;
    dispose(fIntersectNodes);
    FIntersectNodes := Node;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.DoMaxima(E: PEdge; const TopY: Int64);
var
  ENext, EMaxPair: PEdge;
  X: Int64;
begin
  EMaxPair := GetMaximaPair(E);
  X := E.XTop;
  ENext := E.NextInAEL;
  while ENext <> EMaxPair do
  begin
    if not Assigned(ENext) then raise exception.Create(rsDoMaxima);
    IntersectEdges(E, ENext, IntPoint(X, TopY), [ipLeft, ipRight]);
    SwapPositionsInAEL(E, ENext);
    ENext := E.NextInAEL;
  end;
  if (E.OutIdx < 0) and (EMaxPair.OutIdx < 0) then
  begin
    DeleteFromAEL(E);
    DeleteFromAEL(EMaxPair);
  end
  else if (E.OutIdx >= 0) and (EMaxPair.OutIdx >= 0) then
  begin
    IntersectEdges(E, EMaxPair, IntPoint(X, TopY));
  end
  else raise exception.Create(rsDoMaxima);
end;
//------------------------------------------------------------------------------

procedure TClipper.ProcessEdgesAtTopOfScanbeam(const TopY: Int64);
var
  E, ePrev, eNext: PEdge;
  Hj: PHorzRec;
  Pt, Pt2: TIntPoint;
  IntermediateVert: Boolean;
begin
(*******************************************************************************
* Notes: Processing edges at scanline intersections (ie at the top or bottom   *
* of a scanbeam) needs to be done in multiple stages and in the correct order. *
* Firstly, edges forming a 'maxima' need to be processed and then removed.     *
* Next, 'intermediate' and 'maxima' horizontal edges are processed. Then edges *
* that intersect exactly at the top of the scanbeam are processed [%].         *
* Finally, new minima are added and any intersects they create are processed.  *
*******************************************************************************)

(*******************************************************************************
*     \                          /    /          \   /                         *
*      \   Horizontal minima    /    /            \ /                          *
* { --  o======================#====o   --------   .     ------------------- } *
* {       Horizontal maxima    .                   %  scanline intersect     } *
* { -- o=======================#===================#========o     ---------- } *
*      |                      /                   / \        \                 *
*      + maxima intersect    /                   /   \        \                *
*     /|\                   /                   /     \        \               *
*    / | \                 /                   /       \        \              *
*******************************************************************************)

  E := FActiveEdges;
  while Assigned(E) do
  begin
    //1. process maxima, treating them as if they're 'bent' horizontal edges,
    //   but exclude maxima with Horizontal edges. nb: E can't be a Horizontal.
    if IsMaxima(E, TopY) and (GetMaximaPair(E).Dx <> Horizontal) then
    begin
      //'E' might be removed from AEL, as may any following edges so ...
      ePrev := E.PrevInAEL;
      DoMaxima(E, TopY);
      if not Assigned(ePrev) then
        E := FActiveEdges else
        E := ePrev.NextInAEL;
    end else
    begin
      IntermediateVert := IsIntermediate(E, TopY);
      //2. promote horizontal edges, otherwise update XCurr and YCurr ...
      if IntermediateVert and (E.NextInLML.Dx = Horizontal) then
      begin
        if (E.OutIdx >= 0) then
        begin
          AddOutPt(E, IntPoint(E.XTop, E.YTop));

          Hj := FHorizJoins;
          if Assigned(Hj) then
          repeat
            if GetOverlapSegment(IntPoint(Hj.Edge.XBot, Hj.Edge.YBot),
              IntPoint(Hj.Edge.XTop, Hj.Edge.YTop),
              IntPoint(E.NextInLML.XBot, E.NextInLML.YBot),
              IntPoint(E.NextInLML.XTop, E.NextInLML.YTop), Pt, Pt2) then
                AddJoin(Hj.Edge, E.NextInLML, Hj.SavedIdx, E.OutIdx);
            Hj := Hj.Next;
          until Hj = FHorizJoins;

          AddHorzJoin(E.NextInLML, E.OutIdx);
        end;
        UpdateEdgeIntoAEL(E);
        AddEdgeToSEL(E);
      end else
      begin
        E.XCurr := TopX(E, TopY);
        E.YCurr := TopY;

        if FForceSimple and Assigned(E.PrevInAEL) and
          (E.PrevInAEL.XCurr = E.XCurr) and
          (E.OutIdx >= 0) and (E.PrevInAEL.OutIdx >= 0) then
        begin
          if IntermediateVert then
            AddOutPt(E.PrevInAEL, IntPoint(E.XCurr, TopY))
          else
            AddOutPt(E, IntPoint(E.XCurr, TopY));
        end;
      end;
      E := E.NextInAEL;
    end;
  end;

  //3. Process horizontals at the top of the scanbeam ...
  ProcessHorizontals;

  //4. Promote intermediate vertices ...
  E := FActiveEdges;
  while Assigned(E) do
  begin
    if IsIntermediate(E, TopY) then
    begin
      if (E.OutIdx >= 0) then AddOutPt(E, IntPoint(E.XTop, E.YTop));
      UpdateEdgeIntoAEL(E);

      //if output polygons share an Edge, they'll need joining later ...
      ePrev := E.PrevInAEL;
      eNext  := E.NextInAEL;
      if Assigned(ePrev) and (ePrev.XCurr = E.XBot) and
        (ePrev.YCurr = E.YBot) and (E.OutIdx >= 0) and
        (ePrev.OutIdx >= 0) and (ePrev.YCurr > ePrev.YTop) and
        SlopesEqual(E, ePrev, FUse64BitRange) then
      begin
        AddOutPt(ePrev, IntPoint(E.XBot, E.YBot));
        AddJoin(E, ePrev);
      end
      else if Assigned(eNext) and (eNext.XCurr = E.XBot) and
        (eNext.YCurr = E.YBot) and (E.OutIdx >= 0) and
          (eNext.OutIdx >= 0) and (eNext.YCurr > eNext.YTop) and
        SlopesEqual(E, eNext, FUse64BitRange) then
      begin
        AddOutPt(eNext, IntPoint(E.XBot, E.YBot));
        AddJoin(E, eNext);
      end;
    end;
    E := E.NextInAEL;
  end;
end;
//------------------------------------------------------------------------------

function TClipper.GetResult: TPolygons;
var
  I, J, K, Cnt: Integer;
  OutRec: POutRec;
  Op: POutPt;
begin
  J := 0;
  SetLength(Result, FPolyOutList.Count);
  for I := 0 to FPolyOutList.Count -1 do
    if Assigned(fPolyOutList[I]) then
    begin
      OutRec := FPolyOutList[I];
      Cnt := PointCount(OutRec.Pts);
      if (Cnt < 3) then Continue;
      SetLength(Result[J], Cnt);
      Op := OutRec.Pts;
      for K := 0 to Cnt -1 do
      begin
        Result[J][K].X := Op.Pt.X;
        Result[J][K].Y := Op.Pt.Y;
        Op := Op.Prev;
      end;
      Inc(J);
    end;
  SetLength(Result, J);
end;
//------------------------------------------------------------------------------

function TClipper.GetResult2(PolyTree: TPolyTree): Boolean;
var
  I, J, Cnt, CntAll: Integer;
  Op: POutPt;
  OutRec: POutRec;
  PolyNode: TPolyNode;
begin
  try
    PolyTree.Clear;
    SetLength(PolyTree.FAllNodes, FPolyOutList.Count);

    //add PolyTree ...
    CntAll := 0;
    for I := 0 to FPolyOutList.Count -1 do
    begin
      OutRec := fPolyOutList[I];
      Cnt := PointCount(OutRec.Pts);
      if Cnt < 3 then Continue;
      FixHoleLinkage(OutRec);

      PolyNode := TPolyNode.Create;
      PolyTree.FAllNodes[CntAll] := PolyNode;
      OutRec.PolyNode := PolyNode;
      Inc(CntAll);
      SetLength(PolyNode.FPolygon, Cnt);
      Op := OutRec.Pts;
      for J := 0 to Cnt -1 do
      begin
        PolyNode.FPolygon[J].X := Op.Pt.X;
        PolyNode.FPolygon[J].Y := Op.Pt.Y;
        Op := Op.Prev;
      end;
    end;

    //fix Poly links ...
    SetLength(PolyTree.FAllNodes, CntAll);
    SetLength(PolyTree.FChilds, CntAll);
    for I := 0 to FPolyOutList.Count -1 do
    begin
      OutRec := fPolyOutList[I];
      if Assigned(OutRec.PolyNode) then
        if Assigned(OutRec.FirstLeft) then
          OutRec.FirstLeft.PolyNode.AddChild(OutRec.PolyNode) else
          PolyTree.AddChild(OutRec.PolyNode);
    end;
    SetLength(PolyTree.FChilds, PolyTree.FCount);
    Result := True;
  except
    Result := False;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.FixupOutPolygon(OutRec: POutRec);
var
  PP, Tmp, LastOK: POutPt;
begin
  //FixupOutPolygon() - removes duplicate points and simplifies
  //co-linear edges by removing the middle vertex.
  LastOK := nil;
  OutRec.BottomPt := nil;
  PP := OutRec.Pts;
  while True do
  begin
    if (PP.Prev = PP) or (PP.Next = PP.Prev) then
    begin
      DisposePolyPts(PP);
      OutRec.Pts := nil;
      Exit;
    end;

    //test for duplicate points and for co-linear edges ...
    if PointsEqual(PP.Pt, PP.Next.Pt) or
      SlopesEqual(PP.Prev.Pt, PP.Pt, PP.Next.Pt, FUse64BitRange) then
    begin
      //OK, we need to delete a point ...
      LastOK := nil;
      Tmp := PP;
      PP.Prev.Next := PP.Next;
      PP.Next.Prev := PP.Prev;
      PP := PP.Prev;
      dispose(Tmp);
    end
    else if PP = LastOK then Break
    else
    begin
      if not Assigned(LastOK) then LastOK := PP;
      PP := PP.Next;
    end;
  end;
  OutRec.Pts := PP;
end;
//------------------------------------------------------------------------------

function EdgesAdjacent(Inode: PIntersectNode): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  Result := (Inode.Edge1.NextInSEL = Inode.Edge2) or
    (Inode.Edge1.PrevInSEL = Inode.Edge2);
end;
//------------------------------------------------------------------------------

procedure SwapIntersectNodes(Int1, Int2: PIntersectNode); {$IFDEF INLINING} inline; {$ENDIF}
var
  Int: TIntersectNode;
begin
  //just swap the contents (because fIntersectNodes is a single-linked-list)
  Int := Int1^; //gets a copy of Int1
  Int1.Edge1 := Int2.Edge1;
  Int1.Edge2 := Int2.Edge2;
  Int1.Pt := Int2.Pt;
  Int2.Edge1 := Int.Edge1;
  Int2.Edge2 := Int.Edge2;
  Int2.Pt := Int.Pt;
end;
//------------------------------------------------------------------------------

function TClipper.FixupIntersectionOrder: Boolean;
var
  Inode, NextNode: PIntersectNode;
begin
  //pre-condition: intersections are sorted bottom-most first.
  //Now it's crucial that intersections are made only between adjacent edges,
  //and to ensure this the order of intersections may need adjusting ...
  Result := True;
  Inode := FIntersectNodes;
  CopyAELToSEL;
  while Assigned(Inode) do
  begin
    if not EdgesAdjacent(Inode) then
    begin
      NextNode := Inode.Next;
      while (assigned(NextNode) and not EdgesAdjacent(NextNode)) do
        NextNode := NextNode.Next;
      if not assigned(NextNode) then
      begin
        Result := False;
        Exit; //error!!
      end;
      SwapIntersectNodes(Inode, NextNode);
    end;
    SwapPositionsInSEL(Inode.Edge1, Inode.Edge2);
    Inode := Inode.Next;
  end;
end;
//------------------------------------------------------------------------------

function FindSegment(var PP: POutPt; UseFullInt64Range: Boolean;
  var Pt1, Pt2: TIntPoint): Boolean;
var
  Pp2: POutPt;
  Pt1a, Pt2a: TIntPoint;
begin
  if not Assigned(PP) then begin Result := False; Exit; end;
  Result := True;
  Pt1a := Pt1; Pt2a := Pt2;
  Pp2 := PP;
  repeat
    //test for co-linearity before testing for overlap ...
    if SlopesEqual(Pt1a, Pt2a, PP.Pt, PP.Prev.Pt, UseFullInt64Range) and
      SlopesEqual(Pt1a, Pt2a, PP.Pt, UseFullInt64Range) and
        GetOverlapSegment(Pt1a, Pt2a, PP.Pt, PP.Prev.Pt, Pt1, Pt2) then Exit;
    PP := PP.Next;
  until PP = Pp2;
  Result := False;
end;
//------------------------------------------------------------------------------

function Pt3IsBetweenPt1AndPt2(const Pt1, Pt2, Pt3: TIntPoint): Boolean;
begin
  if PointsEqual(Pt1, Pt3) or PointsEqual(Pt2, Pt3) then Result := True
  else if (Pt1.X <> Pt2.X) then Result := (Pt1.X < Pt3.X) = (Pt3.X < Pt2.X)
  else Result := (Pt1.Y < Pt3.Y) = (Pt3.Y < Pt2.Y);
end;
//------------------------------------------------------------------------------

function InsertPolyPtBetween(p1, P2: POutPt; const Pt: TIntPoint): POutPt;
begin
  if (p1 = P2) then raise exception.Create(rsJoinError);

  new(Result);
  Result.Pt := Pt;
  Result.Idx := p1.Idx;
  if P2 = p1.Next then
  begin
    p1.Next := Result;
    P2.Prev := Result;
    Result.Next := P2;
    Result.Prev := p1;
  end else
  begin
    P2.Next := Result;
    p1.Prev := Result;
    Result.Next := p1;
    Result.Prev := P2;
  end;
end;
//------------------------------------------------------------------------------

function TClipper.JoinPoints(JR: PJoinRec; out P1, P2: POutPt): Boolean;
var
  OutRec1, OutRec2: POutRec;
  Prev, p3, p4, Pp1a, Pp2a: POutPt;
  Pt1, Pt2, Pt3, Pt4: TIntPoint;
begin
  Result := False;
  OutRec1 := FPolyOutList[Jr.Poly1Idx];
  OutRec2 := FPolyOutList[Jr.Poly2Idx];
  if not Assigned(OutRec1) then Exit;
  if not Assigned(OutRec2) then Exit;

  Pp1a := OutRec1.Pts;
  Pp2a := OutRec2.Pts;
  Pt1 := Jr.Pt2a; Pt2 := Jr.Pt2b;
  Pt3 := Jr.Pt1a; Pt4 := Jr.Pt1b;
  if not FindSegment(Pp1a, FUse64BitRange, Pt1, Pt2) then Exit;
  if (OutRec1 = OutRec2) then
  begin
    //we're searching the same polygon for overlapping segments so
    //segment 2 mustn't be the same as segment 1 ...
    Pp2a := Pp1a.Next;
    if not FindSegment(Pp2a, FUse64BitRange, Pt3, Pt4) or (Pp2a = Pp1a) then
      Exit;
  end else
    if not FindSegment(Pp2a, FUse64BitRange, Pt3, Pt4) then Exit;
  if not GetOverlapSegment(Pt1, Pt2, Pt3, Pt4, Pt1, Pt2) then Exit;

  Prev := Pp1a.Prev;
  if PointsEqual(Pp1a.Pt, Pt1) then P1 := Pp1a
  else if PointsEqual(Prev.Pt, Pt1) then P1 := Prev
  else P1 := InsertPolyPtBetween(Pp1a, Prev, Pt1);

  if PointsEqual(Pp1a.Pt, Pt2) then P2 := Pp1a
  else if PointsEqual(Prev.Pt, Pt2) then P2 := Prev
  else if (P1 = Pp1a) or (P1 = Prev) then
    P2 := InsertPolyPtBetween(Pp1a, Prev, Pt2)
  else if Pt3IsBetweenPt1AndPt2(Pp1a.Pt, P1.Pt, Pt2) then
    P2 := InsertPolyPtBetween(Pp1a, P1, Pt2)
  else
    P2 := InsertPolyPtBetween(P1, Prev, Pt2);

  Prev := Pp2a.Prev;
  if PointsEqual(Pp2a.Pt, Pt1) then p3 := Pp2a
  else if PointsEqual(Prev.Pt, Pt1) then p3 := Prev
  else p3 := InsertPolyPtBetween(Pp2a, Prev, Pt1);

  if PointsEqual(Pp2a.Pt, Pt2) then p4 := Pp2a
  else if PointsEqual(Prev.Pt, Pt2) then p4 := Prev
  else if (p3 = Pp2a) or (p3 = Prev) then
    p4 := InsertPolyPtBetween(Pp2a, Prev, Pt2)
  else if Pt3IsBetweenPt1AndPt2(Pp2a.Pt, p3.Pt, Pt2) then
    p4 := InsertPolyPtBetween(Pp2a, p3, Pt2)
  else
    p4 := InsertPolyPtBetween(p3, Prev, Pt2);

  if (P1.Next = P2) and (p3.Prev = p4) then
  begin
    P1.Next := p3;
    p3.Prev := P1;
    P2.Prev := p4;
    p4.Next := P2;
    Result := True;
  end
  else if (P1.Prev = P2) and (p3.Next = p4) then
  begin
    P1.Prev := p3;
    p3.Next := P1;
    P2.Next := p4;
    p4.Prev := P2;
    Result := True;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.FixupJoinRecs(JR: PJoinRec; Pt: POutPt; StartIdx: Integer);
var
  JR2: PJoinRec;
begin
  for StartIdx := StartIdx to FJoinList.count -1 do
  begin
    Jr2 := FJoinList[StartIdx];
    if (Jr2.Poly1Idx = Jr.Poly1Idx) and PointIsVertex(Jr2.Pt1a, Pt) then
      Jr2.Poly1Idx := Jr.Poly2Idx;
    if (Jr2.Poly2Idx = Jr.Poly1Idx) and PointIsVertex(Jr2.Pt2a, Pt) then
      Jr2.Poly2Idx := Jr.Poly2Idx;
  end;
end;
//------------------------------------------------------------------------------

function Poly2ContainsPoly1(OutPt1, OutPt2: POutPt;
  UseFullInt64Range: Boolean): Boolean;
var
  Pt: POutPt;
begin
  Pt := OutPt1;
  //Because the polygons may be touching, we need to find a vertex that
  //isn't touching the other polygon ...
  if PointOnPolygon(Pt.Pt, OutPt2, UseFullInt64Range) then
  begin
    Pt := Pt.Next;
    while (Pt <> OutPt1) and
      PointOnPolygon(Pt.Pt, OutPt2, UseFullInt64Range) do
        Pt := Pt.Next;
    if (Pt = OutPt1) then
    begin
      Result := True;
      Exit;
    end;
  end;
  Result := PointInPolygon(Pt.Pt, OutPt2, UseFullInt64Range);
end;
//------------------------------------------------------------------------------

procedure TClipper.FixupFirstLefts1(OldOutRec, NewOutRec: POutRec);
var
  I: Integer;
  OutRec: POutRec;
begin
  for I := 0 to FPolyOutList.Count -1 do
  begin
    OutRec := fPolyOutList[I];
    if Assigned(OutRec.Pts) and (OutRec.FirstLeft = OldOutRec) then
    begin
      if Poly2ContainsPoly1(OutRec.Pts, NewOutRec.Pts, FUse64BitRange) then
        OutRec.FirstLeft := NewOutRec;
    end;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.FixupFirstLefts2(OldOutRec, NewOutRec: POutRec);
var
  I: Integer;
begin
  for I := 0 to FPolyOutList.Count -1 do
    with POutRec(fPolyOutList[I])^ do
      if (FirstLeft = OldOutRec) then FirstLeft := NewOutRec;
end;
//------------------------------------------------------------------------------

procedure TClipper.JoinCommonEdges;
var
  I: Integer;
  Jr: PJoinRec;
  OutRec1, OutRec2, HoleStateRec: POutRec;
  P1, P2: POutPt;
begin
  for I := 0 to FJoinList.count -1 do
  begin
    Jr := FJoinList[I];

    OutRec1 := GetOutRec(Jr.Poly1Idx);
    OutRec2 := GetOutRec(Jr.Poly2Idx);

    if not Assigned(OutRec1.Pts) or not Assigned(OutRec2.Pts) then Continue;

    //get the polygon fragment with the correct hole state (FirstLeft)
    //before calling JoinPoints() ...
    if OutRec1 = OutRec2 then HoleStateRec := OutRec1
    else if Param1RightOfParam2(OutRec1, OutRec2) then HoleStateRec := OutRec2
    else if Param1RightOfParam2(OutRec2, OutRec1) then HoleStateRec := OutRec1
    else HoleStateRec := GetLowermostRec(OutRec1, OutRec2);

    if not JoinPoints(JR, P1, P2) then Continue;

    if (OutRec1 = OutRec2) then
    begin
      //instead of joining two polygons, we've just created a new one by
      //splitting one polygon into two.
      OutRec1.Pts := P1;
      OutRec1.BottomPt := nil;
      OutRec2 := CreateOutRec;
      OutRec2.Pts := P2;
      Jr.Poly2Idx := OutRec2.Idx;

      if Poly2ContainsPoly1(OutRec2.Pts, OutRec1.Pts, FUse64BitRange) then
      begin
        //OutRec2 is contained by OutRec1 ...
        OutRec2.IsHole := not OutRec1.IsHole;
        OutRec2.FirstLeft := OutRec1;

        //now fixup any subsequent joins that match the new polygon ...
        FixupJoinRecs(Jr, P2, I + 1);

        //fixup FirstLeft pointers that may need reassigning to OutRec1
        if FUsingPolyTree then FixupFirstLefts2(OutRec2, OutRec1);

        FixupOutPolygon(OutRec1); //nb: do this BEFORE testing orientation
        FixupOutPolygon(OutRec2); //    but AFTER calling FixupJoinRecs()

        if (OutRec2.IsHole xor FReverseOutput) = (Area(OutRec2, FUse64BitRange) > 0) then
            ReversePolyPtLinks(OutRec2.Pts);
      end else if Poly2ContainsPoly1(OutRec1.Pts, OutRec2.Pts, FUse64BitRange) then
      begin
        //OutRec1 is contained by OutRec2 ...
        OutRec2.IsHole := OutRec1.IsHole;
        OutRec1.IsHole := not OutRec2.IsHole;
        OutRec2.FirstLeft := OutRec1.FirstLeft;
        OutRec1.FirstLeft := OutRec2;

        //now fixup any subsequent joins that match the new polygon ...
        FixupJoinRecs(Jr, P2, I + 1);

        //fixup FirstLeft pointers that may need reassigning to OutRec1
        if FUsingPolyTree then FixupFirstLefts2(OutRec1, OutRec2);

        FixupOutPolygon(OutRec1); //nb: do this BEFORE testing orientation
        FixupOutPolygon(OutRec2); //    but AFTER calling PointIsVertex()

        if (OutRec1.IsHole xor FReverseOutput) = (Area(OutRec1, FUse64BitRange) > 0) then
          ReversePolyPtLinks(OutRec1.Pts);
      end else
      begin
        //the 2 polygons are completely separate ...
        OutRec2.IsHole := OutRec1.IsHole;
        OutRec2.FirstLeft := OutRec1.FirstLeft;

        //now fixup any subsequent joins that match the new polygon ...
        FixupJoinRecs(Jr, P2, I + 1);

        //fixup FirstLeft pointers that may need reassigning to OutRec2
        if FUsingPolyTree then FixupFirstLefts1(OutRec1, OutRec2);

        FixupOutPolygon(OutRec1); //nb: do this AFTER calling PointIsVertex()
        FixupOutPolygon(OutRec2); //    in FixupJoinRecs()
      end;
    end else
    begin
      //joined 2 polygons together ...

      //cleanup edges ...
      FixupOutPolygon(OutRec1);

      //delete the obsolete pointer ...
      OutRec2.Pts := nil;
      OutRec2.BottomPt := nil;
      OutRec2.Idx := OutRec1.Idx;

      OutRec1.IsHole := HoleStateRec.IsHole;
      if HoleStateRec = OutRec2 then
        OutRec1.FirstLeft := OutRec2.FirstLeft;
      OutRec2.FirstLeft := OutRec1;

      //fixup FirstLeft pointers that may need reassigning to OutRec1
      if FUsingPolyTree then FixupFirstLefts2(OutRec2, OutRec1);
    end;
  end;
end;
//------------------------------------------------------------------------------

procedure UpdateOutPtIdxs(OutRec: POutRec);
var
  op: POutPt;
begin
  op := OutRec.Pts;
  repeat
    op.Idx := OutRec.Idx;
    op := op.Prev;
  until op = OutRec.Pts;
end;
//------------------------------------------------------------------------------

procedure TClipper.DoSimplePolygons;
var
  I: Integer;
  OutRec1, OutRec2: POutRec;
  Op, Op2, Op3, Op4: POutPt;
begin
  I := 0;
  while I < FPolyOutList.Count do
  begin
    OutRec1 := POutRec(fPolyOutList[I]);
    inc(I);
    Op := OutRec1.Pts;
    if not assigned(OP) then Continue;
    repeat //for each Pt in Polygon until duplicate found do ...
      Op2 := Op.Next;
      while (Op2 <> OutRec1.Pts) do
      begin
        if (PointsEqual(Op.Pt, Op2.Pt) and
          (Op2.Next <> Op)and (Op2.Prev <> Op)) then
        begin
          //split the polygon into two ...
          Op3 := Op.Prev;
          Op4 := Op2.Prev;
          Op.Prev := Op4;
          Op4.Next := Op;
          Op2.Prev := Op3;
          Op3.Next := Op2;

          OutRec1.Pts := Op;

          OutRec2 := CreateOutRec;
          OutRec2.Pts := Op2;
          UpdateOutPtIdxs(OutRec2);
          if Poly2ContainsPoly1(OutRec2.Pts, OutRec1.Pts, FUse64BitRange) then
          begin
            //OutRec2 is contained by OutRec1 ...
            OutRec2.IsHole := not OutRec1.IsHole;
            OutRec2.FirstLeft := OutRec1;
          end
          else
          if Poly2ContainsPoly1(OutRec1.Pts, OutRec2.Pts, FUse64BitRange) then
          begin
            //OutRec1 is contained by OutRec2 ...
            OutRec2.IsHole := OutRec1.IsHole;
            OutRec1.IsHole := not OutRec2.IsHole;
            OutRec2.FirstLeft := OutRec1.FirstLeft;
            OutRec1.FirstLeft := OutRec2;
          end else
          begin
            //the 2 polygons are separate ...
            OutRec2.IsHole := OutRec1.IsHole;
            OutRec2.FirstLeft := OutRec1.FirstLeft;
          end;
          Op2 := Op; //ie get ready for the next iteration
        end;
        Op2 := Op2.Next;
      end;
      Op := Op.Next;
    until (Op = OutRec1.Pts);
  end;
end;

//------------------------------------------------------------------------------
// OffsetPolygons ...
//------------------------------------------------------------------------------

function GetUnitNormal(const Pt1, Pt2: TIntPoint): TDoublePoint;
var
  Dx, Dy, F: Single;
begin
  if (Pt2.X = Pt1.X) and (Pt2.Y = Pt1.Y) then
  begin
    Result.X := 0;
    Result.Y := 0;
    Exit;
  end;

  Dx := (Pt2.X - Pt1.X);
  Dy := (Pt2.Y - Pt1.Y);
  F := 1 / Hypot(Dx, Dy);
  Dx := Dx * F;
  Dy := Dy * F;
  Result.X := Dy;
  Result.Y := -Dx
end;
//------------------------------------------------------------------------------

//Notes on the number of steps used to build an arc:
//Given S = arbitrary no. steps used to construct chords approximating a CIRCLE,
//then the angle (A) of each step = 2 * Pi / S
//The chord between two steps (pt1) & (pt2) is perpendicular to the line
//segment between the circle's center (pt3) to the chord's midpoint (pt4).
//Let the length of the line segment (pt3) & (Pt4) = D, and let the distance
//from the chord's midpoint (pt4) to the circle = Q, such that R - Q = D
//If Q is a pre-defined constant (ie the maximum allowed deviation from circle),
//then given that cos(angle) = adjacent/hypotenuse ...
//  cos(A/2) = D/R
//           = (R - Q)/R
//           = 1 - Q/R
//       A/2 = ArcCos(1 - Q/R)
//         A = 2 * ArcCos(1 - Q/R)
//2 * Pi / S = 2 * ArcCos(1 - Q/R)
//         S = Pi / ArcCos(1 - Q/R)
//Instead of a CIRCLE, given an ARC from angle A1 to angle A2 ...
//   ArcFrac = Abs(A2 - A1)/(2 * Pi)
//     Steps = ArcFrac * Pi / ArcCos(1 - Q/R)
function BuildArc(const Pt: TIntPoint;
  A1, A2, R: Single; Limit: Double): TPolygon;
var
  I: Integer;
  Steps: Int64;
  X, X2, Y, ArcFrac: Double;
  S, C: Extended;
begin
  ArcFrac := Abs(A2 - A1) / (2 * Pi);
  //Limit == Q in comments above ...
  Steps := Trunc(ArcFrac * Pi / ArcCos(1 - Limit / Abs(R)));
  if Steps < 2 then Steps := 2
  else if Steps > 222.0 * ArcFrac then //ie R > 10000 * Limit
    Steps := Trunc(222.0 * ArcFrac);

  Math.SinCos(A1, S, C);
  X := C; Y := S;
  Math.SinCos((A2 - A1) / Steps, S, C);
  SetLength(Result, Steps + 1);
  for I := 0 to Steps do
  begin
    Result[I].X := Pt.X + Round(X * R);
    Result[I].Y := Pt.Y + Round(Y * R);
    X2 := X;
    X := X * C - S * Y;  //cross product & dot product here ...
    Y := X2 * S + Y * C; //avoids repeat calls to the much slower SinCos()
  end;
end;
//------------------------------------------------------------------------------

function GetBounds(const Pts: TPolygons): TIntRect;
var
  I,J: Integer;
begin
  with Result do
  begin
    Left := HiRange; Top := HiRange;
    Right := -HiRange; Bottom := -HiRange;
  end;
  for I := 0 to high(Pts) do
    for J := 0 to high(Pts[I]) do
    begin
      if Pts[I][J].X < Result.Left then Result.Left := Pts[I][J].X;
      if Pts[I][J].X > Result.Right then Result.Right := Pts[I][J].X;
      if Pts[I][J].Y < Result.Top then Result.Top := Pts[I][J].Y;
      if Pts[I][J].Y > Result.Bottom then Result.Bottom := Pts[I][J].Y;
    end;
  if Result.left = HiRange then
    with Result do begin Left := 0; Top := 0; Right := 0; Bottom := 0; end;
end;

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------

type
  TOffsetBuilder = class
  private
    FDelta: Double;
    FJoinType: TJoinType;
    FLimit: Double;
    FNorms: TArrayOfDoublePoint;
    FSolution: TPolygons;
    FOutPos: Integer;
    FInP: TPolygon;
    FOutP: TPolygon;

    procedure AddPoint(const Pt: TIntPoint);
    procedure DoSquare(J, K: Integer);
    procedure DoMiter(J, K: Integer; R: Double);
    procedure DoRound(J, K: Integer);
    function OffsetPoint(J, K: Integer; RMin: Double): Integer;
  public
    constructor Create(const Pts: TPolygons; Delta: Double;
      IsPolygon: Boolean; JoinType: TJoinType; EndType: TEndType;
      Limit: Double = 0);
    property Solution: TPolygons read FSolution;
  end;

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------

procedure TOffsetBuilder.AddPoint(const Pt: TIntPoint);
const
  BuffLength = 32;
begin
  if FOutPos = length(FOutP) then
    SetLength(FOutP, FOutPos + BuffLength);
  FOutP[FOutPos] := Pt;
  Inc(FOutPos);
end;
//------------------------------------------------------------------------------

procedure TOffsetBuilder.DoSquare(J, K: Integer);
var
  A1, A2, Dx: Double;
  Pt1, Pt2: TIntPoint;
begin
  Pt1.X := round(FInP[J].X + FNorms[K].X * FDelta);
  Pt1.Y := round(FInP[J].Y + FNorms[K].Y * FDelta);
  Pt2.X := round(FInP[J].X + FNorms[J].X * FDelta);
  Pt2.Y := round(FInP[J].Y + FNorms[J].Y * FDelta);
  if ((FNorms[K].X * FNorms[J].Y -
    FNorms[J].X * FNorms[K].Y) * FDelta >= 0) then
  begin
    A1 := ArcTan2(FNorms[K].Y, FNorms[K].X);
    A2 := ArcTan2(-FNorms[J].Y, -FNorms[J].X);
    A1 := abs(A2 - A1);
    if A1 > pi then A1 := pi*2 - A1;
    Dx := tan((pi - A1)/4) * abs(FDelta);
    Pt1 := IntPoint(round(Pt1.X -FNorms[K].Y * Dx),
      round(Pt1.Y + FNorms[K].X * Dx));
    AddPoint(Pt1);
    Pt2 := IntPoint(round(Pt2.X + FNorms[J].Y * Dx),
      round(Pt2.Y - FNorms[J].X * Dx));
    AddPoint(Pt2);
  end else
  begin
    AddPoint(Pt1);
    AddPoint(FInP[J]);
    AddPoint(Pt2);
  end;
end;
//------------------------------------------------------------------------------

procedure TOffsetBuilder.DoMiter(J, K: Integer; R: Double);
var
  Q: Double;
  Pt1, Pt2: TIntPoint;
begin
  if ((FNorms[K].X * FNorms[J].Y -
    FNorms[J].X * FNorms[K].Y) * FDelta >= 0) then
  begin
    Q := FDelta / R;
    AddPoint(IntPoint(round(FInP[J].X + (FNorms[K].X + FNorms[J].X)*Q),
      round(FInP[J].Y + (FNorms[K].Y + FNorms[J].Y)*Q)));
  end else
  begin
    Pt1.X := round(FInP[J].X + FNorms[K].X * FDelta);
    Pt1.Y := round(FInP[J].Y + FNorms[K].Y * FDelta);
    Pt2.X := round(FInP[J].X + FNorms[J].X * FDelta);
    Pt2.Y := round(FInP[J].Y + FNorms[J].Y * FDelta);
    AddPoint(Pt1);
    AddPoint(FInP[J]);
    AddPoint(Pt2);
  end;
end;
//------------------------------------------------------------------------------

procedure TOffsetBuilder.DoRound(J, K: Integer);
var
  M: Integer;
  A1, A2: Double;
  Pt1, Pt2: TIntPoint;
  Arc: TPolygon;
begin
  Pt1.X := round(FInP[J].X + FNorms[K].X * FDelta);
  Pt1.Y := round(FInP[J].Y + FNorms[K].Y * FDelta);
  Pt2.X := round(FInP[J].X + FNorms[J].X * FDelta);
  Pt2.Y := round(FInP[J].Y + FNorms[J].Y * FDelta);
  AddPoint(Pt1);
  //round off reflex angles (ie > 180 deg) unless almost flat (ie < 10deg).
  //(N1.X * N2.Y - N2.X * N1.Y) == unit normal "cross product" == sin(angle)
  //(N1.X * N2.X + N1.Y * N2.Y) == unit normal "dot product" == cos(angle)
  //dot product Normals == 1 -> no angle
  if (FNorms[K].X * FNorms[J].Y -
    FNorms[J].X * FNorms[K].Y) * FDelta >= 0 then
  begin
    if ((FNorms[J].X * FNorms[K].X
      + FNorms[J].Y * FNorms[K].Y) < 0.985) then
    begin
      A1 := ArcTan2(FNorms[K].Y, FNorms[K].X);
      A2 := ArcTan2(FNorms[J].Y, FNorms[J].X);
      if (FDelta > 0) and (A2 < A1) then A2 := A2 + pi*2
      else if (FDelta < 0) and (A2 > A1) then A2 := A2 - pi*2;
      Arc := BuildArc(FInP[J], A1, A2, FDelta, FLimit);
      for M := 0 to high(Arc) do AddPoint(Arc[M]);
    end;
  end else
    AddPoint(FInP[J]);
  AddPoint(Pt2);
end;
//------------------------------------------------------------------------------

function TOffsetBuilder.OffsetPoint(J, K: Integer; RMin: Double): Integer;
var
  R: Double;
begin
  case FJoinType of
    jtMiter:
    begin
      R := 1 + (FNorms[J].X * FNorms[K].X + FNorms[J].Y * FNorms[K].Y);
      if (R >= RMin) then DoMiter(J, K, R)
      else DoSquare(J, K);
    end;
    jtSquare: DoSquare(J, K);
    jtRound: DoRound(J, K);
  end;
  Result := J;
end;
//------------------------------------------------------------------------------

constructor TOffsetBuilder.Create(const Pts: TPolygons; Delta: Double;
  IsPolygon: Boolean; JoinType: TJoinType; EndType: TEndType; Limit: Double = 0);
var
  I, J, K, Len: Integer;
  R, RMin: Double;
  Outer: TPolygon;
  Bounds: TIntRect;
  ForceClose: Boolean;
begin
  FSolution := nil;

  RMin := 0.5;
  FJoinType := JoinType;
  if not IsPolygon and (Delta < 0) then Delta := -Delta;
  FDelta := Delta;

  if FJoinType = jtMiter then
  begin
    if Limit > 2 then RMin := 2/(sqr(Limit));
    FLimit := 0.25; //just in case EndType == etRound
  end else
  begin
    if Limit <= 0 then FLimit := 0.25
    else if Limit > abs(FDelta) then FLimit := abs(FDelta)
    else FLimit := Limit;
  end;

  SetLength(FSolution, length(Pts));
  for I := 0 to high(Pts) do
  begin
    //for each polygon in Pts ...
    FInP := Pts[I];
    Len := length(FInP);

    if (Len = 0) or ((Len < 3) and (FDelta <= 0)) then
      Continue
    else if (Len = 1) then
    begin
      FInP := BuildArc(FInP[0], 0, 2*pi, FDelta, Limit);
      Continue;
    end;

    ForceClose := PointsEqual(FInP[0], FInP[Len -1]);
    if ForceClose then dec(Len);

    //build Normals ...
    SetLength(FNorms, Len);
    for J := 0 to Len-2 do
      FNorms[J] := GetUnitNormal(FInP[J], FInP[J+1]);
    if IsPolygon or ForceClose then
      FNorms[Len-1] := GetUnitNormal(FInP[Len-1], FInP[0])
    else
      FNorms[Len-1] := FNorms[Len-2];

    FOutPos := 0;
    FOutP := nil;

    if IsPolygon or ForceClose then
    begin
      K := Len -1;
      for J := 0 to Len-1 do
        K := OffsetPoint(J, K, RMin);
      SetLength(FOutP, FOutPos);
      FSolution[I] := FOutP;

      if not IsPolygon then
      begin
        FOutPos := 0;
        FOutP := nil;
        FDelta := -FDelta;

        K := Len -1;
        for J := 0 to Len-1 do
          K := OffsetPoint(J, K, RMin);

        FDelta := -FDelta;
        SetLength(FOutP, FOutPos);
        J := Length(FSolution);
        setLength(FSolution, J +1);
        FSolution[J] := ReversePolygon(FOutP);
      end;
    end else //is polyline
    begin
      K := 0;
      //offset the polyline going forward ...
      for J := 1 to Len-2 do
        K := OffsetPoint(J, K, RMin);

      //handle the end (butt, round or square) ...
      if EndType = etButt then
      begin
        J := Len - 1;
        AddPoint(IntPoint(round(FInP[J].X + FNorms[J].X *FDelta),
          round(FInP[J].Y + FNorms[J].Y * FDelta)));
        AddPoint(IntPoint(round(FInP[J].X - FNorms[J].X *FDelta),
          round(FInP[J].Y - FNorms[J].Y * FDelta)));
      end else
      begin
        J := Len - 1;
        K := Len - 2;
        FNorms[J].X := -FNorms[J].X;
        FNorms[J].Y := -FNorms[J].Y;
        if EndType = etSquare then DoSquare(J, K)
        else DoRound(J, K);
      end;

      //re-build Normals ...
      for J := Len-1 downto 1 do
      begin
        FNorms[J].X := -FNorms[J-1].X;
        FNorms[J].Y := -FNorms[J-1].Y;
      end;
      FNorms[0].X := -FNorms[1].X;
      FNorms[0].Y := -FNorms[1].Y;

      //offset the polyline going backward ...
      K := Len -1;
      for J := Len -2 downto 1 do
        K := OffsetPoint(J, K, RMin);

      //finally handle the start (butt, round or square) ...
      if EndType = etButt then
      begin
        AddPoint(IntPoint(round(FInP[0].X - FNorms[0].X *FDelta),
          round(FInP[0].Y - FNorms[0].Y * FDelta)));
        AddPoint(IntPoint(round(FInP[0].X + FNorms[0].X *FDelta),
          round(FInP[0].Y + FNorms[0].Y * FDelta)));
      end else
      begin
        if EndType = etSquare then DoSquare(0, 1)
        else DoRound(0, 1);
      end;
      SetLength(FOutP, FOutPos);
      FSolution[I] := FOutP;
    end;
  end;

  //finally, clean up untidy corners ...
  with TClipper.Create do
  try
    AddPolygons(FSolution, ptSubject);
    if Delta > 0 then
    begin
      Execute(ctUnion, FSolution, pftPositive, pftPositive);
    end else
    begin
      Bounds := GetBounds(FSolution);
      SetLength(Outer, 4);
      Outer[0] := IntPoint(Bounds.left-10, Bounds.bottom+10);
      Outer[1] := IntPoint(Bounds.right+10, Bounds.bottom+10);
      Outer[2] := IntPoint(Bounds.right+10, Bounds.top-10);
      Outer[3] := IntPoint(Bounds.left-10, Bounds.top-10);
      AddPolygon(Outer, ptSubject);
      ReverseSolution := True;
      Execute(ctUnion, FSolution, pftNegative, pftNegative);
      //delete the outer rectangle ...
      Len := length(FSolution);
      for J := 1 to Len -1 do fSolution[J-1] := fSolution[J];
      if Len > 0 then SetLength(FSolution, Len -1);
    end;
  finally
    free;
  end;
end;
//------------------------------------------------------------------------------

function BuildOffset(const Pts: TPolygons; Delta: Double; IsPolygon: Boolean;
  JoinType: TJoinType; EndType: TEndType; Limit: Double = 0): TPolygons;
begin
  with TOffsetBuilder.Create(Pts, Delta, IsPolygon, JoinType, EndType, Limit) do
  try
    result := Solution;
  finally
    Free;
  end;
end;
//------------------------------------------------------------------------------

function UpdateBotPt(const Pt: TIntPoint; var BotPt: TIntPoint): Boolean;
begin
  if (pt.Y > BotPt.Y) or ((pt.Y = BotPt.Y) and (Pt.X < BotPt.X)) then
  begin
    BotPt := Pt;
    Result := True;
  end
  else Result := False;
end;
//------------------------------------------------------------------------------

function OffsetPolygons(const Polys: TPolygons; const Delta: Double;
  JoinType: TJoinType = jtSquare; Limit: Double = 0;
  AutoFix: Boolean = True): TPolygons;
var
  I, J, K, Len, BotI: Integer;
  Pts: TPolygons;
  BotPt: TIntPoint;
begin
  Pts := Polys;
  Result := nil;
  //AutoFix - fixes polygon orientation if necessary and removes
  //duplicate vertices. Can be set False when you're sure that polygon
  //orientation is correct and that there are no duplicate vertices.
  if AutoFix then
  begin
    Len := Length(Polys);
    SetLength(Pts, Len);
    BotI := 0; //index of outermost polygon
    while (BotI < Len) and (Length(Polys[BotI]) = 0) do Inc(BotI);
    if (BotI = Len) then Exit;
    BotPt := Polys[BotI][0];
    for I := BotI to Len - 1 do
    begin
      Len := Length(Polys[I]);
      SetLength(Pts[I], Len);
      if Len = 0 then Continue;
      Pts[I][0] := Polys[I][0];
      if UpdateBotPt(Pts[I][0], BotPt) then BotI := I;
      K := 0;
      for J := 1 to Len - 1 do
        if not PointsEqual(Pts[I][K], Polys[I][J]) then
        begin
          Inc(K);
          Pts[I][K] := Polys[I][J];
          if UpdateBotPt(Pts[I][K], BotPt) then BotI := I;
        end;
      if K + 1 < Len then
        SetLength(Pts[I], K + 1);
    end;
    if not Orientation(Pts[BotI]) then
      Pts := ReversePolygons(Pts);
  end;
  Result := BuildOffset(Pts, Delta, True, JoinType, etButt, Limit);
end;
//------------------------------------------------------------------------------

function StripDups(const Poly: TPolygon): TPolygon;
var
  I, J, Len: Integer;
begin
  Len := Length(Poly);
  SetLength(Result, Len);
  if Len = 0 then Exit;
  J := 0;
  Result[0] := Poly[0];
  for I := 1 to Len - 1 do
    if not PointsEqual(Poly[I], Result[J]) then
    begin
      Inc(J);
      Result[J] := Poly[I];
    end;
  Inc(J);
  if J < Len then SetLength(Result, J);
end;
//------------------------------------------------------------------------------

function OffsetPolyLines(const Lines: TPolygons; Delta: Double;
  JoinType: TJoinType = jtSquare; EndType: TEndType = etSquare;
  Limit: Double = 0): TPolygons;
var
  I, Len: Integer;
  Pts: TPolygons;
begin
  //automatically strip duplicate points because it gets complicated with
  //open and closed lines and when to strip duplicates across begin-end ...
  Pts := Lines;
  Len := Length(Pts);
  SetLength(Pts, Len);
  for I := 0 to Len -1 do
    Pts[I] := StripDups(Lines[I]);

  if EndType = etClosed then
  begin
    SetLength(Pts, Len *2);
    for I := 0 to Len -1 do
      Pts[Len + I] := ReversePolygon(Pts[I]);
    Result := BuildOffset(Pts, Delta, True, JoinType, EndType, Limit);
  end
  else
    Result := BuildOffset(Pts, Delta, False, JoinType, EndType, Limit);
end;
//------------------------------------------------------------------------------

function SimplifyPolygon(const Poly: TPolygon; FillType: TPolyFillType = pftEvenOdd): TPolygons;
begin
  with TClipper.Create do
  try
    ForceSimple := True;
    AddPolygon(Poly, ptSubject);
    Execute(ctUnion, Result, FillType, FillType);
  finally
    free;
  end;
end;
//------------------------------------------------------------------------------

function SimplifyPolygons(const Polys: TPolygons; FillType: TPolyFillType = pftEvenOdd): TPolygons;
begin
  with TClipper.Create do
  try
    ForceSimple := True;
    AddPolygons(Polys, ptSubject);
    Execute(ctUnion, Result, FillType, FillType);
  finally
    free;
  end;
end;
//------------------------------------------------------------------------------

function DistanceSqrd(const Pt1, Pt2: TIntPoint): Double; {$IFDEF INLINING} inline; {$ENDIF}
var
  dx, dy: Double;
begin
  dx := (Pt1.X - Pt2.X);
  dy := (Pt1.Y - Pt2.Y);
  result := (dx*dx + dy*dy);
end;
//------------------------------------------------------------------------------

function ClosestPointOnLine(const Pt, LinePt1, LinePt2: TIntPoint): TDoublePoint;
var
  dx, dy, q: Double;
begin
  dx := (LinePt2.X-LinePt1.X);
  dy := (LinePt2.Y-LinePt1.Y);
  if (dx = 0) and (dy = 0) then
    q := 0 else
    q := ((Pt.X-LinePt1.X)*dx + (Pt.Y-LinePt1.Y)*dy) / (dx*dx + dy*dy);
  Result.X := (1-q)*LinePt1.X + q*LinePt2.X;
  Result.Y := (1-q)*LinePt1.Y + q*LinePt2.Y;
end;
//------------------------------------------------------------------------------

function SlopesNearColinear(const Pt1, Pt2, Pt3: TIntPoint; DistSqrd: Double): Boolean;
var
  Cpol: TDoublePoint;
  Dx, Dy: Double;
begin
  Result := false;
  if DistanceSqrd(Pt1, Pt2) > DistanceSqrd(Pt1, Pt3) then exit;
  Cpol := ClosestPointOnLine(Pt2, Pt1, Pt3);
  Dx := Pt2.X - Cpol.X;
  Dy := Pt2.Y - Cpol.Y;
  result := (Dx*Dx + Dy*Dy) < DistSqrd;
end;
//------------------------------------------------------------------------------

function PointsAreClose(const Pt1, Pt2: TIntPoint;
  DistSqrd: Double): Boolean;
begin
  result := DistanceSqrd(Pt1, Pt2) <= DistSqrd;
end;
//------------------------------------------------------------------------------

function CleanPolygon(const Poly: TPolygon; Distance: Double = 1.415): TPolygon;
var
  I, I2, K, HighI: Integer;
  DistSqrd: double;
  Pt: TIntPoint;
begin
  //Distance = proximity in units/pixels below which vertices
  //will be stripped. Default ~= sqrt(2) so when adjacent
  //vertices have both x & y coords within 1 unit, then
  //the second vertex will be stripped.
  DistSqrd := Round(Distance * Distance);
  HighI := High(Poly);
  while (HighI > 0) and PointsAreClose(Poly[HighI], Poly[0], DistSqrd) do
    Dec(HighI);
  if (HighI < 2) then
  begin
    Result := nil;
    Exit;
  end;
  SetLength(Result, HighI +1);
  Pt := Poly[HighI];
  I := 0;
  K := 0;
  while true do
  begin
    while (I < HighI) and PointsAreClose(Pt, Poly[I+1], DistSqrd) do inc(I,2);
    I2 := I;
    while (I < HighI) and (PointsAreClose(Poly[I], Poly[I+1], DistSqrd) or
      SlopesNearColinear(Pt, Poly[I], Poly[I+1], DistSqrd)) do inc(I);
    if I >= highI then Break
    else if I <> I2 then Continue;
    Pt := Poly[I];
    inc(I);
    Result[K] := Pt;
    inc(K);
  end;

  if (I <= HighI) then
  begin
    Result[K] := Poly[I];
    inc(K);
  end;

  if (K > 2) and SlopesNearCoLinear(Result[K -2],
      Result[K -1], Result[0], DistSqrd) then Dec(K);
  if (K < 3) then Result := nil
  else if (K <= HighI) then SetLength(Result, K);
end;
//------------------------------------------------------------------------------

function CleanPolygons(const Polys: TPolygons; Distance: double = 1.415): TPolygons;
var
  I, Len: Integer;
begin
  Len := Length(Polys);
  SetLength(Result, Len);
  for I := 0 to Len - 1 do
    Result[I] := CleanPolygon(Polys[I], Distance);
end;
//------------------------------------------------------------------------------

procedure AddPolyNodeToPolygons(PolyNode: TPolyNode; var Polygons: TPolygons);
var
  I: Integer;
begin
  if Length(PolyNode.Contour) > 0 then
  begin
    I := Length(Polygons);
    SetLength(Polygons, I +1);
    Polygons[I] := PolyNode.Contour;
  end;
  for I := 0 to PolyNode.ChildCount - 1 do
    AddPolyNodeToPolygons(PolyNode.Childs[I], Polygons);
end;
//------------------------------------------------------------------------------

function PolyTreeToPolygons(PolyTree: TPolyTree): TPolygons;
begin
  Result := nil;
  AddPolyNodeToPolygons(PolyTree, Result);
end;

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------

end.
