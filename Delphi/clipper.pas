unit clipper;

(*******************************************************************************
*                                                                              *
* Author    :  Angus Johnson                                                   *
* Version   :  2.85                                                            *
* Date      :  26 November 2010                                                *
* Website   :  http://www.angusj.com                                           *
* Copyright :  Angus Johnson 2010                                              *
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

//Several type definitions used in the code below are defined in the Delphi
//Graphics32 library ( see http://www.graphics32.org/wiki/ ). These type
//definitions are redefined here in case you don't wish to use Graphics32.
{$DEFINE USING_GRAPHICS32}

interface

uses
{$IFDEF USING_GRAPHICS32}
  GR32,
{$ENDIF}
  SysUtils, Classes, Math;

type
  TClipType = (ctIntersection, ctUnion, ctDifference, ctXor);
  TPolyType = (ptSubject, ptClip);
  TPolyFillType = (pftEvenOdd, pftNonZero);

  //used internally ...
  TEdgeSide = (esLeft, esRight);
  TIntersectProtect = (ipLeft, ipRight);
  TIntersectProtects = set of TIntersectProtect;

{$IFNDEF USING_GRAPHICS32}
  TFloat = Single;
  TFloatPoint = record X, Y: TFloat; end;
  TArrayOfFloatPoint = array of TFloatPoint;
  TArrayOfArrayOfFloatPoint = array of TArrayOfFloatPoint;
  TFloatRect = record left, top, right, bottom: TFloat; end;
{$ENDIF}
  PDoublePoint = ^TDoublePoint;
  TDoublePoint = record X, Y: double; end;
  TArrayOfDoublePoint = array of TDoublePoint;
  TArrayOfArrayOfDoublePoint = array of TArrayOfDoublePoint;

  PEdge = ^TEdge;
  TEdge = record
    x: double;
    y: double;
    xbot: double;
    ybot: double;
    xtop: double;
    ytop: double;
    dx  : double;
    tmpX:  double;
    nextAtTop: boolean;
    polyType: TPolyType;
    side: TEdgeSide;
    windDelta: integer; //1 or -1 depending on winding direction
    windCnt: integer;
    windCnt2: integer;  //winding count of the opposite polytype
    outIdx: integer;
    next: PEdge;
    prev: PEdge;
    nextInLML: PEdge;
    nextInAEL: PEdge;
    prevInAEL: PEdge;
    nextInSEL: PEdge;
    prevInSEL: PEdge;
  end;

  PEdgeArray = ^TEdgeArray;
  TEdgeArray = array[0.. MaxInt div sizeof(TEdge) -1] of TEdge;

  PIntersectNode = ^TIntersectNode;
  TIntersectNode = record
    edge1: PEdge;
    edge2: PEdge;
    pt: TDoublePoint;
    next: PIntersectNode;
    prev: PIntersectNode;
  end;

  PLocalMinima = ^TLocalMinima;
  TLocalMinima = record
    y: double;
    leftBound: PEdge;
    rightBound: PEdge;
    nextLm: PLocalMinima;
  end;

  PScanbeam = ^TScanbeam;
  TScanbeam = record
    y: double;
    nextSb: PScanbeam;
  end;

  TTriState = (sFalse, sTrue, sUndefined);

  PPolyPt = ^TPolyPt;
  TPolyPt = record
    pt: TDoublePoint;
    next: PPolyPt;
    prev: PPolyPt;
    isHole: TTriState; //See TClipper ForceOrientation property
  end;

  TJoinRec = record
    ppt1: PPolyPt;
    idx1: integer;
    ppt2: PPolyPt;
    idx2: integer;
  end;
  TArrayOfJoinRec = array of TJoinRec;

  //TClipperBase is the ancestor to the TClipper class. It should not be
  //instantiated directly. This class simply abstracts the conversion of arrays
  //of polygon coords into edge objects that are stored in a LocalMinima list.
  TClipperBase = class
  private
    fList             : TList;
    fLocalMinima      : PLocalMinima;
    fCurrentLM        : PLocalMinima;
    procedure DisposeLocalMinimaList;
  protected
    procedure PopLocalMinima;
    function Reset: boolean;
    property CurrentLM: PLocalMinima read fCurrentLM;
  public
    constructor Create; virtual;
    destructor Destroy; override;

    //Any number of subject and clip polygons can be added to the clipping task,
    //either individually via the AddPolygon() method, or as groups via the
    //AddPolyPolygon() method, or even using both methods ...
    procedure AddPolygon(const polygon: TArrayOfFloatPoint; polyType: TPolyType); overload;
    procedure AddPolygon(const polygon: TArrayOfDoublePoint; polyType: TPolyType); overload;
    procedure AddPolyPolygon(const polyPolygon: TArrayOfArrayOfFloatPoint; polyType: TPolyType); overload;
    procedure AddPolyPolygon(const polyPolygon: TArrayOfArrayOfDoublePoint; polyType: TPolyType); overload;

    //Clear: If multiple clipping operations are to be performed on different
    //polygon sets, then Clear circumvents the need to recreate Clipper objects.
    procedure Clear; virtual;
    function GetBounds: TFloatRect;
  end;

  TClipper = class(TClipperBase)
  private
    fPolyPtList: TList;
    fClipType: TClipType;
    fScanbeam: PScanbeam;
    fActiveEdges: PEdge;
    fSortedEdges: PEdge; //used for intersection sorts and horizontal edges
    fIntersectNodes: PIntersectNode;
    fExecuteLocked: boolean;
    fForceOrientation: boolean;
    fClipFillType: TPolyFillType;
    fSubjFillType: TPolyFillType;
    fIntersectTolerance: double;
    fJoins: TArrayOfJoinRec;
    fCurrentHorizontals: TArrayOfJoinRec;
    function ResultAsFloatPointArray: TArrayOfArrayOfFloatPoint;
    function ResultAsDoublePointArray: TArrayOfArrayOfDoublePoint;
    function InitializeScanbeam: boolean;
    procedure InsertScanbeam(const y: double);
    function PopScanbeam: double;
    procedure DisposeScanbeamList;
    procedure SetWindingDelta(edge: PEdge);
    procedure SetWindingCount(edge: PEdge);
    function IsNonZeroFillType(edge: PEdge): boolean;
    function IsNonZeroAltFillType(edge: PEdge): boolean;
    procedure InsertLocalMinimaIntoAEL(const botY: double);
    procedure AddEdgeToSEL(edge: PEdge);
    procedure CopyAELToSEL;
    function IsTopHorz(horzEdge: PEdge; const XPos: double): boolean;
    procedure ProcessHorizontal(horzEdge: PEdge);
    procedure ProcessHorizontals;
    procedure SwapPositionsInAEL(edge1, edge2: PEdge);
    procedure SwapPositionsInSEL(edge1, edge2: PEdge);
    function BubbleSwap(edge: PEdge): PEdge;
    function Process1Before2(Node1, Node2: PIntersectNode): boolean;
    procedure AddIntersectNode(e1, e2: PEdge; const pt: TDoublePoint);
    procedure ProcessIntersections(const topY: double);
    procedure BuildIntersectList(const topY: double);
    function TestIntersections: boolean;
    procedure ProcessIntersectList;
    procedure IntersectEdges(e1,e2: PEdge;
      const pt: TDoublePoint; protects: TIntersectProtects = []);
    function GetMaximaPair(e: PEdge): PEdge;
    procedure DeleteFromAEL(e: PEdge);
    procedure DeleteFromSEL(e: PEdge);
    procedure DoMaxima(e: PEdge; const topY: double);
    procedure UpdateEdgeIntoAEL(var e: PEdge);
    procedure ProcessEdgesAtTopOfScanbeam(const topY: double);
    function IsContributing(edge: PEdge): boolean;
    function InsertPolyPtBetween(const pt: TDoublePoint; pp1, pp2: PPolyPt): PPolyPt;
    function AddPolyPt(e: PEdge; const pt: TDoublePoint): PPolyPt;
    procedure AddLocalMaxPoly(e1, e2: PEdge; const pt: TDoublePoint);
    procedure AddLocalMinPoly(e1, e2: PEdge; const pt: TDoublePoint);
    procedure AppendPolygon(e1, e2: PEdge);
    function ExecuteInternal(clipType: TClipType): boolean;
    procedure DisposeAllPolyPts;
    procedure DisposeIntersectNodes;
    procedure FixupJoins(oldIdx, newIdx: integer);
    procedure JoinCommonEdges;
  public
    //SavedSolution: TArrayOfArrayOfFloatPoint; //clipper.DLL only


    //The Execute() method performs the specified clipping task on previously
    //assigned subject and clip polygons. This method can be called multiple
    //times (ie to perform different clipping operations) without having to
    //reassign either subject or clip polygons.
    function Execute(clipType: TClipType;
      out solution: TArrayOfArrayOfFloatPoint;
      subjFillType: TPolyFillType = pftEvenOdd;
      clipFillType: TPolyFillType = pftEvenOdd): boolean; overload;
    function Execute(clipType: TClipType;
      out solution: TArrayOfArrayOfDoublePoint;
      subjFillType: TPolyFillType = pftEvenOdd;
      clipFillType: TPolyFillType = pftEvenOdd): boolean; overload;

    constructor Create; override;
    destructor Destroy; override;

    //The ForceOrientation property ensures that polygons that result from a
    //TClipper.Execute() calls will have clockwise 'outer' and counter-clockwise
    //'inner' (or 'hole') polygons. If ForceOrientation == false, then the
    //polygons returned in the solution will have undefined orientation.<br>
    //Setting ForceOrientation = true results in a minor penalty (~10%) in
    //execution speed. (Default == true)
    property ForceOrientation: boolean read
      fForceOrientation write fForceOrientation;
  end;

  function DoublePoint(const X, Y: double): TDoublePoint; overload;
  //PolygonArea is only useful when polygons don't self-intersect. Negative
  //results indicate polygons with counter-clockwise orientations.
  function PolygonArea(const poly: TArrayOfFloatPoint): double; overload;
  function PolygonArea(const poly: TArrayOfDoublePoint): double; overload;
  function OffsetPolygons(const pts: TArrayOfArrayOfDoublePoint;
    const delta: double): TArrayOfArrayOfDoublePoint; overload;
  function OffsetPolygons(const pts: TArrayOfArrayOfFloatPoint;
    const delta: double): TArrayOfArrayOfFloatPoint; overload;
  function TranslatePolygons(const pts: TArrayOfArrayOfDoublePoint;
    const deltaX, deltaY: double): TArrayOfArrayOfDoublePoint; overload;
  function TranslatePolygons(const pts: TArrayOfArrayOfFloatPoint;
    const deltaX, deltaY: double): TArrayOfArrayOfFloatPoint; overload;

  function IsClockwise(const pts: TArrayOfDoublePoint): boolean; overload;
  
  function MakeArrayOfDoublePoint(const a: TArrayOfFloatPoint): TArrayOfDoublePoint; overload;
  function MakeArrayOfFloatPoint(const a: TArrayOfDoublePoint): TArrayOfFloatPoint; overload;

implementation

type
  TDirection = (dRightToLeft, dLeftToRight);

const
  //infinite: used to define inverse slope (dx/dy) of horizontal edges
  infinite       : double = -3.4e+38;
  almost_infinite: double = -3.39e+38;
  //tolerance: is needed because vertices are floating point values and any
  //comparison of floating point values requires a degree of tolerance. Ideally
  //this value should vary depending on how big (or small) the supplied polygon
  //coordinate values are. If coordinate values are greater than 1.0E+5
  //(ie 100,000+) then tolerance should be adjusted up (since the significand
  //of type double is 15 decimal places). However, for the vast majority
  //of uses ... tolerance = 1.0e-10 will be just fine.
  tolerance: double = 1.0e-10;
  minimal_tolerance: double = 1.0e-14;
  //precision: defines when adjacent vertices will be considered duplicates
  //and hence ignored. This circumvents edges having indeterminate slope.
  precision: double = 1.0e-6;
  slope_precision: double = 1.0e-3;
  nullRect: TFloatRect =(left:0;top:0;right:0;bottom:0);
  
resourcestring
  rsMissingRightbound = 'InsertLocalMinimaIntoAEL: missing rightbound';
  rsDoMaxima = 'DoMaxima error';
  rsUpdateEdgeIntoAEL = 'UpdateEdgeIntoAEL error';
  rsProcessEdgesAtTopOfScanbeam = 'ProcessEdgesAtTopOfScanbeam error';
  rsAppendPolygon = 'AppendPolygon error';
  rsIntersection = 'Intersection error';
  rsInsertPolyPt = 'InsertPolyPtBetween error';

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------

{$IFNDEF USING_GRAPHICS32}
function FloatPoint(X, Y: Single): TFloatPoint;
begin
  Result.X := X;
  Result.Y := Y;
end;
//------------------------------------------------------------------------------
{$ENDIF}

function PolygonArea(const poly: TArrayOfFloatPoint): double;
var
  i, highI: integer;
begin
  result := 0;
  highI := high(poly);
  if highI < 2 then exit;
  for i :=0 to highI -1 do
    result := result + (poly[i].X +poly[i+1].X) *(poly[i].Y -poly[i+1].Y);
  result := result + (poly[highI].X +poly[0].X) *(poly[highI].Y -poly[0].Y);
  result := result / 2;
end;
//------------------------------------------------------------------------------

function PolygonArea(const poly: TArrayOfDoublePoint): double;
var
  i, highI: integer;
begin
  result := 0;
  highI := high(poly);
  if highI < 2 then exit;
  for i :=0 to highI -1 do
    result := result + (poly[i].X +poly[i+1].X) *(poly[i].Y -poly[i+1].Y);
  result := result + (poly[highI].X +poly[0].X) *(poly[highI].Y -poly[0].Y);
  result := result / 2;
end;
//------------------------------------------------------------------------------

function GetUnitNormal(const pt1, pt2: TDoublePoint): TDoublePoint;
var
  dx, dy, f: single;
begin
  dx := (pt2.X - pt1.X);
  dy := (pt2.Y - pt1.Y);

  if (dx = 0) and (dy = 0) then
  begin
    result := DoublePoint(0,0);
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

procedure SinCos(const Theta, Radius : TFloat; out Sin, Cos: double);
var
  S, C: Extended;
begin
  Math.SinCos(Theta, S, C);
  Sin := S * Radius;
  Cos := C * Radius;
end;
//------------------------------------------------------------------------------

function BuildArc(const pt: TDoublePoint;
  a1, a2, r: single): TArrayOfDoublePoint; overload;
const
  MINSTEPS = 6;
var
  I, N: Integer;
  a, da, dx, dy: double;
  Steps: Integer;
begin
  Steps := Max(MINSTEPS, Round(Sqrt(Abs(r)) * Abs(a2 - a1)));
  SetLength(Result, Steps);
  N := Steps - 1;
  da := (a2 - a1) / N;
  a := a1;
  for I := 0 to N do
  begin
    SinCos(a, r, dy, dx);
    Result[I].X := pt.X + dx;
    Result[I].Y := pt.Y + dy;
    a := a + da;
  end;
end;
//------------------------------------------------------------------------------

function MakeArrayOfDoublePoint(const a: TArrayOfFloatPoint): TArrayOfDoublePoint;
var
  i, len: integer;
begin
  len := length(a);
  setlength(result, len);
  for i := 0 to len -1 do
  begin
    result[i].X := a[i].X;
    result[i].Y := a[i].Y;
  end;
end;
//------------------------------------------------------------------------------

function MakeArrayOfFloatPoint(const a: TArrayOfDoublePoint): TArrayOfFloatPoint;
var
  i, len: integer;
begin
  len := length(a);
  setlength(result, len);
  for i := 0 to len -1 do
  begin
    result[i].X := a[i].X;
    result[i].Y := a[i].Y;
  end;
end;
//------------------------------------------------------------------------------

function GetBounds(const pts: TArrayOfDoublePoint): TFloatRect;
var
  i: integer;
begin
  if not assigned(pts) then
    result := nullRect
  else
  begin
    result.Left := pts[0].X; result.Top := pts[0].Y;
    result.Right := pts[0].X; result.Bottom := pts[0].Y;
    for i := 1 to high(pts) do
    begin
      if pts[i].X < result.Left then result.Left := pts[i].X
      else if pts[i].X > result.Right then result.Right := pts[i].X;
      if pts[i].Y < result.Top then result.Top := pts[i].Y
      else if pts[i].Y > result.Bottom then result.Bottom := pts[i].Y;
    end;
  end;
end;
//------------------------------------------------------------------------------

function InsertPoints(const existingPts, newPts:
  TArrayOfDoublePoint; position: integer): TArrayOfDoublePoint; overload;
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
    result[position+lenN],(lenE-position)*sizeof(TDoublePoint));
  Move(newPts[0], result[position], lenN*sizeof(TDoublePoint));
end;
//------------------------------------------------------------------------------

function TranslatePolygons(const pts: TArrayOfArrayOfDoublePoint;
  const deltaX, deltaY: double): TArrayOfArrayOfDoublePoint;
var
  i,j: integer;
begin
  setlength(result, length(pts));
  for i := 0 to high(pts) do
  begin
    setlength(result[i], length(pts[i]));
    for j := 0 to high(pts[i]) do
    begin
      result[i][j].X := pts[i][j].X + deltaX;
      result[i][j].Y := pts[i][j].Y + deltaY;
    end;
  end;
end;
//------------------------------------------------------------------------------

function TranslatePolygons(const pts: TArrayOfArrayOfFloatPoint;
  const deltaX, deltaY: double): TArrayOfArrayOfFloatPoint;
var
  i,j: integer;
begin
  setlength(result, length(pts));
  for i := 0 to high(pts) do
  begin
    setlength(result[i], length(pts[i]));
    for j := 0 to high(pts[i]) do
    begin
      result[i][j].X := pts[i][j].X + deltaX;
      result[i][j].Y := pts[i][j].Y + deltaY;
    end;
  end;
end;
//------------------------------------------------------------------------------

function IsClockwise(const pts: TArrayOfDoublePoint): boolean; overload;
var
  i, highI: integer;
  area: double;
begin
  result := true;
  highI := high(pts);
  if highI < 2 then exit;
  //or ...(x2-x1)(y2+y1)
  area := pts[highI].x * pts[0].y - pts[0].x * pts[highI].y;
  for i := 0 to highI-1 do
    area := area + pts[i].x * pts[i+1].y - pts[i+1].x * pts[i].y;
  //area := area/2;
  result := area > 0; //ie reverse of normal formula because Y axis inverted
end;
//------------------------------------------------------------------------------

function OffsetPolygons(const pts: TArrayOfArrayOfDoublePoint;
  const delta: double): TArrayOfArrayOfDoublePoint;
var
  j, i, highI: integer;
  normals: TArrayOfDoublePoint;
  a1,a2: double;
  arc, outer: TArrayOfDoublePoint;
  r: TFloatRect;
  c: TClipper;
begin
  //a positive delta will offset each polygon edge towards its left -
  //therefore polygons orientated clockwise will expand. Negative deltas
  //will offset polygon edge towards their right.

  //USE THIS FUNCTION WITH CAUTION. VERY OCCASIONALLY HOLES AREN'T PROPERLY
  //HANDLED. THEY MAY BE MISSING OR THE WRONG SIZE. (ie: work-in-progress.)

  setLength(result, length(pts));
  for j := 0 to high(pts) do
  begin
    highI := high(pts[j]);
    if highI < 0 then continue;
    setLength(normals, highI+1);
    normals[0] := GetUnitNormal(pts[j][highI], pts[j][0]);
    for i := 1 to highI do
      normals[i] := GetUnitNormal(pts[j][i-1], pts[j][i]);

    //to minimize artefacts when shrinking, strip out polygons where
    //abs(delta) is larger than half its diameter ...
    if (delta < 0) then with GetBounds(pts[j]) do
      if (-delta*2 > (right - left)) or (-delta*2 > (bottom - top)) then
        highI := 0;

    setLength(result[j], (highI+1)*2);
    for i := 0 to highI-1 do
    begin
      result[j][i*2].X := pts[j][i].X +delta *normals[i].X;
      result[j][i*2].Y := pts[j][i].Y +delta *normals[i].Y;
      result[j][i*2+1].X := pts[j][i].X +delta *normals[i+1].X;
      result[j][i*2+1].Y := pts[j][i].Y +delta *normals[i+1].Y;
    end;
    result[j][highI*2].X := pts[j][highI].X +delta *normals[highI].X;
    result[j][highI*2].Y := pts[j][highI].Y +delta *normals[highI].Y;
    result[j][highI*2+1].X := pts[j][highI].X +delta *normals[0].X;
    result[j][highI*2+1].Y := pts[j][highI].Y +delta *normals[0].Y;

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
    c.AddPolyPolygon(result, ptSubject);
    if delta > 0 then
    begin
      c.Execute(ctUnion, result, pftNonZero, pftNonZero);
    end else
    begin
      r := c.GetBounds;
      setlength(outer, 4);
      outer[0] := DoublePoint(r.left-10, r.bottom+10);
      outer[1] := DoublePoint(r.right+10, r.bottom+10);
      outer[2] := DoublePoint(r.right+10, r.top-10);
      outer[3] := DoublePoint(r.left-10, r.top-10);
      c.AddPolygon(outer, ptSubject);
      c.Execute(ctUnion, result, pftNonZero, pftNonZero);
      //delete the outer rectangle ...
      highI := high(result);
      for i := 1 to highI do result[i-1] := result[i];
      setlength(result, highI);
    end;
  finally
    c.free;
  end;
end;
//------------------------------------------------------------------------------

function OffsetPolygons(const pts: TArrayOfArrayOfFloatPoint;
  const delta: double): TArrayOfArrayOfFloatPoint;
var
  i, len: integer;
  dblPts: TArrayOfArrayOfDoublePoint;
begin
  len := length(pts);
  setlength(dblPts, len);
  for i := 0 to len -1 do
    dblPts[i] := MakeArrayOfDoublePoint(pts[i]);
  dblPts := OffsetPolygons(dblPts, delta);
  len := length(dblPts);
  setlength(result, len);
  for i := 0 to len -1 do
    Result[i] := MakeArrayOfFloatPoint(dblPts[i]);
end;
//------------------------------------------------------------------------------

function DoublePoint(const X, Y: double): TDoublePoint;
begin
  Result.X := X;
  Result.Y := Y;
end;
//------------------------------------------------------------------------------

function AFloatPt2ADoublePt(const pts: TArrayOfFloatPoint): TArrayOfDoublePoint;
var
  i: integer;
begin
  setlength(result, length(pts));
  for i := 0 to high(pts) do
  begin
    result[i].X := pts[i].X;
    result[i].Y := pts[i].Y;
  end;
end;
//------------------------------------------------------------------------------

function AAFloatPt2AADoublePt(const pts: TArrayOfArrayOfFloatPoint): TArrayOfArrayOfDoublePoint;
var
  i,j: integer;
begin
  setlength(result, length(pts));
  for i := 0 to high(pts) do
  begin
    setlength(result[i], length(pts[i]));
    for j := 0 to high(pts[i]) do
    begin
      result[i][j].X := pts[i][j].X;
      result[i][j].Y := pts[i][j].Y;
    end;
  end;
end;
//------------------------------------------------------------------------------

function RoundToTolerance(const pt: TDoublePoint): TDoublePoint;
begin
  Result.X := Round(pt.X / precision) * precision;
  Result.Y := Round(pt.Y / precision) * precision;
end;
//------------------------------------------------------------------------------

function PointsEqual(const pt1, pt2: TDoublePoint): boolean; overload;
begin
  result := (abs(pt1.X-pt2.X) < precision + tolerance) and
    (abs(pt1.Y-pt2.Y) < precision + tolerance);
end;
//------------------------------------------------------------------------------

function PointsEqual(const pt1x, pt1y, pt2x, pt2y: double): boolean; overload;
begin
  result := (abs(pt1x-pt2x) < precision + tolerance) and
    (abs(pt1y-pt2y) < precision + tolerance);
end;
//------------------------------------------------------------------------------

procedure FixupSolutionColinears(list: TList; idx: integer);
var
  pp, tmp: PPolyPt;
  ptDeleted, firstPass: boolean;
begin
	//fixup any occasional 'empty' protrusions (ie adjacent parallel edges) ...
  firstPass := true;
  pp := PPolyPt(list[idx]);
  while true do
  begin
    if pp.prev = pp then exit;
    //test for same slope ... (cross-product)
    if abs((pp.pt.Y - pp.prev.pt.Y)*(pp.next.pt.X - pp.pt.X) -
        (pp.pt.X - pp.prev.pt.X)*(pp.next.pt.Y - pp.pt.Y)) < precision then
    begin
      if (pp.isHole <> sUndefined) and (pp.next.isHole = sUndefined) then
        pp.next.isHole := pp.isHole;
      pp.prev.next := pp.next;
      pp.next.prev := pp.prev;
      tmp := pp;
      if list[idx] = pp then
      begin
        list[idx] := pp.prev;
        pp := pp.next;
      end else
        pp := pp.prev;
      dispose(tmp);
      ptDeleted := true;
    end else
    begin
      pp := pp.next;
      ptDeleted := false;
    end;
    if not firstPass then break;
    if (pp = list[idx]) and not ptDeleted then
      firstPass := false;
  end;
end;
//------------------------------------------------------------------------------

procedure DisposePolyPts(pp: PPolyPt);
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

procedure SetDx(e: PEdge);
var
  dx, dy: double;
begin
  dx := abs(e.x - e.next.x);
  dy := abs(e.y - e.next.y);
  //Very short, nearly horizontal edges can cause problems by very
  //inaccurately determining intermediate X values - see TopX().
  //Therefore treat very short, nearly horizontal edges as horizontal too ...
  if ((dx < 0.1) and  (dy *10 < dx)) or (dy < slope_precision) then
  begin
    e.dx := infinite;
    if (e.y <> e.next.y) then
      e.y := e.next.y;
  end else e.dx :=
    (e.x - e.next.x)/(e.y - e.next.y);
end;
//------------------------------------------------------------------------------

function IsHorizontal(e: PEdge): boolean; overload;
begin
  result := assigned(e) and (e.dx < almost_infinite);
end;
//------------------------------------------------------------------------------

function IsHorizontal(pp1, pp2: PPolyPt): boolean; overload;
begin
  result := (abs(pp1.pt.X - pp2.pt.X) > precision) and
    (abs(pp1.pt.Y - pp2.pt.Y) < precision);
end;
//----------------------------------------------------------------------

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

function TopX(edge: PEdge; const currentY: double): double;
begin
  if currentY = edge.ytop then result := edge.xtop
  else result := edge.x + edge.dx*(currentY - edge.y);
end;
//------------------------------------------------------------------------------

function ShareSamePoly(e1, e2: PEdge): boolean;
begin
  result := assigned(e1) and assigned(e2) and (e1.outIdx = e2.outIdx);
end;
//------------------------------------------------------------------------------

function SlopesEqual(e1, e2: PEdge): boolean;
begin
  if IsHorizontal(e1) then result := IsHorizontal(e2)
  else if IsHorizontal(e2) then result := false
  else result := abs((e1.ytop - e1.y)*(e2.xtop - e2.x) -
    (e1.xtop - e1.x)*(e2.ytop - e2.y)) < slope_precision;
end;
//---------------------------------------------------------------------------

function IntersectPoint(edge1, edge2: PEdge; out ip: TDoublePoint): boolean;
var
  b1,b2: double;
begin
  if (edge1.dx = edge2.dx) then
  begin
    result := false;
    exit;
  end;
  if edge1.dx = 0 then
  begin
    ip.X := edge1.x;
    with edge2^ do b2 := y - x/dx;
    ip.Y := ip.X/edge2.dx + b2;
  end
  else if edge2.dx = 0 then
  begin
    ip.X := edge2.x;
    with edge1^ do b1 := y - x/dx;
    ip.Y := ip.X/edge1.dx + b1;
  end else
  begin
    with edge1^ do b1 := x - y *dx;
    with edge2^ do b2 := x - y *dx;
    ip.Y := (b2-b1)/(edge1.dx - edge2.dx);
    ip.X := edge1.dx * ip.Y + b1;
  end;
  result := (ip.Y > edge1.ytop +tolerance) and (ip.Y > edge2.ytop +tolerance);
end;
//------------------------------------------------------------------------------

function IsClockwise(pt: PPolyPt): boolean; overload;
var
  area: double;
  startPt: PPolyPt;
begin
  area := 0;
  startPt := pt;
  repeat
    //or ...(x2-x1)(y2+y1)
    area := area + (pt.pt.X * pt.next.pt.Y) - (pt.next.pt.X * pt.pt.Y);
    pt := pt.next;
  until pt = startPt;
  //area := area /2;
  result := area > 0; //ie reverse of normal formula because Y axis inverted
end;
//------------------------------------------------------------------------------

function ValidateOrientation(pt: PPolyPt): boolean;
var
  ptStart, bottomPt: PPolyPt;
begin
  //check that orientation matches the hole status ...

  //first, find the hole state of the bottom-most point (because
  //the hole state of other points is not reliable) ...
  bottomPt := pt;
  ptStart := pt;
  pt := pt.next;
  while (pt <> ptStart) do
  begin
    if (pt.pt.Y > bottomPt.pt.Y) or
      ((pt.pt.Y = bottomPt.pt.Y) and (pt.pt.X > bottomPt.pt.X)) then
        bottomPt := pt;
    pt := pt.next;
  end;

//  //alternative method to derive orientation (may be marginally quicker)
//  ptPrev := bottomPt.prev;
//  ptNext := bottomPt.next;
//  N1 := GetUnitNormal(ptPrev.pt, bottomPt.pt);
//  N2 := GetUnitNormal(bottomPt.pt, ptNext.pt);
//  //(N1.X * N2.Y - N2.X * N1.Y) == unit normal "cross product" == sin(angle)
//  IsClockwise := (N1.X * N2.Y - N2.X * N1.Y) > 0; //ie angle > 180deg.

  while (bottomPt.isHole = sUndefined) and
    (bottomPt.next.pt.Y >= bottomPt.pt.Y) do bottomPt := bottomPt.next;
  while (bottomPt.isHole = sUndefined) and
    (bottomPt.prev.pt.Y >= bottomPt.pt.Y) do bottomPt := bottomPt.prev;
  result := IsClockwise(pt) = (bottomPt.isHole <> sTrue);
end;

//------------------------------------------------------------------------------
// TClipperBase methods ...
//------------------------------------------------------------------------------

constructor TClipperBase.Create;
begin
  fList := TList.Create;
  fLocalMinima  := nil;
  fCurrentLM    := nil;
end;
//------------------------------------------------------------------------------

destructor TClipperBase.Destroy;
begin
  Clear;
  fList.Free;
  inherited;
end;
//------------------------------------------------------------------------------

procedure TClipperBase.AddPolygon(const polygon: TArrayOfFloatPoint; polyType: TPolyType);
var
  dblPts: TArrayOfDoublePoint;
begin
  dblPts := AFloatPt2ADoublePt(polygon);
  AddPolygon(dblPts, polyType);
end;
//------------------------------------------------------------------------------

procedure TClipperBase.AddPolygon(const polygon: TArrayOfDoublePoint; polyType: TPolyType);

  //----------------------------------------------------------------------

  procedure InitEdge(e, eNext, ePrev: PEdge; const pt: TDoublePoint);
  begin
    //set up double-link-list linkage and initialize savedBot & dx only
    fillChar(e^, sizeof(TEdge), 0);
    e.x := pt.X;
    e.y := pt.Y;
    e.next := eNext;
    e.prev := ePrev;
    SetDx(e);
  end;
  //----------------------------------------------------------------------

  procedure ReInitEdge(e: PEdge; const nextX, nextY: double);
  begin
    if e.y > nextY then
    begin
      e.xbot := e.x;
      e.ybot := e.y;
      e.xtop := nextX;
      e.ytop := nextY;
      e.nextAtTop := true;
    end else
    begin
      //reverse top and bottom ...
      e.xbot := nextX;
      e.ybot := nextY;
      e.xtop := e.x;
      e.ytop := e.y;
      e.x := e.xbot;
      e.y := e.ybot;
      e.nextAtTop := false;
    end;
    e.polyType := polyType;
    e.outIdx := -1;
  end;
  //----------------------------------------------------------------------

  function SlopesEqualInternal(e1, e2: PEdge): boolean;
  begin
    if IsHorizontal(e1) then result := IsHorizontal(e2)
    else if IsHorizontal(e2) then result := false
    else
      //cross product of dy1/dx1 = dy2/dx2 ...
      result := abs((e1.y - e1.next.y) *
        (e2.x - e2.next.x) -
        (e1.x - e1.next.x) *
        (e2.y - e2.next.y)) < slope_precision;
  end;
  //----------------------------------------------------------------------

  function FixupForDupsAndColinear(var e: PEdge; const edges: PEdgeArray): boolean;
  begin
    result := false;
    while (e.next <> e.prev) and (PointsEqual(e.prev.x, e.prev.y, e.x, e.y) or
      SlopesEqualInternal(e.prev, e)) do
    begin
      result := true;
      //remove 'e' from the double-linked-list ...
      if (e = @edges[0]) then
      begin
        //move the content of e.next to e before removing e.next from DLL ...
        e.x := e.next.x;
        e.y := e.next.y;
        e.next.next.prev := e;
        e.next := e.next.next;
      end else
      begin
        //remove 'e' from the loop ...
        e.prev.next := e.next;
        e.next.prev := e.prev;
        e := e.prev; //now get back into the loop
      end;
      SetDx(e.prev);
      SetDx(e);
    end;
  end;
  //----------------------------------------------------------------------

  procedure SwapX(e: PEdge);
  begin
    //swap horizontal edges' top and bottom x's so they follow the natural
    //progression of the bounds - ie so their xbots will align with the
    //adjoining lower edge. [Helpful in the ProcessHorizontal() method.]
    e.xbot := e.xtop;
    e.xtop := e.x;
    e.x := e.xbot;
  end;
  //----------------------------------------------------------------------

  procedure InsertLocalMinima(newLm: PLocalMinima);
  var
    tmpLm: PLocalMinima;
  begin
    if not assigned(fLocalMinima) then
    begin
      fLocalMinima := newLm;
    end
    else if (newLm.y >= fLocalMinima.y) then
    begin
      newLm.nextLm := fLocalMinima;
      fLocalMinima := newLm;
    end else
    begin
      tmpLm := fLocalMinima;
      while assigned(tmpLm.nextLm) and (newLm.y < tmpLm.nextLm.y) do
        tmpLm := tmpLm.nextLm;
      newLm.nextLm := tmpLm.nextLm;
      tmpLm.nextLm := newLm;
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
      if IsHorizontal(e) then
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
    newLm.nextLm := nil;
    newLm.y := e.prev.ybot;
    if IsHorizontal(e) then //horizontal edges never start a left bound
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
      if (e.next.ytop = e.ytop) and not IsHorizontal(e.next) then break;
      e.nextInLML := e.next;
      e := e.next;
      if IsHorizontal(e) and (e.xbot <> e.prev.xtop) then SwapX(e);
    until false;
    result := e.next;
  end;
  //----------------------------------------------------------------------

var
  i, highI: integer;
  edges: PEdgeArray;
  e, eHighest: PEdge;
  pg: TArrayOfDoublePoint;
begin
  {AddPolygon}

  highI := high(polygon);
  setlength(pg, highI +1);
  for i := 0 to highI do pg[i] := RoundToTolerance(polygon[i]);

  while (highI > 1) and PointsEqual(pg[0], pg[highI]) do dec(highI);
  if highI < 2 then exit;

  //make sure this is still a sensible polygon (ie with at least one minima) ...
  i := 1;
  while (i <= highI) and (abs(pg[i].Y - pg[0].Y) < precision) do inc(i);
  if i > highI then exit;

  GetMem(edges, sizeof(TEdge)*(highI+1));
  //convert 'edges' to a double-linked-list and initialize a few of the vars ...
  edges[0].x := pg[0].X;
  edges[0].y := pg[0].Y;
  InitEdge(@edges[highI], @edges[0], @edges[highI-1], pg[highI]);
  for i := highI-1 downto 1 do
    InitEdge(@edges[i], @edges[i+1], @edges[i-1], pg[i]);
  InitEdge(@edges[0], @edges[1], @edges[highI], pg[0]);

  //fixup by deleting any duplicate points and amalgamating co-linear edges ...
  e := @edges[0];
  repeat
    FixupForDupsAndColinear(e, edges);
    e := e.next;
  until (e = @edges[0]);
  while FixupForDupsAndColinear(e, edges) do
  begin
    e := e.prev;
    if not FixupForDupsAndColinear(e, edges) then break;
    e := @edges[0];
  end;

  if (e.next = e.prev) then
  begin
    //this isn't a valid polygon ...
    dispose(edges);
    exit;
  end;

  fList.Add(edges);

  //now properly re-initialize edges and also find 'eHighest' ...
  e := edges[0].next;
  eHighest := e;
  repeat
    ReInitEdge(e, e.next.x, e.next.y);
    if e.ytop < eHighest.ytop then eHighest := e;
    e := e.next;
  until e = @edges[0];
  if e.next.nextAtTop then
    ReInitEdge(e, e.next.x, e.next.y) else
    ReInitEdge(e, e.next.xtop, e.next.ytop);
  if e.ytop < eHighest.ytop then eHighest := e;

  //make sure eHighest is positioned so the following loop works safely ...
  if eHighest.nextAtTop then eHighest := eHighest.next;
  if IsHorizontal(eHighest) then eHighest := eHighest.next;

  //finally insert each local minima ...
  e := eHighest;
  repeat
    e := AddBoundsToLML(e);
  until (e = eHighest);
end;
//------------------------------------------------------------------------------

procedure TClipperBase.AddPolyPolygon(const polyPolygon: TArrayOfArrayOfFloatPoint;
  polyType: TPolyType);
var
  dblPts: TArrayOfArrayOfDoublePoint;
begin
  dblPts := AAFloatPt2AADoublePt(polyPolygon);
  AddPolyPolygon(dblPts, polyType);
end;
//------------------------------------------------------------------------------

procedure TClipperBase.AddPolyPolygon(const polyPolygon: TArrayOfArrayOfDoublePoint;
  polyType: TPolyType);
var
  i: integer;
begin
  for i := 0 to high(polyPolygon) do AddPolygon(polyPolygon[i], polyType);
end;
//------------------------------------------------------------------------------

procedure TClipperBase.Clear;
var
  i: Integer;
begin
  DisposeLocalMinimaList;
  for i := 0 to fList.Count -1 do dispose(PEdgeArray(fList[i]));
  fList.Clear;
end;
//------------------------------------------------------------------------------

function TClipperBase.GetBounds: TFloatRect;
var
  e: PEdge;
  lm: PLocalMinima;
begin
  lm := fLocalMinima;
  if not assigned(lm) then
  begin
    result := nullRect;
    exit;
  end;
  result.Left := -infinite;
  result.Top := -infinite;
  result.Right := infinite;
  result.Bottom := infinite;
  while assigned(lm) do
  begin
    if lm.leftBound.y > result.Bottom then result.Bottom := lm.leftBound.y;
    e := lm.leftBound;
    while assigned(e.nextInLML) do
    begin
      if e.x < result.Left then result.Left := e.x;
      e := e.nextInLML;
    end;
    if e.x < result.Left then result.Left := e.x
    else if e.xtop < result.Left then result.Left := e.xtop;
    if e.ytop < result.Top then result.Top := e.ytop;

    e := lm.rightBound;
    while assigned(e.nextInLML) do
    begin
      if e.x > result.Right then result.Right := e.x;
      e := e.nextInLML;
    end;
    if e.x > result.Right then result.Right := e.x;
    if e.xtop > result.Right then result.Right := e.xtop;

    lm := lm.nextLm;
  end;
end;
//------------------------------------------------------------------------------

function TClipperBase.Reset: boolean;
var
  e: PEdge;
  lm: PLocalMinima;
begin
  //Reset() allows various clipping operations to be executed
  //multiple times on the same polygon sets. (Protected method.)
  fCurrentLM := fLocalMinima;
  result := assigned(fLocalMinima);
  if not result then exit; //ie nothing to process

  //reset all edges ...
  lm := fLocalMinima;
  while assigned(lm) do
  begin
    e := lm.leftBound;
    while assigned(e) do
    begin
      e.xbot := e.x;
      e.ybot := e.y;
      e.side := esLeft;
      e.outIdx := -1;
      e := e.nextInLML;
    end;
    e := lm.rightBound;
    while assigned(e) do
    begin
      e.xbot := e.x;
      e.ybot := e.y;
      e.side := esRight;
      e.outIdx := -1;
      e := e.nextInLML;
    end;
    lm := lm.nextLm;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipperBase.PopLocalMinima;
begin
  if not assigned(fCurrentLM) then exit;
  fCurrentLM := fCurrentLM.nextLm;
end;
//------------------------------------------------------------------------------

procedure TClipperBase.DisposeLocalMinimaList;
var
  tmpLm: PLocalMinima;
begin
  while assigned(fLocalMinima) do
  begin
    tmpLm := fLocalMinima.nextLm;
    Dispose(fLocalMinima);
    fLocalMinima := tmpLm;
  end;
  fCurrentLM := nil;
end;

//------------------------------------------------------------------------------
// TClipper methods ...
//------------------------------------------------------------------------------

constructor TClipper.Create;
begin
  inherited Create;
  fPolyPtList := TList.Create;
  fForceOrientation := true;
end;
//------------------------------------------------------------------------------

destructor TClipper.Destroy;
begin
  DisposeScanbeamList;
  fPolyPtList.Free;
  inherited;
end;
//------------------------------------------------------------------------------

function TClipper.Execute(clipType: TClipType;
  out solution: TArrayOfArrayOfFloatPoint;
  subjFillType: TPolyFillType = pftEvenOdd;
  clipFillType: TPolyFillType = pftEvenOdd): boolean;
begin
  result := false;
  if fExecuteLocked then exit;
  try try
    fExecuteLocked := true;
    fSubjFillType := subjFillType;
    fClipFillType := clipFillType;
    result := ExecuteInternal(clipType);
    if result then solution := ResultAsFloatPointArray;
  finally
    fExecuteLocked := false;
    DisposeAllPolyPts;
  end;
  except
    result := false;
  end;
end;
//------------------------------------------------------------------------------

function TClipper.Execute(clipType: TClipType;
  out solution: TArrayOfArrayOfDoublePoint;
  subjFillType: TPolyFillType = pftEvenOdd;
  clipFillType: TPolyFillType = pftEvenOdd): boolean;
begin
  result := false;
  if fExecuteLocked then exit;
  try try
    fExecuteLocked := true;
    fSubjFillType := subjFillType;
    fClipFillType := clipFillType;
    result := ExecuteInternal(clipType);
    if result then solution := ResultAsDoublePointArray;
  finally
    fExecuteLocked := false;
    DisposeAllPolyPts;
  end;
  except
    result := false;
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

function TClipper.ExecuteInternal(clipType: TClipType): boolean;
var
  yBot, yTop: double;
begin
  result := false;
  try
    if not InitializeScanbeam then exit;
    fActiveEdges := nil;
    fSortedEdges := nil;
    fJoins := nil;
    fCurrentHorizontals := nil;
    fClipType := clipType;
    yBot := PopScanbeam;
    repeat
      InsertLocalMinimaIntoAEL(yBot);
      ProcessHorizontals;
      yTop := PopScanbeam;
      ProcessIntersections(yTop);
      ProcessEdgesAtTopOfScanbeam(yTop);
      yBot := yTop;
    until not assigned(fScanbeam);
    result := true;
  except
    //result := false;
  end;
end;
//------------------------------------------------------------------------------

function TClipper.ResultAsFloatPointArray: TArrayOfArrayOfFloatPoint;
var
  i,j,k,cnt: integer;
  pt: PPolyPt;
  y: double;
  isHorizontalOnly: boolean;
begin
  k := 0;
  JoinCommonEdges;
  setLength(result, fPolyPtList.Count);
  for i := 0 to fPolyPtList.Count -1 do
    if assigned(fPolyPtList[i]) then
    begin
      FixupSolutionColinears(fPolyPtList, i);

      cnt := 0;
      pt := PPolyPt(fPolyPtList[i]);
      isHorizontalOnly := true;
      y := pt.pt.Y;
      repeat
        pt := pt.next;
        if isHorizontalOnly and (abs(pt.pt.Y - y) > precision) then
          isHorizontalOnly := false;
        inc(cnt);
      until (pt = PPolyPt(fPolyPtList[i]));
      if (cnt < 3) or isHorizontalOnly then continue;

      //optionally validate the orientation of simple polygons ...
      pt := PPolyPt(fPolyPtList[i]);
      if fForceOrientation and not ValidateOrientation(pt) then
      begin
        ReversePolyPtLinks(pt);
        fPolyPtList[i] := pt.next;
        pt := pt.next;
      end;

      setLength(result[k], cnt);
      for j := 0 to cnt -1 do
      begin
        result[k][j].X := pt.pt.X;
        result[k][j].Y := pt.pt.Y;
        pt := pt.next;
      end;
      inc(k);
    end;
  setLength(result, k);
end;
//------------------------------------------------------------------------------

function TClipper.ResultAsDoublePointArray: TArrayOfArrayOfDoublePoint;
var
  i,j,k,cnt: integer;
  pt: PPolyPt;
  y: double;
  isHorizontalOnly: boolean;
begin
  k := 0;
  JoinCommonEdges;
  setLength(result, fPolyPtList.Count);
  for i := 0 to fPolyPtList.Count -1 do
    if assigned(fPolyPtList[i]) then
    begin
      FixupSolutionColinears(fPolyPtList, i);

      cnt := 0;
      pt := PPolyPt(fPolyPtList[i]);
      isHorizontalOnly := true;
      y := pt.pt.Y;
      repeat
        pt := pt.next;
        if isHorizontalOnly and (abs(pt.pt.Y - y) > precision) then
          isHorizontalOnly := false;
        inc(cnt);
      until (pt = PPolyPt(fPolyPtList[i]));
      if (cnt < 3) or isHorizontalOnly then continue;

      //optionally validate the orientation of simple polygons ...
      pt := PPolyPt(fPolyPtList[i]);
      if fForceOrientation and not ValidateOrientation(pt) then
      begin
        ReversePolyPtLinks(pt);
        fPolyPtList[i] := pt.next;
        pt := pt.next;
      end;

      setLength(result[k], cnt);
      for j := 0 to cnt -1 do
      begin
        result[k][j].X := pt.pt.X;
        result[k][j].Y := pt.pt.Y;
        pt := pt.next;
      end;
      inc(k);
    end;
  setLength(result, k);
end;
//------------------------------------------------------------------------------

procedure TClipper.DisposeScanbeamList;
var
  sb2: PScanbeam;
begin
  while assigned(fScanbeam) do
  begin
    sb2 := fScanbeam.nextSb;
    Dispose(fScanbeam);
    fScanbeam := sb2;
  end;
end;
//------------------------------------------------------------------------------

function TClipper.InitializeScanbeam: boolean;
var
  lm: PLocalMinima;
begin
  DisposeScanbeamList;
  result := Reset; //returns false when there are no polygons to process
  if not result then exit;
  //add all the local minima into a fresh fScanbeam list ...
  lm := CurrentLM;
  while assigned(lm) do
  begin
    InsertScanbeam(lm.y);
    InsertScanbeam(lm.leftBound.ytop); //this is necessary too!
    lm := lm.nextLm;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.InsertScanbeam(const y: double);
var
  newSb, sb2: PScanbeam;
begin
  if not assigned(fScanbeam) then
  begin
    new(fScanbeam);
    fScanbeam.nextSb := nil;
    fScanbeam.y := y;
  end else if y > fScanbeam.y then
  begin
    new(newSb);
    newSb.y := y;
    newSb.nextSb := fScanbeam;
    fScanbeam := newSb;
  end else
  begin
    sb2 := fScanbeam;
    while assigned(sb2.nextSb) and (y <= sb2.nextSb.y) do sb2 := sb2.nextSb;
    if y = sb2.y then exit; //ie ignores duplicates
    new(newSb);
    newSb.y := y;
    newSb.nextSb := sb2.nextSb;
    sb2.nextSb := newSb;
  end;
end;
//------------------------------------------------------------------------------

function TClipper.PopScanbeam: double;
var
  sb2: PScanbeam;
begin
  result := fScanbeam.y;
  sb2 := fScanbeam;
  fScanbeam := fScanbeam.nextSb;
  dispose(sb2);
end;
//------------------------------------------------------------------------------

procedure TClipper.SetWindingDelta(edge: PEdge);
begin
  if not IsNonZeroFillType(edge) then edge.windDelta := 1
  else if edge.nextAtTop then edge.windDelta := 1
  else edge.windDelta := -1;
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
  case edge.polyType of
    ptSubject: result := fSubjFillType = pftNonZero;
    else result := fClipFillType = pftNonZero;
  end;
end;
//------------------------------------------------------------------------------

function TClipper.IsNonZeroAltFillType(edge: PEdge): boolean;
begin
  case edge.polyType of
    ptSubject: result := fClipFillType = pftNonZero;
    else result := fSubjFillType = pftNonZero;
  end;
end;
//------------------------------------------------------------------------------

function IsBetween(const val, startrange, endrange: double): boolean;
begin
  result := (abs(val - startrange) < tolerance) or
    (abs(val - endrange) < tolerance) or
      (val - startrange > 0) = (endrange - val > 0);
end;
//------------------------------------------------------------------------------

function Edge2InsertsBeforeEdge1(e1,e2: PEdge): boolean;
begin
  if (e2.xbot - tolerance > e1.xbot) then result := false
  else if (e2.xbot + tolerance < e1.xbot) then result := true
  else if IsHorizontal(e2) then result := false
  else result := e2.dx > e1.dx;
end;
//------------------------------------------------------------------------------

procedure TClipper.InsertLocalMinimaIntoAEL(const botY: double);

  procedure InsertEdgeIntoAEL(edge: PEdge);
  var
    e: PEdge;
  begin
    edge.prevInAEL := nil;
    edge.nextInAEL := nil;
    if not assigned(fActiveEdges) then
    begin
      fActiveEdges := edge;
    end else if Edge2InsertsBeforeEdge1(fActiveEdges, edge) then
    begin
      edge.nextInAEL := fActiveEdges;
      fActiveEdges.prevInAEL := edge;
      fActiveEdges := edge;
    end else
    begin
      e := fActiveEdges;
      while assigned(e.nextInAEL) and
        not Edge2InsertsBeforeEdge1(e.nextInAEL, edge) do e := e.nextInAEL;
      edge.nextInAEL := e.nextInAEL;
      if assigned(e.nextInAEL) then e.nextInAEL.prevInAEL := edge;
      edge.prevInAEL := e;
      e.nextInAEL := edge;
    end;
  end;
  //----------------------------------------------------------------------

var
  i,j: integer;
  e: PEdge;
  pt: TDoublePoint;
begin
  {InsertLocalMinimaIntoAEL}
  while assigned(CurrentLM) and (CurrentLM.y = botY) do
  begin
    InsertEdgeIntoAEL(CurrentLM.leftBound);
    InsertScanbeam(CurrentLM.leftBound.ytop);
    InsertEdgeIntoAEL(CurrentLM.rightBound);

    //set edge winding states ...
    with CurrentLM^ do
    begin
      SetWindingDelta(leftBound);
      if IsNonZeroFillType(leftBound) then
        rightBound.windDelta := -leftBound.windDelta else
        rightBound.windDelta := 1;
      SetWindingCount(leftBound);
      rightBound.windCnt := leftBound.windCnt;
      rightBound.windCnt2 := leftBound.windCnt2;

      if IsHorizontal(rightBound) then
      begin
        //nb: only rightbounds can have a horizontal bottom edge
        AddEdgeToSEL(rightBound);
        InsertScanbeam(rightBound.nextInLML.ytop);
      end else
        InsertScanbeam(rightBound.ytop);

      if IsContributing(leftBound) then
        AddLocalMinPoly(leftBound, rightBound, DoublePoint(leftBound.xbot, y));

      //flag polygons that share colinear edges ready to be joined later ...
      if (leftBound.outIdx >= 0) and
        assigned(leftBound.prevInAEL) and
        (leftBound.prevInAEL.outIdx >= 0) and
        (abs(leftBound.prevInAEL.xbot - leftBound.x) < tolerance) and
        SlopesEqual(leftBound, leftBound.prevInAEL) then
      begin
        pt := DoublePoint(leftBound.x,leftBound.y);
        i := length(fJoins);
        setlength(fJoins, i+1);
        fJoins[i].ppt1 := AddPolyPt(leftBound, pt);
        fJoins[i].idx1 := leftBound.outIdx;
        fJoins[i].ppt2 := AddPolyPt(leftBound.prevInAEL, pt);
        fJoins[i].idx2 := leftBound.prevInAEL.outIdx;
      end;
      if (rightBound.outIdx >= 0) and
        assigned(rightBound.prevInAEL) and
        (rightBound.prevInAEL.outIdx >= 0) and
        (abs(rightBound.prevInAEL.xbot - rightBound.x) < tolerance) and
        SlopesEqual(rightBound, rightBound.prevInAEL) then
      begin
        pt := DoublePoint(rightBound.x,rightBound.y);
        i := length(fJoins);
        setlength(fJoins, i+1);
        fJoins[i].ppt1 := AddPolyPt(rightBound, pt);
        fJoins[i].idx1 := rightBound.outIdx;
        fJoins[i].ppt2 := AddPolyPt(rightBound.prevInAEL, pt);
        fJoins[i].idx2 := rightBound.prevInAEL.outIdx;
      end else if (rightBound.outIdx >= 0) and IsHorizontal(rightBound) then
      begin
        //check for overlap with fCurrentHorizontals
        for i := 0 to high(fCurrentHorizontals) do
          with fCurrentHorizontals[i] do
          begin
            if not assigned(fPolyPtList[idx1]) then continue
            else if IsBetween(ppt1.pt.X, rightBound.x, rightBound.xtop) then
            begin
              j := length(fJoins);
              setlength(fJoins, j+1);
              fJoins[j].ppt1 := ppt1;
              fJoins[j].idx1 := idx1;
              fJoins[j].ppt2 := AddPolyPt(rightBound, ppt1.pt);
              fJoins[j].idx2 := rightBound.outIdx;
            end
            else if IsHorizontal(ppt1.next, ppt1) and
              IsBetween(rightBound.x, ppt1.pt.X, ppt1.next.pt.X) then
            begin
              pt := DoublePoint(rightBound.x,rightBound.y);
              j := length(fJoins);
              setlength(fJoins, j+1);
              fJoins[j].ppt1 := InsertPolyPtBetween(pt, ppt1, ppt1.next);
              fJoins[j].idx1 := idx1;
              fJoins[j].ppt2 := AddPolyPt(rightBound, pt);
              fJoins[j].idx2 := rightBound.outIdx;
            end
            else if IsHorizontal(ppt1.prev, ppt1) and
              IsBetween(rightBound.x, ppt1.pt.X, ppt1.prev.pt.X) then
            begin
              pt := DoublePoint(rightBound.x,rightBound.y);
              j := length(fJoins);
              setlength(fJoins, j+1);
              fJoins[j].ppt1 := InsertPolyPtBetween(pt, ppt1, ppt1.prev);
              fJoins[j].idx1 := idx1;
              fJoins[j].ppt2 := AddPolyPt(rightBound, pt);
              fJoins[j].idx2 := rightBound.outIdx;
            end;
          end;
      end;

      if (leftBound.nextInAEL <> rightBound) then
      begin
        e := leftBound.nextInAEL;
        pt := DoublePoint(leftBound.xbot,leftBound.ybot);
        while e <> rightBound do
        begin
          if not assigned(e) then raise exception.Create(rsMissingRightbound);
          IntersectEdges(rightBound, e, pt); //order important here
          e := e.nextInAEL;
        end;
      end;
    end;

    PopLocalMinima;
  end;
  fCurrentHorizontals := nil;
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

procedure TClipper.SwapPositionsInAEL(edge1, edge2: PEdge);
var
  prev,next: PEdge;
begin
  with edge1^ do if not assigned(nextInAEL) and not assigned(prevInAEL) then exit;
  with edge2^ do if not assigned(nextInAEL) and not assigned(prevInAEL) then exit;

  if edge1.nextInAEL = edge2 then
  begin
    next    := edge2.nextInAEL;
    if assigned(next) then next.prevInAEL := edge1;
    prev    := edge1.prevInAEL;
    if assigned(prev) then prev.nextInAEL := edge2;
    edge2.prevInAEL := prev;
    edge2.nextInAEL := edge1;
    edge1.prevInAEL := edge2;
    edge1.nextInAEL := next;
  end
  else if edge2.nextInAEL = edge1 then
  begin
    next    := edge1.nextInAEL;
    if assigned(next) then next.prevInAEL := edge2;
    prev    := edge2.prevInAEL;
    if assigned(prev) then prev.nextInAEL := edge1;
    edge1.prevInAEL := prev;
    edge1.nextInAEL := edge2;
    edge2.prevInAEL := edge1;
    edge2.nextInAEL := next;
  end else
  begin
    next    := edge1.nextInAEL;
    prev    := edge1.prevInAEL;
    edge1.nextInAEL := edge2.nextInAEL;
    if assigned(edge1.nextInAEL) then edge1.nextInAEL.prevInAEL := edge1;
    edge1.prevInAEL := edge2.prevInAEL;
    if assigned(edge1.prevInAEL) then edge1.prevInAEL.nextInAEL := edge1;
    edge2.nextInAEL := next;
    if assigned(edge2.nextInAEL) then edge2.nextInAEL.prevInAEL := edge2;
    edge2.prevInAEL := prev;
    if assigned(edge2.prevInAEL) then edge2.prevInAEL.nextInAEL := edge2;
  end;
  if not assigned(edge1.prevInAEL) then fActiveEdges := edge1
  else if not assigned(edge2.prevInAEL) then fActiveEdges := edge2;
end;
//------------------------------------------------------------------------------

procedure TClipper.SwapPositionsInSEL(edge1, edge2: PEdge);
var
  prev,next: PEdge;
begin
  if edge1.nextInSEL = edge2 then
  begin
    next    := edge2.nextInSEL;
    if assigned(next) then next.prevInSEL := edge1;
    prev    := edge1.prevInSEL;
    if assigned(prev) then prev.nextInSEL := edge2;
    edge2.prevInSEL := prev;
    edge2.nextInSEL := edge1;
    edge1.prevInSEL := edge2;
    edge1.nextInSEL := next;
  end
  else if edge2.nextInSEL = edge1 then
  begin
    next    := edge1.nextInSEL;
    if assigned(next) then next.prevInSEL := edge2;
    prev    := edge2.prevInSEL;
    if assigned(prev) then prev.nextInSEL := edge1;
    edge1.prevInSEL := prev;
    edge1.nextInSEL := edge2;
    edge2.prevInSEL := edge1;
    edge2.nextInSEL := next;
  end else
  begin
    next    := edge1.nextInSEL;
    prev    := edge1.prevInSEL;
    edge1.nextInSEL := edge2.nextInSEL;
    if assigned(edge1.nextInSEL) then edge1.nextInSEL.prevInSEL := edge1;
    edge1.prevInSEL := edge2.prevInSEL;
    if assigned(edge1.prevInSEL) then edge1.prevInSEL.nextInSEL := edge1;
    edge2.nextInSEL := next;
    if assigned(edge2.nextInSEL) then edge2.nextInSEL.prevInSEL := edge2;
    edge2.prevInSEL := prev;
    if assigned(edge2.prevInSEL) then edge2.prevInSEL.nextInSEL := edge2;
  end;
  if not assigned(edge1.prevInSEL) then fSortedEdges := edge1
  else if not assigned(edge2.prevInSEL) then fSortedEdges := edge2;
end;
//------------------------------------------------------------------------------

function GetNextInAEL(e: PEdge; Direction: TDirection): PEdge;
begin
  if Direction = dLeftToRight then
    result := e.nextInAEL else
    result := e.prevInAEL;
end;
//------------------------------------------------------------------------------

function GetPrevInAEL(e: PEdge; Direction: TDirection): PEdge;
begin
  if Direction = dLeftToRight then
    result := e.prevInAEL else
    result := e.nextInAEL;
end;
//------------------------------------------------------------------------------

function IsMinima(e: PEdge): boolean;
begin
  result := assigned(e) and (e.prev.nextInLML <> e) and (e.next.nextInLML <> e);
end;
//------------------------------------------------------------------------------

function IsMaxima(e: PEdge; const Y: double): boolean;
begin
  result := assigned(e) and
    (abs(e.ytop - Y) < tolerance) and not assigned(e.nextInLML);
end;
//------------------------------------------------------------------------------

function IsIntermediate(e: PEdge; const Y: double): boolean;
begin
  result := (abs(e.ytop - Y) < tolerance) and assigned(e.nextInLML);
end;
//------------------------------------------------------------------------------

function TClipper.GetMaximaPair(e: PEdge): PEdge;
begin
  result := e.next;
  if not IsMaxima(result, e.ytop) or (result.xtop <> e.xtop) then
    result := e.prev;
end;
//------------------------------------------------------------------------------

procedure TClipper.DoMaxima(e: PEdge; const topY: double);
var
  eNext, eMaxPair: PEdge;
  X: double;
begin
  eMaxPair := GetMaximaPair(e);
  X := e.xtop;
  eNext := e.nextInAEL;
  while eNext <> eMaxPair do
  begin
    IntersectEdges(e, eNext, DoublePoint(X, topY), [ipLeft, ipRight]);
    eNext := eNext.nextInAEL;
  end;
  if (e.outIdx < 0) and (eMaxPair.outIdx < 0) then
  begin
    DeleteFromAEL(e);
    DeleteFromAEL(eMaxPair);
  end
  else if (e.outIdx >= 0) and (eMaxPair.outIdx >= 0) then
  begin
    IntersectEdges(e, eMaxPair, DoublePoint(X, topY));
  end
  else raise exception.Create(rsDoMaxima);
end;
//------------------------------------------------------------------------------

procedure TClipper.ProcessHorizontals;
var
  horzEdge: PEdge;
begin
  horzEdge := fSortedEdges;
  while assigned(horzEdge) do
  begin
    DeleteFromSEL(horzEdge);
    ProcessHorizontal(horzEdge);
    horzEdge := fSortedEdges;
  end;
end;
//------------------------------------------------------------------------------

function TClipper.IsTopHorz(horzEdge: PEdge; const XPos: double): boolean;
var
  e: PEdge;
begin
  result := false;
  e := fSortedEdges;
  while assigned(e) do
  begin
    if (XPos >= min(e.xbot,e.xtop)) and (XPos <= max(e.xbot,e.xtop)) then exit;
    e := e.nextInSEL;
  end;
  result := true;
end;
//------------------------------------------------------------------------------

procedure TClipper.ProcessHorizontal(horzEdge: PEdge);
var
  i: integer;
  e, eNext, eMaxPair: PEdge;
  horzLeft, horzRight: double;
  Direction: TDirection;
  pt: TDoublePoint;
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

  if horzEdge.xbot < horzEdge.xtop then
  begin
    horzLeft := horzEdge.xbot; horzRight := horzEdge.xtop;
    Direction := dLeftToRight;
  end else
  begin
    horzLeft := horzEdge.xtop; horzRight := horzEdge.xbot;
    Direction := dRightToLeft;
  end;

  if assigned(horzEdge.nextInLML) then
    eMaxPair := nil else
    eMaxPair := GetMaximaPair(horzEdge);

  e := GetNextInAEL(horzEdge, Direction);
  while assigned(e) do
  begin
    eNext := GetNextInAEL(e, Direction);
    if (e.xbot >= horzLeft -tolerance) and (e.xbot <= horzRight +tolerance) then
    begin
      //ok, so far it looks like we're still in range of the horizontal edge

      if (abs(e.xbot - horzEdge.xtop) < tolerance) and
        assigned(horzEdge.nextInLML) then
      begin
        if SlopesEqual(e, horzEdge.nextInLML) then
        begin
          //we've got 2 colinear edges at the end of the horz. line ...
          if (horzEdge.outIdx >= 0) and (e.outIdx >= 0) then
          begin
            i := length(fJoins);
            setlength(fJoins, i+1);
            pt := DoublePoint(horzEdge.xtop,horzEdge.ytop);
            fJoins[i].ppt1 := AddPolyPt(horzEdge, pt);
            fJoins[i].idx1 := horzEdge.outIdx;
            fJoins[i].ppt2 := AddPolyPt(e, pt);
            fJoins[i].idx2 := e.outIdx;
          end;
          break; //we've reached the end of the horizontal line
        end
        else if (e.dx < horzEdge.nextInLML.dx) then
        //we really have got to the end of the intermediate horz edge so quit.
        //nb: More -ve slopes follow more +ve slopes *above* the horizontal.
          break;
      end;

      if (e = eMaxPair) then
      begin
        //horzEdge is evidently a maxima horizontal and we've arrived at its end.
        if Direction = dLeftToRight then
          IntersectEdges(horzEdge, e, DoublePoint(e.xbot, horzEdge.ybot)) else
          IntersectEdges(e, horzEdge, DoublePoint(e.xbot, horzEdge.ybot));
        exit;
      end
      else if IsHorizontal(e) and not IsMinima(e) and not (e.xbot > e.xtop) then
      begin
        //An overlapping horizontal edge. Overlapping horizontal edges are
        //processed as if layered with the current horizontal edge (horizEdge)
        //being infinitesimally lower that the next (e). Therfore, we
        //intersect with e only if e.xbot is within the bounds of horzEdge ...
        if Direction = dLeftToRight then
          IntersectEdges(horzEdge, e, DoublePoint(e.xbot, horzEdge.ybot),
            ProtectRight[not IsTopHorz(horzEdge, e.xbot)])
        else
          IntersectEdges(e, horzEdge, DoublePoint(e.xbot, horzEdge.ybot),
            ProtectLeft[not IsTopHorz(horzEdge, e.xbot)]);
      end
      else if (Direction = dLeftToRight) then
      begin
        IntersectEdges(horzEdge, e, DoublePoint(e.xbot, horzEdge.ybot),
          ProtectRight[not IsTopHorz(horzEdge, e.xbot)])
      end else
      begin
        IntersectEdges(e, horzEdge, DoublePoint(e.xbot, horzEdge.ybot),
          ProtectLeft[not IsTopHorz(horzEdge, e.xbot)]);
      end;
      SwapPositionsInAEL(horzEdge, e);
    end
    else if (Direction = dLeftToRight) and
      (e.xbot > horzRight + tolerance) and not assigned(horzEdge.nextInSEL) then
        break
    else if (Direction = dRightToLeft) and
      (e.xbot < horzLeft - tolerance) and not assigned(horzEdge.nextInSEL) then
        break;
    e := eNext;
  end;

  if assigned(horzEdge.nextInLML) then
  begin
    if (horzEdge.outIdx >= 0) then
      AddPolyPt(horzEdge, DoublePoint(horzEdge.xtop, horzEdge.ytop));
    UpdateEdgeIntoAEL(horzEdge);
  end else
  begin
    if horzEdge.outIdx >= 0 then
      IntersectEdges(horzEdge, eMaxPair,
        DoublePoint(horzEdge.xtop, horzEdge.ybot), [ipLeft,ipRight]);
    DeleteFromAEL(eMaxPair);
    DeleteFromAEL(horzEdge);
  end;
end;
//------------------------------------------------------------------------------

function TClipper.InsertPolyPtBetween(const pt: TDoublePoint; pp1, pp2: PPolyPt): PPolyPt;
begin
  new(result);
  result.pt := pt;
  result.isHole := sUndefined;
  if pp2 = pp1.next then
  begin
    result.next := pp2;
    result.prev := pp1;
    pp1.next := result;
    pp2.prev := result;
  end else if pp1 = pp2.next then
  begin
    result.next := pp1;
    result.prev := pp2;
    pp2.next := result;
    pp1.prev := result;
  end else
    raise exception.Create(rsInsertPolyPt);

end;
//------------------------------------------------------------------------------

function TClipper.AddPolyPt(e: PEdge; const pt: TDoublePoint): PPolyPt;
var
  fp: PPolyPt;
  ToFront: boolean;
begin
  ToFront := e.side = esLeft;
  if e.outIdx < 0 then
  begin
    new(result);
    result.pt := pt;
    e.outIdx := fPolyPtList.Add(result);
    result.next := result;
    result.prev := result;
    result.isHole := sUndefined;
  end else
  begin
    result := nil;
    fp := PPolyPt(fPolyPtList[e.outIdx]);
    if (ToFront and PointsEqual(pt, fp.pt)) then result := fp
    else if not ToFront and PointsEqual(pt, fp.prev.pt) then result := fp.prev;
    if assigned(result) then exit;

    new(result);
    result.pt := pt;
    result.isHole := sUndefined;
    result.next := fp;
    result.prev := fp.prev;
    result.prev.next := result;
    fp.prev := result;
    if ToFront then fPolyPtList[e.outIdx] := result;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.ProcessIntersections(const topY: double);
begin
  if not assigned(fActiveEdges) then exit;
  try
    fIntersectTolerance := tolerance;
    BuildIntersectList(topY);
    if not assigned(fIntersectNodes) then exit;
    //Test the pending intersections for errors and, if any are found, redo
    //BuildIntersectList (twice if necessary) with adjusted tolerances ...
    if not TestIntersections then
    begin
      fIntersectTolerance := minimal_tolerance;
      DisposeIntersectNodes;
      BuildIntersectList(topY);
      if not TestIntersections then
      begin
        fIntersectTolerance := slope_precision;
        DisposeIntersectNodes;
        BuildIntersectList(topY);
        if not TestIntersections then
          //try eliminating near duplicate points in the input polygons
          //eg by adjusting precision ... to say 0.1;
          raise Exception.Create(rsIntersection);
      end;
    end;
    ProcessIntersectList;
  finally
    //if there's been an error, clean up the mess ...
    DisposeIntersectNodes;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.DisposeIntersectNodes;
var
  iNode: PIntersectNode;
begin
  while assigned(fIntersectNodes) do
  begin
    iNode := fIntersectNodes.next;
    dispose(fIntersectNodes);
    fIntersectNodes := iNode;
  end;
end;
//------------------------------------------------------------------------------

function TClipper.Process1Before2(Node1, Node2: PIntersectNode): boolean;

  function E1PrecedesE2inAEL(e1, e2: PEdge): boolean;
  begin
    result := true;
    while assigned(e1) do
      if e1 = e2 then exit else e1 := e1.nextInAEL;
    result := false;
  end;

begin
  if (abs(Node1.pt.Y - Node2.pt.Y) < fIntersectTolerance) then
  begin
    if (abs(Node1.pt.X - Node2.pt.X) > precision) then
    begin
      result := Node1.pt.X < Node2.pt.X;
      exit;
    end;
    //a complex intersection (with more than 2 edges intersecting) ...
    if (Node1.edge1 = Node2.edge1) or
      SlopesEqual(Node1.edge1, Node2.edge1) then
    begin
      if Node1.edge2 = Node2.edge2 then
        //(N1.E1 & N2.E1 are co-linear) and (N1.E2 == N2.E2)  ...
        result := not E1PrecedesE2inAEL(Node1.edge1, Node2.edge1)
      else if SlopesEqual(Node1.edge2, Node2.edge2) then
        //(N1.E1 == N2.E1) and (N1.E2 & N2.E2 are co-linear) ...
        result := E1PrecedesE2inAEL(Node1.edge2, Node2.edge2)
      else if //check if minima **
        ((abs(Node1.edge2.y - Node1.pt.Y) < slope_precision) or
        (abs(Node2.edge2.y - Node2.pt.Y) < slope_precision)) and
        ((Node1.edge2.next = Node2.edge2) or (Node1.edge2.prev = Node2.edge2)) then
      begin
        if Node1.edge1.dx < 0 then
          result := Node1.edge2.dx > Node2.edge2.dx else
          result := Node1.edge2.dx < Node2.edge2.dx;
      end else if (Node1.edge2.dx - Node2.edge2.dx) < precision then
        result := E1PrecedesE2inAEL(Node1.edge2, Node2.edge2)
      else
        result := (Node1.edge2.dx < Node2.edge2.dx);

    end else if (Node1.edge2 = Node2.edge2) and //check if maxima ***
      ((abs(Node1.edge1.ytop - Node1.pt.Y) < slope_precision) or
      (abs(Node2.edge1.ytop - Node2.pt.Y) < slope_precision)) then
        result := (Node1.edge1.dx > Node2.edge1.dx)
    else
      result := (Node1.edge1.dx < Node2.edge1.dx);
  end else
    result := (Node1.pt.Y > Node2.pt.Y);
  //**a minima that very slightly overlaps an edge can appear like
  //a complex intersection but it's not. (Minima can't have parallel edges.)
  //***a maxima that very slightly overlaps an edge can appear like
  //a complex intersection but it's not. (Maxima can't have parallel edges.)
end;
//------------------------------------------------------------------------------

procedure TClipper.AddIntersectNode(e1, e2: PEdge; const pt: TDoublePoint);
var
  IntersectNode, iNode: PIntersectNode;
begin
  new(IntersectNode);
  IntersectNode.edge1 := e1;
  IntersectNode.edge2 := e2;
  IntersectNode.pt := pt;
  IntersectNode.next := nil;
  IntersectNode.prev := nil;
  if not assigned(fIntersectNodes) then
    fIntersectNodes := IntersectNode
  else if Process1Before2(IntersectNode, fIntersectNodes) then
  begin
    IntersectNode.next := fIntersectNodes;
    fIntersectNodes.prev := IntersectNode;
    fIntersectNodes := IntersectNode;
  end else
  begin
    iNode := fIntersectNodes;
    while assigned(iNode.next) and
      Process1Before2(iNode.next, IntersectNode) do
      iNode := iNode.next;
    if assigned(iNode.next) then iNode.next.prev := IntersectNode;
    IntersectNode.next := iNode.next;
    IntersectNode.prev := iNode;
    iNode.next := IntersectNode;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.BuildIntersectList(const topY: double);
var
  e, eNext: PEdge;
  pt: TDoublePoint;
  isModified: boolean;
begin
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
        if (e.tmpX > eNext.tmpX + tolerance) and
          IntersectPoint(e, eNext, pt) then
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

function TClipper.TestIntersections: boolean;
var
  e: PEdge;
  iNode: PIntersectNode;
begin
  result := true;
  if not assigned(fIntersectNodes) then exit;
  try
    //do the test sort using SEL ...
    CopyAELToSEL;
    iNode := fIntersectNodes;
    while assigned(iNode) do
    begin
      SwapPositionsInSEL(iNode.edge1, iNode.edge2);
      iNode := iNode.next;
    end;
    //now check that tmpXs are in the right order ...
    e := fSortedEdges;
    while assigned(e.nextInSEL) do
    begin
      if e.nextInSEL.tmpX < e.tmpX - precision then
      begin
        result := false;
        exit;
      end;
      e := e.nextInSEL;
    end;
  finally
    fSortedEdges := nil;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.ProcessIntersectList;
var
  iNode: PIntersectNode;
begin
  while assigned(fIntersectNodes) do
  begin
    iNode := fIntersectNodes.next;
    with fIntersectNodes^ do
    begin
      IntersectEdges(edge1, edge2, pt, [ipLeft,ipRight]);
      SwapPositionsInAEL(edge1, edge2);
    end;
    dispose(fIntersectNodes);
    fIntersectNodes := iNode;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.IntersectEdges(e1,e2: PEdge;
  const pt: TDoublePoint; protects: TIntersectProtects = []);

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

  //nb: e1 always precedes e2 in AEL ...
  e1stops := not (ipLeft in protects) and not assigned(e1.nextInLML) and
    (abs(e1.xtop - pt.x) < tolerance) and //nb: not precision
    (abs(e1.ytop - pt.y) < precision);
  e2stops := not (ipRight in protects) and not assigned(e2.nextInLML) and
    (abs(e2.xtop - pt.x) < tolerance) and //nb: not precision
    (abs(e2.ytop - pt.y) < precision);
  e1Contributing := (e1.outIdx >= 0);
  e2contributing := (e2.outIdx >= 0);

  //update winding counts ...
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
    case fClipType of
      ctIntersection: if (abs(e2.windCnt) < 2) and
        ((e2.polyType = ptSubject) or (e2.windCnt2 <> 0)) then DoEdge1;
      else
        if (abs(e2.windCnt) < 2) then DoEdge1;
    end;
  end
  else if e2contributing then
  begin
    case fClipType of
      ctIntersection: if (abs(e1.windCnt) < 2) and
        ((e1.polyType = ptSubject) or (e1.windCnt2 <> 0)) then DoEdge2;
      else
        if (abs(e1.windCnt) < 2) then DoEdge2;
    end;
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

procedure TClipper.DeleteFromAEL(e: PEdge);
var
  AelPrev, AelNext: PEdge;
begin
  AelPrev := e.prevInAEL;
  AelNext := e.nextInAEL;
  if not assigned(AelPrev) and not assigned(AelNext) and
    (e <> fActiveEdges) then exit; //already deleted
  if assigned(AelPrev) then
    AelPrev.nextInAEL := AelNext else
    fActiveEdges := AelNext;
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
  if assigned(SelPrev) then
    SelPrev.nextInSEL := SelNext else
    fSortedEdges := SelNext;
  if assigned(SelNext) then SelNext.prevInSEL := SelPrev;
  e.nextInSEL := nil;
  e.prevInSEL := nil;
end;
//------------------------------------------------------------------------------

procedure TClipper.UpdateEdgeIntoAEL(var e: PEdge);
var
  i: integer;
  pt: TDoublePoint;
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
  if not IsHorizontal(e) then
  begin
    InsertScanbeam(e.ytop);

    //if output polygons share an edge, they'll need joining later ...
    if (e.outIdx >= 0) and assigned(AelPrev) and (AelPrev.outIdx >= 0) and
      (abs(AelPrev.xbot - e.x) < tolerance) and SlopesEqual(e, AelPrev) then
    begin
      i := length(fJoins);
      setlength(fJoins, i+1);
      pt := DoublePoint(e.x,e.y);
      fJoins[i].ppt1 := AddPolyPt(AelPrev, pt);
      fJoins[i].idx1 := AelPrev.outIdx;
      fJoins[i].ppt2 := AddPolyPt(e, pt);
      fJoins[i].idx2 := e.outIdx;
    end;
  end;
end;
//------------------------------------------------------------------------------

function TClipper.BubbleSwap(edge: PEdge): PEdge;
var
  i, cnt: integer;
  e: PEdge;
begin
  cnt := 1;
  result := edge.nextInAEL;
  while assigned(result) and (abs(result.xbot - edge.xbot) <= tolerance) do
  begin
    inc(cnt);
    result := Result.nextInAEL;
  end;
  //let e = no edges in a complex intersect (ie >2 edges intersect at same pt).
  //if cnt = no intersection ops between those edges at that intersection
  //then ... when e =1, cnt =0; e =2, cnt =1; e =3, cnt =3; e =4, cnt =6; ...
  //series s (where s = intersections per no edges) ... s = 0,1,3,6,10,15 ...
  //generalising: given i = e-1, and s[0] = 0, then ... cnt = i + s[i-1]
  //example: no. intersect ops required by 4 edges in a complex intersection ...
  //         cnt = 3 + 2 + 1 + 0 = 6 intersection ops
  //nb: parallel edges within intersections will cause unexpected cnt values.
  if cnt > 2 then
  begin
    try
      //create the sort list ...
      fSortedEdges := edge;
      edge.prevInSEL := nil;
      e := edge.nextInAEL;
      for i := 2 to cnt do
      begin
        e.prevInSEL := e.prevInAEL;
        e.prevInSEL.nextInSEL := e;
        if i = cnt then e.nextInSEL := nil;
        e := e.nextInAEL;
      end;

      //fSortedEdges now contains the sort list. Bubble sort this list,
      //processing intersections and dropping the last edge on each pass
      //until the list contains fewer than two edges.
      while assigned(fSortedEdges) and
        assigned(fSortedEdges.nextInSEL) do
      begin
        e := fSortedEdges;
        while assigned(e.nextInSEL) do
        begin
          if (e.nextInSEL.dx > e.dx) then
          begin
            IntersectEdges(e, e.nextInSEL,
              DoublePoint(e.xbot,e.ybot), [ipLeft,ipRight]);
            SwapPositionsInAEL(e, e.nextInSEL);
            SwapPositionsInSEL(e, e.nextInSEL);
          end else
            e := e.nextInSEL;
        end;
        e.prevInSEL.nextInSEL := nil; //removes 'e' from SEL
      end;

    finally
      fSortedEdges := nil;
    end;
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.ProcessEdgesAtTopOfScanbeam(const topY: double);
var
  i: integer;
  e, ePrior: PEdge;
  pp: PPolyPt;
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
    if IsMaxima(e, topY) and not IsHorizontal(GetMaximaPair(e)) then
    begin
      //'e' might be removed from AEL, as may any following edges so ...
      ePrior := e.prevInAEL;
      DoMaxima(e, topY);
      if not assigned(ePrior) then
        e := fActiveEdges else
        e := ePrior.nextInAEL;
    end else
    begin
      //2. promote horizontal edges, otherwise update xbot and ybot ...
      if IsIntermediate(e, topY) and IsHorizontal(e.nextInLML) then
      begin
        if (e.outIdx >= 0) then
        begin
          pp := AddPolyPt(e, DoublePoint(e.xtop, e.ytop));

          //add the polyPt to a list that later checks for overlaps with
          //contributing horizontal minima since they'll need joining.
          i := length(fCurrentHorizontals);
          setlength(fCurrentHorizontals, i+1);
          fCurrentHorizontals[i].ppt1 := pp;
          fCurrentHorizontals[i].idx1 := e.outIdx;
        end;
        //very rarely an edge just below a horizontal edge in a contour
        //intersects with another edge at the very top of a scanbeam.
        //If this happens that intersection must be managed first ...
        if assigned(e.prevInAEL) and (e.prevInAEL.xbot > e.xtop + tolerance) then
        begin
          IntersectEdges(e.prevInAEL, e,
            DoublePoint(e.prevInAEL.xbot,e.prevInAEL.ybot), [ipLeft,ipRight]);
          SwapPositionsInAEL(e.prevInAEL, e);
          UpdateEdgeIntoAEL(e);
          AddEdgeToSEL(e);
          e := e.nextInAEL;
          UpdateEdgeIntoAEL(e);
          AddEdgeToSEL(e);
        end
        else if assigned(e.nextInAEL) and
          (e.xtop > topX(e.nextInAEL, topY) + tolerance) then
        begin
          e.nextInAEL.xbot := TopX(e.nextInAEL, topY);
          e.nextInAEL.ybot := topY;
          IntersectEdges(e, e.nextInAEL,
            DoublePoint(e.nextInAEL.xbot,e.nextInAEL.ybot), [ipLeft,ipRight]);
          SwapPositionsInAEL(e, e.nextInAEL);
          UpdateEdgeIntoAEL(e);
          AddEdgeToSEL(e);
        end else
        begin
          UpdateEdgeIntoAEL(e);
          AddEdgeToSEL(e);
        end;
      end else
      begin
        //this just simplifies horizontal processing ...
        e.xbot := TopX(e, topY);
        e.ybot := topY;
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
      if (e.outIdx >= 0) then AddPolyPt(e, DoublePoint(e.xtop, e.ytop));
      UpdateEdgeIntoAEL(e);
    end;
    e := e.nextInAEL;
  end;

  //5. Process (non-horizontal) intersections at the top of the scanbeam ...
  e := fActiveEdges;
  if assigned(e) and (e.nextInAEL = nil) then
    raise Exception.Create(rsProcessEdgesAtTopOfScanbeam);
  while assigned(e) do
  begin
    if not assigned(e.nextInAEL) then break;
    if e.nextInAEL.xbot < e.xbot - precision then
      raise Exception.Create(rsProcessEdgesAtTopOfScanbeam);
    if e.nextInAEL.xbot > e.xbot + tolerance then
      e := e.nextInAEL else
      e := BubbleSwap(e);
  end;
end;
//------------------------------------------------------------------------------

procedure TClipper.AddLocalMaxPoly(e1, e2: PEdge; const pt: TDoublePoint);
begin
  AddPolyPt(e1, pt);
  if ShareSamePoly(e1, e2) then
  begin
    e1.outIdx := -1;
    e2.outIdx := -1;
  end else
    AppendPolygon(e1, e2);
end;
//------------------------------------------------------------------------------

procedure TClipper.AddLocalMinPoly(e1, e2: PEdge; const pt: TDoublePoint);
var
  pp: PPolyPt;
  e: PEdge;
  isAHole: boolean;
begin
  AddPolyPt(e1, pt);

  if IsHorizontal(e2) or (e1.dx > e2.dx) then
  begin
    e1.side := esLeft;
    e2.side := esRight;
  end else
  begin
    e1.side := esRight;
    e2.side := esLeft;
  end;

  if fForceOrientation then
  begin
    pp := PPolyPt(fPolyPtList[e1.outIdx]);
    isAHole := false;
    e := fActiveEdges;
    while assigned(e) do
    begin
      if (e.outIdx >= 0) and (TopX(e,pp.pt.Y) < pp.pt.X - precision) then
        isAHole := not isAHole;
      e := e.nextInAEL;
    end;
    if isAHole then pp.isHole := sTrue else pp.isHole := sFalse;
  end;
  e2.outIdx := e1.outIdx;
end;
//------------------------------------------------------------------------------

procedure TClipper.AppendPolygon(e1, e2: PEdge);
var
  p1_lft, p1_rt, p2_lft, p2_rt: PPolyPt;
  side: TEdgeSide;
  e: PEdge;
  ObsoleteIdx: integer;
begin
  if (e1.outIdx < 0) or (e2.outIdx < 0) then
    raise Exception.Create(rsAppendPolygon);

  //get the start and ends of both output polygons ...
  p1_lft := PPolyPt(fPolyPtList[e1.outIdx]);
  p1_rt := p1_lft.prev;
  p2_lft := PPolyPt(fPolyPtList[e2.outIdx]);
  p2_rt := p2_lft.prev;

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
    side := esLeft;
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
    side := esRight;
  end;

  ObsoleteIdx := e2.outIdx;
  e2.outIdx := -1;
  e := fActiveEdges;
  while assigned(e) do
  begin
    if (e.outIdx = ObsoleteIdx) then
    begin
      e.outIdx := e1.outIdx;
      e.side := side;
      break;
    end;
    e := e.nextInAEL;
  end;
  e1.outIdx := -1;
  fPolyPtList[ObsoleteIdx] := nil;
end;
//------------------------------------------------------------------------------

procedure TClipper.FixupJoins(oldIdx, newIdx: integer);
var
  i: integer;
begin
  for i := 0 to high(fJoins) do
    if (fJoins[i].idx1 = oldIdx) then fJoins[i].idx1 := newIdx
    else if (fJoins[i].idx2 = oldIdx) then fJoins[i].idx2 := newIdx;
end;
//------------------------------------------------------------------------------

procedure TClipper.JoinCommonEdges;
var
  i: integer;
  p1, p2, pp1, pp2: PPolyPt;

  function SlopesEqual(const pt1a, pt1b, pt2a, pt2b: TDoublePoint): boolean;
  begin
    result := abs((pt1b.Y - pt1a.Y)*(pt2b.X - pt2a.X) -
      (pt1b.X - pt1a.X)*(pt2b.Y - pt2a.Y)) < slope_precision;
  end;

  function insertPolyPt(afterPolyPt: PPolyPt; pt: TDoublePoint): PPolyPt;
  begin
    new(result);
    result.pt := pt;
    result.prev := afterPolyPt;
    result.next := afterPolyPt.next;
    afterPolyPt.next.prev := result;
    afterPolyPt.next := Result;
    result.isHole := sUndefined;
  end;

begin
  for i := 0 to high(fJoins) do
  begin
    //check that the lines haven't already been joined ...
    if not assigned(fPolyPtList[fJoins[i].idx1]) or
      not assigned(fPolyPtList[fJoins[i].idx2]) then continue;

    p1 := fJoins[i].ppt1;
    p2 := fJoins[i].ppt2;

    if fJoins[i].idx1 = fJoins[i].idx2 then
    begin
      if p2 = p1 then continue;
      //if there are overlapping colinear edges in the same output polygon
      //then the output polygon should be split into 2 polygons ...
      pp1 := insertPolyPt(p1, p1.pt);
      pp2 := insertPolyPt(p2, p2.pt);
      pp1.prev := p2;
      p2.next := pp1;
      p1.next := pp2;
      pp2.prev := p1;
      fPolyPtList[fJoins[i].idx1] := nil;
      fPolyPtList.Add(p1);
      fPolyPtList.Add(p2);
      continue;
    end;

    if (p1.next.pt.Y < p1.pt.Y) and (p2.next.pt.Y < p2.pt.Y) and
      SlopesEqual(p1.pt, p1.next.pt, p2.pt, p2.next.pt) then
    begin
      pp1 := insertPolyPt(p1, p1.pt);
      pp2 := insertPolyPt(p2, p2.pt);
      ReversePolyPtLinks(p2);
      pp1.prev := pp2;
      pp2.next := pp1;
      p1.next := p2;
      p2.prev := p1;
    end
    else if (p1.next.pt.Y <= p1.pt.Y) and (p2.prev.pt.Y <= p2.pt.Y) and
      SlopesEqual(p1.pt, p1.next.pt, p2.pt, p2.prev.pt) then
    begin
      pp1 := insertPolyPt(p1, p1.pt);
      pp2 := insertPolyPt(p2.prev, p2.pt);
      p1.next := p2;
      p2.prev := p1;
      pp2.next := pp1;
      pp1.prev := pp2;
    end
    else if (p1.prev.pt.Y <= p1.pt.Y) and (p2.next.pt.Y <= p2.pt.Y) and
      SlopesEqual(p1.pt, p1.prev.pt, p2.pt, p2.next.pt) then
    begin
      pp1 := insertPolyPt(p1.prev, p1.pt);
      pp2 := insertPolyPt(p2, p2.pt);
      pp1.next := pp2;
      pp2.prev := pp1;
      p1.prev := p2;
      p2.next := p1;
    end
    else if (p1.prev.pt.Y < p1.pt.Y) and (p2.prev.pt.Y < p2.pt.Y) and
      SlopesEqual(p1.pt, p1.prev.pt, p2.pt, p2.prev.pt) then
    begin
      pp1 := insertPolyPt(p1.prev, p1.pt);
      pp2 := insertPolyPt(p2.prev, p2.pt);
      ReversePolyPtLinks(p2);
      p1.prev := p2;
      p2.next := p1;
      pp1.next := pp2;
      pp2.prev := pp1;
    end
    else
      continue;
    fPolyPtList[fJoins[i].idx2] := nil;
    FixupJoins(fJoins[i].idx2, fJoins[i].idx1);
  end;
end;
//------------------------------------------------------------------------------

end.
