/*******************************************************************************
*                                                                              *
* Author    :  Angus Johnson                                                   *
* Version   :  2.9                                                             *
* Date      :  7 December 2010                                                 *
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
* Pages 98 - 106.                                                              *
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
#include <string>

namespace clipper {

typedef enum _ClipType { ctIntersection, ctUnion, ctDifference, ctXor } TClipType;
typedef enum _PolyType { ptSubject, ptClip } TPolyType;
typedef enum _PolyFillType { pftEvenOdd, pftNonZero} TPolyFillType;

struct TDoublePoint { double X; double Y; };
struct TDoubleRect { double left; double top; double right; double bottom; };
typedef std::vector< TDoublePoint > TPolygon;
typedef std::vector< TPolygon > TPolyPolygon;

TDoublePoint DoublePoint(const double &X, const double &Y);
TPolyPolygon OffsetPolygons(const TPolyPolygon &pts, const double &delta);
double Area(const TPolygon &poly);
TDoubleRect GetBounds(const TPolygon &poly);
bool IsClockwise(const TPolygon &poly);

//used internally ...
typedef enum _EdgeSide { esLeft, esRight } TEdgeSide;
typedef enum _IntersectProtects { ipNone = 0,
  ipLeft = 1, ipRight = 2, ipBoth = 3 } TIntersectProtects;
typedef enum _TriState { sFalse, sTrue, sUndefined} TTriState;

struct TEdge {
  double x;
  double y;
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
  TTriState isHole;
};

struct TJoinRec {
    TDoublePoint pt;
    int idx1;
    union {
      int idx2;
      TPolyPt* outPPt; //horiz joins only
    };
};

typedef std::vector < TPolyPt * > PolyPtList;
typedef std::vector < TJoinRec > JoinList;

//ClipperBase is the ancestor to the Clipper class. It should not be
//instantiated directly. This class simply abstracts the conversion of sets of
//polygon coordinates into edge objects that are stored in a LocalMinima list.
class ClipperBase
{
public:
  ClipperBase();
  virtual ~ClipperBase();
  void AddPolygon(const TPolygon &pg, TPolyType polyType);
  void AddPolyPolygon( const TPolyPolygon &ppg, TPolyType polyType);
  virtual void Clear();
  TDoubleRect GetBounds();
protected:
  void DisposeLocalMinimaList();
  void InsertLocalMinima(TLocalMinima *newLm);
  TEdge* AddBoundsToLML(TEdge *e);
  void PopLocalMinima();
  bool Reset();
  TLocalMinima      *m_CurrentLM;
private:
  TLocalMinima      *m_localMinimaList;
  std::vector< TEdge * >  m_edges;
};

class Clipper : public virtual ClipperBase
{
public:
  Clipper();
  ~Clipper();
  bool Execute(TClipType clipType,
  TPolyPolygon &solution,
  TPolyFillType subjFillType = pftEvenOdd,
  TPolyFillType clipFillType = pftEvenOdd);
  //The ForceOrientation property ensures that polygons that result from a
  //TClipper.Execute() calls will have clockwise 'outer' and counter-clockwise
  //'inner' (or 'hole') polygons. If ForceOrientation == false, then the
  //polygons returned in the solution will have undefined orientation.<br>
  //Setting ForceOrientation = true results in a minor penalty (~10%) in
  //execution speed. (Default == true) ***DEPRICATED***
  bool ForceOrientation();
  void ForceOrientation(bool value);
private:
  PolyPtList        m_PolyPts;
  JoinList          m_Joins;
  JoinList          m_CurrentHorizontals;
  TClipType         m_ClipType;
  TScanbeam        *m_Scanbeam;
  TEdge            *m_ActiveEdges;
  TEdge            *m_SortedEdges;
  TIntersectNode   *m_IntersectNodes;
  bool              m_ExecuteLocked;
  bool              m_ForceOrientation;
  TPolyFillType     m_ClipFillType;
  TPolyFillType     m_SubjFillType;
  double            m_IntersectTolerance;
  void UpdateHoleStates();
  void DisposeScanbeamList();
  void SetWindingDelta(TEdge *edge);
  void SetWindingCount(TEdge *edge);
  bool IsNonZeroFillType(TEdge *edge);
  bool IsNonZeroAltFillType(TEdge *edge);
  bool InitializeScanbeam();
  void InsertScanbeam( const double &Y);
  double PopScanbeam();
  void InsertLocalMinimaIntoAEL( const double &botY);
  void InsertEdgeIntoAEL(TEdge *edge);
  void AddEdgeToSEL(TEdge *edge);
  void CopyAELToSEL();
  void DeleteFromSEL(TEdge *e);
  void DeleteFromAEL(TEdge *e);
  void UpdateEdgeIntoAEL(TEdge *&e);
  void SwapPositionsInSEL(TEdge *edge1, TEdge *edge2);
  bool Process1Before2(TIntersectNode *Node1, TIntersectNode *Node2);
  bool TestIntersections();
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
  TPolyPt* AddPolyPt(TEdge *e, const TDoublePoint &pt);
  TPolyPt* InsertPolyPtBetween(const TDoublePoint &pt, TPolyPt* pp1, TPolyPt* pp2);
  void DisposeAllPolyPts();
  void ProcessIntersections( const double &topY);
  void AddIntersectNode(TEdge *e1, TEdge *e2, const TDoublePoint &pt);
  void BuildIntersectList(const double &topY);
  void ProcessIntersectList();
  TEdge *BubbleSwap(TEdge *edge);
  void ProcessEdgesAtTopOfScanbeam( const double &topY);
  void BuildResult(TPolyPolygon &polypoly);
  void DisposeIntersectNodes();
  void FixupJoins(int oldIdx, int newIdx);
  void MergePolysWithCommonEdges();
  void FixupJoins(int joinIdx);
};

class clipperException : public std::exception
{
  public:
    clipperException(const char* description = "Clipper exception")
      throw(): std::exception(), m_description (description) {}
    virtual ~clipperException() throw() {}
    virtual const char* what() const throw() {return m_description.c_str();}
  private:
    std::string m_description;
};

} //clipper namespace
#endif //clipper_hpp


