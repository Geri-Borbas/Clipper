unit clipper;

(*******************************************************************************
*                                                                              *
* Author    :  Angus Johnson                                                   *
* Version   :  4.2.8                                                           *
* Date      :  21 May 2011                                                     *
* Website   :  http://www.angusj.com                                           *
* Copyright :  Angus Johnson 2010-2011                                         *
*                                                                              *
* License:                                                                     *
* Use, modification & distribution is subject to Boost Software License Ver 1. *
* http://www.boost.org/LICENSE_1_0.txt                                         *
*                                                                              *
* Attributions:                                                                *
* The code in this library is an extension of Bala Vatti's clipping algorithm: *
* "A generic solution to polygon clipping"                                     *
* Communications of the ACM, Vol 35, Issue 7 (July 1992) pp 56-63.             *
* http://portal.acm.org/citation.cfm?id=129906                                 *
*                                                                              *
* Computer graphics and geometric modeling: implementation and algorithms      *
* By Max K. Agoston                                                            *
* Springer; 1 edition (January 4, 2005)                                        *
* http://books.google.com/books?q=vatti+clipping+agoston                       *
*                                                                              *
*******************************************************************************)

interface

uses
  SysUtils, Types, Classes, Math;

type

  PIntPoint = ^TIntPoint;
  TIntPoint = record X, Y: int64; end;
  TIntRect = record left, top, right, bottom: int64; end;

  TClipType = (ctIntersection, ctUnion, ctDifference, ctXor);
  TPolyType = (ptSubject, ptClip);
  TPolyFillType = (pftEvenOdd, pftNonZero);

  //used internally ...
  TEdgeSide = (esLeft, esRight);
  TIntersectProtect = (ipLeft, ipRight);
  TIntersectProtects = set of TIntersectProtect;
  TDirection = (dRightToLeft, dLeftToRight);
  TArrayOfIntPoint = array of TIntPoint;
  TArrayOfArrayOfIntPoint = array of TArrayOfIntPoint;

  PEdge = ^TEdge;
  TEdge = record
    xbot : int64;  //bottom
    ybot : int64;
    xcurr: int64;  //current (ie relative to bottom of current scanbeam)
    ycurr: int64;
    xtop : int64;  //top
    ytop : int64;
    tmpX :  int64;
    dx   : double;   //the inverse of slope
    polyType : TPolyType;
    side     : TEdgeSide;
    windDelta: integer; //1 or -1 depending on winding direction
    windCnt  : integer;
    windCnt2 : integer;  //winding count of the opposite polytype
    outIdx   : integer;
    next     : PEdge;
    prev     : PEdge;
    nextInLML: PEdge;
    prevInAEL: PEdge;
    nextInAEL: PEdge;
    prevInSEL: PEdge;
    nextInSEL: PEdge;
  end;

  PEdgeArray = ^TEdgeArray;
  TEdgeArray = array[0.. MaxInt div sizeof(TEdge) -1] of TEdge;

  PScanbeam = ^TScanbeam;
  TScanbeam = record
    y   : int64;
    next: PScanbeam;
  end;

  PIntersectNode = ^TIntersectNode;
  TIntersectNode = record
    edge1: PEdge;
    edge2: PEdge;
    pt   : TIntPoint;
    next : PIntersectNode;
  end;

  PLocalMinima = ^TLocalMinima;
  TLocalMinima = record
    y         : int64;
    leftBound : PEdge;
    rightBound: PEdge;
    next      : PLocalMinima;
  end;

  PPolyPt = ^TPolyPt;
  TPolyPt = record
    pt     : TIntPoint;
    next   : PPolyPt;
    prev   : PPolyPt;
    isHole : boolean;
  end;

  PJoinRec = ^TJoinRec;
  TJoinRec = record
    pt1a     : TIntPoint;
    pt1b     : TIntPoint;
    poly1Idx : integer;
    pt2a     : TIntPoint;
    pt2b     : TIntPoint;
    poly2Idx : integer;
  end;

  PHorzRec = ^THorzRec;
  THorzRec = record
    edge     : PEdge;
    savedIdx : integer;
    next     : PHorzRec;
    prev     : PHorzRec;
  end;

type

  TClipperBase = class
  private
    fEdgeList      : TList;
    fLmList        : PLocalMinima; //localMinima list
    fCurrLm        : PLocalMinima; //current localMinima node
    fUseFullRange : boolean;
    procedure DisposeLocalMinimaList;
    procedure SetUseFullRange(newVal: boolean);
  protected
    procedure Reset; virtual;
    procedure PopLocalMinima;
    property CurrentLm: PLocalMinima read fCurrLm;
  public
    constructor Create; virtual;
    destructor Destroy; override;
    function AddPolygon(const polygon: TArrayOfIntPoint; polyType: TPolyType): boolean;
    function AddPolygons(const polygons: TArrayOfArrayOfIntPoint; polyType: TPolyType): boolean;
    procedure Clear; virtual;
    //UseFullCoordinateRange: When this property is true, polygon coordinates
    //can have any signed 64bit integer values (ie +/- 2^63). When false,
    //coordinates must be in the range +/- 1.5E9 otherwise an error will be
    //thrown on calling the AddPolygon() or AddPolygons() methods. The benefit
    //of setting this property false is a small (~15%) increase in performance.
    //(Default value = true.)
    property UseFullCoordinateRange: boolean read fUseFullRange write SetUseFullRange;
  end;

  TClipper = class(TClipperBase)
  private
    fPolyPtList    : TList;
    fJoinList      : TList;
    fClipType      : TClipType;
    fScanbeam      : PScanbeam; //scanbeam list
    fActiveEdges   : PEdge;     //active edge list
    fSortedEdges   : PEdge;     //used for temporary sorting
    fIntersectNodes: PIntersectNode;
    fClipFillType  : TPolyFillType;
    fSubjFillType  : TPolyFillType;
    fExecuteLocked : boolean;
    fHorizJoins    : PHorzRec;
    procedure DisposeScanbeamList;
    procedure InsertScanbeam(const y: int64);
    function PopScanbeam: int64;
    procedure SetWindingCount(edge: PEdge);
    function IsNonZeroFillType(edge: PEdge): boolean;
    function IsNonZeroAltFillType(edge: PEdge): boolean;
    procedure AddEdgeToSEL(edge: PEdge);
    procedure CopyAELToSEL;
    procedure InsertLocalMinimaIntoAEL(const botY: int64);
    procedure SwapPositionsInAEL(e1, e2: PEdge);
    procedure SwapPositionsInSEL(e1, e2: PEdge);
    function IsTopHorz(const XPos: int64): boolean;
    procedure ProcessHorizontal(horzEdge: PEdge);
    procedure ProcessHorizontals;
    procedure AddIntersectNode(e1, e2: PEdge; const pt: TIntPoint);
    function ProcessIntersections(const topY: int64): boolean;
    procedure BuildIntersectList(const topY: int64);
    procedure ProcessIntersectList;
    procedure DeleteFromAEL(e: PEdge);
    procedure DeleteFromSEL(e: PEdge);
    procedure IntersectEdges(e1,e2: PEdge;
      const pt: TIntPoint; protects: TIntersectProtects = []);
    procedure DoMaxima(e: PEdge; const topY: int64);
    procedure UpdateEdgeIntoAEL(var e: PEdge);
    function FixupIntersections: boolean;
    procedure SwapIntersectNodes(int1, int2: PIntersectNode);
    procedure ProcessEdgesAtTopOfScanbeam(const topY: int64);
    function IsContributing(edge: PEdge): boolean;
    function AddPolyPt(e: PEdge; const pt: TIntPoint): PPolyPt;
    procedure AddLocalMaxPoly(e1, e2: PEdge; const pt: TIntPoint);
    procedure AddLocalMinPoly(e1, e2: PEdge; const pt: TIntPoint);
    procedure AppendPolygon(e1, e2: PEdge);
    procedure DisposePolyPts(pp: PPolyPt);
    procedure DisposeAllPolyPts;
    procedure DisposeIntersectNodes;
    function GetResult: TArrayOfArrayOfIntPoint;
    function FixupOutPolygon(outPoly: PPolyPt): PPolyPt;
    function IsHole(e: PEdge): boolean;
    procedure AddJoin(e1, e2: PEdge;
      e1OutIdx: integer = -1; e2OutIdx: integer = -1);
    procedure ClearJoins;
    procedure AddHorzJoin(e: PEdge; idx: integer);
    procedure ClearHorzJoins;
    procedure JoinCommonEdges;
  protected
    procedure Reset; override;
  public
    function Execute(clipType: TClipType;
      out solution: TArrayOfArrayOfIntPoint;
      subjFillType: TPolyFillType = pftEvenOdd;
      clipFillType: TPolyFillType = pftEvenOdd): boolean;
    constructor Create; override;
    destructor Destroy; override;
  end;

function IsClockwise(const pts: TArrayOfIntPoint;
  UseFullInt64Range: boolean = true): boolean;
function Area(const pts: TArrayOfIntPoint;
  UseFullInt64Range: boolean = true): double;
function OffsetPolygons(const pts: TArrayOfArrayOfIntPoint;
  const delta: single): TArrayOfArrayOfIntPoint;
function IntPoint(const X, Y: Int64): TIntPoint;

implementation

type
  TDoublePoint = record X, Y: double; end;
  TArrayOfDoublePoint = array of TDoublePoint;

const
  horizontal: double = -3.4e+38;

resourcestring
  rsMissingRightbound = 'InsertLocalMinimaIntoAEL: missing rightbound';
  rsDoMaxima = 'DoMaxima error';
  rsUpdateEdgeIntoAEL = 'UpdateEdgeIntoAEL error';
  rsHorizontal = 'ProcessHorizontal error';
  rsInvalidInt = 'Integer exceeds range bounds';
  rsUseFullRange = 'UseFullCoordinateRange() can''t be changed until '+
  'the Clipper object has been cleared."';
  rsJoinError = 'Join Output polygons error';

//------------------------------------------------------------------------------
// Int128 Functions ...
//------------------------------------------------------------------------------

type
  TInt128 = record
    lo   : Int64;
    hi   : Int64;
  end;

{$OVERFLOWCHECKS OFF}
procedure Int128Negate(var val: TInt128);
begin
  if val.lo = 0 then
  begin
    if val.hi = 0 then exit;
    val.lo := not val.lo;
    val.hi := not val.hi +1;
  end else
  begin
    val.lo := not val.lo  +1;
    val.hi := not val.hi;
  end;
end;
//------------------------------------------------------------------------------

function Int128(const val: Int64): TInt128; overload;
begin
  result.hi := 0;
  result.lo := abs(val);
  if val < 0 then Int128Negate(result);
end;
//------------------------------------------------------------------------------

function Int128Equal(const int1, int2: TInt128): boolean;
begin
  result := (int1.lo = int2.lo) and (int1.hi = int2.hi);
end;
//------------------------------------------------------------------------------

function Int128LessThan(const int1, int2: TInt128): boolean;
begin
  if (int1.hi < int2.hi) then result := true
  else if (int1.hi > int2.hi) then result := false
  else if (int1.hi >= 0) then result := UInt64(int1.lo) < UInt64(int2.lo)
  else result := UInt64(int1.lo) > UInt64(int2.lo)
end;
//------------------------------------------------------------------------------

function Int128Add(const int1, int2: TInt128): TInt128;
begin
  if (int1.lo = 0) and (int1.hi = 0) then result := int2
  else if (int2.lo = 0) and (int2.hi = 0) then result := int1
  else
  begin
    result.lo := int1.lo + int2.lo;
    result.hi := int1.hi + int2.hi;
    if ((int1.lo < 0) and (int2.lo < 0)) or
      (((int1.lo < 0) <> (int2.lo < 0)) and (result.lo >= 0)) then
        result.hi := result.hi +1;
  end;
end;
//------------------------------------------------------------------------------

function Int128Sub(int1, int2: TInt128): TInt128;
begin
  Int128Negate(int2);
  result := Int128Add(int1, int2);
end;
//------------------------------------------------------------------------------

function Int128Mul(int1, int2: Int64): TInt128;
var
  a, b, c: Int64;
  int1Hi, int1Lo, int2Hi, int2Lo: Int64;
  hiBitSet, negate: boolean;
begin
  //save the result's sign before clearing both sign bits ...
  negate := (int1 < 0) <> (int2 < 0);
  if int1 < 0 then int1 := -int1;
  if int2 < 0 then int2 := -int2;

  int1Hi := int1 shr 32;
  int1Lo := int1 and $FFFFFFFF;
  int2Hi := int2 shr 32;
  int2Lo := int2 and $FFFFFFFF;

  //It's safe to multiply 32bit ints in unsigned 64bit space without overflow.
  //Also, the *result* of the karatsuba equation (see below) can also be
  //stored in 64bit space given that:
  //x1*y0 + x0*y1 = (x1+x0) * (y1+y0) - x0*y0 - x1*y1 (karatsuba equation)
  //and given that x1 (int1Hi below) and y1 (int2Hi below) are now only 31bits,
  //and also given that (31bit*32bit) + (32bit*31bit) < 64bits.
  //However, if either (x1+x0) > 32bits or (y1+y0) > 32bits, then we must
  //either resort to recursion or avoid using karatsuba altogether.
  //see also - http://en.wikipedia.org/wiki/Karatsuba_algorithm

  a := int1Hi * int2Hi;
  b := int1Lo * int2Lo;
  c := int1Hi*int2Lo + int1Lo*int2Hi;

  //given that result = a shl64 + c shl 32 + b ...
  result.lo := c shl 32;
  result.hi := a + (c shr 32);
  hiBitSet := (result.lo < 0); //prepare to test for overflow carry
  result.lo := result.lo + b;
  if (hiBitSet and (b < 0)) or
    ((hiBitSet <> (b < 0)) and (result.lo >= 0)) then inc(result.hi);

  if negate then Int128Negate(result);
end;
//------------------------------------------------------------------------------

function Int128Div(num, denom: TInt128): TInt128;
var
  i: integer;
  p, p2: TInt128;
  negate: boolean;
begin
  if (denom.lo = 0) and (denom.hi = 0) then
    raise Exception.create('int128Div error: divide by zero');

  negate := (denom.hi < 0) <> (num.hi < 0);
  if num.hi < 0 then Int128Negate(num);
  if denom.hi < 0 then Int128Negate(denom);
  if (denom.hi > num.hi) or ((denom.hi = num.hi) and (denom.lo > num.lo)) then
  begin
    result := Int128(0); //result is only a fraction of 1
    exit;
  end;
  Int128Negate(denom);

  p := int128(0);
  result := num;
  for i := 0 to 127 do
  begin
    p.hi := p.hi shl 1;
    if p.lo < 0 then inc(p.hi);
    p.lo := p.lo shl 1;
    if result.hi < 0 then inc(p.lo);
    result.hi := result.hi shl 1;
    if result.lo < 0 then inc(result.hi);
    result.lo := result.lo shl 1;
    p2 := p;
    p := Int128Add(p, denom);
    if p.hi < 0 then
      p := p2 else
      inc(result.lo);
  end;
  if negate then Int128Negate(result);
end;
//---------------------------------------------------------------------------

procedure int128Div10(val: TInt128; out result: TInt128; out remainder: integer);
var
  i: integer;
begin
  remainder := 0;
  result.lo := 0;
  result.hi := 0;
  for i := 63 downto 0 do
  begin
    if (val.hi and (int64(1) shl i)) <> 0 then
      remainder := remainder * 2 + 1 else
      remainder := remainder *2;
    if remainder >= 10 then
    begin
      result.hi := result.hi + (int64(1) shl i);
      dec(remainder, 10);
    end;
  end;
  for i := 63 downto 0 do
  begin
    if (val.lo and (int64(1) shl i)) <> 0 then
      remainder := remainder * 2 + 1 else
      remainder := remainder *2;
    if remainder >= 10 then
    begin
      result.lo := result.lo + (int64(1) shl i);
      dec(remainder, 10);
    end;
  end;
end;
//------------------------------------------------------------------------------

function Int128AsDouble(val: TInt128): double;
const
  shift64: double = 18446744073709551616.0;
begin
  if (val.hi < 0) then
  begin
    Int128Negate(val);
    result := -(val.lo + val.hi * shift64);
  end else
    result := (val.lo + val.hi * shift64);
end;
//------------------------------------------------------------------------------

function int128AsString(val: TInt128): string;
var
  valDiv10: TInt128;
  r: integer;
  isNeg: boolean;
begin
  result := '';
  if val.hi < 0 then
  begin
    Int128Negate(val);
    isNeg := true;
  end else
    isNeg := false;
  while (val.hi <> 0) or (val.lo <> 0) do
  begin
    int128Div10(val, valDiv10, r);
    result := inttostr(r) + result;
    val := valDiv10;
  end;
  if result = '' then result := '0';
  if isNeg then result := '-' + result;
end;
//------------------------------------------------------------------------------
{$OVERFLOWCHECKS ON}

//------------------------------------------------------------------------------
// Miscellaneous Functions ...
//------------------------------------------------------------------------------

function PointsEqual(const P1, P2: TIntPoint): Boolean; overload;
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

function GetAngle(const pt1, pt2: TIntPoint): double;
begin
  if (pt1.Y = pt2.Y) then
  begin
    if pt1.X > pt2.X then result := pi/2
    else result := -pi/2;
  end
  else
    result := ArcTan2(pt1.X-pt2.X, pt1.Y-pt2.Y);
end;
//---------------------------------------------------------------------------

function IsClockwise(const pts: TArrayOfIntPoint;
  UseFullInt64Range: boolean = true): boolean; overload;
var
  i, highI: integer;
  a: double;
  area: TInt128;
begin
  result := true;
  highI := high(pts);
  if highI < 2 then exit;
  if UseFullInt64Range then
  begin
    area := Int128Sub(Int128Mul(pts[highI].x, pts[0].y),
      Int128Mul(pts[0].x, pts[highI].y));
    for i := 0 to highI-1 do
      area := Int128Add(area, Int128Sub(Int128Mul(pts[i].x, pts[i+1].y),
         Int128Mul(pts[i+1].x, pts[i].y)));
    result := area.hi >= 0; //assumes Y axis is inverted
  end else
  begin
    a := pts[highI].x * pts[0].y - pts[0].x * pts[highI].y;
    for i := 0 to highI-1 do
      a := a + pts[i].x * pts[i+1].y - pts[i+1].x * pts[i].y;
    result := a > 0;     //assumes Y axis is inverted
  end;
end;
//------------------------------------------------------------------------------

function IsClockwise(pt: PPolyPt; UseFullInt64Range: boolean): boolean; overload;
var
  a: double;
  area: TInt128;
  startPt: PPolyPt;
begin
  startPt := pt;
  if UseFullInt64Range then
  begin
    area := int128(0);
    repeat
      area := int128Add(area, int128Sub(Int128Mul(pt.pt.X, pt.next.pt.Y),
        Int128Mul(pt.next.pt.X, pt.pt.Y)));
      pt := pt.next;
    until pt = startPt;
    result := area.hi >= 0;
  end else
  begin
    a := 0;
    repeat
      a := a + (pt.pt.X)*pt.next.pt.Y - (pt.next.pt.X)*pt.pt.Y;
      pt := pt.next;
    until pt = startPt;
    result := a > 0;
  end;
end;
//------------------------------------------------------------------------------

function Area(const pts: TArrayOfIntPoint;
  UseFullInt64Range: boolean = true): double;
var
  i, highI: integer;
  a: TInt128;
const
  leftShift64: double = 18446744073709551616.0;
begin
  result := 0;
  highI := high(pts);
  if highI < 2 then exit;
  if UseFullInt64Range then
  begin
    a := int128(0);
    a := Int128Add(a, Int128Sub(Int128Mul(pts[highI].x, pts[0].y),
      Int128Mul(pts[0].x, pts[highI].y)));
    for i := 0 to highI-1 do
      a := Int128Add(a, Int128Sub(Int128Mul(pts[i].x, pts[i+1].y),
        Int128Mul(pts[i+1].x, pts[i].y)));
    result := Int128AsDouble(a) / 2;
  end else
  begin
    result := pts[highI].x * pts[0].y - pts[0].x * pts[highI].y;
    for i := 0 to highI-1 do
      result := result + pts[i].x * pts[i+1].y - pts[i+1].x * pts[i].y;
    result := result / 2;
  end;
end;
//------------------------------------------------------------------------------

function PointIsVertex(const pt: TIntPoint; pp: PPolyPt): Boolean;
var
  pp2: PPolyPt;
begin
  Result := true;
  pp2 := pp;
  repeat
    if PointsEqual(pp2.pt, pt) then exit;
    pp2 := pp2.next;
  until pp2 = pp;
  Result := false;
end;
//------------------------------------------------------------------------------

function PointInPolygon(const pt: TIntPoint;
  pp: PPolyPt; UseFullInt64Range: boolean): Boolean;
var
  pp2: PPolyPt;
  a, b: TInt128;
begin
  Result := False;
  pp2 := pp;
  if UseFullInt64Range then
  begin
    repeat
      if (((pp2.pt.Y <= pt.Y) and (pt.Y < pp2.prev.pt.Y)) or
        ((pp2.prev.pt.Y <= pt.Y) and (pt.Y < pp2.pt.Y))) then
      begin
        a := Int128(pt.X - pp2.pt.X);
        b := Int128Div( Int128Mul(pp2.prev.pt.X - pp2.pt.X,
          pt.Y - pp2.pt.Y), Int128(pp2.prev.pt.Y - pp2.pt.Y) );
        if Int128LessThan(a, b) then result := not result;
      end;
      pp2 := pp2.next;
    until pp2 = pp;
  end else
  begin
    repeat
      if ((((pp2.pt.Y <= pt.Y) and (pt.Y < pp2.prev.pt.Y)) or
        ((pp2.prev.pt.Y <= pt.Y) and (pt.Y < pp2.pt.Y))) and
        (pt.X < (pp2.prev.pt.X - pp2.pt.X) * (pt.Y - pp2.pt.Y) /
        (pp2.prev.pt.Y - pp2.pt.Y) + pp2.pt.X)) then result := not result;
      pp2 := pp2.next;
    until pp2 = pp;
  end;
end;
//------------------------------------------------------------------------------

function SlopesEqual(e1, e2: PEdge; UseFullInt64Range: boolean): boolean; overload;
begin
  if (e1.ybot = e1.ytop) then result := (e2.ybot = e2.ytop)
  else if (e1.xbot = e1.xtop) then result := (e2.xbot = e2.xtop)
  else if UseFullInt64Range then
    result := Int128Equal(Int128Mul(e1.ytop-e1.ybot, e2.xtop-e2.xbot),
      Int128Mul(e1.xtop-e1.xbot, e2.ytop-e2.ybot))
  else
    result := (e1.ytop-e1.ybot)*(e2.xtop-e2.xbot) =
      (e1.xtop-e1.xbot)*(e2.ytop-e2.ybot);
end;
//---------------------------------------------------------------------------

function SlopesEqual(const pt1, pt2, pt3: TIntPoint;
  UseFullInt64Range: boolean): boolean; overload;
begin
  if (pt1.Y = pt2.Y) then result := (pt2.Y = pt3.Y)
  else if (pt1.X = pt2.X) then result := (pt2.X = pt3.X)
  else if UseFullInt64Range then
    result := Int128Equal( Int128Mul(pt1.Y-pt2.Y, pt2.X-pt3.X),
      Int128Mul(pt1.X-pt2.X, pt2.Y-pt3.Y))
  else
    result := (pt1.Y-pt2.Y)*(pt2.X-pt3.X) = (pt1.X-pt2.X)*(pt2.Y-pt3.Y);
end;
//---------------------------------------------------------------------------

function SlopesEqual(const pt1, pt2, pt3, pt4: TIntPoint;
  UseFullInt64Range: boolean): boolean; overload;
begin
  if (pt1.Y = pt2.Y) then result := (pt3.Y = pt4.Y)
  else if (pt1.X = pt2.X) then result := (pt3.X = pt4.X)
  else if UseFullInt64Range then
    result := Int128Equal( Int128Mul(pt1.Y-pt2.Y, pt3.X-pt4.X),
      Int128Mul(pt1.X-pt2.X, pt3.Y-pt4.Y))
  else
    result := (pt1.Y-pt2.Y * pt3.X-pt4.X) = (pt1.X-pt2.X * pt3.Y-pt4.Y);
end;
//---------------------------------------------------------------------------

procedure SetDx(e: PEdge);
begin
  if (e.ybot = e.ytop) then e.dx := horizontal
  else e.dx := (e.xtop - e.xbot)/(e.ytop - e.ybot);
end;
//---------------------------------------------------------------------------

procedure SwapSides(edge1, edge2: PEdge);
var
  side: TEdgeSide;
begin
  side :=  edge1.side;
  edge1.side := edge2.side;
  edge2.side := side;
end;
//------------------------------------------------------------------------------

procedure SwapPolyIndexes(edge1, edge2: PEdge);
var
  outIdx: integer;
begin
  outIdx :=  edge1.outIdx;
  edge1.outIdx := edge2.outIdx;
  edge2.outIdx := outIdx;
end;
//------------------------------------------------------------------------------

function TopX(edge: PEdge; const currentY: int64): int64; overload;
begin
  if currentY = edge.ytop then result := edge.xtop
  else if edge.xtop = edge.xbot then result := edge.xbot
  else result := edge.xbot + round(edge.dx*(currentY - edge.ybot));
end;
//------------------------------------------------------------------------------

function IntersectPoint(edge1, edge2: PEdge;
  out ip: TIntPoint; UseFullInt64Range: boolean): boolean; overload;
var
  b1,b2: double;
begin
  if SlopesEqual(edge1, edge2, UseFullInt64Range) then
  begin
    result := false;
    exit;
  end;
  if edge1.dx = 0 then
  begin
    ip.X := edge1.xbot;
    if edge2.dx = horizontal then
      ip.Y := edge2.ybot
    else
    begin
      with edge2^ do b2 := ybot - (xbot/dx);
      ip.Y := round(ip.X/edge2.dx + b2);
    end;
  end
  else if edge2.dx = 0 then
  begin
    ip.X := edge2.xbot;
    if edge1.dx = horizontal then
      ip.Y := edge1.ybot
    else
    begin
      with edge1^ do b1 := ybot - (xbot/dx);
      ip.Y := round(ip.X/edge1.dx + b1);
    end;
  end else
  begin
    with edge1^ do b1 := xbot - ybot *dx;
    with edge2^ do b2 := xbot - ybot *dx;
    b2 := (b2-b1)/(edge1.dx - edge2.dx);
    ip.Y := round(b2);
    ip.X := round(edge1.dx * b2 + b1);
  end;
  result :=
    //can be *so close* to the top of one edge that the rounded Y equals one ytop ...
    ((ip.Y = edge1.ytop) and (ip.Y >= edge2.ytop) and (edge1.tmpX > edge2.tmpX)) or
    ((ip.Y = edge2.ytop) and (ip.Y >= edge1.ytop) and (edge1.tmpX > edge2.tmpX)) or
    ((ip.Y > edge1.ytop) and (ip.Y > edge2.ytop));
end;
//------------------------------------------------------------------------------

procedure ReversePolyPtLinks(pp: PPolyPt);
var
  pp1,pp2: PPolyPt;
begin
  pp1 := pp;
  repeat
    pp2:= pp1.next;
    pp1.next := pp1.prev;
    pp1.prev := pp2;
    pp1 := pp2;
  until pp1 = pp;
end;

//------------------------------------------------------------------------------
// TClipperBase methods ...
//------------------------------------------------------------------------------

constructor TClipperBase.Create;
begin
  fEdgeList := TList.Create;
  fLmList := nil;
  fCurrLm := nil;
  fUseFullRange := true;
end;
//------------------------------------------------------------------------------

destructor TClipperBase.Destroy;
begin
  Clear;
  fEdgeList.Free;
  inherited;
end;
//------------------------------------------------------------------------------

procedure TClipperBase.SetUseFullRange(newVal: boolean);
begin
  if (fEdgeList.Count > 0) and newVal then
    raise Exception.Create(rsUseFullRange);
  fUseFullRange := newVal;
end;
//------------------------------------------------------------------------------

function TClipperBase.AddPolygon(const polygon: TArrayOfIntPoint;
  polyType: TPolyType): boolean;

  //----------------------------------------------------------------------

  procedure InitEdge(e, eNext, ePrev: PEdge; const pt: TIntPoint);
  begin
    fillChar(e^, sizeof(TEdge), 0);
    e.next := eNext;
    e.prev := ePrev;
    e.xcurr := pt.X;
    e.ycurr := pt.Y;
    if e.ycurr >= e.next.ycurr then
    begin
      e.xbot := e.xcurr;
      e.ybot := e.ycurr;
      e.xtop := e.next.xcurr;
      e.ytop := e.next.ycurr;
      e.windDelta := 1;
    end else
    begin
      e.xtop := e.xcurr;
      e.ytop := e.ycurr;
      e.xbot := e.next.xcurr;
      e.ybot := e.next.ycurr;
      e.windDelta := -1;
    end;
    SetDx(e);
    e.polyType := polyType;
    e.outIdx := -1;
  end;
  //----------------------------------------------------------------------

  procedure SwapX(e: PEdge);
  begin
    //swap horizontal edges' top and bottom x's so they follow the natural
    //progression of the bounds - ie so their xbots will align with the
    //adjoining lower edge. [Helpful in the ProcessHorizontal() method.]
    e.xcurr := e.xtop;
    e.xtop := e.xbot;
    e.xbot := e.xcurr;
  end;
  //----------------------------------------------------------------------

  procedure InsertLocalMinima(lm: PLocalMinima);
  var
    tmpLm: PLocalMinima;
  begin
    if not assigned(fLmList) then
    begin
      fLmList := lm;
    end
    else if (lm.y >= fLmList.y) then
    begin
      lm.next := fLmList;
      fLmList := lm;
    end else
    begin
      tmpLm := fLmList;
      while assigned(tmpLm.next) and (lm.y < tmpLm.next.y) do
        tmpLm := tmpLm.next;
      lm.next := tmpLm.next;
      tmpLm.next := lm;
    end;
  end;
  //----------------------------------------------------------------------

  function AddBoundsToLML(e: PEdge): PEdge;
  var
    newLm: PLocalMinima;
  begin
    //Starting at the top of one bound we progress to the bottom where there's
    //a local minima. We then go to the top of the next bound. These two bounds
    //form the left and right (or right and left) bounds of the local minima.
    e.nextInLML := nil;
    e := e.next;
    repeat
      if e.dx = horizontal then
      begin
        //nb: proceed through horizontals when approaching from their right,
        //    but break on horizontal minima if approaching from their left.
        //    This ensures 'local minima' are always on the left of horizontals.
        if (e.next.ytop < e.ytop) and (e.next.xbot > e.prev.xbot) then break;
        if (e.xtop <> e.prev.xbot) then SwapX(e);
        e.nextInLML := e.prev;
      end
      else if (e.ybot = e.prev.ybot) then break
      else e.nextInLML := e.prev;
      e := e.next;
    until false;

    //e and e.prev are now at a local minima ...
    new(newLm);
    newLm.y := e.prev.ybot;
    newLm.next := nil;
    if e.dx = horizontal then //horizontal edges never start a left bound
    begin
      if (e.xbot <> e.prev.xbot) then SwapX(e);
      newLm.leftBound := e.prev;
      newLm.rightBound := e;
    end else if (e.dx < e.prev.dx) then
    begin
      newLm.leftBound := e.prev;
      newLm.rightBound := e;
    end else
    begin
      newLm.leftBound := e;
      newLm.rightBound := e.prev;
    end;
    newLm.leftBound.side := esLeft;
    newLm.rightBound.side := esRight;

    InsertLocalMinima(newLm);

    repeat
      if (e.next.ytop = e.ytop) and not (e.next.dx = horizontal) then break;
      e.nextInLML := e.next;
      e := e.next;
      if (e.dx = horizontal) and (e.xbot <> e.prev.xtop) then SwapX(e);
    until false;
    result := e.next;
  end;
  //----------------------------------------------------------------------

var
  i, j, len: integer;
  edges: PEdgeArray;
  e, eHighest: PEdge;
  pg: TArrayOfIntPoint;
const
  MaxVal = 1.5E9; //(2*MaxVal)*(2*MaxVal) < 2^63 - see SlopesEqual()
begin
  {AddPolygon}
  result := false; //ie assume nothing added
  len := length(polygon);
  if len < 3 then exit;
  setlength(pg, len);
  pg[0] := polygon[0];
  j := 0;
  for i := 1 to len-1 do
  begin
    if not fUseFullRange and
      ((abs(polygon[i].X) > MaxVal) or (abs(polygon[i].Y) > MaxVal)) then
        raise exception.Create(rsInvalidInt);
    if PointsEqual(pg[j], polygon[i]) then continue
    else if (j > 0) and SlopesEqual(pg[j-1], pg[j], polygon[i], fUseFullRange) then
    begin
      if PointsEqual(pg[j-1], polygon[i]) then dec(j);
    end else inc(j);
    pg[j] := polygon[i];
  end;
  if (j < 2) then exit;

  len := j+1;
  while true do
  begin
    //nb: test for point equality before testing slopes ...
    if PointsEqual(pg[j], pg[0]) then dec(j)
    else if PointsEqual(pg[0], pg[1]) or
      SlopesEqual(pg[j], pg[0], pg[1], fUseFullRange) then
    begin
      pg[0] := pg[j];
      dec(j);
    end
    else if SlopesEqual(pg[j-1], pg[j], pg[0], fUseFullRange) then dec(j)
    else if SlopesEqual(pg[0], pg[1], pg[2], fUseFullRange) then
    begin
      for i := 2 to j do pg[i-1] := pg[i];
      dec(j);
    end;
    //exit loop if nothing is changed or there are too few vertices ...
    if (j = len -1) or (j < 2) then break;
    len := j +1;
  end;
  if len < 3 then exit;
  result := true;

  GetMem(edges, sizeof(TEdge)*len);
  fEdgeList.Add(edges);

  //convert vertices to a double-linked-list of edges and initialize ...
  edges[0].xcurr := pg[0].X;
  edges[0].ycurr := pg[0].Y;
  InitEdge(@edges[len-1], @edges[0], @edges[len-2], pg[len-1]);
  for i := len-2 downto 1 do
    InitEdge(@edges[i], @edges[i+1], @edges[i-1], pg[i]);
  InitEdge(@edges[0], @edges[1], @edges[len-1], pg[0]);

  //reset xcurr & ycurr and find 'eHighest' (given the Y axis coordinates
  //increase downward so the 'highest' edge will have the smallest ytop) ...
  e := @edges[0];
  eHighest := e;
  repeat
    e.xcurr := e.xbot;
    e.ycurr := e.ybot;
    if e.ytop < eHighest.ytop then eHighest := e;
    e := e.next;
  until e = @edges[0];

  //make sure eHighest is positioned so the following loop works safely ...
  if eHighest.windDelta > 0 then eHighest := eHighest.next;
  if (eHighest.dx = horizontal) then eHighest := eHighest.next;

  //finally insert each local minima ...
  e := eHighest;
  repeat
    e := AddBoundsToLML(e);
  until (e = eHighest);
end;
//------------------------------------------------------------------------------

function TClipperBase.AddPolygons(const polygons: TArrayOfArrayOfIntPoint;
  polyType: TPolyType): boolean;
var
  i: integer;
begin
  result := false;
  for i := 0 to high(polygons) do
    if AddPolygon(polygons[i], polyType) then result := true;
end;
//------------------------------------------------------------------------------

procedure TClipperBase.Clear;
var
  i: Integer;
begin
  DisposeLocalMinimaList;
  for i := 0 to fEdgeList.Count -1 do dispose(PEdgeArray(fEdgeList[i]));
  fEdgeList.Clear;
end;
//------------------------------------------------------------------------------

procedure TClipperBase.Reset;
var
  e: PEdge;
  lm: PLocalMinima;
begin
  //Reset() allows various clipping operations to be executed
  //multiple times on the same polygon sets.

  fCurrLm := fLmList;
  //reset all edges ...
  lm := fCurrLm;
  while assigned(lm) do
  begin
    e := lm.leftBound;
    while assigned(e) do
    begin
      e.xcurr := e.xbot;
      e.ycurr := e.ybot;
      e.side := esLeft;
      e.outIdx := -1;
      e := e.nextInLML;
    end;
    e := lm.rightBound;
    while assigned(e) do
    begin
      e.xcurr := e.xbot;
      e.ycurr := e.ybot;
      e.side := esRight;
      e.outIdx := -1;
      e := e.nextInLML;
    end;
    lm := lm.next;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipperBase.DisposeLocalMinimaList;
begin
  while assigned(fLmList) do
  begin
    fCurrLm := fLmList.next;
    Dispose(fLmList);
    fLmList := fCurrLm;
  end;
  fCurrLm := nil;
end;
//------------------------------------------------------------------------------

procedure TClipperBase.PopLocalMinima;
begin
  if not assigned(fCurrLM) then exit;
  fCurrLM := fCurrLM.next;
end;

//------------------------------------------------------------------------------
// TClipper methods ...
//------------------------------------------------------------------------------

constructor TClipper.Create;
begin
  inherited Create;
  fJoinList := TList.Create;
  fPolyPtList := TList.Create;
end;
//------------------------------------------------------------------------------

destructor TClipper.Destroy;
begin
  DisposeScanbeamList;
  fJoinList.Free;
  fPolyPtList.Free;
  inherited;
end;
//------------------------------------------------------------------------------

procedure TClipper.DisposeScanbeamList;
var
  sb: PScanbeam;
begin
  while assigned(fScanbeam) do
  begin
    sb := fScanbeam.next;
    Dispose(fScanbeam);
    fScanbeam := sb;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.Reset;
var
  lm: PLocalMinima;
begin
  inherited Reset;
  fScanbeam := nil;
  lm := fLmList;
  while assigned(lm) do
  begin
    InsertScanbeam(lm.y);
    InsertScanbeam(lm.leftbound.ytop);
    lm := lm.next;
  end;
end;
//------------------------------------------------------------------------------

function TClipper.Execute(clipType: TClipType;
  out solution: TArrayOfArrayOfIntPoint;
  subjFillType: TPolyFillType = pftEvenOdd;
  clipFillType: TPolyFillType = pftEvenOdd): boolean;
var
  botY, topY: int64;
begin
  result := false;
  solution := nil;
  if fExecuteLocked then exit;
  try try
    fExecuteLocked := true;
    fSubjFillType := subjFillType;
    fClipFillType := clipFillType;
    fClipType := clipType;

    Reset;
    if not assigned(fScanbeam) then
    begin
      result := true;
      exit; //just return true if operating on an empty polygon set
    end;

    botY := PopScanbeam;
    repeat
      InsertLocalMinimaIntoAEL(botY);
      ClearHorzJoins;
      ProcessHorizontals;
      topY := PopScanbeam;
      if not ProcessIntersections(topY) then exit;
      ProcessEdgesAtTopOfScanbeam(topY);
      botY := topY;
    until fScanbeam = nil;
    solution := GetResult;
    result := true;
  except
    //result := false;
  end;
  finally
    ClearJoins;
    ClearHorzJoins;
    DisposeAllPolyPts;
    fExecuteLocked := false;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.InsertScanbeam(const y: int64);
var
  sb, sb2: PScanbeam;
begin
  new(sb);
  sb.y := y;
  if not assigned(fScanbeam) then
  begin
    fScanbeam := sb;
    sb.next := nil;
  end else if y > fScanbeam.y then
  begin
    sb.next := fScanbeam;
    fScanbeam := sb;
  end else
  begin
    sb2 := fScanbeam;
    while assigned(sb2.next) and (y <= sb2.next.y) do sb2 := sb2.next;
    if y <> sb2.y then
    begin
      sb.next := sb2.next;
      sb2.next := sb;
    end
    else dispose(sb); //ie ignores duplicates
  end;
end;
//------------------------------------------------------------------------------

function TClipper.PopScanbeam: int64;
var
  sb: PScanbeam;
begin
  result := fScanbeam.y;
  sb := fScanbeam;
  fScanbeam := fScanbeam.next;
  dispose(sb);
end;
//------------------------------------------------------------------------------

procedure TClipper.DisposePolyPts(pp: PPolyPt);
var
  tmpPp: PPolyPt;
begin
  pp.prev.next := nil;
  while assigned(pp) do
  begin
    tmpPp := pp;
    pp := pp.next;
    dispose(tmpPp);
  end;
end;
//------------------------------------------------------------------------------


procedure TClipper.DisposeAllPolyPts;
var
  i: integer;
begin
  for i := 0 to fPolyPtList.Count -1 do
    if assigned(fPolyPtList[i]) then
      DisposePolyPts(PPolyPt(fPolyPtList[i]));
  fPolyPtList.Clear;
end;
//------------------------------------------------------------------------------

procedure TClipper.SetWindingCount(edge: PEdge);
var
  e: PEdge;
begin
  e := edge.prevInAEL;
  //find the edge of the same polytype that immediately preceeds 'edge' in AEL
  while assigned(e) and (e.polyType <> edge.polyType) do e := e.prevInAEL;
  if not assigned(e) then
  begin
    edge.windCnt := edge.windDelta;
    edge.windCnt2 := 0;
    e := fActiveEdges; //ie get ready to calc windCnt2
  end else if IsNonZeroFillType(edge) then
  begin
    //nonZero filling ...
    if e.windCnt * e.windDelta < 0 then
    begin
      if (abs(e.windCnt) > 1) then
      begin
        if (e.windDelta * edge.windDelta < 0) then edge.windCnt := e.windCnt
        else edge.windCnt := e.windCnt + edge.windDelta;
      end else
        edge.windCnt := e.windCnt + e.windDelta + edge.windDelta;
    end else
    begin
      if (abs(e.windCnt) > 1) and (e.windDelta * edge.windDelta < 0) then
        edge.windCnt := e.windCnt
      else if e.windCnt + edge.windDelta = 0 then
        edge.windCnt := e.windCnt
      else edge.windCnt := e.windCnt + edge.windDelta;
    end;
    edge.windCnt2 := e.windCnt2;
    e := e.nextInAEL; //ie get ready to calc windCnt2
  end else
  begin
    //even-odd filling ...
    edge.windCnt := 1;
    edge.windCnt2 := e.windCnt2;
    e := e.nextInAEL; //ie get ready to calc windCnt2
  end;

  //update windCnt2 ...
  if IsNonZeroAltFillType(edge) then
  begin
    //nonZero filling ...
    while (e <> edge) do
    begin
      inc(edge.windCnt2, e.windDelta);
      e := e.nextInAEL;
    end;
  end else
  begin
    //even-odd filling ...
    while (e <> edge) do
    begin
      if edge.windCnt2 = 0 then edge.windCnt2 := 1 else edge.windCnt2 := 0;
      e := e.nextInAEL;
    end;
  end;
end;
//------------------------------------------------------------------------------

function TClipper.IsNonZeroFillType(edge: PEdge): boolean;
begin
  if edge.polyType = ptSubject then
    result := fSubjFillType = pftNonZero else
    result := fClipFillType = pftNonZero;
end;
//------------------------------------------------------------------------------

function TClipper.IsNonZeroAltFillType(edge: PEdge): boolean;
begin
  if edge.polyType = ptSubject then
    result := fClipFillType = pftNonZero else
    result := fSubjFillType = pftNonZero;
end;
//------------------------------------------------------------------------------

function TClipper.IsContributing(edge: PEdge): boolean;
begin
  result := true;
  case fClipType of
    ctIntersection:
      begin
        if edge.polyType = ptSubject then
          result := (abs(edge.windCnt) = 1) and (edge.windCnt2 <> 0) else
          result := (edge.windCnt2 <> 0) and (abs(edge.windCnt) = 1);
      end;
    ctUnion:
      begin
        result := (abs(edge.windCnt) = 1) and (edge.windCnt2 = 0);
      end;
    ctDifference:
      begin
        if edge.polyType = ptSubject then
        result := (abs(edge.windCnt) = 1) and (edge.windCnt2 = 0) else
        result := (abs(edge.windCnt) = 1) and (edge.windCnt2 <> 0);
      end;
    ctXor:
      result := (abs(edge.windCnt) = 1);
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.AddLocalMinPoly(e1, e2: PEdge; const pt: TIntPoint);
begin
  if (e2.dx = horizontal) or (e1.dx > e2.dx) then
  begin
    AddPolyPt(e1, pt);
    e2.outIdx := e1.outIdx;
    e1.side := esLeft;
    e2.side := esRight;
  end else
  begin
    AddPolyPt(e2, pt);
    e1.outIdx := e2.outIdx;
    e1.side := esRight;
    e2.side := esLeft;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.AddLocalMaxPoly(e1, e2: PEdge; const pt: TIntPoint);
begin
  AddPolyPt(e1, pt);
  if (e1.outIdx = e2.outIdx) then
  begin
    e1.outIdx := -1;
    e2.outIdx := -1;
  end else
    AppendPolygon(e1, e2);
end;
//------------------------------------------------------------------------------

procedure TClipper.AddEdgeToSEL(edge: PEdge);
begin
  //SEL pointers in PEdge are reused to build a list of horizontal edges.
  //However, we don't need to worry about order with horizontal edge processing.
  if not assigned(fSortedEdges) then
  begin
    fSortedEdges := edge;
    edge.prevInSEL := nil;
    edge.nextInSEL := nil;
  end else
  begin
    edge.nextInSEL := fSortedEdges;
    edge.prevInSEL := nil;
    fSortedEdges.prevInSEL := edge;
    fSortedEdges := edge;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.CopyAELToSEL;
var
  e: PEdge;
begin
  e := fActiveEdges;
  fSortedEdges := e;
  if not assigned(fActiveEdges) then exit;

  fSortedEdges.prevInSEL := nil;
  e := e.nextInAEL;
  while assigned(e) do
  begin
    e.prevInSEL := e.prevInAEL;
    e.prevInSEL.nextInSEL := e;
    e.nextInSEL := nil;
    e := e.nextInAEL;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.AddJoin(e1, e2: PEdge;
  e1OutIdx: integer = -1; e2OutIdx: integer = -1);
var
  jr: PJoinRec;
begin
  new(jr);
  if e1OutIdx >= 0 then
    jr.poly1Idx := e1OutIdx else
    jr.poly1Idx := e1.outIdx;
  with e1^ do
  begin
    jr.pt1a := IntPoint(xcurr, ycurr);
    jr.pt1b := IntPoint(xtop, ytop);
  end;
  if e2OutIdx >= 0 then
    jr.poly2Idx := e2OutIdx else
    jr.poly2Idx := e2.outIdx;
  with e2^ do
  begin
    jr.pt2a := IntPoint(xcurr, ycurr);
    jr.pt2b := IntPoint(xtop, ytop);
  end;
  fJoinList.add(jr);
end;
//------------------------------------------------------------------------------

procedure TClipper.ClearJoins;
var
  i: integer;
begin
  for i := 0 to fJoinList.count -1 do
    Dispose(PJoinRec(fJoinList[i]));
  fJoinList.Clear;
end;
//------------------------------------------------------------------------------

procedure TClipper.AddHorzJoin(e: PEdge; idx: integer);
var
  hr: PHorzRec;
begin
  new(hr);
  hr.edge := e;
  hr.savedIdx := idx;
  if fHorizJoins = nil then
  begin
    fHorizJoins := hr;
    hr.next := hr;
    hr.prev := hr;
  end else
  begin
    hr.next := fHorizJoins;
    hr.prev := fHorizJoins.prev;
    fHorizJoins.prev.next := hr;
    fHorizJoins.prev := hr;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.ClearHorzJoins;
var
  m, m2: PHorzRec;
begin
  if not assigned(fHorizJoins) then exit;
  m := fHorizJoins;
  m.prev.next := nil;
  while assigned(m) do
  begin
    m2 := m.next;
    dispose(m);
    m := m2;
  end;
  fHorizJoins := nil;
end;
//------------------------------------------------------------------------------

procedure SwapPoints(var pt1, pt2: TIntPoint);
var
  tmp: TIntPoint;
begin
  tmp := pt1;
  pt1 := pt2;
  pt2 := tmp;
end;
//------------------------------------------------------------------------------

function GetOverlapSegment(pt1a, pt1b, pt2a, pt2b: TIntPoint;
  out pt1, pt2: TIntPoint): boolean;
begin
  //precondition: segments are colinear.
  //todo - reconsider whether this should be protected with TInt128's ...
  if (pt1a.Y = pt1b.Y) or (abs((pt1a.X - pt1b.X)/(pt1a.Y - pt1b.Y)) > 1) then
  begin
    if pt1a.X > pt1b.X then SwapPoints(pt1a, pt1b);
    if pt2a.X > pt2b.X then SwapPoints(pt2a, pt2b);
    if (pt1a.X > pt2a.X) then pt1 := pt1a else pt1 := pt2a;
    if (pt1b.X < pt2b.X) then pt2 := pt1b else pt2 := pt2b;
    result := pt1.X < pt2.X;
  end else
  begin
    if pt1a.Y < pt1b.Y then SwapPoints(pt1a, pt1b);
    if pt2a.Y < pt2b.Y then SwapPoints(pt2a, pt2b);
    if (pt1a.Y < pt2a.Y) then pt1 := pt1a else pt1 := pt2a;
    if (pt1b.Y > pt2b.Y) then pt2 := pt1b else pt2 := pt2b;
    result := pt1.Y > pt2.Y;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.InsertLocalMinimaIntoAEL(const botY: int64);

  function E2InsertsBeforeE1(e1,e2: PEdge): boolean;
  begin
    if e2.xcurr = e1.xcurr then result := e2.dx > e1.dx
    else result := e2.xcurr < e1.xcurr;
  end;
  //----------------------------------------------------------------------

  procedure InsertEdgeIntoAEL(edge: PEdge);
  var
    e: PEdge;
  begin
    edge.prevInAEL := nil;
    edge.nextInAEL := nil;
    if not assigned(fActiveEdges) then
    begin
      fActiveEdges := edge;
    end else if E2InsertsBeforeE1(fActiveEdges, edge) then
    begin
      edge.nextInAEL := fActiveEdges;
      fActiveEdges.prevInAEL := edge;
      fActiveEdges := edge;
    end else
    begin
      e := fActiveEdges;
      while assigned(e.nextInAEL) and not E2InsertsBeforeE1(e.nextInAEL, edge) do
        e := e.nextInAEL;
      edge.nextInAEL := e.nextInAEL;
      if assigned(e.nextInAEL) then e.nextInAEL.prevInAEL := edge;
      edge.prevInAEL := e;
      e.nextInAEL := edge;
    end;
  end;
  //----------------------------------------------------------------------

var
  e: PEdge;
  pt, pt2: TIntPoint;
  lb, rb: PEdge;
  hj: PHorzRec;
begin
  while assigned(CurrentLm) and (CurrentLm.Y = botY) do
  begin
    lb := CurrentLm.leftBound;
    rb := CurrentLm.rightBound;

    InsertEdgeIntoAEL(lb);
    InsertScanbeam(lb.ytop);
    InsertEdgeIntoAEL(rb);

    //set edge winding states ...
    if IsNonZeroFillType(lb) then
    begin
      rb.windDelta := -lb.windDelta
    end else
    begin
      lb.windDelta := 1;
      rb.windDelta := 1;
    end;
    SetWindingCount(lb);
    rb.windCnt := lb.windCnt;
    rb.windCnt2 := lb.windCnt2;

    if rb.dx = horizontal then
    begin
      AddEdgeToSEL(rb);
      InsertScanbeam(rb.nextInLML.ytop);
    end else
      InsertScanbeam(rb.ytop);

    if IsContributing(lb) then
      AddLocalMinPoly(lb, rb, IntPoint(lb.xcurr, CurrentLm.y));

    //if output polygons share an edge, they'll need joining later ...
    if (lb.outIdx >= 0) and assigned(lb.prevInAEL) and
       (lb.prevInAEL.outIdx >= 0) and (lb.prevInAEL.xcurr = lb.xbot) and
       SlopesEqual(lb, lb.prevInAEL, fUseFullRange) then
         AddJoin(lb, lb.prevInAEL);

    //if any output polygons share an edge, they'll need joining later ...
    if (rb.outIdx >= 0) then
    begin
      if (rb.dx = horizontal) then
      begin
        if assigned(fHorizJoins) then
        begin
          hj := fHorizJoins;
          repeat
            //if horizontals rb & hj.edge overlap, flag for joining later ...
            if GetOverlapSegment(IntPoint(hj.edge.xbot, hj.edge.ybot),
              IntPoint(hj.edge.xtop, hj.edge.ytop), IntPoint(rb.xbot, rb.ybot),
              IntPoint(rb.xtop, rb.ytop), pt, pt2) then
                AddJoin(hj.edge, rb, hj.savedIdx);
            hj := hj.next;
          until hj = fHorizJoins;
        end;
      end;
    end;

    if (lb.nextInAEL <> rb) then
    begin
      if (rb.outIdx >= 0) and (rb.prevInAEL.outIdx >= 0) and
        SlopesEqual(rb.prevInAEL, rb, fUseFullRange) then
          AddJoin(rb, rb.prevInAEL);

      e := lb.nextInAEL;
      pt := IntPoint(lb.xcurr,lb.ycurr);
      while e <> rb do
      begin
        if not assigned(e) then raise exception.Create(rsMissingRightbound);
        //nb: For calculating winding counts etc, IntersectEdges() assumes
        //that param1 will be to the right of param2 ABOVE the intersection ...
        IntersectEdges(rb, e, pt);
        e := e.nextInAEL;
      end;
    end;
    PopLocalMinima;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.DeleteFromAEL(e: PEdge);
var
  AelPrev, AelNext: PEdge;
begin
  AelPrev := e.prevInAEL;
  AelNext := e.nextInAEL;
  if not assigned(AelPrev) and not assigned(AelNext) and
    (e <> fActiveEdges) then exit; //already deleted
  if assigned(AelPrev) then AelPrev.nextInAEL := AelNext
  else fActiveEdges := AelNext;
  if assigned(AelNext) then AelNext.prevInAEL := AelPrev;
  e.nextInAEL := nil;
  e.prevInAEL := nil;
end;
//------------------------------------------------------------------------------

procedure TClipper.DeleteFromSEL(e: PEdge);
var
  SelPrev, SelNext: PEdge;
begin
  SelPrev := e.prevInSEL;
  SelNext := e.nextInSEL;
  if not assigned(SelPrev) and not assigned(SelNext) and
    (e <> fSortedEdges) then exit; //already deleted
  if assigned(SelPrev) then SelPrev.nextInSEL := SelNext
  else fSortedEdges := SelNext;
  if assigned(SelNext) then SelNext.prevInSEL := SelPrev;
  e.nextInSEL := nil;
  e.prevInSEL := nil;
end;
//------------------------------------------------------------------------------

procedure TClipper.IntersectEdges(e1,e2: PEdge;
  const pt: TIntPoint; protects: TIntersectProtects = []);

  procedure DoEdge1;
  begin
    AddPolyPt(e1, pt);
    SwapSides(e1, e2);
    SwapPolyIndexes(e1, e2);
  end;
  //----------------------------------------------------------------------

  procedure DoEdge2;
  begin
    AddPolyPt(e2, pt);
    SwapSides(e1, e2);
    SwapPolyIndexes(e1, e2);
  end;
  //----------------------------------------------------------------------

  procedure DoBothEdges;
  begin
    AddPolyPt(e1, pt);
    AddPolyPt(e2, pt);
    SwapSides(e1, e2);
    SwapPolyIndexes(e1, e2);
  end;
  //----------------------------------------------------------------------

var
  oldE1WindCnt: integer;
  e1stops, e2stops: boolean;
  e1Contributing, e2contributing: boolean;
begin
  {IntersectEdges}

  //e1 will be to the left of e2 BELOW the intersection. Therefore e1 is before
  //e2 in AEL except when e1 is being inserted at the intersection point ...

  e1stops := not (ipLeft in protects) and not assigned(e1.nextInLML) and
    (e1.xtop = pt.x) and (e1.ytop = pt.y);
  e2stops := not (ipRight in protects) and not assigned(e2.nextInLML) and
    (e2.xtop = pt.x) and (e2.ytop = pt.y);
  e1Contributing := (e1.outIdx >= 0);
  e2contributing := (e2.outIdx >= 0);

  //update winding counts...
  //assumes that e1 will be to the right of e2 ABOVE the intersection
  if e1.polyType = e2.polyType then
  begin
    if IsNonZeroFillType(e1) then
    begin
      if e1.windCnt + e2.windDelta = 0 then
        e1.windCnt := -e1.windCnt else
        inc(e1.windCnt, e2.windDelta);
      if e2.windCnt - e1.windDelta = 0 then
        e2.windCnt := -e2.windCnt else
        dec(e2.windCnt, e1.windDelta);
    end else
    begin
      oldE1WindCnt := e1.windCnt;
      e1.windCnt := e2.windCnt;
      e2.windCnt := oldE1WindCnt;
    end;
  end else
  begin
    if IsNonZeroFillType(e2) then inc(e1.windCnt2, e2.windDelta)
    else if e1.windCnt2 = 0 then e1.windCnt2 := 1
    else e1.windCnt2 := 0;
    if IsNonZeroFillType(e1) then dec(e2.windCnt2, e1.windDelta)
    else if e2.windCnt2 = 0 then e2.windCnt2 := 1
    else e2.windCnt2 := 0;
  end;

  if e1Contributing and e2contributing then
  begin
    if e1stops or e2stops or
      (abs(e1.windCnt) > 1) or (abs(e2.windCnt) > 1) or
      ((e1.polytype <> e2.polytype) and (fClipType <> ctXor)) then
        AddLocalMaxPoly(e1, e2, pt) else
        DoBothEdges;
  end
  else if e1Contributing then
  begin
    if fClipType = ctIntersection then
    begin
      if (abs(e2.windCnt) < 2) and
        ((e2.polyType = ptSubject) or (e2.windCnt2 <> 0)) then DoEdge1;
    end
    else if (abs(e2.windCnt) < 2) then DoEdge1;
  end
  else if e2contributing then
  begin
    if fClipType = ctIntersection then
    begin
      if (abs(e1.windCnt) < 2) and
        ((e1.polyType = ptSubject) or (e1.windCnt2 <> 0)) then DoEdge2;
    end
    else if (abs(e1.windCnt) < 2) then DoEdge2;
  end
  else
  begin
    //neither edge is currently contributing ...
    if (abs(e1.windCnt) > 1) and (abs(e2.windCnt) > 1) then
      // do nothing
    else if (e1.polytype <> e2.polytype) and
      not e1stops and not e2stops and
      (abs(e1.windCnt) < 2) and (abs(e2.windCnt) < 2)then
      AddLocalMinPoly(e1, e2, pt)
    else if (abs(e1.windCnt) = 1) and (abs(e2.windCnt) = 1) then
      case fClipType of
        ctIntersection:
          if (abs(e1.windCnt2) > 0) and (abs(e2.windCnt2) > 0) then
            AddLocalMinPoly(e1, e2, pt);
        ctUnion:
          if (e1.windCnt2 = 0) and (e2.windCnt2 = 0) then
            AddLocalMinPoly(e1, e2, pt);
        ctDifference:
          if ((e1.polyType = ptClip) and (e2.polyType = ptClip) and
            (e1.windCnt2 <> 0) and (e2.windCnt2 <> 0)) or
            ((e1.polyType = ptSubject) and (e2.polyType = ptSubject) and
            (e1.windCnt2 = 0) and (e2.windCnt2 = 0)) then
              AddLocalMinPoly(e1, e2, pt);
        ctXor:
          AddLocalMinPoly(e1, e2, pt);
      end
    else if (abs(e1.windCnt) < 2) and (abs(e2.windCnt) < 2) then
      swapsides(e1,e2);
  end;

  if (e1stops <> e2stops) and
    ((e1stops and (e1.outIdx >= 0)) or (e2stops and (e2.outIdx >= 0))) then
  begin
    swapsides(e1,e2);
    SwapPolyIndexes(e1, e2);
  end;

  //finally, delete any non-contributing maxima edges  ...
  if e1stops then deleteFromAEL(e1);
  if e2stops then deleteFromAEL(e2);
end;
//------------------------------------------------------------------------------

function PolygonBottom(pp: PPolyPt): PPolyPt;
var
  p: PPolyPt;
begin
  p := pp.next;
  result := pp;
  while p <> pp do
  begin
    if p.pt.Y > result.pt.Y then result := p
    else if (p.pt.Y = result.pt.Y) and (p.pt.X < result.pt.X) then result := p;
    p := p.next;
  end;
end;
//------------------------------------------------------------------------------

procedure SetHoleState(pp: PPolyPt; isHole: boolean);
var
  pp2: PPolyPt;
begin
  pp2 := pp;
  repeat
    pp2.isHole := isHole;
    pp2 := pp2.next;
  until pp2 = pp;
end;
//------------------------------------------------------------------------------

procedure TClipper.AppendPolygon(e1, e2: PEdge);
var
  p, p1_lft, p1_rt, p2_lft, p2_rt: PPolyPt;
  newSide: TEdgeSide;
  i, OKIdx, ObsoleteIdx: integer;
  e: PEdge;
  bottom1, bottom2: PPolyPt;
  j: PJoinRec;
  h: PHorzRec;
begin
  //get the start and ends of both output polygons ...
  p1_lft := PPolyPt(fPolyPtList[e1.outIdx]);
  p1_rt := p1_lft.prev;
  p2_lft := PPolyPt(fPolyPtList[e2.outIdx]);
  p2_rt := p2_lft.prev;

  //fixup hole status ...
  if (p1_lft.isHole <> p2_lft.isHole) then
  begin
    bottom1 := PolygonBottom(p1_lft);
    bottom2 := PolygonBottom(p2_lft);
    if (bottom1.pt.Y > bottom2.pt.Y) then p := p2_lft
    else if (bottom1.pt.Y < bottom2.pt.Y) then p := p1_lft
    else if (bottom1.pt.X < bottom2.pt.X) then p := p2_lft
    else if (bottom1.pt.X > bottom2.pt.X) then p := p1_lft
    //todo - the following line really is only a best guess ...
    else if bottom1.isHole then p := p1_lft else p := p2_lft;

    SetHoleState(p, not p.isHole);
  end;


  //join e2 poly onto e1 poly and delete pointers to e2 ...
  if e1.side = esLeft then
  begin
    if e2.side = esLeft then
    begin
      //z y x a b c
      ReversePolyPtLinks(p2_lft);
      p2_lft.next := p1_lft;
      p1_lft.prev := p2_lft;
      p1_rt.next := p2_rt;
      p2_rt.prev := p1_rt;
      fPolyPtList[e1.outIdx] := p2_rt;
    end else
    begin
      //x y z a b c
      p2_rt.next := p1_lft;
      p1_lft.prev := p2_rt;
      p2_lft.prev := p1_rt;
      p1_rt.next := p2_lft;
      fPolyPtList[e1.outIdx] := p2_lft;
    end;
    newSide := esLeft;
  end else
  begin
    if e2.side = esRight then
    begin
      //a b c z y x
      ReversePolyPtLinks(p2_lft);
      p1_rt.next := p2_rt;
      p2_rt.prev := p1_rt;
      p2_lft.next := p1_lft;
      p1_lft.prev := p2_lft;
    end else
    begin
      //a b c x y z
      p1_rt.next := p2_lft;
      p2_lft.prev := p1_rt;
      p1_lft.prev := p2_rt;
      p2_rt.next := p1_lft;
    end;
    newSide := esRight;
  end;

  OKIdx := e1.outIdx;
  ObsoleteIdx := e2.outIdx;
  fPolyPtList[ObsoleteIdx] := nil;

  e1.outIdx := -1; //nb: safe because we only get here via AddLocalMaxPoly
  e2.outIdx := -1;

  e := fActiveEdges;
  while assigned(e) do
  begin
    if (e.outIdx = ObsoleteIdx) then
    begin
      e.outIdx := OKIdx;
      e.side := newSide;
      break;
    end;
    e := e.nextInAEL;
  end;

  for i := 0 to fJoinList.count -1 do
  begin
    j := fJoinList[i];
    if j.poly1Idx = ObsoleteIdx then j.poly1Idx := OKIdx;
    if j.poly2Idx = ObsoleteIdx then j.poly2Idx := OKIdx;
  end;
  if assigned(fHorizJoins) then
  begin
    h := fHorizJoins;
    repeat
      if h.savedIdx = ObsoleteIdx then h.SavedIdx := OKIdx;
      h := h.next;
    until h = fHorizJoins;
  end;
end;
//------------------------------------------------------------------------------

function TClipper.IsHole(e: PEdge): boolean;
var
  e2: PEdge;
begin
  result := false;
  e2 := fActiveEdges;
  while assigned(e2) and (e2 <> e) do
  begin
    if e2.outIdx >= 0 then result := not result;
    e2 := e2.nextInAEL;
  end;
end;
//------------------------------------------------------------------------------

function TClipper.AddPolyPt(e: PEdge; const pt: TIntPoint): PPolyPt;
var
  fp: PPolyPt;
  ToFront: boolean;
begin
  ToFront := e.side = esLeft;
  if e.outIdx < 0 then
  begin
    new(result);
    e.outIdx := fPolyPtList.Add(result);
    result.isHole := IsHole(e);
    result.pt := pt;
    result.next := result;
    result.prev := result;
  end else
  begin
    result := nil;
    fp := PPolyPt(fPolyPtList[e.outIdx]);
    if (ToFront and PointsEqual(pt, fp.pt)) then result := fp
    else if not ToFront and PointsEqual(pt, fp.prev.pt) then result := fp.prev;
    if assigned(result) then exit;

    new(result);
    result.pt := pt;
    result.next := fp;
    result.prev := fp.prev;
    result.prev.next := result;
    result.isHole := fp.isHole;
    fp.prev := result;
    if ToFront then fPolyPtList[e.outIdx] := result;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.ProcessHorizontals;
var
  e: PEdge;
begin
  while assigned(fSortedEdges) do
  begin
    e := fSortedEdges;
    DeleteFromSEL(e);
    ProcessHorizontal(e);
  end;
end;
//------------------------------------------------------------------------------

function TClipper.IsTopHorz(const XPos: int64): boolean;
var
  e: PEdge;
begin
  result := false;
  e := fSortedEdges;
  while assigned(e) do
  begin
    if (XPos >= min(e.xcurr,e.xtop)) and (XPos <= max(e.xcurr,e.xtop)) then exit;
    e := e.nextInSEL;
  end;
  result := true;
end;
//------------------------------------------------------------------------------

function IsMinima(e: PEdge): boolean;
begin
  result := assigned(e) and (e.prev.nextInLML <> e) and (e.next.nextInLML <> e);
end;
//------------------------------------------------------------------------------

function IsMaxima(e: PEdge; const Y: int64): boolean;
begin
  result := assigned(e) and (e.ytop = Y) and not assigned(e.nextInLML);
end;
//------------------------------------------------------------------------------

function IsIntermediate(e: PEdge; const Y: int64): boolean;
begin
  result := (e.ytop = Y) and assigned(e.nextInLML);
end;
//------------------------------------------------------------------------------

function GetMaximaPair(e: PEdge): PEdge;
begin
  result := e.next;
  if not IsMaxima(result, e.ytop) or (result.xtop <> e.xtop) then
    result := e.prev;
end;
//------------------------------------------------------------------------------

procedure TClipper.SwapPositionsInAEL(e1, e2: PEdge);
var
  prev,next: PEdge;
begin
  with e1^ do if not assigned(nextInAEL) and not assigned(prevInAEL) then exit;
  with e2^ do if not assigned(nextInAEL) and not assigned(prevInAEL) then exit;

  if e1.nextInAEL = e2 then
  begin
    next := e2.nextInAEL;
    if assigned(next) then next.prevInAEL := e1;
    prev := e1.prevInAEL;
    if assigned(prev) then prev.nextInAEL := e2;
    e2.prevInAEL := prev;
    e2.nextInAEL := e1;
    e1.prevInAEL := e2;
    e1.nextInAEL := next;
  end
  else if e2.nextInAEL = e1 then
  begin
    next := e1.nextInAEL;
    if assigned(next) then next.prevInAEL := e2;
    prev := e2.prevInAEL;
    if assigned(prev) then prev.nextInAEL := e1;
    e1.prevInAEL := prev;
    e1.nextInAEL := e2;
    e2.prevInAEL := e1;
    e2.nextInAEL := next;
  end else
  begin
    next := e1.nextInAEL;
    prev := e1.prevInAEL;
    e1.nextInAEL := e2.nextInAEL;
    if assigned(e1.nextInAEL) then e1.nextInAEL.prevInAEL := e1;
    e1.prevInAEL := e2.prevInAEL;
    if assigned(e1.prevInAEL) then e1.prevInAEL.nextInAEL := e1;
    e2.nextInAEL := next;
    if assigned(e2.nextInAEL) then e2.nextInAEL.prevInAEL := e2;
    e2.prevInAEL := prev;
    if assigned(e2.prevInAEL) then e2.prevInAEL.nextInAEL := e2;
  end;
  if not assigned(e1.prevInAEL) then fActiveEdges := e1
  else if not assigned(e2.prevInAEL) then fActiveEdges := e2;
end;
//------------------------------------------------------------------------------

procedure TClipper.SwapPositionsInSEL(e1, e2: PEdge);
var
  prev,next: PEdge;
begin
  if e1.nextInSEL = e2 then
  begin
    next    := e2.nextInSEL;
    if assigned(next) then next.prevInSEL := e1;
    prev    := e1.prevInSEL;
    if assigned(prev) then prev.nextInSEL := e2;
    e2.prevInSEL := prev;
    e2.nextInSEL := e1;
    e1.prevInSEL := e2;
    e1.nextInSEL := next;
  end
  else if e2.nextInSEL = e1 then
  begin
    next    := e1.nextInSEL;
    if assigned(next) then next.prevInSEL := e2;
    prev    := e2.prevInSEL;
    if assigned(prev) then prev.nextInSEL := e1;
    e1.prevInSEL := prev;
    e1.nextInSEL := e2;
    e2.prevInSEL := e1;
    e2.nextInSEL := next;
  end else
  begin
    next    := e1.nextInSEL;
    prev    := e1.prevInSEL;
    e1.nextInSEL := e2.nextInSEL;
    if assigned(e1.nextInSEL) then e1.nextInSEL.prevInSEL := e1;
    e1.prevInSEL := e2.prevInSEL;
    if assigned(e1.prevInSEL) then e1.prevInSEL.nextInSEL := e1;
    e2.nextInSEL := next;
    if assigned(e2.nextInSEL) then e2.nextInSEL.prevInSEL := e2;
    e2.prevInSEL := prev;
    if assigned(e2.prevInSEL) then e2.prevInSEL.nextInSEL := e2;
  end;
  if not assigned(e1.prevInSEL) then fSortedEdges := e1
  else if not assigned(e2.prevInSEL) then fSortedEdges := e2;
end;
//------------------------------------------------------------------------------

procedure TClipper.ProcessHorizontal(horzEdge: PEdge);

  function GetNextInAEL(e: PEdge; Direction: TDirection): PEdge;
  begin
    if Direction = dLeftToRight then
      result := e.nextInAEL else
      result := e.prevInAEL;
  end;
  //------------------------------------------------------------------------

var
  e, eNext, eMaxPair: PEdge;
  horzLeft, horzRight: int64;
  Direction: TDirection;
const
  ProtectLeft: array[boolean] of TIntersectProtects = ([ipRight], [ipLeft,ipRight]);
  ProtectRight: array[boolean] of TIntersectProtects = ([ipLeft], [ipLeft,ipRight]);
begin
(*******************************************************************************
* Notes: Horizontal edges (HEs) at scanline intersections (ie at the top or    *
* bottom of a scanbeam) are processed as if layered. The order in which HEs    *
* are processed doesn't matter. HEs intersect with other HE xbots only [#],    *
* and with other non-horizontal edges [*]. Once these intersections are        *
* processed, intermediate HEs then 'promote' the edge above (nextInLML) into   *
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

  if horzEdge.xcurr < horzEdge.xtop then
  begin
    horzLeft := horzEdge.xcurr; horzRight := horzEdge.xtop;
    Direction := dLeftToRight;
  end else
  begin
    horzLeft := horzEdge.xtop; horzRight := horzEdge.xcurr;
    Direction := dRightToLeft;
  end;

  if assigned(horzEdge.nextInLML) then
    eMaxPair := nil else
    eMaxPair := GetMaximaPair(horzEdge);

  e := GetNextInAEL(horzEdge, Direction);
  while assigned(e) do
  begin
    eNext := GetNextInAEL(e, Direction);
    if (e.xcurr >= horzLeft) and (e.xcurr <= horzRight) then
    begin
      //ok, so far it looks like we're still in range of the horizontal edge

      if (e.xcurr = horzEdge.xtop) and assigned(horzEdge.nextInLML) then
      begin
        if SlopesEqual(e, horzEdge.nextInLML, fUseFullRange) then
        begin
          //if output polygons share an edge, they'll need joining later ...
          if (horzEdge.outIdx >= 0) and (e.outIdx >= 0) then
            AddJoin(horzEdge.nextInLML, e, horzEdge.outIdx);

          break; //we've reached the end of the horizontal line
        end
        else if (e.dx < horzEdge.nextInLML.dx) then
        //we really have got to the end of the intermediate horz edge so quit.
        //nb: More -ve slopes follow more +ve slopes ABOVE the horizontal.
          break;
      end;

      if (e = eMaxPair) then
      begin
        //horzEdge is evidently a maxima horizontal and we've arrived at its end.
        if Direction = dLeftToRight then
          IntersectEdges(horzEdge, e, IntPoint(e.xcurr, horzEdge.ycurr)) else
          IntersectEdges(e, horzEdge, IntPoint(e.xcurr, horzEdge.ycurr));
        exit;
      end
      else if (e.dx = horizontal) and not IsMinima(e) and not (e.xcurr > e.xtop) then
      begin
        //An overlapping horizontal edge. Overlapping horizontal edges are
        //processed as if layered with the current horizontal edge (horizEdge)
        //being infinitesimally lower that the next (e). Therfore, we
        //intersect with e only if e.xcurr is within the bounds of horzEdge ...
        if Direction = dLeftToRight then
          IntersectEdges(horzEdge, e, IntPoint(e.xcurr, horzEdge.ycurr),
            ProtectRight[not IsTopHorz(e.xcurr)])
        else
          IntersectEdges(e, horzEdge, IntPoint(e.xcurr, horzEdge.ycurr),
            ProtectLeft[not IsTopHorz(e.xcurr)]);
      end
      else if (Direction = dLeftToRight) then
      begin
        IntersectEdges(horzEdge, e, IntPoint(e.xcurr, horzEdge.ycurr),
          ProtectRight[not IsTopHorz(e.xcurr)])
      end else
      begin
        IntersectEdges(e, horzEdge, IntPoint(e.xcurr, horzEdge.ycurr),
          ProtectLeft[not IsTopHorz(e.xcurr)]);
      end;
      SwapPositionsInAEL(horzEdge, e);
    end
    else if (Direction = dLeftToRight) and
      (e.xcurr > horzRight) and assigned(fSortedEdges) then break
    else if (Direction = dRightToLeft) and
      (e.xcurr < horzLeft) and assigned(fSortedEdges) then break;
    e := eNext;
  end;

  if assigned(horzEdge.nextInLML) then
  begin
    if (horzEdge.outIdx >= 0) then
      AddPolyPt(horzEdge, IntPoint(horzEdge.xtop, horzEdge.ytop));
    UpdateEdgeIntoAEL(horzEdge);
  end else
  begin
    if horzEdge.outIdx >= 0 then
      IntersectEdges(horzEdge, eMaxPair,
        IntPoint(horzEdge.xtop, horzEdge.ycurr), [ipLeft,ipRight]);
    if eMaxPair.outIdx >= 0 then raise exception.Create(rsHorizontal);
    DeleteFromAEL(eMaxPair);
    DeleteFromAEL(horzEdge);
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.UpdateEdgeIntoAEL(var e: PEdge);
var
  AelPrev, AelNext: PEdge;
begin
  if not assigned(e.nextInLML) then raise exception.Create(rsUpdateEdgeIntoAEL);
  AelPrev := e.prevInAEL;
  AelNext := e.nextInAEL;
  e.nextInLML.outIdx := e.outIdx;
  if assigned(AelPrev) then
    AelPrev.nextInAEL := e.nextInLML else
    fActiveEdges := e.nextInLML;
  if assigned(AelNext) then
    AelNext.prevInAEL := e.nextInLML;
  e.nextInLML.side := e.side;
  e.nextInLML.windDelta := e.windDelta;
  e.nextInLML.windCnt := e.windCnt;
  e.nextInLML.windCnt2 := e.windCnt2;
  e := e.nextInLML;
  e.prevInAEL := AelPrev;
  e.nextInAEL := AelNext;
  if e.dx <> horizontal then
    InsertScanbeam(e.ytop);
end;
//------------------------------------------------------------------------------

function TClipper.ProcessIntersections(const topY: int64): boolean;
begin
  result := true;
  try
    BuildIntersectList(topY);
    if fIntersectNodes = nil then exit;
    if FixupIntersections then ProcessIntersectList
    else result := false;
  finally
    //if there's been an error, clean up the mess ...
    DisposeIntersectNodes;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.DisposeIntersectNodes;
var
  n: PIntersectNode;
begin
  while assigned(fIntersectNodes) do
  begin
    n := fIntersectNodes.next;
    dispose(fIntersectNodes);
    fIntersectNodes := n;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.BuildIntersectList(const topY: int64);
var
  e, eNext: PEdge;
  pt: TIntPoint;
  isModified: boolean;
begin
  if not assigned(fActiveEdges) then exit;

  //prepare for sorting ...
  e := fActiveEdges;
  e.tmpX := TopX(e, topY);
  fSortedEdges := e;
  fSortedEdges.prevInSEL := nil;
  e := e.nextInAEL;
  while assigned(e) do
  begin
    e.prevInSEL := e.prevInAEL;
    e.prevInSEL.nextInSEL := e;
    e.nextInSEL := nil;
    e.tmpX := TopX(e, topY);
    e := e.nextInAEL;
  end;

  try
    //bubblesort ...
    isModified := true;
    while isModified and assigned(fSortedEdges) do
    begin
      isModified := false;
      e := fSortedEdges;
      while assigned(e.nextInSEL) do
      begin
        eNext := e.nextInSEL;
        if (e.tmpX > eNext.tmpX) and
          IntersectPoint(e, eNext, pt, fUseFullRange) then
        begin
          AddIntersectNode(e, eNext, pt);
          SwapPositionsInSEL(e, eNext);
          isModified := true;
        end else
          e := eNext;
      end;
      if assigned(e.prevInSEL) then e.prevInSEL.nextInSEL := nil else break;
    end;
  finally
    fSortedEdges := nil;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.AddIntersectNode(e1, e2: PEdge; const pt: TIntPoint);

  function Process1Before2(node1, node2: PIntersectNode): boolean;
  begin
    if node1.pt.Y = node2.pt.Y then
    begin
      if (node1.edge1 = node2.edge1) or (node1.edge2 = node2.edge1) then
      begin
        result := node2.pt.X > node1.pt.X;
        if node2.edge1.dx > 0 then result := not result;
      end
      else if (node1.edge1 = node2.edge2) or (node1.edge2 = node2.edge2) then
      begin
        result := node2.pt.X > node1.pt.X;
        if node2.edge2.dx > 0 then result := not result;
      end else
        result := node2.pt.X > node1.pt.X;
    end
    else result := node1.pt.Y > node2.pt.Y;
  end;
  //----------------------------------------------------------------------------

var
  node, newNode: PIntersectNode;
begin
  new(newNode);
  newNode.edge1 := e1;
  newNode.edge2 := e2;
  newNode.pt := pt;
  newNode.next := nil;
  if not assigned(fIntersectNodes) then
    fIntersectNodes := newNode
  else if Process1Before2(newNode, fIntersectNodes) then
  begin
    newNode.next := fIntersectNodes;
    fIntersectNodes := newNode;
  end else
  begin
    node := fIntersectNodes;
    while assigned(node.next) and
      Process1Before2(node.next, newNode) do
      node := node.next;
    newNode.next := node.next;
    node.next := newNode;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.ProcessIntersectList;
var
  node: PIntersectNode;
begin
  while assigned(fIntersectNodes) do
  begin
    node := fIntersectNodes.next;
    with fIntersectNodes^ do
    begin
      IntersectEdges(edge1, edge2, pt, [ipLeft,ipRight]);
      SwapPositionsInAEL(edge1, edge2);
    end;
    dispose(fIntersectNodes);
    fIntersectNodes := node;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.DoMaxima(e: PEdge; const topY: int64);
var
  eNext, eMaxPair: PEdge;
  X: int64;
begin
  eMaxPair := GetMaximaPair(e);
  X := e.xtop;
  eNext := e.nextInAEL;
  while eNext <> eMaxPair do
  begin
    if not assigned(eNext) then raise exception.Create(rsDoMaxima);
    IntersectEdges(e, eNext, IntPoint(X, topY), [ipLeft, ipRight]);
    eNext := eNext.nextInAEL;
  end;
  if (e.outIdx < 0) and (eMaxPair.outIdx < 0) then
  begin
    DeleteFromAEL(e);
    DeleteFromAEL(eMaxPair);
  end
  else if (e.outIdx >= 0) and (eMaxPair.outIdx >= 0) then
  begin
    IntersectEdges(e, eMaxPair, IntPoint(X, topY));
  end
  else raise exception.Create(rsDoMaxima);
end;
//------------------------------------------------------------------------------

procedure TClipper.ProcessEdgesAtTopOfScanbeam(const topY: int64);
var
  e, ePrior: PEdge;
  hj: PHorzRec;
  pt, pt2: TIntPoint;
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
*      \   horizontal minima    /    /            \ /                          *
* { --  o======================#====o   --------   .     ------------------- } *
* {       horizontal maxima    .                   %  scanline intersect     } *
* { -- o=======================#===================#========o     ---------- } *
*      |                      /                   / \        \                 *
*      + maxima intersect    /                   /   \        \                *
*     /|\                   /                   /     \        \               *
*    / | \                 /                   /       \        \              *
*******************************************************************************)

  e := fActiveEdges;
  while assigned(e) do
  begin
    //1. process maxima, treating them as if they're 'bent' horizontal edges,
    //   but exclude maxima with horizontal edges. nb: e can't be a horizontal.
    if IsMaxima(e, topY) and (GetMaximaPair(e).dx <> horizontal) then
    begin
      //'e' might be removed from AEL, as may any following edges so ...
      ePrior := e.prevInAEL;
      DoMaxima(e, topY);
      if not assigned(ePrior) then
        e := fActiveEdges else
        e := ePrior.nextInAEL;
    end else
    begin
      //2. promote horizontal edges, otherwise update xcurr and ycurr ...
      if IsIntermediate(e, topY) and (e.nextInLML.dx = horizontal) then
      begin
        if (e.outIdx >= 0) then
        begin
          AddPolyPt(e, IntPoint(e.xtop, e.ytop));

          hj := fHorizJoins;
          if assigned(hj) then
          repeat
            if GetOverlapSegment(IntPoint(hj.edge.xbot, hj.edge.ybot),
              IntPoint(hj.edge.xtop, hj.edge.ytop),
              IntPoint(e.nextInLML.xbot, e.nextInLML.ybot),
              IntPoint(e.nextInLML.xtop, e.nextInLML.ytop), pt, pt2) then
                AddJoin(hj.edge, e.nextInLML, hj.savedIdx, e.outIdx);
            hj := hj.next;
          until hj = fHorizJoins;

          AddHorzJoin(e.nextInLML, e.outIdx);
        end;
        UpdateEdgeIntoAEL(e);
        AddEdgeToSEL(e);
      end else
      begin
        //this just simplifies horizontal processing ...
        e.xcurr := TopX(e, topY);
        e.ycurr := topY;
      end;
      e := e.nextInAEL;
    end;
  end;

  //3. Process horizontals at the top of the scanbeam ...
  ProcessHorizontals;

  //4. Promote intermediate vertices ...
  e := fActiveEdges;
  while assigned(e) do
  begin
    if IsIntermediate(e, topY) then
    begin
      if (e.outIdx >= 0) then AddPolyPt(e, IntPoint(e.xtop, e.ytop));
      UpdateEdgeIntoAEL(e);

      //if output polygons share an edge, they'll need joining later ...
      if (e.outIdx >= 0) and assigned(e.prevInAEL) and
        (e.prevInAEL.outIdx >= 0) and
        (e.prevInAEL.xcurr = e.xbot) and (e.prevInAEL.ycurr = e.ybot) and
        SlopesEqual(IntPoint(e.xbot,e.ybot), IntPoint(e.xtop, e.ytop),
          IntPoint(e.xbot,e.ybot),
          IntPoint(e.prevInAEL.xtop, e.prevInAEL.ytop), fUseFullRange) then
      begin
        AddPolyPt(e.prevInAEL, IntPoint(e.xbot, e.ybot));
        AddJoin(e, e.prevInAEL);
      end
      else if (e.outIdx >= 0) and assigned(e.nextInAEL) and
        (e.nextInAEL.outIdx >= 0) and (e.nextInAEL.ycurr > e.nextInAEL.ytop) and
        (e.nextInAEL.ycurr < e.nextInAEL.ybot) and
        (e.nextInAEL.xcurr = e.xbot) and (e.nextInAEL.ycurr = e.ybot) and
        SlopesEqual(IntPoint(e.xbot,e.ybot), IntPoint(e.xtop, e.ytop),
          IntPoint(e.xbot,e.ybot),
          IntPoint(e.nextInAEL.xtop, e.nextInAEL.ytop), fUseFullRange) then
      begin
        AddPolyPt(e.nextInAEL, IntPoint(e.xbot, e.ybot));
        AddJoin(e, e.nextInAEL);
      end;
    end;
    e := e.nextInAEL;
  end;
end;
//------------------------------------------------------------------------------

function TClipper.GetResult: TArrayOfArrayOfIntPoint;
var
  i,j,k,cnt: integer;
  p: PPolyPt;
begin

  for i := 0 to fPolyPtList.Count -1 do
    if assigned(fPolyPtList[i]) then
    begin
      fPolyPtList[i] := FixupOutPolygon(fPolyPtList[i]);
      //fix orientation ...
      p := fPolyPtList[i];
      if assigned(p) and (p.isHole = IsClockwise(p, fUseFullRange)) then
        ReversePolyPtLinks(p);
    end;

  JoinCommonEdges;

  k := 0;
  setLength(result, fPolyPtList.Count);
  for i := 0 to fPolyPtList.Count -1 do
    if assigned(fPolyPtList[i]) then
    begin
      //make sure each polygon has at least 3 vertices ...
      cnt := 0;
      p := PPolyPt(fPolyPtList[i]);
      repeat
        p := p.next;
        inc(cnt);
      until (p = PPolyPt(fPolyPtList[i]));
      if (cnt < 3) then continue;

      setLength(result[k], cnt);
      for j := 0 to cnt -1 do
      begin
        result[k][j].X := p.pt.X;
        result[k][j].Y := p.pt.Y;
        p := p.next;
      end;
      inc(k);
    end;
  setLength(result, k);
end;
//------------------------------------------------------------------------------

function TClipper.FixupOutPolygon(outPoly: PPolyPt): PPolyPt;
var
  pp, tmp, lastOK: PPolyPt;
begin
  //FixupOutPolygon() - removes duplicate points and simplifies consecutive
  //parallel edges by removing the middle vertex.
  lastOK := nil;
  result := nil;

  result := outPoly;
  pp := outPoly;
  while true do
  begin
    if (pp.prev = pp) or (pp.next = pp.prev) then
    begin
      DisposePolyPts(pp);
      result := nil;
      exit;
    end;

    //test for duplicate points and for colinear edges ...
    if PointsEqual(pp.pt, pp.next.pt) or
      SlopesEqual(pp.prev.pt, pp.pt, pp.next.pt, fUseFullRange) then
    begin
      //OK, we need to delete a point ...
      lastOK := nil;
      pp.prev.next := pp.next;
      pp.next.prev := pp.prev;
      tmp := pp;
      if pp = result then result := pp.prev;
      pp := pp.prev;
      dispose(tmp);
    end
    else if pp = lastOK then break
    else
    begin
      if not assigned(lastOK) then lastOK := pp;
      pp := pp.next;
    end;
  end;
end;
//------------------------------------------------------------------------------

function TClipper.FixupIntersections: boolean;
var
  e1, e2: PEdge;
  int1, int2: PIntersectNode;
begin
  result := not assigned(fIntersectNodes.next);
  if result then exit;
  //logic: only swap (intersect) adjacent edges ...
  try
    CopyAELToSEL;
    int1 := fIntersectNodes;
    int2 := fIntersectNodes.next;
    while assigned(int2) do
    begin
      e1 := int1.edge1;
      if (e1.prevInSEL = int1.edge2) then e2 := e1.prevInSEL
      else if (e1.nextInSEL = int1.edge2) then e2 := e1.nextInSEL
      else
      begin
        //The current intersection is out of order, so try and swap it with
        //a subsequent intersection ...
        while assigned(int2) do
        begin
          if (int2.edge1.nextInSEL = int2.edge2) or
            (int2.edge1.prevInSEL = int2.edge2) then break
          else int2 := int2.next;
        end;
        if not assigned(int2) then exit; //oops!!!
        //found an intersect node that can be swapped ...
        SwapIntersectNodes(int1, int2);
        e1 := int1.edge1;
        e2 := int1.edge2;
      end;
      SwapPositionsInSEL(e1, e2);
      int1 := int1.next;
      int2 := int1.next;
    end;

    //finally, check the last intersection too ...
    result := (int1.edge1.prevInSEL = int1.edge2) or
      (int1.edge1.nextInSEL = int1.edge2);
  finally
    fSortedEdges := nil;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.SwapIntersectNodes(int1, int2: PIntersectNode);
var
  e1,e2: PEdge;
  p: TIntPoint;
begin
  with int1^ do
  begin
    e1 := edge1;
    edge1 := int2.edge1;
    e2 := edge2;
    edge2 := int2.edge2;
    p := pt;
    pt := int2.pt;
  end;
  with int2^ do
  begin
    edge1 := e1;
    edge2 := e2;
    pt := p;
  end;
end;
//------------------------------------------------------------------------------

function FindSegment(var pp: PPolyPt; var pt1, pt2: TIntPoint): boolean;
var
  pp2: PPolyPt;
  pt1a, pt2a: TIntPoint;
begin
  if not assigned(pp) then begin result := false; exit; end;
  result := true;
  pt1a := pt1; pt2a := pt2;
  pp2 := pp;
  repeat
    //test for co-linearity before testing for overlap ...
    if SlopesEqual(pt1a, pt2a, pp.pt, pp.prev.pt, true) and
      SlopesEqual(pt1a, pt2a, pp.pt, true) and
        GetOverlapSegment(pt1a, pt2a, pp.pt, pp.prev.pt, pt1, pt2) then exit;
    pp := pp.next;
  until pp = pp2;
  result := false;
end;
//------------------------------------------------------------------------------

function Pt3IsBetweenPt1AndPt2(const pt1, pt2, pt3: TIntPoint): boolean;
begin
  if PointsEqual(pt1, pt3) then result := true
  else if PointsEqual(pt2, pt3) then result := true
  else if (pt1.X <> pt2.X) then result := (pt1.X < pt3.X) = (pt3.X < pt2.X)
  else result := (pt1.Y < pt3.Y) = (pt3.Y < pt2.Y);
end;
//------------------------------------------------------------------------------

function InsertPolyPtBetween(p1, p2: PPolyPt; const pt: TIntPoint): PPolyPt;
begin
  if (p1 = p2) then raise exception.Create(rsJoinError);

  new(result);
  result.pt := pt;
  result.isHole := p1.isHole;
  if p2 = p1.next then
  begin
    p1.next := result;
    p2.prev := result;
    result.next := p2;
    result.prev := p1;
  end else
  begin
    p2.next := result;
    p1.prev := result;
    result.next := p1;
    result.prev := p2;
  end;
end;
//------------------------------------------------------------------------------

function DeletePolyPt(pp: PPolyPt): PPolyPt;
begin
  if pp.next = pp then
  begin
    dispose(pp);
    result := nil;
  end else
  begin
    result := pp.prev;
    pp.next.prev := result;
    result.next := pp.next;
    dispose(pp);
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.JoinCommonEdges;
var
  i, i2: integer;
  j, j2: PJoinRec;
  prev, p1, p2, p3, p4, pp1a, pp2a: PPolyPt;
  pt1, pt2, pt3, pt4: TIntPoint;
begin
  for i := 0 to fJoinList.count -1 do
  begin
    j := fJoinList[i];
    pp1a := PPolyPt(fPolyPtList[j.poly1Idx]);
    pp2a := PPolyPt(fPolyPtList[j.poly2Idx]);
    pt1 := j.pt2a; pt2 := j.pt2b;
    pt3 := j.pt1a; pt4 := j.pt1b;
    if not FindSegment(pp1a, pt1, pt2) then continue;
    if (j.poly1Idx = j.poly2Idx) then
    begin
      //we're searching the same polygon for overlapping segments so
      //segment 2 mustn't be the same as segment 1 ...
      pp2a := pp1a.next;
      if not FindSegment(pp2a, pt3, pt4) or (pp2a = pp1a) then continue;
    end else
      if not FindSegment(pp2a, pt3, pt4) then continue;

    if not GetOverlapSegment(pt1, pt2, pt3, pt4, pt1, pt2) then continue;

    prev := pp1a.prev;
    if PointsEqual(pp1a.pt, pt1) then p1 := pp1a
    else if PointsEqual(prev.pt, pt1) then p1 := prev
    else p1 := InsertPolyPtBetween(pp1a, prev, pt1);

    if PointsEqual(pp1a.pt, pt2) then p2 := pp1a
    else if PointsEqual(prev.pt, pt2) then p2 := prev
    else if (p1 = pp1a) or (p1 = prev) then
      p2 := InsertPolyPtBetween(pp1a, prev, pt2)
    else if Pt3IsBetweenPt1AndPt2(pp1a.pt, p1.pt, pt2) then
      p2 := InsertPolyPtBetween(pp1a, p1, pt2) else
      p2 := InsertPolyPtBetween(p1, prev, pt2);

    prev := pp2a.prev;
    if PointsEqual(pp2a.pt, pt1) then p3 := pp2a
    else if PointsEqual(prev.pt, pt1) then p3 := prev
    else p3 := InsertPolyPtBetween(pp2a, prev, pt1);

    if PointsEqual(pp2a.pt, pt2) then p4 := pp2a
    else if PointsEqual(prev.pt, pt2) then p4 := prev
    else if (p3 = pp2a) or (p3 = prev) then
      p4 := InsertPolyPtBetween(pp2a, prev, pt2)
    else if Pt3IsBetweenPt1AndPt2(pp2a.pt, p3.pt, pt2) then
      p4 := InsertPolyPtBetween(pp2a, p3, pt2) else
      p4 := InsertPolyPtBetween(p3, prev, pt2);

    //p1.pt == p3.pt and p2.pt == p4.pt so join p1 to p3 and p2 to p4 ...
    if (p1.next = p2) and (p3.prev = p4) then
    begin
      p1.next := p3;
      p3.prev := p1;
      p2.prev := p4;
      p4.next := p2;
    end
    else if (p1.prev = p2) and (p3.next = p4) then
    begin
      p1.prev := p3;
      p3.next := p1;
      p2.next := p4;
      p4.prev := p2;
    end
    else
      continue; //very rare and an orientation is probably wrong

    //delete duplicate points ...
    if (PointsEqual(p1.pt, p3.pt)) then DeletePolyPt(p3);
    if (PointsEqual(p2.pt, p4.pt)) then DeletePolyPt(p4);

    if (j.poly2Idx = j.poly1Idx) then
    begin
      //instead of joining two polygons, we've just created
      //a new one by splitting one polygon into two.
      fPolyPtList[j.poly1Idx] := p1;
      j.poly2Idx := fPolyPtList.Add(p2);

      if PointInPolygon(p2.pt, p1, fUseFullRange) then
        SetHoleState(p2, not p1.isHole)
      else if PointInPolygon(p1.pt, p2, fUseFullRange) then
        SetHoleState(p1, not p2.isHole);

      //now fixup any subsequent fJoins that match this polygon
      for i2 := i+1 to fJoinList.count -1 do
      begin
        j2 := fJoinList[i2];
        if (j2.poly1Idx = j.poly1Idx) and PointIsVertex(j2.pt1a, p2) then
          j2.poly1Idx := j.poly2Idx;
        if (j2.poly2Idx = j.poly1Idx) and PointIsVertex(j2.pt2a, p2) then
          j2.poly2Idx := j.poly2Idx;
      end;
    end else
    begin
      //having joined 2 polygons together, delete the obsolete pointer ...
      fPolyPtList[j.poly2Idx] := nil;

      //now fixup any subsequent fJoins ...
      for i2 := i+1 to fJoinList.count -1 do
      begin
        j2 := fJoinList[i2];
        if (j2.poly1Idx = j.poly2Idx) then j2.poly1Idx := j.poly1Idx;
        if (j2.poly2Idx = j.poly2Idx) then j2.poly2Idx := j.poly1Idx;
      end;
      j.poly2Idx := j.poly1Idx;
    end;

    //cleanup redundant edges ...
    fPolyPtList[j.poly1Idx] := FixupOutPolygon(p1);
    if j.poly2Idx <> j.poly1Idx then
      fPolyPtList[j.poly2Idx] := FixupOutPolygon(p2);
  end;
end;

//------------------------------------------------------------------------------
// OffsetPolygons ...
//------------------------------------------------------------------------------

function GetUnitNormal(const pt1, pt2: TIntPoint): TDoublePoint;
var
  dx, dy, f: single;
begin
  dx := (pt2.X - pt1.X);
  dy := (pt2.Y - pt1.Y);

  if (dx = 0) and (dy = 0) then
  begin
    result.X := 0;
    result.Y := 0;
  end else
  begin
    f := 1 / Hypot(dx, dy);
    dx := dx * f;
    dy := dy * f;
  end;
  Result.X := dy;
  Result.Y := -dx;
end;
//------------------------------------------------------------------------------

function BuildArc(const pt: TIntPoint; a1, a2, r: single): TArrayOfIntPoint;
var
  i, N: Integer;
  a, da: double;
  Steps: Integer;
  S, C: Extended; //sin & cos
begin
  Steps := Max(6, Round(Sqrt(Abs(r)) * Abs(a2 - a1)));
  SetLength(Result, Steps);
  N := Steps - 1;
  da := (a2 - a1) / N;
  a := a1;
  for i := 0 to N do
  begin
    SinCos(a, S, C);
    Result[i].X := pt.X + Round(C * r);
    Result[i].Y := pt.Y + Round(S * r);
    a := a + da;
  end;
end;
//------------------------------------------------------------------------------

function InsertPoints(const existingPts, newPts: TArrayOfIntPoint;
  position: integer): TArrayOfIntPoint; overload;
var
  lenE, lenN: integer;
begin
  result := existingPts;
  lenE := length(existingPts);
  lenN := length(newPts);
  if lenN = 0 then exit;
  if position < 0 then position := 0
  else if position > lenE then position := lenE;
  setlength(result, lenE + lenN);
  Move(result[position],
    result[position+lenN],(lenE-position)*sizeof(TIntPoint));
  Move(newPts[0], result[position], lenN*sizeof(TIntPoint));
end;
//------------------------------------------------------------------------------

function GetBounds(const a: TArrayOfArrayOfIntPoint): TIntRect;
var
  i,j,len: integer;
const
  nullRect: TIntRect = (left:0;top:0;right:0;bottom:0);
begin
  len := length(a);
  i := 0;

  while (i < len) and (length(a[i]) = 0) do inc(i);
  if i = len then begin result := nullRect; exit; end;

  with result, a[i][0] do
  begin
    Left := X; Top := Y; Right := X; Bottom := Y;
  end;

  for i := i to len-1 do
    for j := 0 to high(a[i]) do
    begin
      if a[i][j].X < result.Left then result.Left := a[i][j].X
      else if a[i][j].X > result.Right then result.Right := a[i][j].X;
      if a[i][j].Y < result.Top then result.Top := a[i][j].Y
      else if a[i][j].Y > result.Bottom then result.Bottom := a[i][j].Y;
    end;
end;
//------------------------------------------------------------------------------

function OffsetPolygons(const pts: TArrayOfArrayOfIntPoint;
  const delta: single): TArrayOfArrayOfIntPoint;
var
  j, i, highI: integer;
  normals: TArrayOfDoublePoint;
  a1, a2, deltaSq: double;
  arc, outer: TArrayOfIntPoint;
  bounds: TIntRect;
  c: TClipper;
begin
  deltaSq := delta*delta;
  setLength(result, length(pts));
  for j := 0 to high(pts) do
  begin
    highI := high(pts[j]);

    //to minimize artefacts, strip out those polygons where
    //it's shrinking and where its area < Sqr(delta) ...
    a1 := Area(pts[j]);
    if (delta < 0) then
    begin
      if (a1 > 0) and (a1 < deltaSq) then highI := 0;
    end else
      if (a1 < 0) and (-a1 < deltaSq) then highI := 0; //nb: a hole if area < 0

    if highI < 2 then
    begin
      result[j] := nil;
      continue;
    end;

    setLength(normals, highI+1);
    normals[0] := GetUnitNormal(pts[j][highI], pts[j][0]);
    for i := 1 to highI do
      normals[i] := GetUnitNormal(pts[j][i-1], pts[j][i]);

    setLength(result[j], (highI+1)*2);
    for i := 0 to highI-1 do
    begin
      result[j][i*2].X := round(pts[j][i].X +delta *normals[i].X);
      result[j][i*2].Y := round(pts[j][i].Y +delta *normals[i].Y);
      result[j][i*2+1].X := round(pts[j][i].X +delta *normals[i+1].X);
      result[j][i*2+1].Y := round(pts[j][i].Y +delta *normals[i+1].Y);
    end;
    result[j][highI*2].X := round(pts[j][highI].X +delta *normals[highI].X);
    result[j][highI*2].Y := round(pts[j][highI].Y +delta *normals[highI].Y);
    result[j][highI*2+1].X := round(pts[j][highI].X +delta *normals[0].X);
    result[j][highI*2+1].Y := round(pts[j][highI].Y +delta *normals[0].Y);

    //round off reflex angles (ie > 180 deg) unless it's almost flat (ie < 10deg angle) ...
    //cross product normals < 0 -> reflex angle; dot product normals == 1 -> no angle
    if ((normals[highI].X*normals[0].Y-normals[0].X*normals[highI].Y)*delta > 0) and
      ((normals[0].X*normals[highI].X+normals[0].Y*normals[highI].Y) < 0.985) then
    begin
      a1 := ArcTan2(normals[highI].Y, normals[highI].X);
      a2 := ArcTan2(normals[0].Y, normals[0].X);
      if (delta > 0) and (a2 < a1) then a2 := a2 + pi*2
      else if (delta < 0) and (a2 > a1) then a2 := a2 - pi*2;
      arc := BuildArc(pts[j][highI],a1,a2,delta);
      result[j] := InsertPoints(result[j],arc,highI*2+1);
    end;
    for i := highI downto 1 do
      if ((normals[i-1].X*normals[i].Y-normals[i].X*normals[i-1].Y)*delta > 0) and
         ((normals[i].X*normals[i-1].X+normals[i].Y*normals[i-1].Y) < 0.985) then
      begin
        a1 := ArcTan2(normals[i-1].Y, normals[i-1].X);
        a2 := ArcTan2(normals[i].Y, normals[i].X);
        if (delta > 0) and (a2 < a1) then a2 := a2 + pi*2
        else if (delta < 0) and (a2 > a1) then a2 := a2 - pi*2;
        arc := BuildArc(pts[j][i-1],a1,a2,delta);
        result[j] := InsertPoints(result[j],arc,(i-1)*2+1);
      end;
  end;

  //finally, clean up untidy corners ...
  c := TClipper.Create;
  try
    c.AddPolygons(result, ptSubject);
    if delta > 0 then
    begin
      if not c.Execute(ctUnion, result, pftNonZero, pftNonZero) then
        result := nil;
    end else
    begin
      bounds := GetBounds(result);
      setlength(outer, 4);
      outer[0] := IntPoint(bounds.left-10, bounds.bottom+10);
      outer[1] := IntPoint(bounds.right+10, bounds.bottom+10);
      outer[2] := IntPoint(bounds.right+10, bounds.top-10);
      outer[3] := IntPoint(bounds.left-10, bounds.top-10);
      c.AddPolygon(outer, ptSubject);
      if c.Execute(ctUnion, result, pftNonZero, pftNonZero) then
      begin
        //delete the outer rectangle ...
        highI := high(result);
        for i := 1 to highI do result[i-1] := result[i];
        setlength(result, highI);
      end else
        result := nil;
    end;
  finally
    c.free;
  end;
end;
//------------------------------------------------------------------------------

end.
