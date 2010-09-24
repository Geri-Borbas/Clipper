/*******************************************************************************
*                                                                              *
* Author    :  Angus Johnson                                                   *
* Version   :  2.52                                                            *
* Date      :  18 September 2010                                               *
* Copyright :  Angus Johnson                                                   *
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
*******************************************************************************/

/*******************************************************************************
*                                                                              *
* This is a translation of my Delphi clipper code and is the very first stuff  *
* I've written in C++ (or C). My apologies if the coding style is unorthodox.  *
* Please see the accompanying Delphi Clipper library (clipper.pas) for a more  *
* detailed explanation of the code algorithms.                                 *
*                                                                              *
*******************************************************************************/

#include "clipper.hpp"
#include <cmath>
#include <vector>
#include <cstring>
#include <algorithm>

namespace clipper {

//infinite: simply used to define inverse slope (dx/dy) of horizontal edges
static double const infinite = -3.4E+38;
static double const almost_infinite = -3.39E+38;

//tolerance: is needed because vertices are floating point values and any
//comparison of floating point values requires a degree of tolerance. Ideally
//this value should vary depending on how big (or small) the supplied polygon
//coordinate values are. If coordinate values are greater than 1.0E+5
//(ie 100,000+) then tolerance should be adjusted up (since the significand
//of type double is 15 decimal places). However, for the vast majority
//of uses ... tolerance = 1.0e-10 will be just fine.
static double const tolerance = 1.0E-10;
static double const minimal_tolerance = 1.0E-14;
//precision: defines when adjacent vertices will be considered duplicates
//and hence ignored. This circumvents edges having indeterminate slope.
static double const precision = 1.0E-6;
static double const slope_precision = 1.0E-3;

static const unsigned ipLeft = 1;
static const unsigned ipRight = 2;
typedef enum { dRightToLeft, dLeftToRight } TDirection;

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------

TDoublePoint DoublePoint(const double &X, const double &Y)
{
  TDoublePoint p;
  p.X = X;
  p.Y = Y;
  return p;
}
//------------------------------------------------------------------------------

bool PointsEqual( const TDoublePoint &pt1, const TDoublePoint &pt2)
{
  return ( std::fabs( pt1.X - pt2.X ) < precision + tolerance ) &&
  ( std::fabs( (pt1.Y - pt2.Y) ) < precision + tolerance );
}
//------------------------------------------------------------------------------

bool PointsEqual( const double &pt1x, const double &pt1y,
  const double &pt2x, const double &pt2y)
{
  return ( std::fabs( pt1x - pt2x ) < precision + tolerance ) &&
  ( std::fabs( (pt1y - pt2y) ) < precision + tolerance );
}
//------------------------------------------------------------------------------

void DisposePolyPts(TPolyPt *&pp)
{
  if (pp == 0) return;
  TPolyPt *tmpPp;
  pp->prev->next = 0;
  while( pp )
  {
  tmpPp = pp;
  pp = pp->next;
  delete tmpPp ;
  }
}
//------------------------------------------------------------------------------

void Clipper::DisposeAllPolyPts(){
  for (unsigned i = 0; i < m_PolyPts.size(); ++i)
    DisposePolyPts(m_PolyPts[i]);
  m_PolyPts.clear();
}
//------------------------------------------------------------------------------

void ReversePolyPtLinks(TPolyPt &pp)
{
  TPolyPt *pp1, *pp2;
  pp1 = &pp;
  do {
  pp2 = pp1->next;
  pp1->next = pp1->prev;
  pp1->prev = pp2;
  pp1 = pp2;
  } while( pp1 != &pp );
}
//------------------------------------------------------------------------------

void SetDx(TEdge &e)
{
  double dx = std::fabs(e.x - e.next->x);
  double dy = std::fabs(e.y - e.next->y);
  //Very short, nearly horizontal edges can cause problems by very
  //inaccurately determining intermediate X values - see TopX().
  //Therefore treat very short, nearly horizontal edges as horizontal too ...
  if ( (dx < 0.1 && dy *10 < dx) || dy < slope_precision ) {
    e.dx = infinite;
    if (e.y != e.next->y) e.y = e.next->y;
  }
  else e.dx =
    (e.x - e.next->x)/(e.y - e.next->y);
}
//------------------------------------------------------------------------------

bool IsHorizontal(const TEdge &e)
{
  return &e  && ( e.dx < almost_infinite );
}
//------------------------------------------------------------------------------

void SwapSides(TEdge &edge1, TEdge &edge2)
{
  TEdgeSide side =  edge1.side;
  edge1.side = edge2.side;
  edge2.side = side;
}
//------------------------------------------------------------------------------

void SwapPolyIndexes(TEdge &edge1, TEdge &edge2)
{
  int outIdx =  edge1.outIdx;
  edge1.outIdx = edge2.outIdx;
  edge2.outIdx = outIdx;
}
//------------------------------------------------------------------------------

double TopX(TEdge *edge, const double &currentY)
{
  if(  currentY == edge->ytop ) return edge->xtop;
  return edge->x + edge->dx *( currentY - edge->y );
}
//------------------------------------------------------------------------------

bool EdgesShareSamePoly(TEdge &e1, TEdge &e2)
{
  return &e1  && &e2  && ( e1.outIdx == e2.outIdx );
}
//------------------------------------------------------------------------------

bool SlopesEqual(TEdge &e1, TEdge &e2)
{
  if (IsHorizontal(e1)) return IsHorizontal(e2);
  if (IsHorizontal(e2)) return false;
  return std::fabs((e1.ytop - e1.y)*(e2.xtop - e2.x) -
      (e1.xtop - e1.x)*(e2.ytop - e2.y)) < slope_precision;
}
//------------------------------------------------------------------------------

bool IntersectPoint(TEdge &edge1, TEdge &edge2, TDoublePoint &ip)
{
  double b1, b2;
  if(  edge1.dx == 0 )
  {
    ip.X = edge1.x;
    b2 = edge2.y - edge2.x/edge2.dx;
    ip.Y = ip.X/edge2.dx + b2;
  }
  else if(  edge2.dx == 0 )
  {
    ip.X = edge2.x;
    b1 = edge1.y - edge1.x/edge1.dx;
    ip.Y = ip.X/edge1.dx + b1;
  } else
  {
    b1 = edge1.x - edge1.y *edge1.dx;
    b2 = edge2.x - edge2.y *edge2.dx;
    ip.Y = (b2-b1)/(edge1.dx - edge2.dx);
    ip.X = edge1.dx * ip.Y + b1;
  }
  return (ip.Y > edge1.ytop + tolerance) && (ip.Y > edge2.ytop + tolerance);
}
//------------------------------------------------------------------------------

TDoublePoint GetUnitNormal( const TDoublePoint &pt1, const TDoublePoint &pt2)
{
  double dx = ( pt2.X - pt1.X );
  double dy = ( pt2.Y - pt1.Y );
  if(  ( dx == 0 ) && ( dy == 0 ) ) return DoublePoint( 0, 0 );

  //double f = 1 *1.0/ hypot( dx , dy );
  double f = 1 *1.0/ std::hypot( dx , dy );
  dx = dx * f;
  dy = dy * f;
  return DoublePoint(dy, -dx);
}
//------------------------------------------------------------------------------

bool ValidateOrientation(TPolyPt *pt)
{
  //compares the orientation (clockwise vs counter-clockwise) of a *simple*
  //polygon with its hole status (ie test whether an inner or outer polygon).
  //nb: complex polygons have indeterminate orientations.
  TPolyPt* bottomPt = pt;
  TPolyPt* ptStart = pt;
  pt = pt->next;
  while(  ( pt != ptStart ) )
  {
  if(  ( pt->pt.Y > bottomPt->pt.Y ) ||
    ( ( pt->pt.Y == bottomPt->pt.Y ) && ( pt->pt.X > bottomPt->pt.X ) ) )
    bottomPt = pt;
  pt = pt->next;
  }

  TPolyPt* ptPrev = bottomPt->prev;
  TPolyPt* ptNext = bottomPt->next;
  TDoublePoint N1 = GetUnitNormal( ptPrev->pt , bottomPt->pt );
  TDoublePoint N2 = GetUnitNormal( bottomPt->pt , ptNext->pt );
  //(N1.X * N2.Y - N2.X * N1.Y) == unit normal "cross product" == sin(angle)
  bool IsClockwise = ( N1.X * N2.Y - N2.X * N1.Y ) > 0; //ie angle > 180deg.

  while (bottomPt->isHole == sUndefined &&
    bottomPt->next->pt.Y >= bottomPt->pt.Y) bottomPt = bottomPt->next;
  while (bottomPt->isHole == sUndefined &&
    bottomPt->prev->pt.Y >= bottomPt->pt.Y) bottomPt = bottomPt->prev;
  return (IsClockwise != (bottomPt->isHole == sTrue));
}
//------------------------------------------------------------------------------

void InitEdge(TEdge *e, TEdge *eNext, TEdge *ePrev, const TDoublePoint &pt)
{
  std::memset( e, 0, sizeof( TEdge ));
  e->x = pt.X;
  e->y = pt.Y;
  e->next = eNext;
  e->prev = ePrev;
  SetDx(*e);
}
//------------------------------------------------------------------------------

void ReInitEdge(TEdge *e, const double &nextX,
  const double &nextY, TPolyType polyType)
{
  if ( e->y > nextY )
  {
    e->xbot = e->x;
    e->ybot = e->y;
    e->xtop = nextX;
    e->ytop = nextY;
    e->nextAtTop = true;
  } else {
    e->xbot = nextX;
    e->ybot = nextY;
    e->xtop = e->x;
    e->ytop = e->y;
    e->x = e->xbot;
    e->y = e->ybot;
    e->nextAtTop = false;
  }
  e->polyType = polyType;
  e->outIdx = -1;
}
//------------------------------------------------------------------------------

bool SlopesEqualInternal(TEdge &e1, TEdge &e2)
{
  if (IsHorizontal(e1)) return IsHorizontal(e2);
  if (IsHorizontal(e2)) return false;
  return std::fabs((e1.y - e1.next->y) *
      (e2.x - e2.next->x) -
      (e1.x - e1.next->x) *
      (e2.y - e2.next->y)) < slope_precision;
}
//------------------------------------------------------------------------------

bool FixupForDupsAndColinear( TEdge *&e, TEdge *edges)
{
  bool result = false;
  while ( e->next != e->prev &&
    (PointsEqual(e->prev->x, e->prev->y, e->x, e->y) ||
    SlopesEqualInternal(*e->prev, *e)) )
  {
    result = true;
    //remove 'e' from the double-linked-list ...
    if ( e == edges )
    {
      //move the content of e.next to e before removing e.next from DLL ...
      e->x = e->next->x;
      e->y = e->next->y;
      e->next->next->prev = e;
      e->next = e->next->next;
    } else
    {
      //remove 'e' from the loop ...
      e->prev->next = e->next;
      e->next->prev = e->prev;
      e = e->prev; //ie get back into the loop
    }
    SetDx(*e->prev);
    SetDx(*e);
  }
  return result;
}
//------------------------------------------------------------------------------

void SwapX(TEdge &e)
{
  //swap horizontal edges' top and bottom x's so they follow the natural
  //progression of the bounds - ie so their xbots will align with the
  //adjoining lower edge. [Helpful in the ProcessHorizontal() method.]
  e.xbot = e.xtop;
  e.xtop = e.x;
  e.x = e.xbot;
  e.nextAtTop = !e.nextAtTop; //but really redundant for horizontals
}
//------------------------------------------------------------------------------

TEdge *BuildBound(TEdge *e,  TEdgeSide s, bool buildForward)
{
  TEdge *eNext; TEdge *eNextNext;
  do {
    e->side = s;
    if(  buildForward ) eNext = e->next;
    else eNext = e->prev;
    if(  IsHorizontal( *eNext ) )
    {
      if(  buildForward ) eNextNext = eNext->next;
      else eNextNext = eNext->prev;
      if(  ( eNextNext->ytop < eNext->ytop ) )
      {
        //eNext is an intermediate horizontal.
        //All horizontals have their xbot aligned with the adjoining lower edge
        if(  eNext->xbot != e->xtop ) SwapX( *eNext );
      } else if(  buildForward )
      {
        //to avoid duplicating top bounds, stop if this is a
        //horizontal edge at the top of a going forward bound ...
        e->nextInLML = 0;
        return eNext;
      }
      else if(  eNext->xbot != e->xtop ) SwapX( *eNext );
    }
    else if(  std::fabs(e->ytop - eNext->ytop) < tolerance )
    {
      e->nextInLML = 0;
      return eNext;
    }
    e->nextInLML = eNext;
    e = eNext;
  } while( true );
}

//------------------------------------------------------------------------------
// ClipperBase methods ...
//------------------------------------------------------------------------------

ClipperBase::ClipperBase() //constructor
{
  m_localMinimaList = 0;
  m_CurrentLM = 0;
  m_edges.reserve(32);
}
//------------------------------------------------------------------------------

ClipperBase::~ClipperBase() //destructor
{
  Clear();
}
//------------------------------------------------------------------------------

void ClipperBase::InsertLocalMinima(TLocalMinima *newLm)
{
  if( ! m_localMinimaList )
  {
    m_localMinimaList = newLm;
  }
  else if( newLm->Y >= m_localMinimaList->Y )
  {
    newLm->nextLm = m_localMinimaList;
    m_localMinimaList = newLm;
  } else
  {
    TLocalMinima* tmpLm = m_localMinimaList;
    while( tmpLm->nextLm  && ( newLm->Y < tmpLm->nextLm->Y ) )
    tmpLm = tmpLm->nextLm;
    newLm->nextLm = tmpLm->nextLm;
    tmpLm->nextLm = newLm;
  }
}
//------------------------------------------------------------------------------

TEdge *ClipperBase::AddBoundsToLML(TEdge *e)
{
  //Starting at the top of one bound we progress to the bottom where there's
  //a local minima. We then go to the top of the next bound. These two bounds
  //form the left and right (or right and left) bounds of the local minima.
  e->nextInLML = 0;
  e = e->next;
  for (;;)
  {
    if ( IsHorizontal(*e) )
    {
      //nb: proceed through horizontals when approaching from their right,
      //    but break on horizontal minima if approaching from their left.
      //    This ensures 'local minima' are always on the left of horizontals.
      if (e->next->ytop < e->ytop && e->next->xbot > e->prev->xbot) break;
      if (e->xtop != e->prev->xbot) SwapX( *e );
      e->nextInLML = e->prev;
    }
    else if (e->ybot == e->prev->ybot) break;
    else e->nextInLML = e->prev;
    e = e->next;
  }

  //e and e.prev are now at a local minima ...
  TLocalMinima* newLm = new TLocalMinima;
  newLm->nextLm = 0;
  newLm->Y = e->prev->ybot;

  if ( IsHorizontal(*e) ) //horizontal edges never start a left bound
  {
    if (e->xbot != e->prev->xbot) SwapX(*e);
    newLm->leftBound = e->prev;
    newLm->rightBound = e;
  } else if (e->dx < e->prev->dx)
  {
    newLm->leftBound = e->prev;
    newLm->rightBound = e;
  } else
  {
    newLm->leftBound = e;
    newLm->rightBound = e->prev;
  }
  newLm->leftBound->side = esLeft;
  newLm->rightBound->side = esRight;
  InsertLocalMinima( newLm );

  for (;;)
  {
    if ( e->next->ytop == e->ytop && !IsHorizontal(*e->next) ) break;
    e->nextInLML = e->next;
    e = e->next;
    if ( IsHorizontal(*e) && e->xbot != e->prev->xtop) SwapX(*e);
  }
  return e->next;
}
//------------------------------------------------------------------------------

TDoublePoint RoundToTolerance(const TDoublePoint &pt){
  TDoublePoint result;
  result.X = (pt.X >= 0.0) ?
    (std::floor( pt.X/precision + 0.5 ) * precision):
    (std::ceil ( pt.X/precision + 0.5 ) * precision);
  result.Y = (pt.Y >= 0.0) ?
    (std::floor( pt.Y/precision + 0.5 ) * precision):
    (std::ceil ( pt.Y/precision + 0.5 ) * precision);
  return result;
}
//------------------------------------------------------------------------------

void ClipperBase::AddPolygon( const TPolygon &pg, TPolyType polyType)
{
  int highI = pg.size() -1;
  TPolygon p(highI + 1);
  for (int i = 0; i <= highI; ++i) p[i] = RoundToTolerance(pg[i]);
  while( (highI > 1) && PointsEqual(p[0] , p[highI]) ) highI--;
  if(  highI < 2 ) return;

  //make sure this is still a sensible polygon (ie with at least one minima) ...
  int i = 1;
  while(  i <= highI && std::fabs(p[i].Y - p[0].Y) < precision ) i++;
  if( i > highI ) return;

  //create a new edge array ...
  TEdge *edges = new TEdge [highI +1];
  m_edges.push_back(edges);

  //convert 'edges' to a double-linked-list and initialize a few of the vars ...
  edges[0].x = p[0].X;
  edges[0].y = p[0].Y;
  InitEdge(&edges[highI], &edges[0], &edges[highI-1], p[highI]);
  for (i = highI-1; i > 0; --i)
    InitEdge(&edges[i], &edges[i+1], &edges[i-1], p[i]);
  InitEdge(&edges[0], &edges[1], &edges[highI], p[0]);

  //fixup by deleting any duplicate points and amalgamating co-linear edges ...
  TEdge* e = edges;
  do {
    FixupForDupsAndColinear(e, edges);
    e = e->next;
  }
  while ( e != edges );
  while  ( FixupForDupsAndColinear(e, edges))
  {
    e = e->prev;
    if ( !FixupForDupsAndColinear(e, edges) ) break;
    e = edges;
  }

  //make sure we still have a valid polygon ...
  if( e->next == e->prev )
  {
    m_edges.pop_back();
    delete [] edges;
    return;
  }

  //now properly re-initialize edges and also find 'eHighest' ...
  e = edges->next;
  TEdge* eHighest = e;
  do {
    ReInitEdge(e, e->next->x, e->next->y, polyType);
    if(  e->ytop < eHighest->ytop ) eHighest = e;
    e = e->next;
  } while( e != edges );

  TDoublePoint nextPt;
  if ( e->next->nextAtTop )
    ReInitEdge(e, e->next->x, e->next->y, polyType); else
    ReInitEdge(e, e->next->xtop, e->next->ytop, polyType);
  if ( e->ytop < eHighest->ytop ) eHighest = e;

  //make sure eHighest is positioned so the following loop works safely ...
  if ( eHighest->nextAtTop ) eHighest = eHighest->next;
  if ( IsHorizontal( *eHighest) ) eHighest = eHighest->next;

  //finally insert each local minima ...
  e = eHighest;
  do {
    e = AddBoundsToLML(e);
  } while( e != eHighest );

}
//------------------------------------------------------------------------------

void ClipperBase::AddPolyPolygon( const TPolyPolygon &ppg, TPolyType polyType)
{
  for (unsigned i = 0; i < ppg.size(); ++i)
  AddPolygon(ppg[i], polyType);
}
//------------------------------------------------------------------------------

void ClipperBase::Clear()
{
  DisposeLocalMinimaList();
  for (unsigned i = 0; i < m_edges.size(); ++i) delete [] m_edges[i];
  m_edges.clear();
}
//------------------------------------------------------------------------------

bool ClipperBase::Reset()
{
  m_CurrentLM = m_localMinimaList;
  if( !m_CurrentLM ) return false; //ie nothing to process

  //reset all edges ...
  TLocalMinima* lm = m_localMinimaList;
  while( lm )
  {
    TEdge* e = lm->leftBound;
    while( e )
    {
      e->xbot = e->x;
      e->ybot = e->y;
      e->side = esLeft;
      e->outIdx = -1;
      e = e->nextInLML;
    }
    e = lm->rightBound;
    while( e )
    {
      e->xbot = e->x;
      e->ybot = e->y;
      e->side = esRight;
      e->outIdx = -1;
      e = e->nextInLML;
    }
    lm = lm->nextLm;
  }
  return true;
}
//------------------------------------------------------------------------------

void ClipperBase::PopLocalMinima()
{
  if( ! m_CurrentLM ) return;
  m_CurrentLM = m_CurrentLM->nextLm;
}
//------------------------------------------------------------------------------

void ClipperBase::DisposeLocalMinimaList()
{
  while( m_localMinimaList )
  {
    TLocalMinima* tmpLm = m_localMinimaList->nextLm;
    delete m_localMinimaList;
    m_localMinimaList = tmpLm;
  }
  m_CurrentLM = 0;
}

//------------------------------------------------------------------------------
// Clipper methods ...
//------------------------------------------------------------------------------

Clipper::Clipper() : ClipperBase() //constructor
{
  m_Scanbeam = 0;
  m_ActiveEdges = 0;
  m_SortedEdges = 0;
  m_IntersectNodes = 0;
  m_ExecuteLocked = false;
  m_ForceOrientation = true;
  m_PolyPts.reserve(32);
};
//------------------------------------------------------------------------------

Clipper::~Clipper() //destructor
{
  DisposeScanbeamList();
  DisposeAllPolyPts();
};
//------------------------------------------------------------------------------

void Clipper::DisposeScanbeamList()
{
  while ( m_Scanbeam ) {
  TScanbeam* sb2 = m_Scanbeam->nextSb;
  delete m_Scanbeam;
  m_Scanbeam = sb2;
  }
}
//------------------------------------------------------------------------------

bool Clipper::InitializeScanbeam()
{
  DisposeScanbeamList();
  if(  !Reset() ) return false;
  //add all the local minima into a fresh fScanbeam list ...
  TLocalMinima* lm = m_CurrentLM;
  while( lm )
  {
  InsertScanbeam( lm->Y );
  InsertScanbeam(lm->leftBound->ytop); //this is necessary too!
  lm = lm->nextLm;
  }
  return true;
}
//------------------------------------------------------------------------------

void Clipper::InsertScanbeam( const double &Y)
{
  if( !m_Scanbeam )
  {
    m_Scanbeam = new TScanbeam;
    m_Scanbeam->nextSb = 0;
    m_Scanbeam->Y = Y;
  }
  else if(  Y > m_Scanbeam->Y )
  {
    TScanbeam* newSb = new TScanbeam;
    newSb->Y = Y;
    newSb->nextSb = m_Scanbeam;
    m_Scanbeam = newSb;
  } else
  {
    TScanbeam* sb2 = m_Scanbeam;
    while( sb2->nextSb  && ( Y <= sb2->nextSb->Y ) ) sb2 = sb2->nextSb;
    if(  Y == sb2->Y ) return; //ie ignores duplicates
    TScanbeam* newSb = new TScanbeam;
    newSb->Y = Y;
    newSb->nextSb = sb2->nextSb;
    sb2->nextSb = newSb;
  }
}
//------------------------------------------------------------------------------

double Clipper::PopScanbeam()
{
  double Y = m_Scanbeam->Y;
  TScanbeam* sb2 = m_Scanbeam;
  m_Scanbeam = m_Scanbeam->nextSb;
  delete sb2;
  return Y;
}
//------------------------------------------------------------------------------

void Clipper::SetWindingDelta(TEdge *edge)
{
  if ( !IsNonZeroFillType(edge) ) edge->windDelta = 1;
  else if ( edge->nextAtTop ) edge->windDelta = 1;
  else edge->windDelta = -1;
}
//------------------------------------------------------------------------------

void Clipper::SetWindingCount(TEdge *edge)
{
  TEdge* e = edge->prevInAEL;
  //find the edge of the same polytype that immediately preceeds 'edge' in AEL
  while ( e  && e->polyType != edge->polyType ) e = e->prevInAEL;
  if ( !e )
  {
    edge->windCnt = edge->windDelta;
    edge->windCnt2 = 0;
    e = m_ActiveEdges; //ie get ready to calc windCnt2
  } else if ( IsNonZeroFillType(edge) )
  {
    //nonZero filling ...
    if ( e->windCnt * e->windDelta < 0 )
    {
      if (std::abs(e->windCnt) > 1)
      {
        if (e->windDelta * edge->windDelta < 0) edge->windCnt = e->windCnt;
        else edge->windCnt = e->windCnt + edge->windDelta;
      } else
        edge->windCnt = e->windCnt + e->windDelta + edge->windDelta;
    } else
    {
      if ( std::abs(e->windCnt) > 1 && e->windDelta * edge->windDelta < 0)
        edge->windCnt = e->windCnt;
      else if ( e->windCnt + edge->windDelta == 0 )
        edge->windCnt = e->windCnt;
      else edge->windCnt = e->windCnt + edge->windDelta;
    }
    edge->windCnt2 = e->windCnt2;
    e = e->nextInAEL; //ie get ready to calc windCnt2
  } else
  {
    //even-odd filling ...
    edge->windCnt = 1;
    edge->windCnt2 = e->windCnt2;
    e = e->nextInAEL; //ie get ready to calc windCnt2
  }

  //update windCnt2 ...
  if ( IsNonZeroAltFillType(edge) )
  {
    //nonZero filling ...
    while ( e != edge )
    {
      edge->windCnt2 += e->windDelta;
      e = e->nextInAEL;
    }
  } else
  {
    //even-odd filling ...
    while ( e != edge )
    {
      edge->windCnt2 = (edge->windCnt2 == 0) ? 1 : 0;
      e = e->nextInAEL;
    }
  }
}
//------------------------------------------------------------------------------

bool Clipper::IsNonZeroFillType(TEdge *edge)
{
  switch (edge->polyType) {
    case ptSubject: return m_SubjFillType == pftNonZero;
  default: return m_ClipFillType == pftNonZero;
  }
}
//------------------------------------------------------------------------------

bool Clipper::IsNonZeroAltFillType(TEdge *edge)
{
  switch (edge->polyType) {
    case ptSubject: return m_ClipFillType == pftNonZero;
  default: return m_SubjFillType == pftNonZero;
  }
}
//------------------------------------------------------------------------------

bool Edge2InsertsBeforeEdge1(TEdge &e1, TEdge &e2)
{
  if( e2.xbot - tolerance > e1.xbot ) return false;
  if( e2.xbot + tolerance < e1.xbot ) return true;
  if( IsHorizontal(e2) ) return false;
  return (e2.dx > e1.dx);
}
//------------------------------------------------------------------------------

void Clipper::InsertEdgeIntoAEL(TEdge *edge)
{
  edge->prevInAEL = 0;
  edge->nextInAEL = 0;
  if(  !m_ActiveEdges )
  {
    m_ActiveEdges = edge;
  }
  else if( Edge2InsertsBeforeEdge1(*m_ActiveEdges, *edge) )
  {
    edge->nextInAEL = m_ActiveEdges;
    m_ActiveEdges->prevInAEL = edge;
    m_ActiveEdges = edge;
  } else
  {
    TEdge* e = m_ActiveEdges;
    while( e->nextInAEL  && !Edge2InsertsBeforeEdge1(*e->nextInAEL , *edge) )
      e = e->nextInAEL;
    edge->nextInAEL = e->nextInAEL;
    if( e->nextInAEL ) e->nextInAEL->prevInAEL = edge;
    edge->prevInAEL = e;
    e->nextInAEL = edge;
  }
}
//----------------------------------------------------------------------

void Clipper::InsertLocalMinimaIntoAEL( const double &botY)
{
  while(  m_CurrentLM  && ( m_CurrentLM->Y == botY ) )
  {
    InsertEdgeIntoAEL( m_CurrentLM->leftBound );
    InsertScanbeam( m_CurrentLM->leftBound->ytop );
    InsertEdgeIntoAEL( m_CurrentLM->rightBound );

    SetWindingDelta( m_CurrentLM->leftBound );
    if ( IsNonZeroFillType(m_CurrentLM->leftBound) )
      m_CurrentLM->rightBound->windDelta =
        -m_CurrentLM->leftBound->windDelta; else
      m_CurrentLM->rightBound->windDelta = 1;

    SetWindingCount( m_CurrentLM->leftBound );
    m_CurrentLM->rightBound->windCnt =
      m_CurrentLM->leftBound->windCnt;
    m_CurrentLM->rightBound->windCnt2 =
      m_CurrentLM->leftBound->windCnt2;

    if(  IsHorizontal( *m_CurrentLM->rightBound ) )
    {
      //nb: only rightbounds can have a horizontal bottom edge
      AddEdgeToSEL( m_CurrentLM->rightBound );
      InsertScanbeam( m_CurrentLM->rightBound->nextInLML->ytop );
    }
    else
      InsertScanbeam( m_CurrentLM->rightBound->ytop );

    TLocalMinima* lm = m_CurrentLM;
    if( IsContributing(lm->leftBound) )
      AddLocalMinPoly( lm->leftBound,
        lm->rightBound, DoublePoint( lm->leftBound->xbot , lm->Y ) );

    if( lm->leftBound->nextInAEL != lm->rightBound )
    {
      TEdge* e = lm->leftBound->nextInAEL;
      TDoublePoint pt = DoublePoint( lm->leftBound->xbot, lm->leftBound->ybot );
      while( e != lm->rightBound )
      {
        if(!e) throw clipperException("AddLocalMinima: missing rightbound!");
        IntersectEdges( lm->rightBound , e , pt , 0); //order important here
        e = e->nextInAEL;
      }
    }
    PopLocalMinima();
  }
}
//------------------------------------------------------------------------------

void Clipper::AddEdgeToSEL(TEdge *edge)
{
  //SEL pointers in PEdge are reused to build a list of horizontal edges.
  //However, we don't need to worry about order with horizontal edge processing.
  if( !m_SortedEdges )
  {
    m_SortedEdges = edge;
    edge->prevInSEL = 0;
    edge->nextInSEL = 0;
  }
  else
  {
    edge->nextInSEL = m_SortedEdges;
    edge->prevInSEL = 0;
    m_SortedEdges->prevInSEL = edge;
    m_SortedEdges = edge;
  }
}
//------------------------------------------------------------------------------

void Clipper::CopyAELToSEL()
{
  TEdge* e = m_ActiveEdges;
  m_SortedEdges = e;
  if (!m_ActiveEdges) return;
  m_SortedEdges->prevInSEL = 0;
  e = e->nextInAEL;
  while ( e )
  {
    e->prevInSEL = e->prevInAEL;
    e->prevInSEL->nextInSEL = e;
    e->nextInSEL = 0;
    e = e->nextInAEL;
  }
}
//------------------------------------------------------------------------------

void Clipper::SwapPositionsInAEL(TEdge *edge1, TEdge *edge2)
{
  if(  !( edge1->nextInAEL ) &&  !( edge1->prevInAEL ) ) return;
  if(  !( edge2->nextInAEL ) &&  !( edge2->prevInAEL ) ) return;

  if(  edge1->nextInAEL == edge2 )
  {
    TEdge* next = edge2->nextInAEL;
    if( next ) next->prevInAEL = edge1;
    TEdge* prev = edge1->prevInAEL;
    if( prev ) prev->nextInAEL = edge2;
    edge2->prevInAEL = prev;
    edge2->nextInAEL = edge1;
    edge1->prevInAEL = edge2;
    edge1->nextInAEL = next;
  }
  else if(  edge2->nextInAEL == edge1 )
  {
    TEdge* next = edge1->nextInAEL;
    if( next ) next->prevInAEL = edge2;
    TEdge* prev = edge2->prevInAEL;
    if( prev ) prev->nextInAEL = edge1;
    edge1->prevInAEL = prev;
    edge1->nextInAEL = edge2;
    edge2->prevInAEL = edge1;
    edge2->nextInAEL = next;
  }
  else
  {
    TEdge* next = edge1->nextInAEL;
    TEdge* prev = edge1->prevInAEL;
    edge1->nextInAEL = edge2->nextInAEL;
    if( edge1->nextInAEL ) edge1->nextInAEL->prevInAEL = edge1;
    edge1->prevInAEL = edge2->prevInAEL;
    if( edge1->prevInAEL ) edge1->prevInAEL->nextInAEL = edge1;
    edge2->nextInAEL = next;
    if( edge2->nextInAEL ) edge2->nextInAEL->prevInAEL = edge2;
    edge2->prevInAEL = prev;
    if( edge2->prevInAEL ) edge2->prevInAEL->nextInAEL = edge2;
  }

  if( !edge1->prevInAEL ) m_ActiveEdges = edge1;
  else if( !edge2->prevInAEL ) m_ActiveEdges = edge2;
}
//------------------------------------------------------------------------------

void Clipper::SwapPositionsInSEL(TEdge *edge1, TEdge *edge2)
{
  if(  !( edge1->nextInSEL ) &&  !( edge1->prevInSEL ) ) return;
  if(  !( edge2->nextInSEL ) &&  !( edge2->prevInSEL ) ) return;

  if(  edge1->nextInSEL == edge2 )
  {
    TEdge* next = edge2->nextInSEL;
    if( next ) next->prevInSEL = edge1;
    TEdge* prev = edge1->prevInSEL;
    if( prev ) prev->nextInSEL = edge2;
    edge2->prevInSEL = prev;
    edge2->nextInSEL = edge1;
    edge1->prevInSEL = edge2;
    edge1->nextInSEL = next;
  }
  else if(  edge2->nextInSEL == edge1 )
  {
    TEdge* next = edge1->nextInSEL;
    if( next ) next->prevInSEL = edge2;
    TEdge* prev = edge2->prevInSEL;
    if( prev ) prev->nextInSEL = edge1;
    edge1->prevInSEL = prev;
    edge1->nextInSEL = edge2;
    edge2->prevInSEL = edge1;
    edge2->nextInSEL = next;
  }
  else
  {
    TEdge* next = edge1->nextInSEL;
    TEdge* prev = edge1->prevInSEL;
    edge1->nextInSEL = edge2->nextInSEL;
    if( edge1->nextInSEL ) edge1->nextInSEL->prevInSEL = edge1;
    edge1->prevInSEL = edge2->prevInSEL;
    if( edge1->prevInSEL ) edge1->prevInSEL->nextInSEL = edge1;
    edge2->nextInSEL = next;
    if( edge2->nextInSEL ) edge2->nextInSEL->prevInSEL = edge2;
    edge2->prevInSEL = prev;
    if( edge2->prevInSEL ) edge2->prevInSEL->nextInSEL = edge2;
  }

  if( !edge1->prevInSEL ) m_SortedEdges = edge1;
  else if( !edge2->prevInSEL ) m_SortedEdges = edge2;
}
//------------------------------------------------------------------------------

TEdge *GetNextInAEL(TEdge *e, TDirection Direction)
{
  if( Direction == dLeftToRight ) return e->nextInAEL;
  else return e->prevInAEL;
}
//------------------------------------------------------------------------------

TEdge *GetPrevInAEL(TEdge *e, TDirection Direction)
{
  if( Direction == dLeftToRight ) return e->prevInAEL;
  else return e->nextInAEL;
}
//------------------------------------------------------------------------------

bool IsMinima(TEdge *e)
{
  return e  && (e->prev->nextInLML != e) && (e->next->nextInLML != e);
}
//------------------------------------------------------------------------------

bool IsMaxima(TEdge *e, const double &Y)
{
  return e  && std::fabs(e->ytop - Y) < tolerance &&  !e->nextInLML;
}
//------------------------------------------------------------------------------

bool IsIntermediate(TEdge *e, const double &Y)
{
  return std::fabs( e->ytop - Y ) < tolerance && e->nextInLML;
}
//------------------------------------------------------------------------------

TEdge *GetMaximaPair(TEdge *e)
{
  if( !IsMaxima(e->next, e->ytop) || (e->next->xtop != e->xtop) )
    return e->prev; else
    return e->next;
}
//------------------------------------------------------------------------------

void Clipper::DoMaxima(TEdge *e, const double &topY)
{
  TEdge* eMaxPair = GetMaximaPair(e);
  double X = e->xtop;
  TEdge* eNext = e->nextInAEL;
  while( eNext != eMaxPair )
  {
    IntersectEdges( e , eNext , DoublePoint( X , topY ), (ipLeft | ipRight) );
    eNext = eNext->nextInAEL;
  }
  if(  ( e->outIdx < 0 ) && ( eMaxPair->outIdx < 0 ) )
  {
    DeleteFromAEL( e );
    DeleteFromAEL( eMaxPair );
  }
  else if(  ( e->outIdx >= 0 ) && ( eMaxPair->outIdx >= 0 ) )
  {
    IntersectEdges( e , eMaxPair , DoublePoint(X, topY), 0 );
  }
  else throw clipperException("DoMaxima error");
}
//------------------------------------------------------------------------------

void Clipper::ProcessHorizontals()
{
  TEdge* horzEdge = m_SortedEdges;
  while( horzEdge )
  {
    DeleteFromSEL( horzEdge );
    ProcessHorizontal( horzEdge );
    horzEdge = m_SortedEdges;
  }
}
//------------------------------------------------------------------------------

bool Clipper::IsTopHorz(TEdge *horzEdge, const double &XPos)
{
  TEdge* e = m_SortedEdges;
  while( e )
  {
    if(  ( XPos >= std::min(e->xbot, e->xtop) ) &&
      ( XPos <= std::max(e->xbot, e->xtop) ) ) return false;
    e = e->nextInSEL;
  }
  return true;
}
//------------------------------------------------------------------------------

void Clipper::ProcessHorizontal(TEdge *horzEdge)
{
  TDirection Direction;
  double horzLeft, horzRight;

  if( horzEdge->xbot < horzEdge->xtop )
  {
    horzLeft = horzEdge->xbot;
    horzRight = horzEdge->xtop;
    Direction = dLeftToRight;
  } else
  {
    horzLeft = horzEdge->xtop;
    horzRight = horzEdge->xbot;
    Direction = dRightToLeft;
  }

  TEdge* eMaxPair;
  if( horzEdge->nextInLML ) eMaxPair = 0;
  else eMaxPair = GetMaximaPair(horzEdge);

  TEdge* e = GetNextInAEL( horzEdge , Direction );
  while( e )
  {
    TEdge* eNext = GetNextInAEL( e, Direction );
    if((e->xbot >= horzLeft - tolerance) && (e->xbot <= horzRight + tolerance))
    {
      //ok, so far it looks like we're still in range of the horizontal edge
      if ( std::fabs(e->xbot - horzEdge->xtop) < tolerance &&
          horzEdge->nextInLML  &&
          (SlopesEqual(*e, *horzEdge->nextInLML) ||
            (e->dx < horzEdge->nextInLML->dx))){
          //we really have gone past the end of intermediate horz edge so quit.
          //nb: More -ve slopes follow more +ve slopes *above* the horizontal.
          break;
      }
      else if( e == eMaxPair )
      {
        //horzEdge is evidently a maxima horizontal and we've arrived at its end.
        if (Direction == dLeftToRight)
          IntersectEdges(horzEdge, e, DoublePoint(e->xbot, horzEdge->ybot), 0);
        else
          IntersectEdges(e, horzEdge, DoublePoint(e->xbot, horzEdge->ybot), 0);
        return;
      }
      else if( IsHorizontal(*e) &&  !IsMinima(e) &&  !(e->xbot > e->xtop) )
      {
        if(  Direction == dLeftToRight )
          IntersectEdges( horzEdge , e , DoublePoint(e->xbot, horzEdge->ybot),
            (IsTopHorz( horzEdge , e->xbot ))? ipLeft : ipLeft | ipRight );
        else
          IntersectEdges( e , horzEdge , DoublePoint(e->xbot, horzEdge->ybot),
            (IsTopHorz( horzEdge , e->xbot ))? ipRight : ipLeft | ipRight );
      }
      else if( Direction == dLeftToRight )
      {
        IntersectEdges( horzEdge , e , DoublePoint(e->xbot, horzEdge->ybot),
          (IsTopHorz( horzEdge , e->xbot ))? ipLeft : ipLeft | ipRight );
      }
      else
      {
        IntersectEdges( e , horzEdge , DoublePoint(e->xbot, horzEdge->ybot),
          (IsTopHorz( horzEdge , e->xbot ))? ipRight : ipLeft | ipRight );
      }
      SwapPositionsInAEL( horzEdge , e );
    }
    else if(  ( Direction == dLeftToRight ) &&
      ( e->xbot > horzRight + tolerance ) &&  !horzEdge->nextInSEL ) break;
    else if(  ( Direction == dRightToLeft ) &&
      ( e->xbot < horzLeft - tolerance ) &&  !horzEdge->nextInSEL  ) break;
    e = eNext;
  } //end while ( e )

  if( horzEdge->nextInLML )
  {
    if( horzEdge->outIdx >= 0 )
      AddPolyPt( horzEdge, DoublePoint(horzEdge->xtop, horzEdge->ytop));
    UpdateEdgeIntoAEL( horzEdge );
  }
  else DeleteFromAEL( horzEdge );
}
//------------------------------------------------------------------------------

void Clipper::AddPolyPt(TEdge *e, const TDoublePoint &pt)
{
  bool ToFront = (e->side == esLeft);
  if(  e->outIdx < 0 )
  {
    TPolyPt* newPolyPt = new TPolyPt;
    newPolyPt->pt = pt;
    m_PolyPts.push_back(newPolyPt);
    newPolyPt->next = newPolyPt;
    newPolyPt->prev = newPolyPt;
    newPolyPt->isHole = sUndefined;
    e->outIdx = m_PolyPts.size()-1;
  } else
  {
    TPolyPt* pp = m_PolyPts[e->outIdx];
    if((ToFront && PointsEqual(pt, pp->pt)) ||
      (!ToFront && PointsEqual(pt, pp->prev->pt))) return;
    TPolyPt* newPolyPt = new TPolyPt;
    newPolyPt->pt = pt;
    newPolyPt->isHole = sUndefined;
    newPolyPt->next = pp;
    newPolyPt->prev = pp->prev;
    newPolyPt->prev->next = newPolyPt;
    pp->prev = newPolyPt;
    if (ToFront) m_PolyPts[e->outIdx] = newPolyPt;
  }
}
//------------------------------------------------------------------------------

void Clipper::ProcessIntersections( const double &topY)
{
  if( !m_ActiveEdges ) return;
  try {
    m_IntersectTolerance = tolerance;
    BuildIntersectList( topY );
    if (!m_IntersectNodes) return;
    //Test pending intersections for errors and, if any are found, redo
    //BuildIntersectList (twice if necessary) with adjusted tolerances.
    //While this adds ~2% extra to processing time, I believe this is justified
    //by further halving of the algorithm's failure rate, though admittedly
    //failures were already extremely rare ...
    if ( !TestIntersections() )
    {
      m_IntersectTolerance = minimal_tolerance;
      DisposeIntersectNodes();
      BuildIntersectList( topY );
      if ( !TestIntersections() )
      {
        m_IntersectTolerance = slope_precision;
        DisposeIntersectNodes();
        BuildIntersectList( topY );
        if (!TestIntersections()) throw clipperException("Intersection error");
      }
    }
    ProcessIntersectList();
  }
  catch(...) {
    m_SortedEdges = 0;
    DisposeIntersectNodes();
    throw clipperException("ProcessIntersections error");
  }
}
//------------------------------------------------------------------------------

void Clipper::DisposeIntersectNodes()
{
  while ( m_IntersectNodes )
  {
    TIntersectNode* iNode = m_IntersectNodes->next;
    delete m_IntersectNodes;
    m_IntersectNodes = iNode;
  }
}
//------------------------------------------------------------------------------

bool E1PrecedesE2inAEL(TEdge *e1, TEdge *e2)
{
  while( e1 ){
    if(  e1 == e2 ) return true;
    else e1 = e1->nextInAEL;
  }
  return false;
}
//------------------------------------------------------------------------------

bool Clipper::Process1Before2(TIntersectNode *Node1, TIntersectNode *Node2)
{
  if ( std::fabs(Node1->pt.Y - Node2->pt.Y) < m_IntersectTolerance )
  {
    if ( std::fabs(Node1->pt.X - Node2->pt.X) > precision )
      return Node1->pt.X < Node2->pt.X;
    //a complex intersection (with more than 2 edges intersecting) ...
    if ( Node1->edge1 == Node2->edge1  || SlopesEqual(*Node1->edge1, *Node2->edge1) )
    {
      if (Node1->edge2 == Node2->edge2 )
        //(N1.E1 & N2.E1 are co-linear) and (N1.E2 == N2.E2)  ...
        return !E1PrecedesE2inAEL(Node1->edge1, Node2->edge1);
      else if ( SlopesEqual(*Node1->edge2, *Node2->edge2) )
        //(N1.E1 == N2.E1) and (N1.E2 & N2.E2 are co-linear) ...
        return E1PrecedesE2inAEL(Node1->edge2, Node2->edge2);
      else if //check if minima **
        ( (std::fabs(Node1->edge2->y - Node1->pt.Y) < slope_precision  ||
        std::fabs(Node2->edge2->y - Node2->pt.Y) < slope_precision ) &&
        (Node1->edge2->next == Node2->edge2 || Node1->edge2->prev == Node2->edge2) )
      {
        if ( Node1->edge1->dx < 0 ) return Node1->edge2->dx > Node2->edge2->dx;
        else return Node1->edge2->dx < Node2->edge2->dx;
      }
      else if ( (Node1->edge2->dx - Node2->edge2->dx) < precision )
        return E1PrecedesE2inAEL(Node1->edge2, Node2->edge2);
      else
        return (Node1->edge2->dx < Node2->edge2->dx);

    } else if ( Node1->edge2 == Node2->edge2  && //check if maxima ***
      (std::fabs(Node1->edge1->ytop - Node1->pt.Y) < slope_precision ||
      std::fabs(Node2->edge1->ytop - Node2->pt.Y) < slope_precision) )
        return (Node1->edge1->dx > Node2->edge1->dx);
    else
      return (Node1->edge1->dx < Node2->edge1->dx);
  } else
      return (Node1->pt.Y > Node2->pt.Y);
  //**a minima that very slightly overlaps an edge can appear like
  //a complex intersection but it's not. (Minima can't have parallel edges.)
  //***a maxima that very slightly overlaps an edge can appear like
  //a complex intersection but it's not. (Maxima can't have parallel edges.)
}
//------------------------------------------------------------------------------

void Clipper::AddIntersectNode(TEdge *e1, TEdge *e2, const TDoublePoint &pt)
{
  TIntersectNode* IntersectNode = new TIntersectNode;
  IntersectNode->edge1 = e1;
  IntersectNode->edge2 = e2;
  IntersectNode->pt = pt;
  IntersectNode->next = 0;
  IntersectNode->prev = 0;
  if( !m_IntersectNodes )
    m_IntersectNodes = IntersectNode;
  else if(  Process1Before2(IntersectNode , m_IntersectNodes) )
  {
    IntersectNode->next = m_IntersectNodes;
    m_IntersectNodes->prev = IntersectNode;
    m_IntersectNodes = IntersectNode;
  }
  else
  {
    TIntersectNode* iNode = m_IntersectNodes;
    while( iNode->next  && Process1Before2(iNode->next, IntersectNode) )
        iNode = iNode->next;
    if( iNode->next ) iNode->next->prev = IntersectNode;
    IntersectNode->next = iNode->next;
    IntersectNode->prev = iNode;
    iNode->next = IntersectNode;
  }
}
//------------------------------------------------------------------------------

void Clipper::BuildIntersectList( const double &topY)
{
  //prepare for sorting ...
  TEdge* e = m_ActiveEdges;
  e->tmpX = TopX( e, topY );
  m_SortedEdges = e;
  m_SortedEdges->prevInSEL = 0;
  e = e->nextInAEL;
  while( e )
  {
    e->prevInSEL = e->prevInAEL;
    e->prevInSEL->nextInSEL = e;
    e->nextInSEL = 0;
    e->tmpX = TopX( e, topY );
    e = e->nextInAEL;
  }

  //bubblesort ...
  bool isModified = true;
  while( isModified && m_SortedEdges )
  {
    isModified = false;
    e = m_SortedEdges;
    while( e->nextInSEL )
    {
      TEdge *eNext = e->nextInSEL;
      TDoublePoint pt;
      if((e->tmpX > eNext->tmpX + tolerance) && IntersectPoint(*e, *eNext, pt))
      {
        AddIntersectNode( e, eNext, pt );
        SwapPositionsInSEL(e, eNext);
        isModified = true;
      }
      else
        e = eNext;
    }
    if( e->prevInSEL ) e->prevInSEL->nextInSEL = 0;
    else break;
  }
  m_SortedEdges = 0;
}
//------------------------------------------------------------------------------

bool Clipper::TestIntersections()
{
  if ( !m_IntersectNodes ) return true;
  //do the test sort using SEL ...
  CopyAELToSEL();
  TIntersectNode* iNode = m_IntersectNodes;
  while ( iNode )
  {
    SwapPositionsInSEL(iNode->edge1, iNode->edge2);
    iNode = iNode->next;
  }
  //now check that tmpXs are in the right order ...
  TEdge* e = m_SortedEdges;
  while ( e->nextInSEL )
  {
    if ( e->nextInSEL->tmpX < e->tmpX - precision ) return false;
    e = e->nextInSEL;
  }
  m_SortedEdges = 0;
  return true;
}
//------------------------------------------------------------------------------

void Clipper::ProcessIntersectList()
{
  while( m_IntersectNodes )
  {
    TIntersectNode* iNode = m_IntersectNodes->next;
    {
      IntersectEdges( m_IntersectNodes->edge1 ,
        m_IntersectNodes->edge2 , m_IntersectNodes->pt, (ipLeft | ipRight) );
      SwapPositionsInAEL( m_IntersectNodes->edge1 , m_IntersectNodes->edge2 );
    }
    delete m_IntersectNodes;
    m_IntersectNodes = iNode;
  }
}
//------------------------------------------------------------------------------

void Clipper::DoEdge1(TEdge *edge1, TEdge *edge2, const TDoublePoint &pt)
{
  AddPolyPt(edge1, pt);
  SwapSides(*edge1, *edge2);
  SwapPolyIndexes(*edge1, *edge2);
}
//----------------------------------------------------------------------

void Clipper::DoEdge2(TEdge *edge1, TEdge *edge2, const TDoublePoint &pt)
{
  AddPolyPt(edge2, pt);
  SwapSides(*edge1, *edge2);
  SwapPolyIndexes(*edge1, *edge2);
}
//----------------------------------------------------------------------

void Clipper::DoBothEdges(TEdge *edge1, TEdge *edge2, const TDoublePoint &pt)
{
  AddPolyPt(edge1, pt);
  AddPolyPt(edge2, pt);
  SwapSides( *edge1 , *edge2 );
  SwapPolyIndexes( *edge1 , *edge2 );
}
//----------------------------------------------------------------------

void Clipper::IntersectEdges(TEdge *e1, TEdge *e2,
     const TDoublePoint &pt, TIntersectProtects protects)
{
  bool e1stops = !(ipLeft & protects) &&  !e1->nextInLML &&
    ( std::fabs( e1->xtop - pt.X ) < tolerance ) && //nb: not precision
    ( std::fabs( e1->ytop - pt.Y ) < precision );
  bool e2stops = !(ipRight & protects) &&  !e2->nextInLML &&
    ( std::fabs( e2->xtop - pt.X ) < tolerance ) && //nb: not precision
    ( std::fabs( e2->ytop - pt.Y ) < precision );
  bool e1Contributing = ( e1->outIdx >= 0 );
  bool e2contributing = ( e2->outIdx >= 0 );

  //update winding counts ...
  if ( e1->polyType == e2->polyType )
  {
    if ( IsNonZeroFillType(e1) )
    {
      if (e1->windCnt + e2->windDelta == 0 ) e1->windCnt = -e1->windCnt;
      else e1->windCnt += e2->windDelta;
      if ( e2->windCnt - e1->windDelta == 0 ) e2->windCnt = -e2->windCnt;
      else e2->windCnt -= e1->windDelta;
    } else
    {
      int oldE1WindCnt = e1->windCnt;
      e1->windCnt = e2->windCnt;
      e2->windCnt = oldE1WindCnt;
    }
  } else
  {
    if ( IsNonZeroFillType(e2) ) e1->windCnt2 += e2->windDelta;
    else e1->windCnt2 = ( e1->windCnt2 == 0 ) ? 1 : 0;
    if ( IsNonZeroFillType(e1) ) e2->windCnt2 -= e1->windDelta;
    else e2->windCnt2 = ( e2->windCnt2 == 0 ) ? 1 : 0;
  }

  if ( e1Contributing && e2contributing )
  {
    if ( e1stops || e2stops || std::abs(e1->windCnt) > 1 ||
      std::abs(e2->windCnt) > 1 ||
      (e1->polyType != e2->polyType && m_ClipType != ctXor) )
        AddLocalMaxPoly(e1, e2, pt); else
        DoBothEdges( e1, e2, pt );
  }
  else if ( e1Contributing )
  {
    switch( m_ClipType ) {
      case ctIntersection:
        if ( (e2->polyType == ptSubject || e2->windCnt2 != 0) &&
           std::abs(e2->windCnt) < 2 ) DoEdge1( e1, e2, pt);
        break;
      default:
        if ( std::abs(e2->windCnt) < 2 ) DoEdge1(e1, e2, pt);
    }
  }
  else if ( e2contributing )
  {
    switch( m_ClipType ) {
      case ctIntersection:
        if ( (e1->polyType == ptSubject || e1->windCnt2 != 0) &&
          std::abs(e1->windCnt) < 2 ) DoEdge2( e1, e2, pt );
        break;
      default:
        if (std::abs(e1->windCnt) < 2) DoEdge2( e1, e2, pt );
    }
  } else
  {
    //neither edge is currently contributing ...
    if ( std::abs(e1->windCnt) > 1 && std::abs(e2->windCnt) > 1 ) ;// do nothing
    else if ( e1->polyType != e2->polyType && !e1stops && !e2stops &&
      std::abs(e1->windCnt) < 2 && std::abs(e2->windCnt) < 2 )
        AddLocalMinPoly(e1, e2, pt);
    else if ( std::abs(e1->windCnt) == 1 && std::abs(e2->windCnt) == 1 )
      switch( m_ClipType ) {
        case ctIntersection:
          if ( std::abs(e1->windCnt2) > 0 && std::abs(e2->windCnt2) > 0 )
            AddLocalMinPoly(e1, e2, pt);
          break;
        case ctUnion:
          if ( e1->windCnt2 == 0 && e2->windCnt2 == 0 )
            AddLocalMinPoly(e1, e2, pt);
          break;
        case ctDifference:
          if ( (e1->polyType == ptClip && e2->polyType == ptClip &&
            e1->windCnt2 != 0 && e2->windCnt2 != 0) ||
            (e1->polyType == ptSubject && e2->polyType == ptSubject &&
            e1->windCnt2 == 0 && e2->windCnt2 == 0) )
              AddLocalMinPoly(e1, e2, pt);
          break;
        case ctXor:
          AddLocalMinPoly(e1, e2, pt);
      }
    else if ( std::abs(e1->windCnt) < 2 && std::abs(e2->windCnt) < 2 )
      SwapSides( *e1, *e2 );
  }

  if(  (e1stops != e2stops) &&
    ( (e1stops && (e1->outIdx >= 0)) || (e2stops && (e2->outIdx >= 0)) ) )
  {
    SwapSides( *e1, *e2 );
    SwapPolyIndexes( *e1, *e2 );
  }

  //finally, delete any non-contributing maxima edges  ...
  if( e1stops ) DeleteFromAEL( e1 );
  if( e2stops ) DeleteFromAEL( e2 );
}
//------------------------------------------------------------------------------

void Clipper::DeleteFromAEL(TEdge *e)
{
  TEdge* AelPrev = e->prevInAEL;
  TEdge* AelNext = e->nextInAEL;
  if(  !AelPrev &&  !AelNext && (e != m_ActiveEdges) ) return; //already deleted
  if( AelPrev ) AelPrev->nextInAEL = AelNext;
  else m_ActiveEdges = AelNext;
  if( AelNext ) AelNext->prevInAEL = AelPrev;
  e->nextInAEL = 0;
  e->prevInAEL = 0;
}
//------------------------------------------------------------------------------

void Clipper::DeleteFromSEL(TEdge *e)
{
  TEdge* SelPrev = e->prevInSEL;
  TEdge* SelNext = e->nextInSEL;
  if(  !SelPrev &&  !SelNext && (e != m_SortedEdges) ) return; //already deleted
  if( SelPrev ) SelPrev->nextInSEL = SelNext;
  else m_SortedEdges = SelNext;
  if( SelNext ) SelNext->prevInSEL = SelPrev;
  e->nextInSEL = 0;
  e->prevInSEL = 0;
}
//------------------------------------------------------------------------------

void Clipper::UpdateEdgeIntoAEL(TEdge *&e)
{
  if( !e->nextInLML ) throw
    clipperException("UpdateEdgeIntoAEL: invalid call");
  TEdge* AelPrev = e->prevInAEL;
  TEdge* AelNext = e->nextInAEL;
  e->nextInLML->outIdx = e->outIdx;
  if( AelPrev ) AelPrev->nextInAEL = e->nextInLML;
  else m_ActiveEdges = e->nextInLML;
  if( AelNext ) AelNext->prevInAEL = e->nextInLML;
  e->nextInLML->side = e->side;
  e->nextInLML->windDelta = e->windDelta;
  e->nextInLML->windCnt = e->windCnt;
  e->nextInLML->windCnt2 = e->windCnt2;
  e = e->nextInLML;
  e->prevInAEL = AelPrev;
  e->nextInAEL = AelNext;
  if( !IsHorizontal(*e) ) InsertScanbeam( e->ytop );
}
//------------------------------------------------------------------------------

bool Clipper::IsContributing(TEdge *edge)
{
  switch( m_ClipType ){
    case ctIntersection:
      if ( edge->polyType == ptSubject )
        return std::abs(edge->windCnt) == 1 && edge->windCnt2 != 0; else
        return std::abs(edge->windCnt2) > 0 && std::abs(edge->windCnt) == 1;
    case ctUnion:
      return std::abs(edge->windCnt) == 1 && edge->windCnt2 == 0;
    case ctDifference:
      if ( edge->polyType == ptSubject )
        return std::abs(edge->windCnt) == 1 && edge->windCnt2 == 0; else
        return std::abs(edge->windCnt) == 1 && edge->windCnt2 != 0;
    default: //case ctXor:
      return std::abs(edge->windCnt) == 1;
  }
}
//------------------------------------------------------------------------------

bool Clipper::Execute(TClipType clipType, TPolyPolygon &solution,
    TPolyFillType subjFillType, TPolyFillType clipFillType)
{
  m_SubjFillType = subjFillType;
  m_ClipFillType = clipFillType;

  solution.resize(0);
  if(  m_ExecuteLocked || !InitializeScanbeam() ) return false;
  try {
    m_ExecuteLocked = true;
    m_ActiveEdges = 0;
    m_SortedEdges = 0;
    m_ClipType = clipType;

    double ybot = PopScanbeam();
    do {
      InsertLocalMinimaIntoAEL( ybot );
      ProcessHorizontals();
      double ytop = PopScanbeam();
      ProcessIntersections( ytop );
      ProcessEdgesAtTopOfScanbeam( ytop );
      ybot = ytop;
    } while( m_Scanbeam );

    //build the return polygons ...
    BuildResult(solution);
    DisposeAllPolyPts();
    m_ExecuteLocked = false;
    return true;
  }
  catch(...) {
    //returns false ...
  }
  DisposeAllPolyPts();
  m_ExecuteLocked = false;
  return false;
}
//------------------------------------------------------------------------------

void FixupSolutionColinears(PolyPtList &list, int idx){
  //fixup any occasional 'empty' protrusions (ie adjacent parallel edges)
  bool ptDeleted;
  TPolyPt *pp = list[idx];
  do {
    if (pp->prev == pp) return;
    //test for same slope ... (cross-product)
    if (std::fabs((pp->pt.Y - pp->prev->pt.Y)*(pp->next->pt.X - pp->pt.X) -
        (pp->pt.X - pp->prev->pt.X)*(pp->next->pt.Y - pp->pt.Y)) < precision) {
      pp->prev->next = pp->next;
      pp->next->prev = pp->prev;
      TPolyPt* tmp = pp;
      if (list[idx] == pp) {
        list[idx] = pp->prev;
        pp = pp->next;
      } else pp = pp->prev;
      delete tmp;
      ptDeleted = true;
    } else {
      pp = pp->next;
      ptDeleted = false;
    }
  } while (pp != list[idx] && !ptDeleted);
}
//------------------------------------------------------------------------------

void Clipper::BuildResult(TPolyPolygon &polypoly){
  unsigned k = 0;
  polypoly.resize(m_PolyPts.size());
  for (unsigned i = 0; i < m_PolyPts.size(); ++i) {
    if (m_PolyPts[i]) {

      FixupSolutionColinears(m_PolyPts, i);

      TPolyPt* pt = m_PolyPts[i];
      unsigned cnt = 0;
      double y = pt->pt.Y;
      bool isHorizontalOnly = true;
      do {
        pt = pt->next;
        if (isHorizontalOnly && std::fabs(pt->pt.Y - y) > precision)
          isHorizontalOnly = false;
        ++cnt;
      } while (pt != m_PolyPts[i]);
      if ( cnt < 3  || isHorizontalOnly ) continue;

      //validate the orientation of simple polygons ...
      if ( ForceOrientation() &&
        !ValidateOrientation(pt) ) ReversePolyPtLinks(*pt);

      polypoly[k].resize(cnt);
      for (unsigned j = 0; j < cnt; ++j) {
        polypoly[k][j].X = pt->pt.X;
        polypoly[k][j].Y = pt->pt.Y;
        pt = pt->next;
      }
      ++k;
    }
  }
  polypoly.resize(k);
}
//------------------------------------------------------------------------------

bool Clipper::ForceOrientation(){
  return m_ForceOrientation;
}
//------------------------------------------------------------------------------

void Clipper::ForceOrientation(bool value){
  m_ForceOrientation = value;
}
//------------------------------------------------------------------------------

TEdge *Clipper::BubbleSwap(TEdge *edge)
{
  int cnt = 1;
  TEdge* result = edge->nextInAEL;
  while( result  && ( std::fabs(result->xbot - edge->xbot) <= tolerance ) )
  {
    ++cnt;
    result = result->nextInAEL;
  }

  //let e = no edges in a complex intersection
  //let cnt = no intersection ops between those edges at that intersection
  //then ... e =1, cnt =0; e =2, cnt =1; e =3, cnt =3; e =4, cnt =6; ...
  //series s (where s = intersections per no edges) ... s = 0,1,3,6,10,15 ...
  //generalising: given i = e-1, and s[0] = 0, then ... cnt = i + s[i-1]
  //example: no. intersect ops required by 4 edges in a complex intersection ...
  //         cnt = 3 + 2 + 1 + 0 = 6 intersection ops
  if( cnt > 2 )
  {
    //create the sort list ...
    try {
      m_SortedEdges = edge;
      edge->prevInSEL = 0;
      TEdge *e = edge->nextInAEL;
      for( int i = 2 ; i <= cnt ; ++i )
      {
        e->prevInSEL = e->prevInAEL;
        e->prevInSEL->nextInSEL = e;
        if(  i == cnt ) e->nextInSEL = 0;
        e = e->nextInAEL;
      }
      while( m_SortedEdges  && m_SortedEdges->nextInSEL )
      {
        e = m_SortedEdges;
        while( e->nextInSEL )
        {
          if( e->nextInSEL->dx > e->dx )
          {
            IntersectEdges( e, e->nextInSEL,
              DoublePoint(e->xbot, e->ybot), (ipLeft | ipRight) );
            SwapPositionsInAEL( e , e->nextInSEL );
            SwapPositionsInSEL( e , e->nextInSEL );
          }
          else
            e = e->nextInSEL;
        }
        e->prevInSEL->nextInSEL = 0; //removes 'e' from SEL
      }
    }
    catch(...) {
      m_SortedEdges = 0;
      throw clipperException("BubbleSwap error");
    }
    m_SortedEdges = 0;
  }
return result;
}
//------------------------------------------------------------------------------

void Clipper::ProcessEdgesAtTopOfScanbeam( const double &topY)
{
  TEdge* e = m_ActiveEdges;
  while( e )
  {
    //1. process all maxima ...
    //   logic behind code - maxima are treated as if 'bent' horizontal edges
    if( IsMaxima(e, topY) && !IsHorizontal(*GetMaximaPair(e)) )
    {
      //'e' might be removed from AEL, as may any following edges so ...
      TEdge* ePrior = e->prevInAEL;
      DoMaxima( e , topY );
      if( !ePrior ) e = m_ActiveEdges;
      else e = ePrior->nextInAEL;
    }
    else
    {
      //2. promote horizontal edges, otherwise update xbot and ybot ...
      if(  IsIntermediate( e , topY ) && IsHorizontal( *e->nextInLML ) )
      {
        if( e->outIdx >= 0 ) AddPolyPt(e, DoublePoint(e->xtop ,e->ytop));
        UpdateEdgeIntoAEL( e );
        AddEdgeToSEL( e );
      } else
      {
        //this just simplifies horizontal processing ...
        e->xbot = TopX( e , topY );
        e->ybot = topY;
      }
      e = e->nextInAEL;
    }
  }

  //3. Process horizontals at the top of the scanbeam ...
  ProcessHorizontals();

  //4. Promote intermediate vertices ...
  e = m_ActiveEdges;
  while( e )
  {
    if( IsIntermediate( e, topY ) )
    {
      if( e->outIdx >= 0 ) AddPolyPt(e, DoublePoint(e->xtop,e->ytop));
      UpdateEdgeIntoAEL(e);
    }
    e = e->nextInAEL;
  }

  //5. Process (non-horizontal) intersections at the top of the scanbeam ...
  e = m_ActiveEdges;
  while( e )
  {
    if( !e->nextInAEL ) break;
    if( e->nextInAEL->xbot < e->xbot - precision )
      throw clipperException("ProcessEdgesAtTopOfScanbeam: Broken AEL order");
    if( e->nextInAEL->xbot > e->xbot + tolerance )
      e = e->nextInAEL;
    else
      e = BubbleSwap( e );
  }
}
//------------------------------------------------------------------------------

void Clipper::AddLocalMaxPoly(TEdge *e1, TEdge *e2, const TDoublePoint &pt)
{
  AddPolyPt( e1, pt );
  if(  EdgesShareSamePoly(*e1, *e2) )
  {
    e1->outIdx = -1;
    e2->outIdx = -1;
  }
  else AppendPolygon( e1, e2 );
}
//------------------------------------------------------------------------------

void Clipper::AddLocalMinPoly(TEdge *e1, TEdge *e2, const TDoublePoint &pt)
{
  AddPolyPt( e1, pt );
  e2->outIdx = e1->outIdx;

  if( !IsHorizontal( *e2 ) && ( e1->dx > e2->dx ) )
  {
    e1->side = esLeft;
    e2->side = esRight;
  } else
  {
    e1->side = esRight;
    e2->side = esLeft;
  }

  if (m_ForceOrientation) {
    TPolyPt* pp = m_PolyPts[e1->outIdx];
    bool isAHole = false;
    TEdge* e = m_ActiveEdges;
    while (e) {
      if (e->outIdx >= 0 && TopX(e,pp->pt.Y) < pp->pt.X - precision)
        isAHole = !isAHole;
      e = e->nextInAEL;
    }
    if (isAHole) pp->isHole = sTrue; else pp->isHole = sFalse;
  }
}
//------------------------------------------------------------------------------

void Clipper::AppendPolygon(TEdge *e1, TEdge *e2)
{
  if( (e1->outIdx < 0) || (e2->outIdx < 0) )
    throw clipperException("AppendPolygon error");

  //get the start and ends of both output polygons ...
  TPolyPt* p1_lft = m_PolyPts[e1->outIdx];
  TPolyPt* p1_rt = p1_lft->prev;
  TPolyPt* p2_lft = m_PolyPts[e2->outIdx];
  TPolyPt* p2_rt = p2_lft->prev;
  TEdgeSide side;

  //join e2 poly onto e1 poly and delete pointers to e2 ...
  if(  e1->side == esLeft )
  {
    if(  e2->side == esLeft )
    {
      //z y x a b c
      ReversePolyPtLinks(*p2_lft);
      p2_lft->next = p1_lft;
      p1_lft->prev = p2_lft;
      p1_rt->next = p2_rt;
      p2_rt->prev = p1_rt;
      m_PolyPts[e1->outIdx] = p2_rt;
    } else
    {
      //x y z a b c
      p2_rt->next = p1_lft;
      p1_lft->prev = p2_rt;
      p2_lft->prev = p1_rt;
      p1_rt->next = p2_lft;
      m_PolyPts[e1->outIdx] = p2_lft;
    }
    side = esLeft;
  } else
  {
    if(  e2->side == esRight )
    {
      //a b c z y x
      ReversePolyPtLinks( *p2_lft );
      p1_rt->next = p2_rt;
      p2_rt->prev = p1_rt;
      p2_lft->next = p1_lft;
      p1_lft->prev = p2_lft;
    } else
    {
      //a b c x y z
      p1_rt->next = p2_lft;
      p2_lft->prev = p1_rt;
      p1_lft->prev = p2_rt;
      p2_rt->next = p1_lft;
    }
    side = esRight;
  }

  int ObsoleteIdx = e2->outIdx;
  e2->outIdx = -1;
  TEdge* e = m_ActiveEdges;
  while( e )
  {
    if( e->
    outIdx == ObsoleteIdx )
    {
      e->outIdx = e1->outIdx;
      e->side = side;
      break;
    }
    e = e->nextInAEL;
  }
  e1->outIdx = -1;
  m_PolyPts[ObsoleteIdx] = 0;
}
//------------------------------------------------------------------------------

} //namespace clipper


