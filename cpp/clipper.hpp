/*******************************************************************************
*                                                                              *
* Author    :  Angus Johnson                                                   *
* Version   :  6.0.0 (alpha)                                                   *
* Date      :  25 June 2013                                                    *
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
* Communications of the ACM, Vol 35, Issue 7 (July 1992) pp 56-63.             *
* http://portal.acm.org/citation.cfm?id=129906                                 *
*                                                                              *
* Computer graphics and geometric modeling: implementation and algorithms      *
* By Max K. Agoston                                                            *
* Springer; 1 edition (January 4, 2005)                                        *
* http://books.google.com/books?q=vatti+clipping+agoston                       *
*                                                                              *
* See also:                                                                    *
* "Polygon Offsetting by Computing Winding Numbers"                            *
* Paper no. DETC2005-85513 pp. 565-575                                         *
* ASME 2005 International Design Engineering Technical Conferences             *
* and Computers and Information in Engineering Conference (IDETC/CIE2005)      *
* September 24-28, 2005 , Long Beach, California, USA                          *
* http://www.me.berkeley.edu/~mcmains/pubs/DAC05OffsetPolygon.pdf              *
*                                                                              *
*******************************************************************************/

#ifndef clipper_hpp
#define clipper_hpp

//use_int32: improves performance but limits coordinate values to +/- 46340 range
//#define use_int32

#ifndef use_int32
//use_xyz: adds a Z member to IntPoint (with only a minor cost to perfomance)
//nb: 'use_xyz' can only be used with 64bit integers.
//#define use_xyz
#endif

#include <vector>
#include <stdexcept>
#include <cstring>
#include <cstdlib>
#include <ostream>

namespace ClipperLib {

enum ClipType { ctIntersection, ctUnion, ctDifference, ctXor };
enum PolyType { ptSubject, ptClip };
//By far the most widely used winding rules for polygon filling are
//EvenOdd & NonZero (GDI, GDI+, XLib, OpenGL, Cairo, AGG, Quartz, SVG, Gr32)
//Others rules include Positive, Negative and ABS_GTR_EQ_TWO (only in OpenGL)
//see http://glprogramming.com/red/chapter11.html
enum PolyFillType { pftEvenOdd, pftNonZero, pftPositive, pftNegative };

#ifdef use_int32
typedef int cInt;
typedef unsigned int cUInt;
#else
typedef signed long long long64; //backward compatibility only
typedef signed long long cInt;
typedef unsigned long long cUInt;
#endif

struct IntPoint {
  cInt X;
  cInt Y;
#ifdef use_xyz
  cInt Z;
  IntPoint(cInt x = 0, cInt y = 0, cInt z = 0): X(x), Y(y), Z(z) {};
#else
  IntPoint(cInt x = 0, cInt y = 0): X(x), Y(y) {};
#endif
};

typedef std::vector< IntPoint > Polygon;
typedef std::vector< Polygon > Polygons;

std::ostream& operator <<(std::ostream &s, const Polygon &p);
std::ostream& operator <<(std::ostream &s, const Polygons &p);

inline Polygon& operator <<(Polygon& poly, const IntPoint& p) {poly.push_back(p); return poly;}
inline Polygons& operator <<(Polygons& polys, const Polygon& p) {polys.push_back(p); return polys;}

#ifdef use_xyz
typedef void (*ZFillFunc)(long64 z1, long64 z2, IntPoint& pt);
#endif

class PolyNode;
typedef std::vector< PolyNode* > PolyNodes;

class PolyNode 
{ 
public:
    PolyNode();
    Polygon Contour;
    PolyNodes Childs;
    PolyNode* Parent;
    PolyNode* GetNext() const;
    bool IsHole() const;
    int ChildCount() const;
private:
    PolyNode* GetNextSiblingUp() const;
    unsigned Index; //node index in Parent.Childs
    void AddChild(PolyNode& child);
    friend class Clipper; //to access Index
};

class PolyTree: public PolyNode
{ 
public:
    ~PolyTree(){Clear();};
    PolyNode* GetFirst() const;
    void Clear();
    int Total() const;
private:
    PolyNodes AllNodes;
    friend class Clipper; //to access AllNodes
};
        
enum JoinType { jtSquare, jtRound, jtMiter };
enum EndType { etClosed, etButt, etSquare, etRound};

bool Orientation(const Polygon &poly);
double Area(const Polygon &poly);

void OffsetPolygons(const Polygons &in_polys, Polygons &out_polys,
  double delta, JoinType jointype = jtSquare, double limit = 0, bool autoFix = true);

void OffsetPolyLines(const Polygons &in_lines, Polygons &out_lines,
  double delta, JoinType jointype = jtSquare, EndType endtype = etSquare, double limit = 0, bool autoFix = true);

void SimplifyPolygon(const Polygon &in_poly, Polygons &out_polys, PolyFillType fillType = pftEvenOdd);
void SimplifyPolygons(const Polygons &in_polys, Polygons &out_polys, PolyFillType fillType = pftEvenOdd);
void SimplifyPolygons(Polygons &polys, PolyFillType fillType = pftEvenOdd);

void CleanPolygon(const Polygon& in_poly, Polygon& out_poly, double distance = 1.415);
void CleanPolygons(const Polygons& in_polys, Polygons& out_polys, double distance = 1.415);

void PolyTreeToPolygons(const PolyTree& polytree, Polygons& polygons);

void ReversePolygon(Polygon& p);
void ReversePolygons(Polygons& p);

struct IntRect { cInt left; cInt top; cInt right; cInt bottom; };

//enums that are used internally ...
enum EdgeSide { esLeft = 1, esRight = 2};
enum IntersectProtects { ipNone = 0, ipLeft = 1, ipRight = 2, ipBoth = 3 };
//inline IntersectProtects operator|(IntersectProtects a, IntersectProtects b)
//{return static_cast<IntersectProtects>(static_cast<int>(a) | static_cast<int>(b));}

//forward declarations (for stuff used internally) ...
struct TEdge;
struct IntersectNode;
struct LocalMinima;
struct Scanbeam;
struct OutPt;
struct OutRec;
struct JoinRec;
struct HorzJoinRec;

typedef std::vector < OutRec* > PolyOutList;
typedef std::vector < TEdge* > EdgeList;
typedef std::vector < JoinRec* > JoinList;
typedef std::vector < HorzJoinRec* > HorzJoinList;

//------------------------------------------------------------------------------

//ClipperBase is the ancestor to the Clipper class. It should not be
//instantiated directly. This class simply abstracts the conversion of sets of
//polygon coordinates into edge objects that are stored in a LocalMinima list.
class ClipperBase
{
public:
  ClipperBase();
  virtual ~ClipperBase();
  bool AddPolygon(const Polygon &pg, PolyType polyType);
  bool AddPolygons( const Polygons &ppg, PolyType polyType);
  virtual void Clear();
  IntRect GetBounds();
protected:
  void DisposeLocalMinimaList();
  TEdge* AddBoundsToLML(TEdge *e);
  void PopLocalMinima();
  virtual void Reset();
  void InsertLocalMinima(LocalMinima *newLm);
  LocalMinima      *m_CurrentLM;
  LocalMinima      *m_MinimaList;
  bool              m_UseFullRange;
  EdgeList          m_edges;
};
//------------------------------------------------------------------------------

class Clipper : public virtual ClipperBase
{
public:
  Clipper();
  ~Clipper();
  bool Execute(ClipType clipType,
    Polygons &solution,
    PolyFillType subjFillType = pftEvenOdd,
    PolyFillType clipFillType = pftEvenOdd);
  bool Execute(ClipType clipType,
    PolyTree &polytree,
    PolyFillType subjFillType = pftEvenOdd,
    PolyFillType clipFillType = pftEvenOdd);
  void Clear();
  bool ReverseSolution() {return m_ReverseOutput;};
  void ReverseSolution(bool value) {m_ReverseOutput = value;};
  bool ForceSimple() {return m_ForceSimple;};
  void ForceSimple(bool value) {m_ForceSimple = value;};
  //set the callback function for z value filling on intersections (otherwise Z is 0)
#ifdef use_xyz
  void ZFillFunction(ZFillFunc zFillFunc);
#endif
protected:
  void Reset();
  virtual bool ExecuteInternal();
private:
  PolyOutList       m_PolyOuts;
  JoinList          m_Joins;
  HorzJoinList      m_HorizJoins;
  ClipType          m_ClipType;
  Scanbeam         *m_Scanbeam;
  TEdge           *m_ActiveEdges;
  TEdge           *m_SortedEdges;
  IntersectNode   *m_IntersectNodes;
  bool             m_ExecuteLocked;
  PolyFillType     m_ClipFillType;
  PolyFillType     m_SubjFillType;
  bool             m_ReverseOutput;
  bool             m_UsingPolyTree; 
  bool             m_ForceSimple;
#ifdef use_xyz
  ZFillFunc        m_ZFill; //custom callback 
#endif
  void DisposeScanbeamList();
  void SetWindingCount(TEdge& edge);
  bool IsEvenOddFillType(const TEdge& edge) const;
  bool IsEvenOddAltFillType(const TEdge& edge) const;
  void InsertScanbeam(const cInt Y);
  cInt PopScanbeam();
  void InsertLocalMinimaIntoAEL(const cInt botY);
  void InsertEdgeIntoAEL(TEdge *edge);
  void AddEdgeToSEL(TEdge *edge);
  void CopyAELToSEL();
  void DeleteFromSEL(TEdge *e);
  void DeleteFromAEL(TEdge *e);
  void UpdateEdgeIntoAEL(TEdge *&e);
  void SwapPositionsInSEL(TEdge *edge1, TEdge *edge2);
  bool IsContributing(const TEdge& edge) const;
  bool IsTopHorz(const cInt XPos);
  void SwapPositionsInAEL(TEdge *edge1, TEdge *edge2);
  void DoMaxima(TEdge *e, cInt topY);
  void ProcessHorizontals();
  void ProcessHorizontal(TEdge *horzEdge);
  void AddLocalMaxPoly(TEdge *e1, TEdge *e2, const IntPoint &pt);
  void AddLocalMinPoly(TEdge *e1, TEdge *e2, const IntPoint &pt);
  OutRec* GetOutRec(int idx);
  void AppendPolygon(TEdge *e1, TEdge *e2);
  void IntersectEdges(TEdge *e1, TEdge *e2,
    const IntPoint &pt, const IntersectProtects protects);
  OutRec* CreateOutRec();
  void AddOutPt(TEdge *e, const IntPoint &pt);
  void DisposeAllPolyPts();
  void DisposeOutRec(PolyOutList::size_type index);
  bool ProcessIntersections(const cInt botY, const cInt topY);
  void InsertIntersectNode(TEdge *e1, TEdge *e2, const IntPoint &pt);
  void BuildIntersectList(const cInt botY, const cInt topY);
  void ProcessIntersectList();
  void ProcessEdgesAtTopOfScanbeam(const cInt topY);
  void BuildResult(Polygons& polys);
  void BuildResult2(PolyTree& polytree);
  void SetHoleState(TEdge *e, OutRec *outrec);
  void DisposeIntersectNodes();
  bool FixupIntersectionOrder();
  void FixupOutPolygon(OutRec &outrec);
  bool IsHole(TEdge *e);
  void FixHoleLinkage(OutRec &outrec);
  void AddJoin(TEdge *e1, TEdge *e2, int e1OutIdx = -1, int e2OutIdx = -1);
  void ClearJoins();
  void AddHorzJoin(TEdge *e, int idx);
  void ClearHorzJoins();
  bool JoinPoints(const JoinRec *j, OutPt *&p1, OutPt *&p2);
  void FixupJoinRecs(JoinRec *j, OutPt *pt, unsigned startIdx);
  void JoinCommonEdges();
  void DoSimplePolygons();
  void FixupFirstLefts1(OutRec* OldOutRec, OutRec* NewOutRec);
  void FixupFirstLefts2(OutRec* OldOutRec, OutRec* NewOutRec);
#ifdef use_xyz
  void SetZ(IntPoint& pt, TEdge& e, TEdge& eNext);
#endif
};
//------------------------------------------------------------------------------

class clipperException : public std::exception
{
  public:
    clipperException(const char* description): m_descr(description) {}
    virtual ~clipperException() throw() {}
    virtual const char* what() const throw() {return m_descr.c_str();}
  private:
    std::string m_descr;
};
//------------------------------------------------------------------------------

} //ClipperLib namespace

#endif //clipper_hpp


