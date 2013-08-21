unit clipper;

(*******************************************************************************
*                                                                              *
* Author    :  Angus Johnson                                                   *
* Version   :  6.0.0                                                           *
* Date      :  22 August 2013                                                  *
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

//use_int32: When enabled 32bit ints are used instead of 64bit ints. This
//improve performance but coordinate values are limited to the range +/- 46340
{.$DEFINE use_int32}

//use_xyz: adds a Z member to IntPoint (with only a minor cost to perfomance)
{.$DEFINE use_xyz}

//use_lines: Enables line clipping. Adds a very minor cost to performance.
//{$DEFINE use_lines}

//When enabled, code developed with earlier versions of Clipper
//(ie prior to ver 6) should compile without changes.
//In a future update, this compatability code will be removed.
{$DEFINE use_deprecated}

interface

uses
  SysUtils, Types, Classes, Math;

type
{$IFDEF use_int32}
  cInt = Int32;
{$ELSE}
  cInt = Int64;
{$ENDIF}

  PIntPoint = ^TIntPoint;
{$IFDEF use_xyz}
  TIntPoint = record X, Y, Z: cInt; end;
{$ELSE}
  TIntPoint = record X, Y: cInt; end;
{$ENDIF}

  TIntRect = record Left, Top, Right, Bottom: cInt; end;

  TDoublePoint = record X, Y: Double; end;
  TArrayOfDoublePoint = array of TDoublePoint;

{$IFDEF use_xyz}
  TZFillCallback = procedure (const Z1, Z2: cInt; var Pt: TIntPoint);
{$ENDIF}

  TInitOption = (ioReverseSolution, ioStrictlySimple, ioPreserveCollinear);
  TInitOptions = set of TInitOption;

  TClipType = (ctIntersection, ctUnion, ctDifference, ctXor);
  TPolyType = (ptSubject, ptClip);
  //By far the most widely used winding rules for polygon filling are
  //EvenOdd & NonZero (GDI, GDI+, XLib, OpenGL, Cairo, AGG, Quartz, SVG, Gr32)
  //Others rules include Positive, Negative and ABS_GTR_EQ_TWO (only in OpenGL)
  //see http://glprogramming.com/red/chapter11.html
  TPolyFillType = (pftEvenOdd, pftNonZero, pftPositive, pftNegative);

  //TJoinType & TEndType are used by OffsetPaths()
  TJoinType = (jtSquare, jtRound, jtMiter);
  TEndType = (etClosed, etButt, etSquare, etRound);

  TPath = array of TIntPoint;
  TPaths = array of TPath;

{$IFDEF use_deprecated}
  TPolygon = TPath;
  TPolygons = TPaths;
{$ENDIF}

  TPolyNode = class;
  TArrayOfPolyNode = array of TPolyNode;

  TPolyNode = class
  private
    FPath: TPath;
    FParent : TPolyNode;
    FIndex  : Integer;
    FCount  : Integer;
    FBuffLen: Integer;
    FIsOpen : Boolean;
    FChilds : TArrayOfPolyNode;
    function  GetChild(Index: Integer): TPolyNode;
    function  IsHoleNode: boolean;
    procedure AddChild(PolyNode: TPolyNode);
    function  GetNextSiblingUp: TPolyNode;
  public
    function  GetNext: TPolyNode;
    property  ChildCount: Integer read FCount;
    property  Childs[index: Integer]: TPolyNode read GetChild;
    property  Parent: TPolyNode read FParent;
    property  IsHole: Boolean read IsHoleNode;
    property  IsOpen: Boolean read FIsOpen;
    property  Contour: TPath read FPath;
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
  TDirection = (dRightToLeft, dLeftToRight);

  POutPt = ^TOutPt;

  PEdge = ^TEdge;
  TEdge = record
    Bot  : TIntPoint;      //bottom
    Curr : TIntPoint;      //current (ie relative to bottom of current scanbeam)
    Top  : TIntPoint;      //top
    Delta: TIntPoint;
    Dx   : Double;         //inverse of slope
    PolyType : TPolyType;
    Side     : TEdgeSide;
    WindDelta: Integer;    //1 or -1 depending on winding direction
    WindCnt  : Integer;
    WindCnt2 : Integer;    //winding count of the opposite PolyType
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
    Y   : cInt;
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
    Y         : cInt;
    LeftBound : PEdge;
    RightBound: PEdge;
    Next      : PLocalMinima;
  end;

  POutRec = ^TOutRec;
  TOutRec = record
    Idx         : Integer;
    BottomPt    : POutPt;
    IsHole      : Boolean;
    IsOpen      : Boolean;
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

  PJoin = ^TJoin;
  TJoin = record
    OutPt1   : POutPt;
    OutPt2   : POutPt;
    OffPt    : TIntPoint; //offset point (provides slope of common edges)
  end;

  TClipperBase = class
  private
    FEdgeList         : TList;
    FLmList           : PLocalMinima; //localMinima list
    FCurrLm           : PLocalMinima; //current localMinima node
    FUse64BitRange    : Boolean;      //see LoRange and HiRange consts notes below
    FHasOpenPaths     : Boolean;
    procedure DisposeLocalMinimaList;
    procedure DisposePolyPts(PP: POutPt);
  protected
    FPreserveCollinear : Boolean;
    procedure Reset; virtual;
    procedure PopLocalMinima;
    property CurrentLm: PLocalMinima read FCurrLm;
    property HasOpenPaths: Boolean read FHasOpenPaths;
  public
    constructor Create; virtual;
    destructor Destroy; override;
    procedure Clear; virtual;

    function AddPath(const Path: TPath; PolyType: TPolyType; Closed: Boolean): Boolean;
    function AddPaths(const Paths: TPaths; PolyType: TPolyType; Closed: Boolean): Boolean;

{$IFDEF use_deprecated}
    function AddPolygon(const Path: TPath; PolyType: TPolyType): Boolean;
    function AddPolygons(const Paths: TPaths; PolyType: TPolyType): Boolean;
{$ENDIF}

    //PreserveCollinear: Prevents removal of 'inner' vertices when three or
    //more vertices are collinear in solution polygons.
    property PreserveCollinear: Boolean
      read FPreserveCollinear write FPreserveCollinear;
  end;

  TClipper = class(TClipperBase)
  private
    FPolyOutList      : TList;
    FJoinList         : TList;
    FGhostJoinList    : TList;
    FClipType         : TClipType;
    FScanbeam         : PScanbeam; //scanbeam list
    FActiveEdges      : PEdge;     //active Edge list
    FSortedEdges      : PEdge;     //used for temporary sorting
    FIntersectNodes   : PIntersectNode;
    FClipFillType     : TPolyFillType;
    FSubjFillType     : TPolyFillType;
    FExecuteLocked    : Boolean;
    FReverseOutput    : Boolean;
    FStrictSimple      : Boolean;
    FUsingPolyTree    : Boolean;
{$IFDEF use_xyz}
    FZFillCallback    : TZFillCallback;
{$ENDIF}
    procedure DisposeScanbeamList;
    procedure InsertScanbeam(const Y: cInt);
    function PopScanbeam: cInt;
    procedure SetWindingCount(Edge: PEdge);
    function IsEvenOddFillType(Edge: PEdge): Boolean;
    function IsEvenOddAltFillType(Edge: PEdge): Boolean;
    procedure AddEdgeToSEL(Edge: PEdge);
    procedure CopyAELToSEL;
    procedure InsertLocalMinimaIntoAEL(const BotY: cInt);
    procedure SwapPositionsInAEL(E1, E2: PEdge);
    procedure SwapPositionsInSEL(E1, E2: PEdge);
    procedure ProcessHorizontal(HorzEdge: PEdge; IsTopOfScanbeam: Boolean);
    procedure ProcessHorizontals(IsTopOfScanbeam: Boolean);
    procedure InsertIntersectNode(E1, E2: PEdge; const Pt: TIntPoint);
    function ProcessIntersections(const BotY, TopY: cInt): Boolean;
    procedure BuildIntersectList(const BotY, TopY: cInt);
    procedure ProcessIntersectList;
    procedure DeleteFromAEL(E: PEdge);
    procedure DeleteFromSEL(E: PEdge);
    procedure IntersectEdges(E1,E2: PEdge;
      const Pt: TIntPoint; Protect: Boolean = False);
    procedure DoMaxima(E: PEdge);
    procedure UpdateEdgeIntoAEL(var E: PEdge);
    function FixupIntersectionOrder: Boolean;
    procedure ProcessEdgesAtTopOfScanbeam(const TopY: cInt);
    function IsContributing(Edge: PEdge): Boolean;
    function CreateOutRec: POutRec;
    function AddOutPt(E: PEdge; const Pt: TIntPoint): POutPt;
    procedure AddLocalMaxPoly(E1, E2: PEdge; const Pt: TIntPoint);
    function AddLocalMinPoly(E1, E2: PEdge; const Pt: TIntPoint): POutPt;
    function GetOutRec(Idx: integer): POutRec;
    procedure AppendPolygon(E1, E2: PEdge);
    procedure DisposeAllOutRecs;
    procedure DisposeOutRec(Index: Integer);
    procedure DisposeIntersectNodes;
    function BuildResult: TPaths;
    function BuildResult2(PolyTree: TPolyTree): Boolean;
    procedure FixupOutPolygon(OutRec: POutRec);
    procedure SetHoleState(E: PEdge; OutRec: POutRec);
    procedure AddJoin(Op1, Op2: POutPt; const OffPt: TIntPoint);
    procedure ClearJoins;
    procedure AddGhostJoin(OutPt: POutPt; const OffPt: TIntPoint);
    procedure ClearGhostJoins;
    function JoinPoints(Jr: PJoin; out P1, P2: POutPt): Boolean;
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
      out solution: TPaths;
      subjFillType: TPolyFillType = pftEvenOdd;
      clipFillType: TPolyFillType = pftEvenOdd): Boolean; overload;
    function Execute(clipType: TClipType;
      var PolyTree: TPolyTree;
      subjFillType: TPolyFillType = pftEvenOdd;
      clipFillType: TPolyFillType = pftEvenOdd): Boolean; overload;
    constructor Create(InitOptions: TInitOptions = []); reintroduce; overload;
    destructor Destroy; override;
    procedure Clear; override;
    //ReverseSolution: reverses the default orientation
    property ReverseSolution: Boolean read FReverseOutput write FReverseOutput;
    //StrictlySimple: when false (the default) solutions are 'weakly' simple
    property StrictlySimple: Boolean read FStrictSimple write FStrictSimple;
{$IFDEF use_xyz}
    property ZFillFunction: TZFillCallback read FZFillCallback write FZFillCallback;
{$ENDIF}
  end;

function Orientation(const Pts: TPath): Boolean; overload;
function Area(const Pts: TPath): Double; overload;

{$IFDEF use_xyz}
function IntPoint(const X, Y: Int64; Z: Int64 = 0): TIntPoint;
{$ELSE}
function IntPoint(const X, Y: cInt): TIntPoint;
{$ENDIF}

function DoublePoint(const X, Y: Double): TDoublePoint; overload;
function DoublePoint(const Ip: TIntPoint): TDoublePoint; overload;

function ReversePath(const Pts: TPath): TPath;
function ReversePaths(const Pts: TPaths): TPaths;

function OffsetPaths(const Polys: TPaths; const Delta: Double;
  JoinType: TJoinType = jtSquare; EndType: TEndType = etClosed;
  Limit: Double = 0): TPaths;

{$IFDEF use_deprecated}
function ReversePolygon(const Pts: TPolygon): TPolygon;
function ReversePolygons(const Pts: TPolygons): TPolygons;
function OffsetPolygons(const Polys: TPolygons; const Delta: Double;
  JoinType: TJoinType = jtSquare; Limit: Double = 0;
  AutoFix: Boolean = True): TPolygons;
function PolyTreeToPolygons(PolyTree: TPolyTree): TPolygons;
{$ENDIF}

//SimplifyPolygon converts a self-intersecting polygon into a simple polygon.
function SimplifyPolygon(const Poly: TPath; FillType: TPolyFillType = pftEvenOdd): TPaths;
function SimplifyPolygons(const Polys: TPaths; FillType: TPolyFillType = pftEvenOdd): TPaths;

//CleanPolygon removes adjacent vertices closer than the specified distance.
function CleanPolygon(const Poly: TPath; Distance: double = 1.415): TPath;
function CleanPolygons(const Polys: TPaths; Distance: double = 1.415): TPaths;

function PolyTreeToPaths(PolyTree: TPolyTree): TPaths;
function ClosedPathsFromPolyTree(PolyTree: TPolyTree): TPaths;
function OpenPathsFromPolyTree(PolyTree: TPolyTree): TPaths;

implementation

const
  Horizontal: Double = -3.4e+38;

  Unassigned : Integer = -1;
  Skip       : Integer = -2; //flag for the edge that closes an open path

  //The SlopesEqual function places the most limits on coordinate values
  //So, to avoid overflow errors, they must not exceed the following values...
  //Also, if all coordinates are within +/-LoRange, then calculations will be
  //faster. Otherwise using Int128 math will render the library ~10-15% slower.
{$IFDEF use_int32}
  LoRange: cInt = 46340;
  HiRange: cInt = 46340;
{$ELSE}
  LoRange: cInt = $B504F333;          //3.0e+9
  HiRange: cInt = $7FFFFFFFFFFFFFFF;  //9.2e+18
{$ENDIF}

resourcestring
  rsDoMaxima = 'DoMaxima error';
  rsUpdateEdgeIntoAEL = 'UpdateEdgeIntoAEL error';
  rsHorizontal = 'ProcessHorizontal error';
  rsInvalidInt = 'Coordinate exceeds range bounds';
  rsIntersect = 'Intersection error';
  rsOpenPath  = 'AddPath: Open paths must be subject.';
  rsOpenPath2  = 'AddPath: Open paths have been disabled.';
  rsOpenPath3  = 'Error: TPolyTree struct is need for open path clipping.';
  rsPolylines = 'Error intersecting polylines';

{$IFDEF FPC}
  {$DEFINE INLINING}
{$ELSE}
  {$IF CompilerVersion >= 20}
    {$DEFINE INLINING}
  {$IFEND}
{$ENDIF}

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

{$IFNDEF use_int32}

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

//function Int128AsDouble(val: TInt128): Double;
//const
//  shift64: Double = 18446744073709551616.0;
//var
//  lo: Int64;
//begin
//  if (val.Hi < 0) then
//  begin
//    lo := -val.Lo;
//    if lo = 0 then
//      Result := val.Hi * shift64 else
//      Result := -(not val.Hi * shift64 + UInt64(lo));
//  end else
//    Result := val.Hi * shift64 + UInt64(val.Lo);
//end;
//------------------------------------------------------------------------------

{$OVERFLOWCHECKS ON}

{$ENDIF}

//------------------------------------------------------------------------------
// Miscellaneous Functions ...
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
  {$IFDEF INLINING} inline; {$ENDIF}
begin
  Result := (P1.X = P2.X) and (P1.Y = P2.Y);
end;
//------------------------------------------------------------------------------

{$IFDEF use_xyz}
function IntPoint(const X, Y: Int64; Z: Int64 = 0): TIntPoint;
begin
  Result.X := X;
  Result.Y := Y;
  Result.Z := Z;
end;
{$ELSE}
function IntPoint(const X, Y: cInt): TIntPoint;
begin
  Result.X := X;
  Result.Y := Y;
end;
{$ENDIF}
//------------------------------------------------------------------------------

function DoublePoint(const X, Y: Double): TDoublePoint;
begin
  Result.X := X;
  Result.Y := Y;
end;
//------------------------------------------------------------------------------

function DoublePoint(const Ip: TIntPoint): TDoublePoint;
begin
  Result.X := Ip.X;
  Result.Y := Ip.Y;
end;
//------------------------------------------------------------------------------

function Area(const Pts: TPath): Double;
var
  I, HighI: Integer;
  D, D2: Double;
begin
  Result := 0;
  HighI := high(Pts);
  if HighI < 2 then Exit;
  //see http://www.mathopenref.com/coordpolygonarea2.html
  D2 := (Pts[HighI].X + Pts[0].X);
  D := D2 * (Pts[0].Y - Pts[HighI].Y);
  for I := 1 to HighI do
  begin
    D2 := (Pts[I-1].X + Pts[I].X); //ie forces floating point multiplication
    D := D + D2 * (Pts[I].Y - Pts[I-1].Y);
  end;
  Result := D / 2;
end;
//------------------------------------------------------------------------------

function Area(OutRec: POutRec): Double; overload;
var
  Op: POutPt;
  D, D2: Double;
begin
  D := 0;
  Op := OutRec.Pts;
  if Assigned(Op) then
    repeat
      //nb: subtraction reversed since vertices are stored in reverse order ...
      D2 := (Op.Pt.X + Op.Prev.Pt.X);
      D := D + D2 * (Op.Prev.Pt.Y - Op.Pt.Y);
      Op := Op.Next;
    until Op = OutRec.Pts;
  Result := D / 2;
end;
//------------------------------------------------------------------------------

function Orientation(const Pts: TPath): Boolean;
begin
  Result := Area(Pts) >= 0;
end;
//------------------------------------------------------------------------------

function ReversePath(const Pts: TPath): TPath;
var
  I, HighI: Integer;
begin
  HighI := high(Pts);
  SetLength(Result, HighI +1);
  for I := 0 to HighI do
    Result[I] := Pts[HighI - I];
end;
//------------------------------------------------------------------------------

function ReversePaths(const Pts: TPaths): TPaths;
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

function PointOnLineSegment(const Pt, LinePt1, LinePt2: TIntPoint;
  UseFullInt64Range: Boolean): Boolean;
begin
{$IFNDEF use_int32}
  if UseFullInt64Range then
    Result :=
      ((Pt.X = LinePt1.X) and (Pt.Y = LinePt1.Y)) or
      ((Pt.X = LinePt2.X) and (Pt.Y = LinePt2.Y)) or
      (((Pt.X > LinePt1.X) = (Pt.X < LinePt2.X)) and
      ((Pt.Y > LinePt1.Y) = (Pt.Y < LinePt2.Y)) and
      Int128Equal(Int128Mul((Pt.X - LinePt1.X), (LinePt2.Y - LinePt1.Y)),
      Int128Mul((LinePt2.X - LinePt1.X), (Pt.Y - LinePt1.Y))))
  else
{$ENDIF}
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
{$IFNDEF use_int32}
  A, B: TInt128;
{$ENDIF}
begin
  Result := False;
  Pp2 := PP;
{$IFNDEF use_int32}
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
{$ENDIF}
    repeat
      if ((((Pp2.Pt.Y <= Pt.Y) and (Pt.Y < Pp2.Prev.Pt.Y)) or
        ((Pp2.Prev.Pt.Y <= Pt.Y) and (Pt.Y < Pp2.Pt.Y))) and
        (Pt.X < (Pp2.Prev.Pt.X - Pp2.Pt.X) * (Pt.Y - Pp2.Pt.Y) /
        (Pp2.Prev.Pt.Y - Pp2.Pt.Y) + Pp2.Pt.X)) then Result := not Result;
      Pp2 := Pp2.Next;
    until Pp2 = PP;
end;
//------------------------------------------------------------------------------

function SlopesEqual(E1, E2: PEdge;
  UseFullInt64Range: Boolean): Boolean; overload;
begin
{$IFNDEF use_int32}
  if UseFullInt64Range then
    Result := Int128Equal(Int128Mul(E1.Delta.Y, E2.Delta.X),
      Int128Mul(E1.Delta.X, E2.Delta.Y))
  else
{$ENDIF}
    Result := E1.Delta.Y * E2.Delta.X = E1.Delta.X * E2.Delta.Y;
end;
//---------------------------------------------------------------------------

function SlopesEqual(const Pt1, Pt2, Pt3: TIntPoint;
  UseFullInt64Range: Boolean): Boolean; overload;
begin
{$IFNDEF use_int32}
  if UseFullInt64Range then
    Result := Int128Equal(
      Int128Mul(Pt1.Y-Pt2.Y, Pt2.X-Pt3.X), Int128Mul(Pt1.X-Pt2.X, Pt2.Y-Pt3.Y))
  else
{$ENDIF}
    Result := (Pt1.Y-Pt2.Y)*(Pt2.X-Pt3.X) = (Pt1.X-Pt2.X)*(Pt2.Y-Pt3.Y);
end;
//---------------------------------------------------------------------------

(*****************************************************************************
*  Dx:                  0(90º)                       Slope:   0  = Dx: -inf  *
*                       |                            Slope: 0.5  = Dx:   -2  *
*      +inf (180º) <--- o ---> -inf (0º)             Slope: 2.0  = Dx: -0.5  *
*                                                    Slope: inf  = Dx:    0  *
*****************************************************************************)

function GetDx(const Pt1, Pt2: TIntPoint): Double;
begin
  if (Pt1.Y = Pt2.Y) then Result := Horizontal
  else Result := (Pt2.X - Pt1.X)/(Pt2.Y - Pt1.Y);
end;
//---------------------------------------------------------------------------

procedure SetDx(E: PEdge); {$IFDEF INLINING} inline; {$ENDIF}
begin
  E.Delta.X := (E.Top.X - E.Bot.X);
  E.Delta.Y := (E.Top.Y - E.Bot.Y);
  if E.Delta.Y = 0 then E.Dx := Horizontal
  else E.Dx := E.Delta.X/E.Delta.Y;
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

function TopX(Edge: PEdge; const currentY: cInt): cInt;
begin
  if currentY = Edge.Top.Y then Result := Edge.Top.X
  else if Edge.Top.X = Edge.Bot.X then Result := Edge.Bot.X
  else Result := Edge.Bot.X + round(Edge.Dx*(currentY - Edge.Bot.Y));
end;
//------------------------------------------------------------------------------

{$IFDEF use_xyz}
procedure GetZ(var Pt: TIntPoint; E: PEdge); {$IFDEF INLINING} inline; {$ENDIF}
begin
  if PointsEqual(Pt, E.Bot) then Pt.Z := E.Bot.Z
  else if PointsEqual(Pt, E.Top) then Pt.Z := E.Top.Z
  else if E.WindDelta > 0 then Pt.Z := E.Bot.Z
  else Pt.Z := E.Top.Z;
end;
//------------------------------------------------------------------------------

Procedure SetZ(var Pt: TIntPoint; E, eNext: PEdge; ZFillFunc: TZFillCallback);
var
  Pt1, Pt2: TIntPoint;
begin
  Pt.Z := 0;
  if assigned(ZFillFunc) then
  begin
    Pt1 := Pt;
    GetZ(Pt1, E);
    Pt2 := Pt;
    GetZ(Pt2, eNext);
    ZFillFunc(Pt1.Z, Pt2.Z, Pt);
  end;
end;
//------------------------------------------------------------------------------
{$ENDIF}

function IntersectPoint(Edge1, Edge2: PEdge;
  out ip: TIntPoint; UseFullInt64Range: Boolean): Boolean; overload;
var
  B1,B2,M: Double;
begin
{$IFDEF use_xyz}
  ip.Z := 0;
{$ENDIF}
  if SlopesEqual(Edge1, Edge2, UseFullInt64Range) then
  begin
    //parallel edges, but nevertheless prepare to force the intersection
    //since Edge2.Curr.X < Edge1.Curr.X ...
    if Edge2.Bot.Y > Edge1.Bot.Y then
      ip.Y := Edge2.Bot.Y else
      ip.Y := Edge1.Bot.Y;
    Result := False;
    Exit;
  end;
  if Edge1.Delta.X = 0 then
  begin
    ip.X := Edge1.Bot.X;
    if Edge2.Dx = Horizontal then
      ip.Y := Edge2.Bot.Y
    else
    begin
      with Edge2^ do B2 := Bot.Y - (Bot.X/Dx);
      ip.Y := round(ip.X/Edge2.Dx + B2);
    end;
  end
  else if Edge2.Delta.X = 0 then
  begin
    ip.X := Edge2.Bot.X;
    if Edge1.Dx = Horizontal then
      ip.Y := Edge1.Bot.Y
    else
    begin
      with Edge1^ do B1 := Bot.Y - (Bot.X/Dx);
      ip.Y := round(ip.X/Edge1.Dx + B1);
    end;
  end else
  begin
    with Edge1^ do B1 := Bot.X - Bot.Y * Dx;
    with Edge2^ do B2 := Bot.X - Bot.Y * Dx;
    M := (B2-B1)/(Edge1.Dx - Edge2.Dx);
    ip.Y := round(M);
    if Abs(Edge1.Dx) < Abs(Edge2.Dx) then
      ip.X := round(Edge1.Dx * M + B1)
    else
      ip.X := round(Edge2.Dx * M + B2);
  end;

  //The precondition - E.Curr.X > eNext.Curr.X - indicates that the two edges do
  //intersect below TopY (and hence below the tops of either Edge). However,
  //when edges are almost parallel, rounding errors may cause False positives -
  //indicating intersections when there really aren't any. Also, floating point
  //imprecision can incorrectly place an intersect point beyond/above an Edge.
  //Therfore, further validation of the IP is warranted ...
  if (ip.Y < Edge1.Top.Y) or (ip.Y < Edge2.Top.Y) then
  begin
    //Find the lower top of the two edges and compare X's at this Y.
    //If Edge1's X is greater than Edge2's X then it's fair to assume an
    //intersection really has occurred...
    if (Edge1.Top.Y > Edge2.Top.Y) then
    begin
      ip.Y := edge1.Top.Y;
      ip.X := TopX(edge2, edge1.Top.Y);
      Result := ip.X < edge1.Top.X;
    end else
    begin
      ip.Y := edge2.Top.Y;
      ip.X := TopX(edge1, edge2.Top.Y);
      Result := ip.X > edge2.Top.X;
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

function Pt2IsBetweenPt1AndPt3(const Pt1, Pt2, Pt3: TIntPoint): Boolean;
begin
  //nb: assumes collinearity.
  if PointsEqual(Pt1, Pt3) or PointsEqual(Pt1, Pt2) or PointsEqual(Pt3, Pt2) then
    Result := False
  else if (Pt1.X <> Pt3.X) then
    Result := (Pt2.X > Pt1.X) = (Pt2.X < Pt3.X)
  else
    Result := (Pt2.Y > Pt1.Y) = (Pt2.Y < Pt3.Y);
end;
//------------------------------------------------------------------------------

function GetOverlap(const A1, A2, B1, B2: cInt; out Left, Right: cInt): Boolean;
begin
  if (A1 < A2) then
  begin
    if (B1 < B2) then begin Left := Max(A1,B1); Right := Min(A2,B2); end
    else begin Left := Max(A1,B2); Right := Min(A2,B1); end;
  end else
  begin
    if (B1 < B2) then begin Left := Max(A2,B1); Right := Min(A1,B2); end
    else begin Left := Max(A2,B2); Right := Min(A1,B1); end
  end;
  Result := Left < Right;
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

procedure RangeTest(const Pt: TIntPoint; var Use64BitRange: Boolean);
begin
  if Use64BitRange then
  begin
    if (Pt.X > HiRange) or (Pt.Y > HiRange) or
      (-Pt.X > HiRange) or (-Pt.Y > HiRange) then
        raise exception.Create(rsInvalidInt);
  end
  else if (Pt.X > LoRange) or (Pt.Y > LoRange) or
    (-Pt.X > LoRange) or (-Pt.Y > LoRange) then
  begin
    Use64BitRange := true;
    RangeTest(Pt, Use64BitRange);
  end;
end;
//------------------------------------------------------------------------------

procedure ReverseHorizontal(E: PEdge);
var
  tmp: cInt;
begin
  //swap horizontal edges' top and bottom x's so they follow the natural
  //progression of the bounds - ie so their xbots will align with the
  //adjoining lower Edge. [Helpful in the ProcessHorizontal() method.]
  tmp := E.Top.X;
  E.Top.X := E.Bot.X;
  E.Bot.X := tmp;

{$IFDEF use_xyz}
  tmp := E.Top.Z;
  E.Top.Z := E.Bot.Z;
  E.Bot.Z := tmp;
{$ENDIF}
end;
//------------------------------------------------------------------------------

procedure InitEdge(E, Next, Prev: PEdge;
  const Pt: TIntPoint); {$IFDEF INLINING} inline; {$ENDIF}
begin
  E.Curr := Pt;
  E.Next := Next;
  E.Prev := Prev;
  E.OutIdx := -1;
end;
//------------------------------------------------------------------------------

procedure InitEdge2(E: PEdge; PolyType: TPolyType); {$IFDEF INLINING} inline; {$ENDIF}
begin
  if E.Curr.Y >= E.Next.Curr.Y then
  begin
    E.Bot := E.Curr;
    E.Top := E.Next.Curr;
  end else
  begin
    E.Top := E.Curr;
    E.Bot := E.Next.Curr;
  end;
  SetDx(E);
  E.PolyType := PolyType;
end;
//------------------------------------------------------------------------------

function RemoveEdge(E: PEdge): PEdge; {$IFDEF INLINING} inline; {$ENDIF}
begin
  //removes E from double_linked_list (but without disposing from memory)
  E.Prev.Next := E.Next;
  E.Next.Prev := E.Prev;
  Result := E.Next;
  E.Prev := nil; //flag as removed (see ClipperBase.Clear)
end;
//------------------------------------------------------------------------------

function SharedVertWithPrevAtTop(Edge: PEdge): Boolean;
var
  E: PEdge;
begin
  Result := True;
  E := Edge;
  while E.Prev <> Edge do
  begin
    if PointsEqual(E.Top, E.Prev.Top) then
    begin
      if PointsEqual(E.Bot, E.Prev.Bot) then
      begin E := E.Prev; Continue; end
      else Result := True;
    end else
      Result := False;
     Break;
  end;
  while E <> Edge do
  begin
    Result := not Result;
    E := E.Next;
  end;
end;
//------------------------------------------------------------------------------

function SharedVertWithNextIsBot(Edge: PEdge): Boolean;
var
  E: PEdge;
  A,B: Boolean;
begin
  Result := True;
  E := Edge;
  while E.Prev <> Edge do
  begin
    A := PointsEqual(E.Next.Bot, E.Bot);
    B := PointsEqual(E.Prev.Bot, E.Bot);
    if A <> B then
    begin
      Result := A;
      Break;
    end;
    A := PointsEqual(E.Next.Top, E.Top);
    B := PointsEqual(E.Prev.Top, E.Top);
    if A <> B then
    begin
      Result := B;
      Break;
    end;
    E := E.Prev;
  end;
  while E <> Edge do
  begin
    Result := not Result;
    E := E.Next;
  end;
end;
//------------------------------------------------------------------------------

function GetLastHorz(Edge: PEdge): PEdge; {$IFDEF INLINING} inline; {$ENDIF}
begin
  Result := Edge;
  while (Result.OutIdx <> Skip) and
    (Result.Next <> Edge) and (Result.Next.Dx = Horizontal) do
      Result := Result.Next;
end;
//------------------------------------------------------------------------------

function MoreBelow(Edge: PEdge): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
var
  E: PEdge;
begin
  //Edge is Skip heading down.
  E := Edge;
  if E.Dx = Horizontal then
  begin
    while E.Next.Dx = Horizontal do E := E.Next;
    Result := E.Next.Bot.Y > E.Bot.Y;
  end else if E.Next.Dx = Horizontal then
  begin
    while E.Next.Dx = Horizontal do E := E.Next;
    Result := E.Next.Bot.Y > E.Bot.Y;
  end else
    Result := PointsEqual(E.Bot, E.Next.Top);
end;
//------------------------------------------------------------------------------

function JustBeforeLocMin(Edge: PEdge): Boolean;
var
  E: PEdge;
begin
  //Edge is Skip and was heading down.
  E := Edge;
  if E.Dx = Horizontal then
  begin
    while E.Next.Dx = Horizontal do E := E.Next;
    Result := E.Next.Top.Y < E.Bot.Y;
  end else
    result := SharedVertWithNextIsBot(E);
end;
//------------------------------------------------------------------------------

function MoreAbove(Edge: PEdge): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  if (Edge.Dx = Horizontal)  then
  begin
    Edge := GetLastHorz(Edge);
    Result := (Edge.Next.Top.Y < Edge.Top.Y);
  end else if (Edge.Next.Dx = Horizontal) then
  begin
    Edge := GetLastHorz(Edge.Next);
    Result := (Edge.Next.Top.Y < Edge.Top.Y);
  end else
    Result := (Edge.Next.Top.Y < Edge.Top.Y);
end;
//------------------------------------------------------------------------------

function AllHorizontal(Edge: PEdge): Boolean;
var
  E: PEdge;
begin
  Result := Edge.Dx = Horizontal;
  if not Result then Exit;
  E := Edge.Next;
  while (E <> Edge) do
    if E.Dx <> Horizontal then
    begin
      Result := False;
      Exit;
    end else
      E := E.Next;
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

function TClipperBase.AddPath(const Path: TPath;
  PolyType: TPolyType; Closed: Boolean): Boolean;

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

  procedure DoMinimaLML(E1, E2: PEdge);
  var
    NewLm: PLocalMinima;
  begin
    if not assigned(E1) then
    begin
      if not assigned(E2) then Exit;
      new(NewLm);
      NewLm.Next := nil;
      NewLm.Y := E2.Bot.Y;
      NewLm.LeftBound := nil;
      E2.WindDelta := 0;
      NewLm.RightBound := E2;
      InsertLocalMinima(NewLm);
    end else
    begin
      //E and E.Prev are now at a local minima ...
      new(NewLm);
      NewLm.Y := E1.Bot.Y;
      NewLm.Next := nil;
      if E2.Dx = Horizontal then //Horz. edges never start a left bound
      begin
        if (E2.Bot.X <> E1.Bot.X) then ReverseHorizontal(E2);
        NewLm.LeftBound := E1;
        NewLm.RightBound := E2;
      end else if (E2.Dx < E1.Dx) then
      begin
        NewLm.LeftBound := E1;
        NewLm.RightBound := E2;
      end else
      begin
        NewLm.LeftBound := E2;
        NewLm.RightBound := E1;
      end;
      NewLm.LeftBound.Side := esLeft;
      NewLm.RightBound.Side := esRight;
      //set the winding state of the first edge in each bound
      //(it'll be copied to subsequent edges in the bound) ...
      with NewLm^ do
      begin
        if not Closed then LeftBound.WindDelta := 0
        else if (LeftBound.Next = RightBound) then LeftBound.WindDelta := -1
        else LeftBound.WindDelta := 1;
        RightBound.WindDelta := -LeftBound.WindDelta;
      end;
      InsertLocalMinima(NewLm);
    end;
  end;
  //----------------------------------------------------------------------

  function DescendToMin(var E: PEdge): PEdge;
  var
    EHorz: PEdge;
  begin
    //PRECONDITION: STARTING EDGE IS A VALID DESCENDING EDGE.
    //Starting at the top of one bound we progress to the bottom where there's
    //A local minima. We then go to the top of the Next bound. These two bounds
    //form the left and right (or right and left) bounds of the local minima.
    E.NextInLML := nil;
    if (E.Dx = Horizontal) then
    begin
      EHorz := E;
      while (EHorz.Next.Dx = Horizontal) do EHorz := EHorz.Next;
      if not PointsEqual(EHorz.Bot, EHorz.Next.Top) then
        ReverseHorizontal(E);
    end;
    while true do
    begin
      E := E.Next;
      if (E.OutIdx = Skip) then Break
      else if E.Dx = Horizontal then
      begin
        //nb: proceed through horizontals when approaching from their right,
        //    but break on horizontal minima if approaching from their left.
        //    This ensures 'local minima' are always on the left of horizontals.

        //look ahead is required in case of multiple consec. horizontals
        EHorz := GetLastHorz(E);
        if (EHorz = E.Prev) or                    //horizontal polyline OR
          ((EHorz.Next.Top.Y < E.Top.Y) and       //bottom horizontal
          (EHorz.Next.Bot.X > E.Prev.Bot.X)) then //approaching from the left
            Break;
        if (E.Top.X <> E.Prev.Bot.X) then ReverseHorizontal(E);
        if EHorz.OutIdx = Skip then EHorz := EHorz.Prev;
        while E <> EHorz do
        begin
          E.NextInLML := E.Prev;
          E := E.Next;
          if (E.Top.X <> E.Prev.Bot.X) then ReverseHorizontal(E);
        end;
      end
      else if (E.Bot.Y = E.Prev.Bot.Y) then Break;
      E.NextInLML := E.Prev;
    end;
    Result := E.Prev;
  end;
  //----------------------------------------------------------------------

  procedure AscendToMax(var E: PEdge; Appending: Boolean);
  var
    EStart: PEdge;
  begin
    if (E.OutIdx = Skip) then
    begin
      E := E.Next;
      if not MoreAbove(E.Prev) then Exit;
    end;

    if (E.Dx = Horizontal) and Appending and
      not PointsEqual(E.Bot, E.Prev.Bot) then
        ReverseHorizontal(E);
    //now process the ascending bound ....
    EStart := E;
    while True do
    begin
      if (E.Next.OutIdx = Skip) or
        ((E.Next.Top.Y = E.Top.Y) and (E.Next.Dx <> Horizontal)) then Break;
      E.NextInLML := E.Next;
      E := E.Next;
      if (E.Dx = Horizontal) and (E.Bot.X <> E.Prev.Top.X) then
        ReverseHorizontal(E);
    end;

    if not Appending then
    begin
      if EStart.OutIdx = Skip then EStart := EStart.Next;
      if (EStart <> E.Next) then
        DoMinimaLML(nil, EStart);
    end;
    E := E.Next;
  end;
  //----------------------------------------------------------------------

  function AddBoundsToLML(E: PEdge): PEdge;
  var
    AppendMaxima: Boolean;
    B: PEdge;
  begin
    //Starting at the top of one bound we progress to the bottom where there's
    //A local minima. We then go to the top of the Next bound. These two bounds
    //form the left and right (or right and left) bounds of the local minima.

    //do minima ...
    if E.OutIdx = Skip then
    begin
      if MoreBelow(E) then
      begin
        E := E.Next;
        B := DescendToMin(E);
      end else
        B := nil;
    end else
      B := DescendToMin(E);

    if (E.OutIdx = Skip) then    //nb: may be BEFORE, AT or just THRU LM
    begin
      //do minima before Skip...
      DoMinimaLML(nil, B);      //store what we've got so far (if anything)
      AppendMaxima := False;
      //finish off any minima ...
      if not PointsEqual(E.Bot,E.Prev.Bot) and MoreBelow(E) then
      begin
        E := E.Next;
        B := DescendToMin(E);
        DoMinimaLML(B, E);
        AppendMaxima := True;
      end
      else if JustBeforeLocMin(E) then
        E := E.Next;
    end else
    begin
      DoMinimaLML(B, E);
      AppendMaxima := True;
    end;

    //now do maxima ...
    AscendToMax(E, AppendMaxima);

    if (E.OutIdx = Skip) and not PointsEqual(E.Top, E.Prev.Top) then
    begin
      //may be BEFORE, AT or just AFTER maxima
      //finish off any maxima ...
      if MoreAbove(E) then
      begin
        E := E.Next;
        AscendToMax(E, false);
      end
      else if PointsEqual(E.Top, E.Next.Top) or
       ((E.Next.Dx = Horizontal) and PointsEqual(E.Top, E.Next.Bot)) then
        E := E.Next; //ie just before Maxima
    end;
    Result := E;
  end;
  //----------------------------------------------------------------------

var
  I, HighI: Integer;
  Edges: PEdgeArray;
  E, EStart, ELoopStop, EHighest: PEdge;
  ClosedOrSemiClosed: Boolean;
begin
  {AddPath}
  Result := False; //ie assume nothing added
  HighI := High(Path);
  if HighI < 1 then Exit;

{$IFDEF use_lines}
  if not Closed and (polyType = ptClip) then
    raise exception.Create(rsOpenPath);
{$ELSE}
  if not Closed then raise exception.Create(rsOpenPath2);
{$ENDIF}

  ClosedOrSemiClosed := Closed or PointsEqual(Path[0],Path[HighI]);
  while (HighI > 0) and PointsEqual(Path[HighI],Path[HighI -1]) do Dec(HighI);
  if (highI > 0) and PointsEqual(Path[0],Path[highI]) then Dec(HighI);
  if (Closed and (HighI < 2)) or (not Closed and (HighI < 1)) then Exit;

  //1. Basic initialization of Edges ...
  GetMem(Edges, sizeof(TEdge)*(HighI +1));
  try
    FillChar(Edges^, sizeof(TEdge)*(HighI +1), 0);
    Edges[1].Curr := Path[1];
    RangeTest(Path[0], FUse64BitRange);
    RangeTest(Path[HighI], FUse64BitRange);
    InitEdge(@Edges[0], @Edges[1], @Edges[HighI], Path[0]);
    InitEdge(@Edges[HighI], @Edges[0], @Edges[HighI-1], Path[HighI]);
    for I := HighI - 1 downto 1 do
    begin
      RangeTest(Path[I], FUse64BitRange);
      InitEdge(@Edges[I], @Edges[I+1], @Edges[I-1], Path[I]);
    end;
  except
    FreeMem(Edges);
    raise; //Range test fails
  end;

  EStart := @Edges[0];
  if not ClosedOrSemiClosed then EStart.Prev.OutIdx := Skip;

  //2. Remove duplicate vertices, and collinear edges (when closed) ...
  E := EStart;
  ELoopStop := EStart;
  while (E <> E.Next) do //ie in case loop reduces to a single vertex
  begin
    if PointsEqual(E.Curr, E.Next.Curr) then
    begin
      //nb E.OutIdx never equals Skip here because it would then be SemiClosed
      if E = EStart then EStart := E.Next;
      E := RemoveEdge(E);
      ELoopStop := E;
      Continue;
    end;
    if (E.Prev = E.Next) then
      Break //only two vertices
    else if (ClosedOrSemiClosed or
      ((E.Prev.OutIdx <> Skip) and (E.OutIdx <> Skip) and
      (E.Next.OutIdx <> Skip))) and
      SlopesEqual(E.Prev.Curr, E.Curr, E.Next.Curr, FUse64BitRange) then
    begin
      //All collinear edges are allowed for open paths but in closed paths
      //inner vertices of adjacent collinear edges are removed. However if the
      //PreserveCollinear property has been enabled, only overlapping collinear
      //edges (ie spikes) are removed from closed paths.
      if Closed and (not FPreserveCollinear or
        not Pt2IsBetweenPt1AndPt3(E.Prev.Curr, E.Curr, E.Next.Curr)) then
      begin
        if E = EStart then EStart := E.Next;
        E := RemoveEdge(E);
        E := E.Prev;
        ELoopStop := E;
        Continue;
      end;
    end;
    E := E.Next;
    if E = ELoopStop then Break;
  end;

  if (not Closed and (E = E.Next)) or (Closed and (E.Prev = E.Next)) then
  begin
    FreeMem(Edges);
    Exit;
  end;

  if not Closed then
    FHasOpenPaths := True;

  //3. Do the final Init and also find the 'highest' Edge.
  //(nb: since I'm much more familiar with positive downwards Y axes,
  //'highest' here is the Edge with the *smallest* Top.Y.)
  E := EStart;
  EHighest := E;
  repeat
    InitEdge2(E, PolyType);
    if E.Top.Y < EHighest.Top.Y then EHighest := E;
    E := E.Next;
  until E = EStart;

  Result := True;
  FEdgeList.Add(Edges);

  //4. build the local minima list ...
  if AllHorizontal(E) then
  begin
    if ClosedOrSemiClosed then
      E.Prev.OutIdx := Skip;
    AscendToMax(E, false);
    Exit;
  end;

  //if eHighest is also the Skip then it's a natural break, otherwise
  //make sure eHighest is positioned so we're either at a top horizontal or
  //just starting to head down one edge of the polygon
  E := EStart.Prev; //EStart.Prev == Skip edge
  if (E.Prev = E.Next) then
    EHighest := E.Next
  else if not ClosedOrSemiClosed and (E.Top.Y = EHighest.Top.Y) then
  begin
    if ((E.Dx = Horizontal) or (E.Next.Dx = Horizontal)) and
      (E.Next.Bot.Y = eHighest.Top.Y) then
        EHighest := E.Next
    else if SharedVertWithPrevAtTop(E) then EHighest := E
    else if PointsEqual(E.Top, E.Prev.Top) then EHighest := E.Prev
    else EHighest := E.Next;
  end else
  begin
    E := EHighest;
    while (EHighest.Dx = Horizontal) or
      (PointsEqual(EHighest.top, EHighest.next.top) or
      PointsEqual(EHighest.top, EHighest.next.bot)) do {next is high horizontal}
    begin
      EHighest := EHighest.Next;
      if EHighest = E then
      begin
        while (EHighest.Dx = Horizontal) or
          not SharedVertWithPrevAtTop(EHighest) do
            EHighest := EHighest.Next;
        Break; //ie avoids potential endless loop
      end;
    end;
  end;

  E := EHighest;
  repeat
    E := AddBoundsToLML(E);
  until (E = EHighest);
end;
//------------------------------------------------------------------------------

function TClipperBase.AddPaths(const Paths: TPaths;
  PolyType: TPolyType; Closed: Boolean): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to high(Paths) do
    if AddPath(Paths[I], PolyType, Closed) then Result := True;
end;
//------------------------------------------------------------------------------

procedure TClipperBase.Clear;
var
  I: Integer;
begin
  DisposeLocalMinimaList;
  //dispose of Edges ...
  for I := 0 to FEdgeList.Count -1 do
    FreeMem(PEdgeArray(fEdgeList[I]));
  FEdgeList.Clear;

  FUse64BitRange := False;
  FHasOpenPaths := False;
end;
//------------------------------------------------------------------------------

procedure TClipperBase.Reset;
var
  Lm: PLocalMinima;
begin
  //Reset() allows various clipping operations to be executed
  //multiple times on the same polygon sets.
  FCurrLm := FLmList;
  Lm := FCurrLm;
  while Assigned(Lm) do
  begin
    //resets just the two (L & R) edges attached to each Local Minima ...
    if assigned(Lm.LeftBound) then
      with Lm.LeftBound^ do
      begin
        Curr := Bot;
        Side := esLeft;
        if OutIdx <> Skip then
          OutIdx := Unassigned;
      end;
    with Lm.RightBound^ do
    begin
      Curr := Bot;
      Side := esRight;
      if OutIdx <> Skip then
        OutIdx := Unassigned;
    end;
    Lm := Lm.Next;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipperBase.DisposePolyPts(PP: POutPt);
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

constructor TClipper.Create(InitOptions: TInitOptions = []);
begin
  inherited Create;
  FJoinList := TList.Create;
  FGhostJoinList := TList.Create;
  FPolyOutList := TList.Create;
  if ioReverseSolution in InitOptions then
    FReverseOutput := true;
  if ioStrictlySimple in InitOptions then
    FStrictSimple := true;
  if ioPreserveCollinear in InitOptions then
    FPreserveCollinear := true;
end;
//------------------------------------------------------------------------------

destructor TClipper.Destroy;
begin
  inherited; //this must be first since inherited Destroy calls Clear.
  DisposeScanbeamList;
  FJoinList.Free;
  FGhostJoinList.Free;
  FPolyOutList.Free;
end;
//------------------------------------------------------------------------------

procedure TClipper.Clear;
begin
  DisposeAllOutRecs;
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
  DisposeAllOutRecs;
  Lm := FLmList;
  while Assigned(Lm) do
  begin
    InsertScanbeam(Lm.Y);
    Lm := Lm.Next;
  end;
end;
//------------------------------------------------------------------------------

function TClipper.Execute(clipType: TClipType;
  out solution: TPaths;
  subjFillType: TPolyFillType = pftEvenOdd;
  clipFillType: TPolyFillType = pftEvenOdd): Boolean;
begin
  Result := False;
  solution := nil;
  if FExecuteLocked then Exit;
  //nb: Open paths can only be returned via the PolyTree structure ...
  if HasOpenPaths then raise Exception.Create(rsOpenPath3);
  try try
    FExecuteLocked := True;
    FSubjFillType := subjFillType;
    FClipFillType := clipFillType;
    FClipType := clipType;
    FUsingPolyTree := False;
    Result := ExecuteInternal;
    solution := BuildResult;
  except
    solution := nil;
    Result := False;
  end;
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
  try try
    FExecuteLocked := True;
    FSubjFillType := subjFillType;
    FClipFillType := clipFillType;
    FClipType := clipType;
    FUsingPolyTree := True;
    Result := ExecuteInternal and BuildResult2(PolyTree);
  except
    Result := False;
  end;
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
  BotY, TopY: cInt;
begin
  try
    Reset;
    Result := Assigned(fScanbeam);
    if not Result then Exit;

    BotY := PopScanbeam;
    repeat
      InsertLocalMinimaIntoAEL(BotY);
      ClearGhostJoins;
      ProcessHorizontals(False);
      if not assigned(FScanbeam) then Break;
      TopY := PopScanbeam;
      if not ProcessIntersections(BotY, TopY) then Exit;
      ProcessEdgesAtTopOfScanbeam(TopY);
      BotY := TopY;
    until not assigned(FScanbeam) and not assigned(CurrentLm);

    //fix orientations ...
    for I := 0 to FPolyOutList.Count -1 do
    begin
      OutRec := FPolyOutList[I];
      if Assigned(OutRec.Pts) and not OutRec.IsOpen and
        ((OutRec.IsHole xor FReverseOutput) = (Area(OutRec) > 0)) then
          ReversePolyPtLinks(OutRec.Pts);
    end;

    if FJoinList.count > 0 then JoinCommonEdges;

    //unfortunately FixupOutPolygon() must be done after JoinCommonEdges ...
    for I := 0 to FPolyOutList.Count -1 do
    begin
      OutRec := FPolyOutList[I];
      if Assigned(OutRec.Pts) and not OutRec.IsOpen then
        FixupOutPolygon(OutRec);
    end;

    if FStrictSimple then DoSimplePolygons;

    Result := True;
  finally
    ClearJoins;
    ClearGhostJoins;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.InsertScanbeam(const Y: cInt);
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

function TClipper.PopScanbeam: cInt;
var
  Sb: PScanbeam;
begin
  Result := FScanbeam.Y;
  Sb := FScanbeam;
  FScanbeam := FScanbeam.Next;
  dispose(Sb);
end;
//------------------------------------------------------------------------------

procedure TClipper.DisposeAllOutRecs;
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
  E, E2: PEdge;
  Inside: Boolean;
begin
  E := Edge.PrevInAEL;
  //find the Edge of the same PolyType that immediately preceeds 'Edge' in AEL
  while Assigned(E) and ((E.PolyType <> Edge.PolyType) or (E.WindDelta = 0)) do
    E := E.PrevInAEL;
  if not Assigned(E) then
  begin
    if Edge.WindDelta = 0 then Edge.WindCnt := 1
    else Edge.WindCnt := Edge.WindDelta;
    Edge.WindCnt2 := 0;
    E := FActiveEdges; //ie get ready to calc WindCnt2
  end else if IsEvenOddFillType(Edge) then
  begin
    //even-odd filling ...
    if (Edge.WindDelta = 0) then  //if edge is part of a line
    begin
      //are we inside a subj polygon ...
      Inside := true;
      E2 := E.PrevInAEL;
      while assigned(E2) do
      begin
        if (E2.PolyType = E.PolyType) and (E2.WindDelta <> 0) then
          Inside := not Inside;
        E2 := E2.PrevInAEL;
      end;
      if Inside then Edge.WindCnt := 0
      else Edge.WindCnt := 1;
    end
    else //else a polygon
    begin
      Edge.WindCnt := Edge.WindDelta;
    end;
    Edge.WindCnt2 := E.WindCnt2;
    E := E.NextInAEL; //ie get ready to calc WindCnt2
  end else
  begin
    //NonZero, Positive, or Negative filling ...
    if (e.WindCnt * e.WindDelta < 0) then
    begin
      //prev edge is 'decreasing' WindCount (WC) toward zero
      //so we're outside the previous polygon ...
      if (Abs(e.WindCnt) > 1) then
      begin
        //outside prev poly but still inside another.
        //when reversing direction of prev poly use the same WC
        if (e.WindDelta * edge.WindDelta < 0) then edge.WindCnt := e.WindCnt
        //otherwise continue to 'decrease' WC ...
        else edge.WindCnt := e.WindCnt + edge.WindDelta;
      end
      else
        //now outside all polys of same polytype so set own WC ...
        if edge.WindDelta = 0 then edge.WindCnt := 1
        else edge.WindCnt := edge.WindDelta;
    end else
    begin
      //prev edge is 'increasing' WindCount (WC) away from zero
      //so we're inside the previous polygon ...
      if (edge.WindDelta = 0) then
        edge.WindCnt := 0
      //if wind direction is reversing prev then use same WC
      else if (e.WindDelta * edge.WindDelta < 0) then
        edge.WindCnt := e.WindCnt
      //otherwise add to WC ...
      else edge.WindCnt := e.WindCnt + edge.WindDelta;
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
      if E.WindDelta = 0 then //do nothing (ie ignore lines)
      else if Edge.WindCnt2 = 0 then Edge.WindCnt2 := 1
      else Edge.WindCnt2 := 0;
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
    pftEvenOdd: Result := (Edge.WindDelta <> 0) or (Edge.WindCnt = 1);
    pftNonZero: Result := abs(Edge.WindCnt) = 1;
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
      ctXor:
        if Edge.WindDelta = 0 then //XOr always contributing unless open
          case Pft2 of
            pftEvenOdd, pftNonZero: Result := (Edge.WindCnt2 = 0);
            pftPositive: Result := (Edge.WindCnt2 <= 0);
            pftNegative: Result := (Edge.WindCnt2 >= 0);
          end;
  end;
end;
//------------------------------------------------------------------------------

function TClipper.AddLocalMinPoly(E1, E2: PEdge; const Pt: TIntPoint): POutPt;
var
  E, prevE: PEdge;
  OutPt: POutPt;
begin
  if (E2.Dx = Horizontal) or (E1.Dx > E2.Dx) then
  begin
    Result := AddOutPt(E1, Pt);
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
    Result := AddOutPt(E2, Pt);
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
    SlopesEqual(E, prevE, FUse64BitRange) and
    (E.WindDelta <> 0) and (prevE.WindDelta <> 0) then
  begin
    OutPt := AddOutPt(prevE, Pt);
    AddJoin(Result, OutPt, E.Top);
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.AddLocalMaxPoly(E1, E2: PEdge; const Pt: TIntPoint);
begin
  AddOutPt(E1, Pt);
  if (E1.OutIdx = E2.OutIdx) then
  begin
    E1.OutIdx := Unassigned;
    E2.OutIdx := Unassigned;
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
  if not Assigned(FSortedEdges) then
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

procedure TClipper.AddJoin(Op1, Op2: POutPt; const OffPt: TIntPoint);
var
  Jr: PJoin;
begin
  new(Jr);
  Jr.OutPt1 := Op1;
  Jr.OutPt2 := Op2;
  Jr.OffPt := OffPt;
  FJoinList.add(Jr);
end;
//------------------------------------------------------------------------------

procedure TClipper.ClearJoins;
var
  I: Integer;
begin
  for I := 0 to FJoinList.count -1 do
    Dispose(PJoin(fJoinList[I]));
  FJoinList.Clear;
end;
//------------------------------------------------------------------------------

procedure TClipper.AddGhostJoin(OutPt: POutPt; const OffPt: TIntPoint);
var
  Jr: PJoin;
begin
  new(Jr);
  Jr.OutPt1 := OutPt;
  Jr.OffPt := OffPt;
  FGhostJoinList.Add(Jr);
end;
//------------------------------------------------------------------------------

procedure TClipper.ClearGhostJoins;
var
  I: Integer;
begin
  for I := 0 to FGhostJoinList.Count -1 do
    Dispose(PJoin(FGhostJoinList[I]));
  FGhostJoinList.Clear;
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

function HorzSegmentsOverlap(const Pt1a, Pt1b, Pt2a, Pt2b: TIntPoint): Boolean;
begin
  //precondition: both segments are horizontal
  Result := true;
  if (Pt1a.X > Pt2a.X) = (Pt1a.X < Pt2b.X) then Exit
  else if (Pt1b.X > Pt2a.X) = (Pt1b.X < Pt2b.X) then Exit
  else if (Pt2a.X > Pt1a.X) = (Pt2a.X < Pt1b.X) then Exit
  else if (Pt2b.X > Pt1a.X) = (Pt2b.X < Pt1b.X) then Exit
  else if (Pt1a.X = Pt2a.X) and (Pt1b.X = Pt2b.X) then Exit
  else if (Pt1a.X = Pt2b.X) and (Pt1b.X = Pt2a.X) then Exit
  else Result := False;
end;
//------------------------------------------------------------------------------

function E2InsertsBeforeE1(E1, E2: PEdge): Boolean;
  {$IFDEF INLINING} inline; {$ENDIF}
begin
  if E2.Curr.X = E1.Curr.X then
  begin
    if E2.Top.Y > E1.Top.Y then
      Result := E2.Top.X < TopX(E1, E2.Top.Y) else
      Result := E1.Top.X > TopX(E2, E1.Top.Y);
  end else
    Result := E2.Curr.X < E1.Curr.X;
end;
//----------------------------------------------------------------------

procedure TClipper.InsertLocalMinimaIntoAEL(const BotY: cInt);

  procedure InsertEdgeIntoAEL(Edge, StartEdge: PEdge);
  begin
    if not Assigned(FActiveEdges) then
    begin
      Edge.PrevInAEL := nil;
      Edge.NextInAEL := nil;
      FActiveEdges := Edge;
    end
    else if not Assigned(StartEdge) and
      E2InsertsBeforeE1(FActiveEdges, Edge) then
    begin
      Edge.PrevInAEL := nil;
      Edge.NextInAEL := FActiveEdges;
      FActiveEdges.PrevInAEL := Edge;
      FActiveEdges := Edge;
    end else
    begin
      if not Assigned(StartEdge) then StartEdge := FActiveEdges;
      while Assigned(StartEdge.NextInAEL) and
        not E2InsertsBeforeE1(StartEdge.NextInAEL, Edge) do
          StartEdge := StartEdge.NextInAEL;
      Edge.NextInAEL := StartEdge.NextInAEL;
      if Assigned(StartEdge.NextInAEL) then
        StartEdge.NextInAEL.PrevInAEL := Edge;
      Edge.PrevInAEL := StartEdge;
      StartEdge.NextInAEL := Edge;
    end;
  end;
  //----------------------------------------------------------------------

var
  I: Integer;
  E: PEdge;
  Pt: TIntPoint;
  Lb, Rb: PEdge;
  Jr: PJoin;
  Op1, Op2: POutPt;
begin
  while Assigned(CurrentLm) and (CurrentLm.Y = BotY) do
  begin
    Lb := CurrentLm.LeftBound;
    Rb := CurrentLm.RightBound;
    PopLocalMinima;

    Op1 := nil;
    if not assigned(Lb) then
    begin
      //nb: don't insert LB into either AEL or SEL
      InsertEdgeIntoAEL(Rb, nil);
      SetWindingCount(Rb);
      if IsContributing(Rb) then
        Op1 := AddOutPt(Rb, Rb.Bot);
    end else
    begin
      InsertEdgeIntoAEL(Lb, nil);
      InsertEdgeIntoAEL(Rb, Lb);
      SetWindingCount(Lb);
      Rb.WindCnt := Lb.WindCnt;
      Rb.WindCnt2 := Lb.WindCnt2;
      if IsContributing(Lb) then
        Op1 := AddLocalMinPoly(Lb, Rb, Lb.Bot);
      InsertScanbeam(Lb.Top.Y);
    end;

    if Rb.Dx = Horizontal then
      AddEdgeToSEL(Rb) else
      InsertScanbeam(Rb.Top.Y);

    if not assigned(Lb) then Continue;

    //if output polygons share an Edge with rb, they'll need joining later ...
    if assigned(Op1) and (Rb.Dx = Horizontal) and
      (FGhostJoinList.Count > 0) and (Rb.WindDelta <> 0) then
    begin
      for I := 0 to FGhostJoinList.Count -1 do
      begin
        //if the horizontal Rb and a 'ghost' horizontal overlap, then convert
        //the 'ghost' join to a real join ready for later ...
        Jr := PJoin(FGhostJoinList[I]);
        if HorzSegmentsOverlap(Jr.OutPt1.Pt, Jr.OffPt, Rb.Bot, Rb.Top) then
          AddJoin(Jr.OutPt1, Op1, Jr.OffPt);
      end;
    end;

    if (Lb.OutIdx >= 0) and assigned(Lb.PrevInAEL) and
      (Lb.PrevInAEL.Curr.X = Lb.Bot.X) and
      (Lb.PrevInAEL.OutIdx >= 0) and
      SlopesEqual(Lb.PrevInAEL, Lb, FUse64BitRange) and
      (Lb.WindDelta <> 0) and (Lb.PrevInAEL.WindDelta <> 0) then
    begin
        Op2 := AddOutPt(Lb.PrevInAEL, Lb.Bot);
        AddJoin(Op1, Op2, Lb.Top);
    end;

    if (Lb.NextInAEL <> Rb) then
    begin
      if (Rb.OutIdx >= 0) and (Rb.PrevInAEL.OutIdx >= 0) and
        SlopesEqual(Rb.PrevInAEL, Rb, FUse64BitRange) and
        (Rb.WindDelta <> 0) and (Rb.PrevInAEL.WindDelta <> 0) then
      begin
          Op2 := AddOutPt(Rb.PrevInAEL, Rb.Bot);
          AddJoin(Op1, Op2, Rb.Top);
      end;

      E := Lb.NextInAEL;
      Pt := Lb.Curr;
      if Assigned(E) then
        while (E <> Rb) do
        begin
{$IFDEF use_xyz}
          SetZ(Pt, Rb, E, FZFillCallback);
{$ENDIF}
          //nb: For calculating winding counts etc, IntersectEdges() assumes
          //that param1 will be to the right of param2 ABOVE the intersection ...
          IntersectEdges(Rb, E, Pt);
          E := E.NextInAEL;
        end;
    end;
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
  const Pt: TIntPoint; Protect: Boolean = False);
var
  E1stops, E2stops: Boolean;
  E1Contributing, E2contributing: Boolean;
  E1FillType, E2FillType, E1FillType2, E2FillType2: TPolyFillType;
  E1Wc, E2Wc, E1Wc2, E2Wc2: Integer;
begin
  {IntersectEdges}
  //E1 will be to the left of E2 BELOW the intersection. Therefore E1 is before
  //E2 in AEL except when E1 is being inserted at the intersection point ...

  E1stops := not Protect and not Assigned(E1.NextInLML) and
    (E1.Top.X = Pt.x) and (E1.Top.Y = Pt.Y);
  E2stops := not Protect and not Assigned(E2.NextInLML) and
    (E2.Top.X = Pt.x) and (E2.Top.Y = Pt.Y);
  E1Contributing := (E1.OutIdx >= 0);
  E2contributing := (E2.OutIdx >= 0);

{$IFDEF use_lines}
  //if either edge is on an OPEN path ...
  if (E1.WindDelta = 0) or (E2.WindDelta = 0) then
  begin
    //ignore subject-subject open path intersections UNLESS they
    //are both open paths, AND they are both 'contributing maximas' ...
    if (E1.WindDelta = 0) AND (E2.WindDelta = 0) and (E1stops or E2stops) then
    begin
      if E1Contributing and E2Contributing then
        AddLocalMaxPoly(E1, E2, Pt);
    end
    else if (E1.PolyType = E2.PolyType) and (E1.WindDelta <> E2.WindDelta) then
    begin
      //intersecting a subj line with a subj poly ...
      if (E1.WindDelta = 0) then
      begin
        if (E2Contributing) then
        begin
          AddOutPt(e1, Pt);
          if (E1Contributing) then E1.OutIdx := Unassigned;
        end;
      end else
      begin
        if (E1Contributing) then
        begin
          AddOutPt(E2, Pt);
          if (E2Contributing) then E2.OutIdx := Unassigned;
        end;
      end;
    end
    else if E1.PolyType <> E2.PolyType then
    begin
      //toggle subj open path OutIdx on/off when Abs(clip.WndCnt) = 1 ...
      if (E1.WindDelta = 0) and
        (Abs(E2.WindCnt) = 1) and (E2.WindCnt2 = 0) then
      begin
        AddOutPt(E1, Pt);
        if E1Contributing then E1.OutIdx := Unassigned;
      end
      else if (E2.WindDelta = 0) and
        (Abs(E1.WindCnt) = 1) and (E1.WindCnt2 = 0) then
      begin
        AddOutPt(E2, Pt);
        if E2Contributing then E2.OutIdx := Unassigned;
      end
    end;

    if E1stops then
      if (E1.OutIdx < 0) then deleteFromAEL(E1)
      else raise Exception.Create(rsPolylines);
    if E2stops then
      if (E2.OutIdx < 0) then deleteFromAEL(E2)
      else raise Exception.Create(rsPolylines);
    Exit;
  end;
{$ENDIF}

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
    begin
        AddLocalMaxPoly(E1, E2, Pt);
    end else
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
    if (E2.OutIdx >= 0) and (E2.WindDelta <> 0) then
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

  //get the start and ends of both output polygons and
  //join E2 poly onto E1 poly and delete pointers to E2 ...

  P1_lft := OutRec1.Pts;
  P2_lft := OutRec2.Pts;
  P1_rt := P1_lft.Prev;
  P2_rt := P2_lft.Prev;

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

  E1.OutIdx := Unassigned; //safe because we only get here via AddLocalMaxPoly
  E2.OutIdx := Unassigned;

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
  Result.IsOpen := False;
  Result.FirstLeft := nil;
  Result.Pts := nil;
  Result.BottomPt := nil;
  Result.PolyNode := nil;
  Result.Idx := FPolyOutList.Add(Result);
end;
//------------------------------------------------------------------------------

function TClipper.AddOutPt(E: PEdge; const Pt: TIntPoint): POutPt;
var
  OutRec: POutRec;
  PrevOp, Op: POutPt;
  ToFront: Boolean;
begin
  ToFront := E.Side = esLeft;
  if E.OutIdx < 0 then
  begin
    OutRec := CreateOutRec;
    OutRec.IsOpen := (E.WindDelta = 0);
    E.OutIdx := OutRec.Idx;
    new(Result);
    OutRec.Pts := Result;
    Result.Next := Result;
    Result.Prev := Result;
    Result.Idx := OutRec.Idx;
    if not OutRec.IsOpen then
      SetHoleState(E, OutRec);
  end else
  begin
    OutRec := FPolyOutList[E.OutIdx];
    //OutRec.Pts is the 'left-most' point & OutRec.Pts.Prev is the 'right-most'
    Op := OutRec.Pts;
    if ToFront then PrevOp := Op else PrevOp := Op.Prev;
    if PointsEqual(Pt, PrevOp.Pt) then
    begin
      Result := PrevOp;
      Exit;
    end;
    new(Result);
    Result.Idx := OutRec.Idx;
    Result.Next := Op;
    Result.Prev := Op.Prev;
    Op.Prev.Next := Result;
    Op.Prev := Result;
    if ToFront then OutRec.Pts := Result;
  end;
  Result.Pt := Pt;
end;
//------------------------------------------------------------------------------

procedure TClipper.ProcessHorizontals(IsTopOfScanbeam: Boolean);
var
  E: PEdge;
begin
  while Assigned(fSortedEdges) do
  begin
    E := FSortedEdges;
    DeleteFromSEL(E);
    ProcessHorizontal(E, IsTopOfScanbeam);
  end;
end;
//------------------------------------------------------------------------------

function IsMinima(E: PEdge): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  Result := Assigned(E) and (E.Prev.NextInLML <> E) and (E.Next.NextInLML <> E);
end;
//------------------------------------------------------------------------------

function IsMaxima(E: PEdge; const Y: cInt): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  Result := Assigned(E) and (E.Top.Y = Y) and not Assigned(E.NextInLML);
end;
//------------------------------------------------------------------------------

function IsIntermediate(E: PEdge; const Y: cInt): Boolean; {$IFDEF INLINING} inline; {$ENDIF}
begin
  Result := (E.Top.Y = Y) and Assigned(E.NextInLML);
end;
//------------------------------------------------------------------------------

function GetMaximaPair(E: PEdge): PEdge;
begin
  if PointsEqual(E.Next.Top, E.Top) and not assigned(E.Next.NextInLML) then
    Result := E.Next
  else if PointsEqual(E.Prev.Top, E.Top) and not assigned(E.Prev.NextInLML) then
    Result := E.Prev
  else
    Result := nil;
  if assigned(Result) and ((Result.OutIdx = Skip) or
    //result is false if both NextInAEL & PrevInAEL are nil & not horizontal ...
    ((Result.NextInAEL = Result.PrevInAEL) and (Result.Dx <> Horizontal))) then
      Result := nil;
end;
//------------------------------------------------------------------------------

procedure TClipper.SwapPositionsInAEL(E1, E2: PEdge);
var
  Prev,Next: PEdge;
begin
  //check that one or other edge hasn't already been removed from AEL ...
  if (E1.NextInAEL = E1.PrevInAEL) or (E2.NextInAEL = E2.PrevInAEL) then
    Exit;

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

function GetNextInAEL(E: PEdge; Direction: TDirection): PEdge;
  {$IFDEF INLINING} inline; {$ENDIF}
begin
  if Direction = dLeftToRight then
    Result := E.NextInAEL else
    Result := E.PrevInAEL;
end;
//------------------------------------------------------------------------

procedure GetHorzDirection(HorzEdge: PEdge; out Dir: TDirection;
  out Left, Right: cInt); {$IFDEF INLINING} inline; {$ENDIF}
begin
  if HorzEdge.Bot.X < HorzEdge.Top.X then
  begin
    Left := HorzEdge.Bot.X;
    Right := HorzEdge.Top.X;
    Dir := dLeftToRight;
  end else
  begin
    Left := HorzEdge.Top.X;
    Right := HorzEdge.Bot.X;
    Dir := dRightToLeft;
  end;
end;
//------------------------------------------------------------------------

procedure TClipper.ProcessHorizontal(HorzEdge: PEdge; IsTopOfScanbeam: Boolean);

  procedure PrepareHorzJoins;
  var
    I: Integer;
    OutPt: POutPt;
  begin
    //get the last Op for this horizontal edge
    //the point may be anywhere along the horizontal ...
    OutPt := POutRec(FPolyOutList[HorzEdge.OutIdx]).Pts;
    if HorzEdge.Side <> esLeft then OutPt := OutPt.Prev;

    //First, match up overlapping horizontal edges (eg when one polygon's
    //intermediate horz edge overlaps an intermediate horz edge of another, or
    //when one polygon sits on top of another) ...
    for I := 0 to FGhostJoinList.Count -1 do
      with PJoin(FGhostJoinList[I])^ do
        if HorzSegmentsOverlap(OutPt1.Pt, OffPt, HorzEdge.Bot, HorzEdge.Top) then
          AddJoin(OutPt1, OutPt, OffPt);

    //Also, since horizontal edges at the top of one SB are often removed from
    //the AEL before we process the horizontal edges at the bottom of the next,
    //we need to create 'ghost' Join records of 'contrubuting' horizontals that
    //we can compare with horizontals at the bottom of the next SB.
    if IsTopOfScanbeam then
      if PointsEqual(OutPt.Pt, HorzEdge.Top) then
        AddGhostJoin(OutPt, HorzEdge.Bot) else
        AddGhostJoin(OutPt, HorzEdge.Top);
  end;

var
  E, eNext, ePrev, eMaxPair, eLastHorz: PEdge;
  HorzLeft, HorzRight: cInt;
  Direction: TDirection;
  Pt: TIntPoint;
  Op1, Op2: POutPt;
  IsLastHorz: Boolean;
begin
(*******************************************************************************
* Notes: Horizontal edges (HEs) at scanline intersections (ie at the top or    *
* bottom of a scanbeam) are processed as if layered. The order in which HEs    *
* are processed doesn't matter. HEs intersect with other HE Bot.Xs only [#]    *
* (or they could intersect with Top.Xs only, ie EITHER Bot.Xs OR Top.Xs),      *
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

  GetHorzDirection(HorzEdge, Direction, HorzLeft, HorzRight);

  eLastHorz := HorzEdge;
  while Assigned(eLastHorz.NextInLML) and
    (eLastHorz.NextInLML.Dx = Horizontal) do eLastHorz := eLastHorz.NextInLML;
  if Assigned(eLastHorz.NextInLML) then
    eMaxPair := nil else
    eMaxPair := GetMaximaPair(eLastHorz);

  while true do //loops consec. horizontal edges
  begin
    IsLastHorz := (HorzEdge = eLastHorz);
    E := GetNextInAEL(HorzEdge, Direction);
    while Assigned(E) do
    begin
      //Break if we've got to the end of an intermediate horizontal edge ...
      //nb: Smaller Dx's are to the right of larger Dx's ABOVE the horizontal.
      if (E.Curr.X = HorzEdge.Top.X) and
        Assigned(HorzEdge.NextInLML) and (E.Dx < HorzEdge.NextInLML.Dx) then
          Break;
      eNext := GetNextInAEL(E, Direction); //saves eNext for later

      if ((Direction = dLeftToRight) and (E.Curr.X <= HorzRight)) or
        ((Direction = dRightToLeft) and (E.Curr.X >= HorzLeft)) then
      begin
        //so far we're still in range of the horizontal Edge  but make sure
        //we're at the last of consec. horizontals when matching with eMaxPair
        if (E = eMaxPair) and IsLastHorz then
        begin
          if (HorzEdge.OutIdx >= 0) and (HorzEdge.WindDelta <> 0) then
            PrepareHorzJoins;
          if Direction = dLeftToRight then
            IntersectEdges(HorzEdge, E, E.Top) else
            IntersectEdges(E, HorzEdge, E.Top);
          if (eMaxPair.OutIdx >= 0) then raise exception.Create(rsHorizontal);
          Exit;
        end
        else if (Direction = dLeftToRight) then
        begin
          Pt := IntPoint(E.Curr.X, HorzEdge.Curr.Y);
{$IFDEF use_xyz}
          SetZ(Pt, HorzEdge, E, FZFillCallback);
{$ENDIF}
          IntersectEdges(HorzEdge, E, Pt, True);
        end else
        begin
          Pt := IntPoint(E.Curr.X, HorzEdge.Curr.Y);
{$IFDEF use_xyz}
          SetZ(Pt, E, HorzEdge, FZFillCallback);
{$ENDIF}
          IntersectEdges(E, HorzEdge, Pt, True);
        end;
        SwapPositionsInAEL(HorzEdge, E);
      end
      else if ((Direction = dLeftToRight) and (E.Curr.X >= HorzRight)) or
        ((Direction = dRightToLeft) and (E.Curr.X <= HorzLeft)) then
          Break;
      E := eNext;
    end;

    if (HorzEdge.OutIdx >= 0) and (HorzEdge.WindDelta <> 0) then
      PrepareHorzJoins;

    if Assigned(HorzEdge.NextInLML) and
      (HorzEdge.NextInLML.Dx = Horizontal) then
    begin
      UpdateEdgeIntoAEL(HorzEdge);
      if (HorzEdge.OutIdx >= 0) then AddOutPt(HorzEdge, HorzEdge.Bot);
      GetHorzDirection(HorzEdge, Direction, HorzLeft, HorzRight);
    end else
      Break;
  end;

  if Assigned(HorzEdge.NextInLML) then
  begin
    if (HorzEdge.OutIdx >= 0) then
    begin
      Op1 := AddOutPt(HorzEdge, HorzEdge.Top);
      UpdateEdgeIntoAEL(HorzEdge);
      if (HorzEdge.WindDelta = 0) then Exit;
      //nb: HorzEdge is no longer horizontal here
      ePrev := HorzEdge.PrevInAEL;
      eNext := HorzEdge.NextInAEL;
      if Assigned(ePrev) and (ePrev.Curr.X = HorzEdge.Bot.X) and
        (ePrev.Curr.Y = HorzEdge.Bot.Y) and (ePrev.WindDelta <> 0) and
        (ePrev.OutIdx >= 0) and (ePrev.Curr.Y > ePrev.Top.Y) and
        SlopesEqual(HorzEdge, ePrev, FUse64BitRange) then
      begin
        Op2 := AddOutPt(ePrev, HorzEdge.Bot);
        AddJoin(Op1, Op2, HorzEdge.Top);
      end
      else if Assigned(eNext) and (eNext.Curr.X = HorzEdge.Bot.X) and
        (eNext.Curr.Y = HorzEdge.Bot.Y) and (eNext.WindDelta <> 0) and
          (eNext.OutIdx >= 0) and (eNext.Curr.Y > eNext.Top.Y) and
        SlopesEqual(HorzEdge, eNext, FUse64BitRange) then
      begin
        Op2 := AddOutPt(eNext, HorzEdge.Bot);
        AddJoin(Op1, Op2, HorzEdge.Top);
      end;
    end else
      UpdateEdgeIntoAEL(HorzEdge);
  end
  else if assigned(eMaxPair) then
  begin
    if (eMaxPair.OutIdx >= 0) then
    begin
      if Direction = dLeftToRight then
        IntersectEdges(HorzEdge, eMaxPair, HorzEdge.Top) else
        IntersectEdges(eMaxPair, HorzEdge, HorzEdge.Top);
      if (eMaxPair.OutIdx >= 0) then
        raise exception.Create(rsHorizontal);
    end else
    begin
      DeleteFromAEL(HorzEdge);
      DeleteFromAEL(eMaxPair);
    end;
  end else
  begin
    if (HorzEdge.OutIdx >= 0) then AddOutPt(HorzEdge, HorzEdge.Top);
    DeleteFromAEL(HorzEdge);
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.UpdateEdgeIntoAEL(var E: PEdge);
var
  AelPrev, AelNext: PEdge;
begin
  //return true when AddOutPt() call needed too
  if not Assigned(E.NextInLML) then
    raise exception.Create(rsUpdateEdgeIntoAEL);

  E.NextInLML.OutIdx := E.OutIdx;

  AelPrev := E.PrevInAEL;
  AelNext := E.NextInAEL;
  if Assigned(AelPrev) then
    AelPrev.NextInAEL := E.NextInLML else
    FActiveEdges := E.NextInLML;
  if Assigned(AelNext) then
    AelNext.PrevInAEL := E.NextInLML;
  E.NextInLML.Side := E.Side;
  E.NextInLML.WindDelta := E.WindDelta;
  E.NextInLML.WindCnt := E.WindCnt;
  E.NextInLML.WindCnt2 := E.WindCnt2;
  E := E.NextInLML; ////
  E.Curr := E.Bot;
  E.PrevInAEL := AelPrev;
  E.NextInAEL := AelNext;
  if E.Dx <> Horizontal then
    InsertScanbeam(E.Top.Y);
end;
//------------------------------------------------------------------------------

function TClipper.ProcessIntersections(const BotY, TopY: cInt): Boolean;
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

procedure TClipper.BuildIntersectList(const BotY, TopY: cInt);
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
    E.Curr.X := TopX(E, TopY);
    E := E.NextInAEL;
  end;

  //bubblesort ...
  repeat
    IsModified := False;
    E := FSortedEdges;
    while Assigned(E.NextInSEL) do
    begin
      eNext := E.NextInSEL;
      if (E.Curr.X > eNext.Curr.X) then
      begin
        if not IntersectPoint(E, eNext, Pt, FUse64BitRange) and
          (E.Curr.X > eNext.Curr.X +1) then
            raise Exception.Create(rsIntersect);
        if (Pt.Y > botY) then
        begin
          Pt.Y := botY;
          if (abs(E.Dx) > abs(eNext.Dx)) then
            Pt.X := TopX(eNext, botY) else
            Pt.X := TopX(e, botY);
        end;

{$IFDEF use_xyz}
        SetZ(Pt, E, eNext, FZFillCallback);
{$ENDIF}
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
      IntersectEdges(Edge1, Edge2, Pt, True);
      SwapPositionsInAEL(Edge1, Edge2);
    end;
    dispose(fIntersectNodes);
    FIntersectNodes := Node;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.DoMaxima(E: PEdge);
var
  ENext, EMaxPair: PEdge;
  Pt: TIntPoint;
begin
  EMaxPair := GetMaximaPair(E);
  if not assigned(EMaxPair) then
  begin
    if E.OutIdx >= 0 then
      AddOutPt(E, E.Top);
    DeleteFromAEL(E);
    Exit;
  end;

  ENext := E.NextInAEL;
  //rarely, with overlapping collinear edges (in open paths) ENext can be nil
  while Assigned(ENext) and (ENext <> EMaxPair) do
  begin
    Pt := E.Top;
{$IFDEF use_xyz}
    SetZ(Pt, E, ENext, FZFillCallback);
{$ENDIF}
    IntersectEdges(E, ENext, Pt, True);
    SwapPositionsInAEL(E, ENext);
    ENext := E.NextInAEL;
  end;

  if (E.OutIdx = Unassigned) and (EMaxPair.OutIdx = Unassigned) then
  begin
    DeleteFromAEL(E);
    DeleteFromAEL(EMaxPair);
  end
  else if (E.OutIdx >= 0) and (EMaxPair.OutIdx >= 0) then
  begin
    IntersectEdges(E, EMaxPair, E.Top);
  end
{$IFDEF use_lines}
  else if E.WindDelta = 0 then
  begin
    if (E.OutIdx >= 0) then
    begin
      AddOutPt(E, E.Top);
      E.OutIdx := Unassigned;
    end;
    DeleteFromAEL(E);

    if (EMaxPair.OutIdx >= 0) then
    begin
      AddOutPt(EMaxPair, E.Top);
      EMaxPair.OutIdx := Unassigned;
    end;
    DeleteFromAEL(EMaxPair);
  end
{$ENDIF}
  else
    raise exception.Create(rsDoMaxima);
end;
//------------------------------------------------------------------------------

procedure TClipper.ProcessEdgesAtTopOfScanbeam(const TopY: cInt);
var
  E, EMaxPair, ePrev, eNext: PEdge;
  Pt: TIntPoint;
  Op, Op2: POutPt;
  IsMaximaEdge: Boolean;
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
    IsMaximaEdge := IsMaxima(E, TopY);
    if IsMaximaEdge then
    begin
      EMaxPair := GetMaximaPair(E);
      IsMaximaEdge := not assigned(EMaxPair) or (EMaxPair.Dx <> Horizontal);
    end;

    if IsMaximaEdge then
    begin
      //'E' might be removed from AEL, as may any following edges so ...
      ePrev := E.PrevInAEL;
      DoMaxima(E);
      if not Assigned(ePrev) then
        E := FActiveEdges else
        E := ePrev.NextInAEL;
    end else
    begin
      //2. promote horizontal edges, otherwise update Curr.X and Curr.Y ...
      if IsIntermediate(E, TopY) and (E.NextInLML.Dx = Horizontal) then
      begin
        UpdateEdgeIntoAEL(E);
        if (E.OutIdx >= 0) then
          AddOutPt(E, E.Bot);
        AddEdgeToSEL(E);
      end else
      begin
        E.Curr.X := TopX(E, TopY);
        E.Curr.Y := TopY;
      end;

      //When StrictlySimple and 'e' is being touched by another edge, then
      //make sure both edges have a vertex here ...
      if FStrictSimple then
      begin
        ePrev := E.PrevInAEL;
        if (E.OutIdx >= 0) and (E.WindDelta <> 0) and
          Assigned(ePrev) and (ePrev.Curr.X = E.Curr.X) and
          (ePrev.OutIdx >= 0) and (ePrev.WindDelta <> 0) then
        begin
          Pt := IntPoint(E.Curr.X, TopY);
{$IFDEF use_xyz}
          GetZ(Pt, ePrev);
          Op := AddOutPt(ePrev, Pt);
          GetZ(Pt, E);
{$ELSE}
          Op := AddOutPt(ePrev, Pt);
{$ENDIF}
          Op2 := AddOutPt(E, Pt);
          AddJoin(Op, Op2, Pt); //strictly-simple (type-3) 'join'
        end;
      end;

      E := E.NextInAEL;
    end;
  end;

  //3. Process horizontals at the top of the scanbeam ...
  ProcessHorizontals(True);

  //4. Promote intermediate vertices ...
  E := FActiveEdges;
  while Assigned(E) do
  begin
    if IsIntermediate(E, TopY) then
    begin
      if (E.OutIdx >= 0) then
        Op := AddOutPt(E, E.Top) else
        Op := nil;
      UpdateEdgeIntoAEL(E);

      //if output polygons share an Edge, they'll need joining later ...
      ePrev := E.PrevInAEL;
      eNext  := E.NextInAEL;
      if Assigned(ePrev) and (ePrev.Curr.X = E.Bot.X) and
        (ePrev.Curr.Y = E.Bot.Y) and assigned(Op) and
        (ePrev.OutIdx >= 0) and (ePrev.Curr.Y > ePrev.Top.Y) and
        SlopesEqual(E, ePrev, FUse64BitRange) and
        (E.WindDelta <> 0) and (ePrev.WindDelta <> 0) then
      begin
        Op2 := AddOutPt(ePrev, E.Bot);
        AddJoin(Op, Op2, E.Top);
      end
      else if Assigned(eNext) and (eNext.Curr.X = E.Bot.X) and
        (eNext.Curr.Y = E.Bot.Y) and assigned(Op) and
          (eNext.OutIdx >= 0) and (eNext.Curr.Y > eNext.Top.Y) and
        SlopesEqual(E, eNext, FUse64BitRange) and
        (E.WindDelta <> 0) and (eNext.WindDelta <> 0) then
      begin
        Op2 := AddOutPt(eNext, E.Bot);
        AddJoin(Op, Op2, E.Top);
      end;
    end;
    E := E.NextInAEL;
  end;
end;
//------------------------------------------------------------------------------

function TClipper.BuildResult: TPaths;
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
      if not assigned(OutRec.Pts) then Continue;

      Op := OutRec.Pts.Prev;
      Cnt := PointCount(Op);
      if (Cnt < 2) then Continue;
      SetLength(Result[J], Cnt);
      for K := 0 to Cnt -1 do
      begin
        Result[J][K] := Op.Pt;
        Op := Op.Prev;
      end;
      Inc(J);
    end;
  SetLength(Result, J);
end;
//------------------------------------------------------------------------------

function TClipper.BuildResult2(PolyTree: TPolyTree): Boolean;
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
      if (OutRec.IsOpen and (cnt < 2)) or
        (not outRec.IsOpen and (cnt < 3)) then Continue;
      FixHoleLinkage(OutRec);

      PolyNode := TPolyNode.Create;
      PolyTree.FAllNodes[CntAll] := PolyNode;
      OutRec.PolyNode := PolyNode;
      Inc(CntAll);
      SetLength(PolyNode.FPath, Cnt);
      Op := OutRec.Pts.Prev;
      for J := 0 to Cnt -1 do
      begin
        PolyNode.FPath[J] := Op.Pt;
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
        if OutRec.IsOpen then
        begin
          OutRec.PolyNode.FIsOpen := true;
          PolyTree.AddChild(OutRec.PolyNode);
        end
        else if Assigned(OutRec.FirstLeft) then
          OutRec.FirstLeft.PolyNode.AddChild(OutRec.PolyNode)
        else
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
  //remove duplicate points and collinear edges
  LastOK := nil;
  OutRec.BottomPt := nil; //flag as stale
  PP := OutRec.Pts;
  while True do
  begin
    if (PP = PP.Prev) or (PP.Next = PP.Prev) then
    begin
      DisposePolyPts(PP);
      OutRec.Pts := nil;
      Exit;
    end;

    //test for duplicate points and collinear edges ...
    if PointsEqual(PP.Pt, PP.Next.Pt) or PointsEqual(PP.Pt, PP.Prev.Pt) or
      (SlopesEqual(PP.Prev.Pt, PP.Pt, PP.Next.Pt, FUse64BitRange) and
      (not FPreserveCollinear or
      not Pt2IsBetweenPt1AndPt3(PP.Prev.Pt, PP.Pt, PP.Next.Pt))) then
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

function DupOutPt(OutPt: POutPt; InsertAfter: Boolean = true): POutPt;
begin
  new(Result);
  Result.Pt := OutPt.Pt;
  Result.Idx := OutPt.Idx;
  if InsertAfter then
  begin
    Result.Next := OutPt.Next;
    Result.Prev := OutPt;
    OutPt.Next.Prev := Result;
    OutPt.Next := Result;
  end else
  begin
    Result.Prev := OutPt.Prev;
    Result.Next := OutPt;
    OutPt.Prev.Next := Result;
    OutPt.Prev := Result;
  end;
end;
//------------------------------------------------------------------------------

function JoinHorz(Op1, Op1b, Op2, Op2b: POutPt;
  const Pt: TIntPoint; DiscardLeft: Boolean): Boolean;
var
  Dir1, Dir2: TDirection;
begin
  if Op1.Pt.X > Op1b.Pt.X then Dir1 := dRightToLeft else Dir1 := dLeftToRight;
  if Op2.Pt.X > Op2b.Pt.X then Dir2 := dRightToLeft else Dir2 := dLeftToRight;
  Result := Dir1 <> Dir2;
  if not Result then Exit;

  //When DiscardLeft, we want Op1b to be on the left of Op1, otherwise we
  //want Op1b to be on the right. (And likewise with Op2 and Op2b.)
  //So, to facilitate this while inserting Op1b and Op2b ...
  //when DiscardLeft, make sure we're AT or RIGHT of Pt before adding Op1b,
  //otherwise make sure we're AT or LEFT of Pt. (Likewise with Op2b.)
  if Dir1 = dLeftToRight then
  begin
    while (Op1.Next.Pt.X <= Pt.X) and
      (Op1.Next.Pt.X >= Op1.Pt.X) and (Op1.Next.Pt.Y = Pt.Y) do
      Op1 := Op1.Next;
    if DiscardLeft and (Op1.Pt.X <> Pt.X) then Op1 := Op1.Next;
    Op1b := DupOutPt(Op1, not DiscardLeft);
    if not PointsEqual(Op1b.Pt, Pt) then
    begin
      Op1 := Op1b;
      Op1.Pt := Pt;
      Op1b := DupOutPt(Op1, not DiscardLeft);
    end;
  end else
  begin
    while (Op1.Next.Pt.X >= Pt.X) and
      (Op1.Next.Pt.X <= Op1.Pt.X) and (Op1.Next.Pt.Y = Pt.Y) do
      Op1 := Op1.Next;
    if not DiscardLeft and (Op1.Pt.X <> Pt.X) then Op1 := Op1.Next;
    Op1b := DupOutPt(Op1, DiscardLeft);
    if not PointsEqual(Op1b.Pt, Pt) then
    begin
      Op1 := Op1b;
      Op1.Pt := Pt;
      Op1b := DupOutPt(Op1, DiscardLeft);
    end;
  end;

  if Dir2 = dLeftToRight then
  begin
    while (Op2.Next.Pt.X <= Pt.X) and
      (Op2.Next.Pt.X >= Op2.Pt.X) and (Op2.Next.Pt.Y = Pt.Y) do
        Op2 := Op2.Next;
    if DiscardLeft and (Op2.Pt.X <> Pt.X) then Op2 := Op2.Next;
    Op2b := DupOutPt(Op2, not DiscardLeft);
    if not PointsEqual(Op2b.Pt, Pt) then
    begin
      Op2 := Op2b;
      Op2.Pt := Pt;
      Op2b := DupOutPt(Op2, not DiscardLeft);
    end;
  end else
  begin
    while (Op2.Next.Pt.X >= Pt.X) and
      (Op2.Next.Pt.X <= Op2.Pt.X) and (Op2.Next.Pt.Y = Pt.Y) do
      Op2 := Op2.Next;
    if not DiscardLeft and (Op2.Pt.X <> Pt.X) then Op2 := Op2.Next;
    Op2b := DupOutPt(Op2, DiscardLeft);
    if not PointsEqual(Op2b.Pt, Pt) then
    begin
      Op2 := Op2b;
      Op2.Pt := Pt;
      Op2b := DupOutPt(Op2, DiscardLeft);
    end;
  end;

  if (Dir1 = dLeftToRight) = DiscardLeft then
  begin
    Op1.Prev := Op2;
    Op2.Next := Op1;
    Op1b.Next := Op2b;
    Op2b.Prev := Op1b;
  end
  else
  begin
    Op1.Next := Op2;
    Op2.Prev := Op1;
    Op1b.Prev := Op2b;
    Op2b.Next := Op1b;
  end;
end;
//------------------------------------------------------------------------------

function TClipper.JoinPoints(Jr: PJoin; out P1, P2: POutPt): Boolean;
var
  OutRec1, OutRec2: POutRec;
  Op1, Op1b, Op2, Op2b: POutPt;
  Pt: TIntPoint;
  Reverse1, Reverse2, DiscardLeftSide: Boolean;
  IsHorizontal: Boolean;
  Left, Right: cInt;
begin
  Result := False;

  OutRec1 := GetOutRec(Jr.OutPt1.Idx);
  OutRec2 := GetOutRec(Jr.OutPt2.Idx);
  Op1 := Jr.OutPt1;
  Op2 := Jr.OutPt2;

  //There are 3 kinds of joins for output polygons ...
  //1. Horizontal joins where Join.OutPt1 & Join.OutPt2 are a vertices anywhere
  //along (horizontal) collinear edges (& Join.OffPt is on the same horizontal).
  //2. Non-horizontal joins where Join.OutPt1 & Join.OutPt2 are at the same
  //location at the bottom of the overlapping segment (& Join.OffPt is above).
  //3. StrictSimple joins where edges touch but are not collinear and where
  //Join.OutPt1, Join.OutPt2 & Join.OffPt all share the same point.
  IsHorizontal := (Jr.OutPt1.Pt.Y = Jr.OffPt.Y);

  if IsHorizontal and PointsEqual(Jr.OffPt, Jr.OutPt1.Pt) and
  PointsEqual(Jr.OffPt, Jr.OutPt2.Pt) then
  begin
    //Strictly Simple join ...
    Op1b := Jr.OutPt1.Next;
    while (Op1b <> Op1) and
      PointsEqual(Op1b.Pt, Jr.OffPt) do Op1b := Op1b.Next;
    Reverse1 := (Op1b.Pt.Y > Jr.OffPt.Y);
    Op2b := Jr.OutPt2.Next;
    while (Op2b <> Op2) and
      PointsEqual(Op2b.Pt, Jr.OffPt) do Op2b := Op2b.Next;
    Reverse2 := (Op2b.Pt.Y > Jr.OffPt.Y);
    if (Reverse1 = Reverse2) then Exit;
    if Reverse1 then
    begin
      Op1b := DupOutPt(Op1, False);
      Op2b := DupOutPt(Op2, True);
      Op1.Prev := Op2;
      Op2.Next := Op1;
      Op1b.Next := Op2b;
      Op2b.Prev := Op1b;
      P1 := Op1;
      P2 := Op1b;
      Result := True;
    end else
    begin
      Op1b := DupOutPt(Op1, True);
      Op2b := DupOutPt(Op2, False);
      Op1.Next := Op2;
      Op2.Prev := Op1;
      Op1b.Prev := Op2b;
      Op2b.Next := Op1b;
      P1 := Op1;
      P2 := Op1b;
      Result := True;
    end;
  end
  else if IsHorizontal then
  begin
    //treat horizontal joins differently to non-horizontal joins since with
    //them we're not yet sure where the overlapping is, so
    //OutPt1.Pt & OutPt2.Pt may be anywhere along the horizontal edge.
    Op1 := Jr.OutPt1; Op1b := Jr.OutPt1;
    while (Op1.Prev.Pt.Y = Op1.Pt.Y) and (Op1.Prev <> Jr.OutPt1) do
      Op1 := Op1.Prev;
    while (Op1b.Next.Pt.Y = Op1b.Pt.Y) and (Op1b.Next <> Jr.OutPt1) do
      Op1b := Op1b.Next;
    if Op1.Pt.X = Op1b.Pt.X then Exit; //todo - test if this ever happens

    Op2 := Jr.OutPt2; Op2b := Jr.OutPt2;
    while (Op2.Prev.Pt.Y = Op2.Pt.Y) and (Op2.Prev <> Jr.OutPt2) do
      Op2 := Op2.Prev;
    while (Op2b.Next.Pt.Y = Op2b.Pt.Y) and (Op2b.Next <> Jr.OutPt2) do
      Op2b := Op2b.Next;
    if Op2.Pt.X = Op2b.Pt.X then Exit; //todo - test if this ever happens

    //Op1 --> Op1b & Op2 --> Op2b are the extremites of the horizontal edges
    if not GetOverlap(Op1.Pt.X, Op1b.Pt.X, Op2.Pt.X, Op2b.Pt.X, Left, Right) then
      Exit;

    //DiscardLeftSide: when overlapping edges are joined, a spike will created
    //which needs to be cleaned up. However, we don't want Op1 or Op2 caught up
    //on the discard side as either may still be needed for other joins ...
    if (Op1.Pt.X >= Left) and (Op1.Pt.X <= Right) then
    begin
      Pt := Op1.Pt; DiscardLeftSide := Op1.Pt.X > Op1b.Pt.X;
    end else if (Op2.Pt.X >= Left) and (Op2.Pt.X <= Right) then
    begin
      Pt := Op2.Pt; DiscardLeftSide := Op2.Pt.X > Op2b.Pt.X;
    end else if (Op1b.Pt.X >= Left) and (Op1b.Pt.X <= Right) then
    begin
      Pt := Op1b.Pt; DiscardLeftSide := Op1b.Pt.X > Op1.Pt.X;
    end else
    begin
      Pt := Op2b.Pt; DiscardLeftSide := Op2b.Pt.X > Op2.Pt.X;
    end;

    Result := JoinHorz(Op1, Op1b, Op2, Op2b, Pt, DiscardLeftSide);
    if not Result then Exit;
    P1 := Op1; P2 := Op2;
  end else
  begin
    //make sure the polygons are correctly oriented ...
    Op1b := Op1.Next;
    while PointsEqual(Op1b.Pt, Op1.Pt) and (Op1b <> Op1) do Op1b := Op1b.Next;
    Reverse1 := (Op1b.Pt.Y > Op1.Pt.Y) or
      not SlopesEqual(Op1.Pt, Op1b.Pt, Jr.OffPt, FUse64BitRange);
    if Reverse1 then
    begin
      Op1b := Op1.Prev;
      while PointsEqual(Op1b.Pt, Op1.Pt) and (Op1b <> Op1) do Op1b := Op1b.Prev;
      if (Op1b.Pt.Y > Op1.Pt.Y) or
        not SlopesEqual(Op1.Pt, Op1b.Pt, Jr.OffPt, FUse64BitRange) then Exit;
    end;
    Op2b := Op2.Next;
    while PointsEqual(Op2b.Pt, Op2.Pt) and (Op2b <> Op2) do Op2b := Op2b.Next;
    Reverse2 := (Op2b.Pt.Y > Op2.Pt.Y) or
      not SlopesEqual(Op2.Pt, Op2b.Pt, Jr.OffPt, FUse64BitRange);
    if Reverse2 then
    begin
      Op2b := Op2.Prev;
      while PointsEqual(Op2b.Pt, Op2.Pt) and (Op2b <> Op2) do Op2b := Op2b.Prev;
      if (Op2b.Pt.Y > Op2.Pt.Y) or
        not SlopesEqual(Op2.Pt, Op2b.Pt, Jr.OffPt, FUse64BitRange) then Exit;
    end;

    if (Op1b = Op1) or (Op2b = Op2) or (Op1b = Op2b) or
      ((OutRec1 = OutRec2) and (Reverse1 = Reverse2)) then Exit;

    if Reverse1 then
    begin
      Op1b := DupOutPt(Op1, False);
      Op2b := DupOutPt(Op2, True);
      Op1.Prev := Op2;
      Op2.Next := Op1;
      Op1b.Next := Op2b;
      Op2b.Prev := Op1b;
      P1 := Op1;
      P2 := Op1b;
      Result := True;
    end else
    begin
      Op1b := DupOutPt(Op1, True);
      Op2b := DupOutPt(Op2, False);
      Op1.Next := Op2;
      Op2.Prev := Op1;
      Op1b.Prev := Op2b;
      Op2b.Next := Op1b;
      P1 := Op1;
      P2 := Op1b;
      Result := True;
    end;
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
  Jr: PJoin;
  OutRec1, OutRec2, HoleStateRec: POutRec;
  P1, P2: POutPt;
begin
  for I := 0 to FJoinList.count -1 do
  begin
    Jr := FJoinList[I];

    OutRec1 := GetOutRec(Jr.OutPt1.Idx);
    OutRec2 := GetOutRec(Jr.OutPt2.Idx);

    if not Assigned(OutRec1.Pts) or not Assigned(OutRec2.Pts) then Continue;
    if OutRec1.IsOpen or OutRec2.IsOpen then Continue;

    //get the polygon fragment with the correct hole state (FirstLeft)
    //before calling JoinPoints() ...
    if OutRec1 = OutRec2 then HoleStateRec := OutRec1
    else if Param1RightOfParam2(OutRec1, OutRec2) then HoleStateRec := OutRec2
    else if Param1RightOfParam2(OutRec2, OutRec1) then HoleStateRec := OutRec1
    else HoleStateRec := GetLowermostRec(OutRec1, OutRec2);

    if not JoinPoints(Jr, P1, P2) then Continue;

    if (OutRec1 = OutRec2) then
    begin
      //instead of joining two polygons, we've just created a new one by
      //splitting one polygon into two.
      OutRec1.Pts := P1; //Jr.OutPt1
      OutRec1.BottomPt := nil;
      OutRec2 := CreateOutRec;
      OutRec2.Pts := P2;

      //update all OutRec2.Pts idx's ...
      UpdateOutPtIdxs(OutRec2);

      //sort out the hole states of both polygon ...
      if Poly2ContainsPoly1(OutRec2.Pts, OutRec1.Pts, FUse64BitRange) then
      begin
        //OutRec2 is contained by OutRec1 ...
        OutRec2.IsHole := not OutRec1.IsHole;
        OutRec2.FirstLeft := OutRec1;

        //fixup FirstLeft pointers that may need reassigning to OutRec1
        if FUsingPolyTree then FixupFirstLefts2(OutRec2, OutRec1);

        if (OutRec2.IsHole xor FReverseOutput) = (Area(OutRec2) > 0) then
            ReversePolyPtLinks(OutRec2.Pts);
      end else if Poly2ContainsPoly1(OutRec1.Pts, OutRec2.Pts, FUse64BitRange) then
      begin
        //OutRec1 is contained by OutRec2 ...
        OutRec2.IsHole := OutRec1.IsHole;
        OutRec1.IsHole := not OutRec2.IsHole;
        OutRec2.FirstLeft := OutRec1.FirstLeft;
        OutRec1.FirstLeft := OutRec2;

        //fixup FirstLeft pointers that may need reassigning to OutRec1
        if FUsingPolyTree then FixupFirstLefts2(OutRec1, OutRec2);

        if (OutRec1.IsHole xor FReverseOutput) = (Area(OutRec1) > 0) then
          ReversePolyPtLinks(OutRec1.Pts);
      end else
      begin
        //the 2 polygons are completely separate ...
        OutRec2.IsHole := OutRec1.IsHole;
        OutRec2.FirstLeft := OutRec1.FirstLeft;

        //fixup FirstLeft pointers that may need reassigning to OutRec2
        if FUsingPolyTree then FixupFirstLefts1(OutRec1, OutRec2);
      end;
    end else
    begin
      //joined 2 polygons together ...

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
    repeat //for each Pt in Path until duplicate found do ...
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
// OffsetPaths ...
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

function GetBounds(const Pts: TPaths): TIntRect;
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
    FSinA, FSin, FCos: Extended;
    FMiterLim, FSteps360: Double;
    FNorms: TArrayOfDoublePoint;
    FSolution: TPaths;
    FOutPos: Integer;
    FInP: TPath;
    FOutP: TPath;

    procedure AddPoint(const Pt: TIntPoint);
    procedure DoSquare(J, K: Integer);
    procedure DoMiter(J, K: Integer; R: Double);
    procedure DoRound(J, K: Integer);
    procedure OffsetPoint(J: Integer;
      var K: Integer; JoinType: TJoinType);
  public
    constructor Create(const Pts: TPaths; Delta: Double;
      JoinType: TJoinType; EndType: TEndType;
      Limit: Double = 0);
    property Solution: TPaths read FSolution;
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
  A, Dx: Double;
begin
  //see offset_triginometry.svg in the documentation folder ...
  A := ArcTan2(FSinA, FNorms[K].X * FNorms[J].X + FNorms[K].Y * FNorms[J].Y);
  Dx := tan(A/4);
  AddPoint(IntPoint(
    round(FInP[J].X + FDelta * (FNorms[K].X - FNorms[K].Y *Dx)),
    round(FInP[J].Y + FDelta * (FNorms[K].Y + FNorms[K].X *Dx))));
  AddPoint(IntPoint(
    round(FInP[J].X + FDelta * (FNorms[J].X + FNorms[J].Y *Dx)),
    round(FInP[J].Y + FDelta * (FNorms[J].Y - FNorms[J].X *Dx))));
end;
//------------------------------------------------------------------------------

procedure TOffsetBuilder.DoMiter(J, K: Integer; R: Double);
var
  Q: Double;
begin
  Q := FDelta / R;
  AddPoint(IntPoint(round(FInP[J].X + (FNorms[K].X + FNorms[J].X)*Q),
    round(FInP[J].Y + (FNorms[K].Y + FNorms[J].Y)*Q)));
end;
//------------------------------------------------------------------------------

procedure TOffsetBuilder.DoRound(J, K: Integer);
var
  I, Steps: Integer;
  A, X, X2, Y: Double;
begin
  A := ArcTan2(FSinA, FNorms[K].X * FNorms[J].X + FNorms[K].Y * FNorms[J].Y);
  Steps := Round(FSteps360 * Abs(A));

  X := FNorms[K].X;
  Y := FNorms[K].Y;
  for I := 1 to Steps do
  begin
    AddPoint(IntPoint(
      round(FInP[J].X + X * FDelta),
      round(FInP[J].Y + Y * FDelta)));
    X2 := X;
    X := X * FCos - FSin * Y;
    Y := X2 * FSin + Y * FCos;
  end;
  AddPoint(IntPoint(
    round(FInP[J].X + FNorms[J].X * FDelta),
    round(FInP[J].Y + FNorms[J].Y * FDelta)));
end;
//------------------------------------------------------------------------------

procedure TOffsetBuilder.OffsetPoint(J: Integer;
  var K: Integer; JoinType: TJoinType);
var
  R: Double;
begin
  FSinA := (FNorms[K].X * FNorms[J].Y - FNorms[J].X * FNorms[K].Y);
  if FSinA > 1 then FSinA := 1
  else if FSinA < -1 then FSinA := -1;

  if FSinA * FDelta < 0 then
  begin
    AddPoint(IntPoint(round(FInP[J].X + FNorms[K].X * FDelta),
      round(FInP[J].Y + FNorms[K].Y * FDelta)));
    AddPoint(FInP[J]);
    AddPoint(IntPoint(round(FInP[J].X + FNorms[J].X * FDelta),
      round(FInP[J].Y + FNorms[J].Y * FDelta)));
  end
  else
    case JoinType of
      jtMiter:
      begin
        R := 1 + (FNorms[J].X * FNorms[K].X + FNorms[J].Y * FNorms[K].Y);
        if (R >= FMiterLim) then DoMiter(J, K, R)
        else DoSquare(J, K);
      end;
      jtSquare: DoSquare(J, K);
      jtRound: DoRound(J, K);
    end;
  K := J;
end;
//------------------------------------------------------------------------------

constructor TOffsetBuilder.Create(const Pts: TPaths; Delta: Double;
  JoinType: TJoinType; EndType: TEndType; Limit: Double = 0);
var
  I, J, K, Len: Integer;
  Outer: TPath;
  Bounds: TIntRect;
  X,X2,Y: Double;
begin
  FSolution := nil;

  if (EndType <> etClosed) and (Delta < 0) then Delta := -Delta;
  FDelta := Delta;
  if JoinType = jtMiter then
  begin
    //FMiterConst: see offset_triginometry3.svg in the documentation folder ...
    if Limit > 2 then FMiterLim := 2/(sqr(Limit))
    else FMiterLim := 0.5;
    if EndType = etRound then Limit := 0.25;
  end;

  if (JoinType = jtRound) or (EndType = etRound) then
  begin
    if (Limit <= 0) then Limit := 0.25
    else if Limit > abs(FDelta) * 0.25 then Limit := abs(FDelta) * 0.25;
    //FRoundConst: see offset_triginometry2.svg in the documentation folder ...
    FSteps360 := Pi / ArcCos(1 - Limit / Abs(FDelta));
    Math.SinCos(2 * Pi / FSteps360, FSin, FCos);
    FSteps360 := FSteps360 / (Pi * 2);
    if FDelta < 0 then FSin := -FSin;
  end;

  SetLength(FSolution, length(Pts));
  for I := 0 to high(Pts) do
  begin
    //for each polygon in Pts ...
    FInP := Pts[I];
    Len := length(FInP);

    if (Len = 0) or ((Len < 3) and (FDelta <= 0)) then Continue;

    //if a single vertex then build circle or a square ...
    if (Len = 1) then
    begin
      if JoinType = jtRound then
      begin
        X := 1; Y := 0;
        for J := 1 to Round(FSteps360 * 2 * Pi) do
        begin
          AddPoint(IntPoint(
            Round(FInP[0].X + X * FDelta),
            Round(FInP[0].Y + Y * FDelta)));
          X2 := X;
          X := X * FCos - FSin * Y;
          Y := X2 * FSin + Y * FCos;
        end
      end else
      begin
        X := -1; Y := -1;
        for J := 1 to 4 do
        begin
          AddPoint(IntPoint( Round(FInP[0].X + X * FDelta),
            Round(FInP[0].Y + Y * FDelta)));
          if X < 0 then X := 1
          else if Y < 0 then Y := 1
          else X := -1;
        end;
      end;
      SetLength(FOutP, FOutPos);
      FSolution[I] := FOutP;
      Continue;
    end;

    //build Normals ...
    SetLength(FNorms, Len);
    for J := 0 to Len-2 do
      FNorms[J] := GetUnitNormal(FInP[J], FInP[J+1]);
    if (EndType = etClosed) then
      FNorms[Len-1] := GetUnitNormal(FInP[Len-1], FInP[0])
    else
      FNorms[Len-1] := FNorms[Len-2];

    FOutPos := 0;
    FOutP := nil;

    if (EndType = etClosed)  then
    begin
      K := Len -1;
      for J := 0 to Len-1 do
        OffsetPoint(J, K, JoinType);
      SetLength(FOutP, FOutPos);
      FSolution[I] := FOutP;
    end else //is polyline
    begin
      K := 0;
      //offset the polyline going forward ...
      for J := 1 to Len-2 do
        OffsetPoint(J, K, JoinType);

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
        FSinA := 0;
        if EndType = etSquare then
          DoSquare(J, K) else
          DoRound(J, K);
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
        OffsetPoint(J, K, JoinType);

      //finally handle the start (butt, round or square) ...
      if EndType = etButt then
      begin
        AddPoint(IntPoint(round(FInP[0].X - FNorms[0].X *FDelta),
          round(FInP[0].Y - FNorms[0].Y * FDelta)));
        AddPoint(IntPoint(round(FInP[0].X + FNorms[0].X *FDelta),
          round(FInP[0].Y + FNorms[0].Y * FDelta)));
      end else
      begin
        FSinA := 0;
        if EndType = etSquare then
          DoSquare(0, 1) else
          DoRound(0, 1);
      end;
      SetLength(FOutP, FOutPos);
      FSolution[I] := FOutP;
    end;
  end;

  //now clean up untidy corners ...
  with TClipper.Create do
  try
    AddPaths(FSolution, ptSubject, True);
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
      AddPath(Outer, ptSubject, True);
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

function StripDupsAndGetBotPt(const Poly: TPath; Closed: Boolean;
  out BotPt: PIntPoint): TPath;
var
  I, J, Len: Integer;
begin
  Result := nil;
  BotPt := nil;
  Len := Length(Poly);
  if Closed then
    while (Len > 0) and PointsEqual(Poly[0], Poly[Len -1]) do Dec(Len);
  if Len = 0 then Exit;
  SetLength(Result, Len);
  J := 0;
  Result[0] := Poly[0];
  BotPt := @Result[0];
  for I := 1 to Len - 1 do
    if not PointsEqual(Poly[I], Result[J]) then
    begin
      Inc(J);
      Result[J] := Poly[I];
      if Result[J].Y > BotPt.Y then
        BotPt := @Result[J]
      else if (Result[J].Y = BotPt.Y) and (Result[J].X < BotPt.X)  then
        BotPt := @Result[J];
    end;
  Inc(J);
  if (J < 2) or (Closed and (J = 2)) then J := 0;
  SetLength(Result, J);
end;
//------------------------------------------------------------------------------

function OffsetPaths(const Polys: TPaths; const Delta: Double;
  JoinType: TJoinType = jtSquare; EndType: TEndType = etClosed;
  Limit: Double = 0): TPaths;
var
  I, Len, BotI: Integer;
  Pts: TPaths;
  BotPt, Pt: PIntPoint;
begin
  Result := nil;
  Len := Length(Polys);
  SetLength(Pts, Len);
  BotPt :=  nil;
  BotI := -1;
  //BotPt => lower most and left most point which must be an outer polygon
  for I := 0 to Len -1 do
  begin
    Pts[I] := StripDupsAndGetBotPt(Polys[I], EndType = etClosed, Pt);
    if assigned(Pt) then
      if not assigned(BotPt) or (Pt.Y > BotPt.Y) or
        ((Pt.Y = BotPt.Y) and (Pt.X < BotPt.X)) then
      begin
        BotPt := Pt;
        BotI := I;
      end;
  end;

  if (EndType = etClosed) and (BotI >= 0) and not Orientation(Pts[BotI]) then
    Pts := ReversePaths(Pts);

  with TOffsetBuilder.Create(Pts, Delta, JoinType, EndType, Limit) do
  try
    result := Solution;
  finally
    Free;
  end;
end;
//------------------------------------------------------------------------------

function SimplifyPolygon(const Poly: TPath; FillType: TPolyFillType = pftEvenOdd): TPaths;
begin
  with TClipper.Create do
  try
    StrictlySimple := True;
    AddPath(Poly, ptSubject, True);
    Execute(ctUnion, Result, FillType, FillType);
  finally
    free;
  end;
end;
//------------------------------------------------------------------------------

function SimplifyPolygons(const Polys: TPaths; FillType: TPolyFillType = pftEvenOdd): TPaths;
begin
  with TClipper.Create do
  try
    StrictlySimple := True;
    AddPaths(Polys, ptSubject, True);
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

function SlopesNearCollinear(const Pt1, Pt2, Pt3: TIntPoint; DistSqrd: Double): Boolean;
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

function CleanPolygon(const Poly: TPath; Distance: Double = 1.415): TPath;
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
      SlopesNearCollinear(Pt, Poly[I], Poly[I+1], DistSqrd)) do inc(I);
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

  if (K > 2) and SlopesNearCollinear(Result[K -2],
      Result[K -1], Result[0], DistSqrd) then Dec(K);
  if (K < 3) then Result := nil
  else if (K <= HighI) then SetLength(Result, K);
end;
//------------------------------------------------------------------------------

function CleanPolygons(const Polys: TPaths; Distance: double = 1.415): TPaths;
var
  I, Len: Integer;
begin
  Len := Length(Polys);
  SetLength(Result, Len);
  for I := 0 to Len - 1 do
    Result[I] := CleanPolygon(Polys[I], Distance);
end;
//------------------------------------------------------------------------------

type
  TNodeType = (ntAny, ntOpen, ntClosed);

procedure AddPolyNodeToPolygons(PolyNode: TPolyNode;
  NodeType: TNodeType; var Paths: TPaths);
var
  I: Integer;
  Match: Boolean;
begin
  case NodeType of
    ntAny: Match := True;
    ntClosed: Match := not PolyNode.IsOpen;
    else Exit;
  end;

  if (Length(PolyNode.Contour) > 0) and Match then
  begin
    I := Length(Paths);
    SetLength(Paths, I +1);
    Paths[I] := PolyNode.Contour;
  end;
  for I := 0 to PolyNode.ChildCount - 1 do
    AddPolyNodeToPolygons(PolyNode.Childs[I], NodeType, Paths);
end;
//------------------------------------------------------------------------------

function PolyTreeToPaths(PolyTree: TPolyTree): TPaths;
begin
  Result := nil;
  AddPolyNodeToPolygons(PolyTree, ntAny, Result);
end;
//------------------------------------------------------------------------------

function ClosedPathsFromPolyTree(PolyTree: TPolyTree): TPaths;
begin
  Result := nil;
  AddPolyNodeToPolygons(PolyTree, ntClosed, Result);
end;
//------------------------------------------------------------------------------

function OpenPathsFromPolyTree(PolyTree: TPolyTree): TPaths;
var
  I, J: Integer;
begin
  Result := nil;
  //Open polys are top level only, so ...
  for I := 0 to PolyTree.ChildCount - 1 do
    if PolyTree.Childs[I].IsOpen then
    begin
      J := Length(Result);
      SetLength(Result, J +1);
      Result[J] := PolyTree.Childs[I].Contour;
    end;
end;

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------

{$IFDEF use_deprecated}
function TClipperBase.AddPolygons(const Paths: TPaths; PolyType: TPolyType): Boolean;
begin
  Result := AddPaths(Paths, PolyType, True);
end;
//------------------------------------------------------------------------------

function TClipperBase.AddPolygon(const Path: TPath; PolyType: TPolyType): Boolean;
begin
  Result := AddPath(Path, PolyType, True);
end;
//------------------------------------------------------------------------------

function OffsetPolygons(const Polys: TPolygons; const Delta: Double;
  JoinType: TJoinType = jtSquare; Limit: Double = 0;
  AutoFix: Boolean = True): TPolygons;
begin
  result := OffsetPaths(Polys, Delta, JoinType, etClosed, Limit);
end;
//------------------------------------------------------------------------------

function PolyTreeToPolygons(PolyTree: TPolyTree): TPolygons;
begin
  result := PolyTreeToPaths(PolyTree);
end;
//------------------------------------------------------------------------------

function ReversePolygon(const Pts: TPolygon): TPolygon;
begin
  result := ReversePath(Pts);
end;
//------------------------------------------------------------------------------

function ReversePolygons(const Pts: TPolygons): TPolygons;
begin
  result := ReversePaths(Pts);
end;
//------------------------------------------------------------------------------
{$ENDIF}


end.
