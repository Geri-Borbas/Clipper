/*******************************************************************************
*                                                                              *
* Author    :  Angus Johnson                                                   *
* Version   :  2.22                                                            *
* Date      :  16 August 2010                                                  *
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

#pragma once
#ifndef clipper_hpp
#define clipper_hpp

#include <vector>

namespace clipper {

typedef enum { ctIntersection, ctUnion, ctDifference, ctXor } TClipType;
typedef enum { ptSubject, ptClip } TPolyType;
typedef enum { pftEvenOdd, pftNonZero} TPolyFillType;

//used internally ...
typedef enum { esLeft, esRight } TEdgeSide;
typedef unsigned TIntersectProtects;
typedef enum { sFalse, sTrue, sUndefined} TriState;

struct TDoublePoint { double X; double Y; };
TDoublePoint DoublePoint(const double &X, const double &Y);
typedef std::vector<TDoublePoint> TPolygon;
typedef std::vector< TPolygon > TPolyPolygon;

struct TEdge {
  double xbot;
  double ybot;
  double xtop;
  double ytop;
  double dx;
  double tmpX;
  bool nextAtTop;
  TPolyType polyType;
  TEdgeSide side;
  int windDelta; //1 or -1 depending on winding direction
  int windCnt;
  int windCnt2; //winding count of the opposite polytype
  int outIdx;
  TEdge *next;
  TEdge *prev;
  TEdge *nextInLML;
  TEdge *nextInAEL;
  TEdge *prevInAEL;
  TEdge *nextInSEL;
  TEdge *prevInSEL;
  TDoublePoint savedBot;
};

struct TIntersectNode {
  TEdge *edge1;
  TEdge *edge2;
  TDoublePoint pt;
  TIntersectNode *next;
  TIntersectNode *prev;
};

struct TLocalMinima {
  double Y;
  TEdge *leftBound;
  TEdge *rightBound;
  TLocalMinima *nextLm;
};

struct TScanbeam {
  double Y;
  TScanbeam *nextSb;
};

struct TPolyPt {
  TDoublePoint pt;
  TPolyPt *next;
  TPolyPt *prev;
  TriState isHole;
};

typedef std::vector < TPolyPt * > PolyPtList;

//ClipperBase is the ancestor to the Clipper class. It should not be
//instantiated directly. This class simply abstracts the conversion of sets of
//polygon coordinates into edge objects that are stored in a LocalMinima list.
class ClipperBase
{
private:
  std::vector< TEdge * >  m_edges;
protected:
  TLocalMinima      *m_localMinimaList;
  TLocalMinima      *m_recycledLocMin;
  TLocalMinima      *m_recycledLocMinEnd;
  void DisposeLocalMinimaList();
  void InsertLocalMinima(TLocalMinima *newLm);
  TEdge* AddLML(TEdge *e);
  void PopLocalMinima();
  bool Reset();
public:
  ClipperBase();
  virtual ~ClipperBase();
  void AddPolygon(const TPolygon &pg, TPolyType polyType);
  void AddPolyPolygon( const TPolyPolygon &ppg, TPolyType polyType);
  void Clear();
};

class Clipper : public ClipperBase
{
private:
  PolyPtList        m_PolyPts;
  TClipType         m_ClipType;
  TScanbeam        *m_Scanbeam;
  TEdge            *m_ActiveEdges;
  TEdge            *m_SortedEdges;
  TIntersectNode   *m_IntersectNodes;
  bool              m_ExecuteLocked;
  bool              m_ForceOrientation;
  TPolyFillType     m_ClipFillType;
  TPolyFillType     m_SubjFillType;
  void DisposeScanbeamList();
  void SetWindingDelta(TEdge *edge);
  void SetWindingCount(TEdge *edge);
  bool IsNonZeroFillType(TEdge *edge);
  bool InitializeScanbeam();
  void InsertScanbeam( const double &Y);
  double PopScanbeam();
  void InsertLocalMinimaIntoAEL( const double &botY);
  void InsertEdgeIntoAEL(TEdge *edge);
  void AddHorzEdgeToSEL(TEdge *edge);
  void DeleteFromSEL(TEdge *e);
  void DeleteFromAEL(TEdge *e);
  void UpdateEdgeIntoAEL(TEdge *&e);
  void SwapWithNextInSEL(TEdge *edge);
  bool IsContributing(TEdge *edge);
  bool IsTopHorz(TEdge *horzEdge, const double &XPos);
  void SwapPositionsInAEL(TEdge *edge1, TEdge *edge2);
  void DoMaxima(TEdge *e, const double &topY);
  void ProcessHorizontals();
  void ProcessHorizontal(TEdge *horzEdge);
  void AddLocalMaxPoly(TEdge *e1, TEdge *e2, const TDoublePoint &pt);
  void AddLocalMinPoly(TEdge *e1, TEdge *e2, const TDoublePoint &pt);
  void AppendPolygon(TEdge *e1, TEdge *e2);
  void DoEdge1(TEdge *edge1, TEdge *edge2, const TDoublePoint &pt);
  void DoEdge2(TEdge *edge1, TEdge *edge2, const TDoublePoint &pt);
  void DoBothEdges(TEdge *edge1, TEdge *edge2, const TDoublePoint &pt);
  void IntersectEdges(TEdge *e1, TEdge *e2,
     const TDoublePoint &pt, TIntersectProtects protects);
  int AddPolyPt(int idx, const TDoublePoint &pt, bool ToFront);
  void DisposeAllPolyPts();
  void ProcessIntersections( const double &topY);
  void AddIntersectNode(TEdge *e1, TEdge *e2, const TDoublePoint &pt);
  void BuildIntersectList(const double &topY);
  void ProcessIntersectList();
  TEdge *BubbleSwap(TEdge *edge);
  void ProcessEdgesAtTopOfScanbeam( const double &topY);
  void BuildResult(TPolyPolygon &polypoly);
public:
  Clipper();
  ~Clipper();
  bool Execute(TClipType clipType,
    TPolyPolygon &solution,
    TPolyFillType subjFillType = pftEvenOdd,
    TPolyFillType clipFillType = pftEvenOdd);
  //The ForceOrientation property is only useful when operating on simple
  //polygons. It ensures that the simple polygons that result from a
  //TClipper.Execute() calls will have clockwise 'outer' and counter-clockwise
  //'inner' (or 'hole') polygons. If ForceOrientation == false, then the
  //polygons returned in the solution will have undefined orientation.<br>
  //The only disadvantage in setting ForceOrientation = true is it will result
  //in a very minor penalty (~10%) in execution speed. (Default == true)
  bool ForceOrientation();
  void ForceOrientation(bool value);
};

} //clipper namespace
#endif //clipper_hpp


