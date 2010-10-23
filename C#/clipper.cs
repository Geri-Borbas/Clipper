/*******************************************************************************
*                                                                              *
* Author    :  Angus Johnson                                                   *
* Version   :  2.6                                                             *
* Date      :  22 October 2010                                                 *
* Copyright :  Angus Johnson                                                   *
*                                                                              *
* License:                                                                     *
* Use, modification & distribution is subject to Boost Software License Ver 1. *
* http://www.boost.org/LICENSE_1_0.txt                                         *
*                                                                              *
*******************************************************************************/

/*******************************************************************************
*                                                                              *
* C# translation kindly provided by Olivier Lejeune <Olivier.Lejeune@2020.net> *
*                                                                              *
*******************************************************************************/

using System;
using System.Collections.Generic;

namespace Clipper
{
    using TPolygon = List<TDoublePoint>;
    using PolyPtList = List<TPolyPt>;
    using TPolyPolygon = List<List<TDoublePoint>>;

    public enum TClipType { ctIntersection, ctUnion, ctDifference, ctXor };
    public enum TPolyType { ptSubject, ptClip };
    public enum TPolyFillType { pftEvenOdd, pftNonZero };

    //used internally ...
    enum TEdgeSide { esLeft, esRight };
    enum THoleState { sFalse, sTrue, sPending, sUndefined };
    enum TDirection { dRightToLeft, dLeftToRight };

    public class TDoublePoint
    {
        public double X { get; set; }
        public double Y { get; set; }
    };

    public class TDoubleRect
    {
        public double left { get; set; }
        public double top { get; set; }
        public double right { get; set; }
        public double bottom { get; set; }
    };

    internal class TEdge
    {
        internal double x;
        internal double y;
        internal double xbot;
        internal double ybot;
        internal double xtop;
        internal double ytop;
        internal double dx;
        internal double tmpX;
        internal bool nextAtTop;
        internal TPolyType polyType;
        internal TEdgeSide side;
        internal int windDelta; //1 or -1 depending on winding direction
        internal int windCnt;
        internal int windCnt2; //winding count of the opposite polytype
        internal int outIdx;
        internal TEdge next;
        internal TEdge prev;
        internal TEdge nextInLML;
        internal TEdge nextInAEL;
        internal TEdge prevInAEL;
        internal TEdge nextInSEL;
        internal TEdge prevInSEL;
    };

    internal class TIntersectNode
    {
        internal TEdge edge1;
        internal TEdge edge2;
        internal TDoublePoint pt;
        internal TIntersectNode next;
        internal TIntersectNode prev;
    };

    internal class TLocalMinima
    {
        internal double Y;
        internal TEdge leftBound;
        internal TEdge rightBound;
        internal TLocalMinima nextLm;
    };

    internal class TScanbeam
    {
        internal double Y;
        internal TScanbeam nextSb;
    };

    internal class TPolyPt
    {
        internal TDoublePoint pt;
        internal TPolyPt next;
        internal TPolyPt prev;
        internal THoleState isHole;
    };

    public class ClipperBase
    {

        //infinite: simply used to define inverse slope (dx/dy) of horizontal edges
        protected internal const double infinite = -3.4E+38;
        protected internal const double almost_infinite = -3.39E+38;

        //tolerance: is needed because vertices are floating point values and any
        //comparison of floating point values requires a degree of tolerance. Ideally
        //this value should vary depending on how big (or small) the supplied polygon
        //coordinate values are. If coordinate values are greater than 1.0E+5
        //(ie 100,000+) then tolerance should be adjusted up (since the significand
        //of type double is 15 decimal places). However, for the vast majority
        //of uses ... tolerance = 1.0e-10 will be just fine.
        protected internal const double tolerance = 1.0E-10;
        protected internal const double minimal_tolerance = 1.0E-14;
        //precision: defines when adjacent vertices will be considered duplicates
        //and hence ignored. This circumvents edges having indeterminate slope.
        protected internal const double precision = 1.0E-6;
        protected internal const double slope_precision = 1.0E-3;

        protected internal const int ipLeft = 1;
        protected internal const int ipRight = 2;

        internal TLocalMinima m_localMinimaList;
        internal TLocalMinima m_CurrentLM;
        internal List<TEdge> m_edges = new List<TEdge>();

        TDoubleRect nullRect = new TDoubleRect {left = 0, top = 0, right = 0, bottom = 0};

        internal static bool PointsEqual(TDoublePoint pt1, TDoublePoint pt2)
        {
            return (Math.Abs(pt1.X - pt2.X) < precision + tolerance && Math.Abs(pt1.Y - pt2.Y) < precision + tolerance);
        }

        protected internal static bool PointsEqual(double pt1x, double pt1y, double pt2x, double pt2y)
        {
            return (Math.Abs(pt1x - pt2x) < precision + tolerance && Math.Abs(pt1y - pt2y) < precision + tolerance);
        }

        internal static void DisposePolyPts(TPolyPt pp)
        {
            if (pp == null)
                return;
            TPolyPt tmpPp = null;
            pp.prev.next = null;
            while (pp != null)
            {
                tmpPp = pp;
                pp = pp.next;
                tmpPp = null;
            }
        }

        internal static void ReversePolyPtLinks(TPolyPt pp)
        {
            TPolyPt pp1;
            TPolyPt pp2;
            pp1 = pp;
            do
            {
                pp2 = pp1.next;
                pp1.next = pp1.prev;
                pp1.prev = pp2;
                pp1 = pp2;
            } while (pp1 != pp);
        }

        private static void SetDx(TEdge e)
        {
            double dx = Math.Abs(e.x - e.next.x);
            double dy = Math.Abs(e.y - e.next.y);
            //Very short, nearly horizontal edges can cause problems by very
            //inaccurately determining intermediate X values - see TopX().
            //Therefore treat very short, nearly horizontal edges as horizontal too ...
            if ((dx < 0.1 && dy * 10 < dx) || dy < slope_precision)
            {
                e.dx = infinite;
                if (e.y != e.next.y) 
                    e.y = e.next.y;
            }
            else 
                e.dx = (e.x - e.next.x) / (e.y - e.next.y);
        }

        internal static bool IsHorizontal(TEdge e)
        {
            return (e != null) && (e.dx < almost_infinite);
        }

        internal static void SwapSides(TEdge edge1, TEdge edge2)
        {
            TEdgeSide side = edge1.side;
            edge1.side = edge2.side;
            edge2.side = side;
        }

        internal static void SwapPolyIndexes(TEdge edge1, TEdge edge2)
        {
            int outIdx = edge1.outIdx;
            edge1.outIdx = edge2.outIdx;
            edge2.outIdx = outIdx;
        }

        internal static double TopX(TEdge edge, double currentY)
        {
            if (currentY == edge.ytop)
                return edge.xtop;
            return edge.x + edge.dx * (currentY - edge.y);
        }

        internal static bool EdgesShareSamePoly(TEdge e1, TEdge e2)
        {
            return (e1 != null) && (e2 != null) && (e1.outIdx == e2.outIdx);
        }

        internal static bool SlopesEqual(TEdge e1, TEdge e2)
        {
            if (IsHorizontal(e1))
                return IsHorizontal(e2);
            if (IsHorizontal(e2))
                return false;
            return Math.Abs((e1.ytop - e1.y) * (e2.xtop - e2.x) - (e1.xtop - e1.x) * (e2.ytop - e2.y)) < slope_precision;
        }

        internal static bool IntersectPoint(TEdge edge1, TEdge edge2, TDoublePoint ip)
        {
            double b1, b2;
            if (edge1.dx == 0)
            {
                ip.X = edge1.x;
                b2 = edge2.y - edge2.x / edge2.dx;
                ip.Y = ip.X / edge2.dx + b2;
            }
            else if (edge2.dx == 0)
            {
                ip.X = edge2.x;
                b1 = edge1.y - edge1.x / edge1.dx;
                ip.Y = ip.X / edge1.dx + b1;
            }
            else
            {
                b1 = edge1.x - edge1.y * edge1.dx;
                b2 = edge2.x - edge2.y * edge2.dx;
                ip.Y = (b2 - b1) / (edge1.dx - edge2.dx);
                ip.X = edge1.dx * ip.Y + b1;
            }
            return (ip.Y > edge1.ytop + tolerance) && (ip.Y > edge2.ytop + tolerance);
        }

        private static void InitEdge(TEdge e, TEdge eNext, TEdge ePrev, TDoublePoint pt)
        {
            e.x = pt.X;
            e.y = pt.Y;
            e.next = eNext;
            e.prev = ePrev;
            SetDx(e);
        }

        private static void ReInitEdge(TEdge e, double nextX, double nextY, TPolyType polyType)
        {
            if (e.y > nextY)
            {
                e.xbot = e.x;
                e.ybot = e.y;
                e.xtop = nextX;
                e.ytop = nextY;
                e.nextAtTop = true;
            }
            else
            {
                e.xbot = nextX;
                e.ybot = nextY;
                e.xtop = e.x;
                e.ytop = e.y;
                e.x = e.xbot;
                e.y = e.ybot;
                e.nextAtTop = false;
            }
            e.polyType = polyType;
            e.outIdx = -1;
        }

        internal static bool SlopesEqualInternal(TEdge e1, TEdge e2)
        {
            if (IsHorizontal(e1))
                return IsHorizontal(e2);
            if (IsHorizontal(e2)) 
                return false;
            return Math.Abs((e1.y - e1.next.y) * (e2.x - e2.next.x) - (e1.x - e1.next.x) * (e2.y - e2.next.y)) < slope_precision;
        }

        private static bool FixupForDupsAndColinear(ref TEdge e, TEdge edges)
        {
            bool result = false;
            while (e.next != e.prev && (PointsEqual(e.prev.x, e.prev.y, e.x, e.y) || SlopesEqualInternal(e.prev, e)))
            {
                result = true;
                //remove 'e' from the double-linked-list ...
                if (e == edges)
                {
                    //move the content of e.next to e before removing e.next from DLL ...
                    e.x = e.next.x;
                    e.y = e.next.y;
                    e.next.next.prev = e;
                    e.next = e.next.next;
                }
                else
                {
                    //remove 'e' from the loop ...
                    e.prev.next = e.next;
                    e.next.prev = e.prev;
                    e = e.prev; //ie get back into the loop
                }
                SetDx(e.prev);
                SetDx(e);
            }
            return result;
        }

        private static void SwapX(TEdge e)
        {
            //swap horizontal edges' top and bottom x's so they follow the natural
            //progression of the bounds - ie so their xbots will align with the
            //adjoining lower edge. [Helpful in the ProcessHorizontal() method.]
            e.xbot = e.xtop;
            e.xtop = e.x;
            e.x = e.xbot;
            e.nextAtTop = !e.nextAtTop; //but really redundant for horizontals
        }

        private static TEdge BuildBound(TEdge e, TEdgeSide s, bool buildForward)
        {
            TEdge eNext;
            TEdge eNextNext;
            do
            {
                e.side = s;
                if (buildForward) 
                    eNext = e.next;
                else 
                    eNext = e.prev;
                if (IsHorizontal(eNext))
                {
                    if (buildForward)
                        eNextNext = eNext.next;
                    else
                        eNextNext = eNext.prev;
                    if (eNextNext.ytop < eNext.ytop)
                    {
                        //eNext is an intermediate horizontal.
                        //All horizontals have their xbot aligned with the adjoining lower edge
                        if (eNext.xbot != e.xtop)
                            SwapX(eNext);
                    }
                    else if (buildForward)
                    {
                        //to avoid duplicating top bounds, stop if this is a
                        //horizontal edge at the top of a going forward bound ...
                        e.nextInLML = null;
                        return eNext;
                    }
                    else if (eNext.xbot != e.xtop)
                        SwapX(eNext);
                }
                else if (Math.Abs(e.ytop - eNext.ytop) < tolerance)
                {
                    e.nextInLML = null;
                    return eNext;
                }
                e.nextInLML = eNext;
                e = eNext;
            } while (true);
        }

        internal ClipperBase() //constructor
        {
            m_localMinimaList = null;
            m_CurrentLM = null;
        }

        ~ClipperBase() //destructor
        {
            Clear();
        }

        void InsertLocalMinima(TLocalMinima newLm)
        {
            if (m_localMinimaList == null)
                m_localMinimaList = newLm;
            else if (newLm.Y >= m_localMinimaList.Y)
            {
                newLm.nextLm = m_localMinimaList;
                m_localMinimaList = newLm;
            }
            else
            {
                TLocalMinima tmpLm = m_localMinimaList;
                while (tmpLm.nextLm != null && (newLm.Y < tmpLm.nextLm.Y))
                    tmpLm = tmpLm.nextLm;
                newLm.nextLm = tmpLm.nextLm;
                tmpLm.nextLm = newLm;
            }
        }
        
        TEdge AddBoundsToLML(TEdge e)
        {
            //Starting at the top of one bound we progress to the bottom where there's
            //a local minima. We then go to the top of the next bound. These two bounds
            //form the left and right (or right and left) bounds of the local minima.
            e.nextInLML = null;
            e = e.next;
            for (; ; )
            {
                if (IsHorizontal(e))
                {
                    //nb: proceed through horizontals when approaching from their right,
                    //    but break on horizontal minima if approaching from their left.
                    //    This ensures 'local minima' are always on the left of horizontals.
                    if (e.next.ytop < e.ytop && e.next.xbot > e.prev.xbot) 
                        break;
                    if (e.xtop != e.prev.xbot)
                        SwapX(e);
                    e.nextInLML = e.prev;
                }
                else if (e.ybot == e.prev.ybot)
                    break;
                else e.nextInLML = e.prev;
                e = e.next;
            }

            //e and e.prev are now at a local minima ...
            TLocalMinima newLm = new TLocalMinima { nextLm = null, Y = e.prev.ybot };

            if (IsHorizontal(e)) //horizontal edges never start a left bound
            {
                if (e.xbot != e.prev.xbot)
                    SwapX(e);
                newLm.leftBound = e.prev;
                newLm.rightBound = e;
            }
            else if (e.dx < e.prev.dx)
            {
                newLm.leftBound = e.prev;
                newLm.rightBound = e;
            }
            else
            {
                newLm.leftBound = e;
                newLm.rightBound = e.prev;
            }
            newLm.leftBound.side = TEdgeSide.esLeft;
            newLm.rightBound.side = TEdgeSide.esRight;
            InsertLocalMinima(newLm);

            for (; ; )
            {
                if (e.next.ytop == e.ytop && !IsHorizontal(e.next)) 
                    break;
                e.nextInLML = e.next;
                e = e.next;
                if (IsHorizontal(e) && e.xbot != e.prev.xtop)
                    SwapX(e);
            }
            return e.next;
        }

        private static TDoublePoint RoundToTolerance(TDoublePoint pt)
        {
            TDoublePoint result = new TDoublePoint();
            result.X = (pt.X >= 0.0) ?
              (Math.Floor(pt.X / precision + 0.5) * precision) :
              (Math.Ceiling(pt.X / precision + 0.5) * precision);
            result.Y = (pt.Y >= 0.0) ?
              (Math.Floor(pt.Y / precision + 0.5) * precision) :
              (Math.Ceiling(pt.Y / precision + 0.5) * precision);
            return result;
        }

        public virtual void AddPolygon(TPolygon pg, TPolyType polyType)
        {
            int highI = pg.Count - 1;
            TPolygon p = new TPolygon(highI + 1);
            for (int i = 0; i <= highI; ++i)
                p.Add(RoundToTolerance(pg[i]));
            while ((highI > 1) && PointsEqual(p[0], p[highI])) 
                highI--;
            if (highI < 2) 
                return;

            //make sure this is still a sensible polygon (ie with at least one minima) ...
            int j = 1;
            while (j <= highI && Math.Abs(p[j].Y - p[0].Y) < precision)
                j++;

            if (j > highI)
                return;

            //create a new edge array ...
            List<TEdge> edges = new List<TEdge>();
            for (int i = 0; i < highI + 1; i++)
                edges.Add(new TEdge());
            m_edges.AddRange(edges);

            //convert 'edges' to a double-linked-list and initialize a few of the vars ...
            edges[0].x = p[0].X;
            edges[0].y = p[0].Y;


            TEdge edgeRef = edges[highI];
            InitEdge(edgeRef, edges[0], edges[highI - 1], p[highI]);
            for (int i = highI - 1; i > 0; --i)
            {
                edgeRef = edges[i];
                InitEdge(edgeRef, edges[i + 1], edges[i - 1], p[i]);
            }

            edgeRef = edges[0];
            InitEdge(edgeRef, edges[1], edges[highI], p[0]);

            //fixup by deleting any duplicate points and amalgamating co-linear edges ...
            TEdge e = edges[0];
            do
            {
                FixupForDupsAndColinear(ref e, edges[0]);
                e = e.next;
            }
            while (e != edges[0]);
            while (FixupForDupsAndColinear(ref e, edges[0]))
            {
                e = e.prev;
                if (!FixupForDupsAndColinear(ref e, edges[0]))
                    break;
                e = edges[0];
            }

            //make sure we still have a valid polygon ...
            if (e.next == e.prev)
            {
                m_edges.RemoveAt(m_edges.Count - 1);
                return;
            }

            //now properly re-initialize edges and also find 'eHighest' ...
            e = edges[0].next;
            TEdge eHighest = e;
            do
            {
                ReInitEdge(e, e.next.x, e.next.y, polyType);
                if (e.ytop < eHighest.ytop) eHighest = e;
                e = e.next;
            } while (e != edges[0]);

            if (e.next.nextAtTop)
                ReInitEdge(e, e.next.x, e.next.y, polyType);
            else
                ReInitEdge(e, e.next.xtop, e.next.ytop, polyType);
            if (e.ytop < eHighest.ytop) eHighest = e;

            //make sure eHighest is positioned so the following loop works safely ...
            if (eHighest.nextAtTop) eHighest = eHighest.next;
            if (IsHorizontal(eHighest))
                eHighest = eHighest.next;

            //finally insert each local minima ...
            e = eHighest;
            do
            {
                e = AddBoundsToLML(e);
            } while (e != eHighest);

        }

        public virtual void AddPolyPolygon(TPolyPolygon ppg, TPolyType polyType)
        {
            for (int i = 0; i < ppg.Count; ++i)
                AddPolygon(ppg[i], polyType);
        }
    
        public void Clear()
        {
            DisposeLocalMinimaList();
            m_edges.Clear();
        }

        internal bool Reset()
        {
            m_CurrentLM = m_localMinimaList;
            if (m_CurrentLM == null)
                return false; //ie nothing to process

            //reset all edges ...
            TLocalMinima lm = m_localMinimaList;
            while (lm != null)
            {
                TEdge e = lm.leftBound;
                while (e != null)
                {
                    e.xbot = e.x;
                    e.ybot = e.y;
                    e.side = TEdgeSide.esLeft;
                    e.outIdx = -1;
                    e = e.nextInLML;
                }
                e = lm.rightBound;
                while (e != null)
                {
                    e.xbot = e.x;
                    e.ybot = e.y;
                    e.side = TEdgeSide.esRight;
                    e.outIdx = -1;
                    e = e.nextInLML;
                }
                lm = lm.nextLm;
            }
            return true;
        }
        
        protected internal void PopLocalMinima()
        {
            if (m_CurrentLM == null)
                return;
            m_CurrentLM = m_CurrentLM.nextLm;
        }
        
        void DisposeLocalMinimaList()
        {
            while (m_localMinimaList != null)
            {
                TLocalMinima tmpLm = m_localMinimaList.nextLm;
                m_localMinimaList = null;
                m_localMinimaList = tmpLm;
            }
            m_CurrentLM = null; 
        }

        internal static TDoublePoint DoublePoint(double _X, double _Y)
        {
            return new TDoublePoint { X = _X, Y = _Y };
        }

        protected TDoubleRect GetBounds()
        {
            TDoubleRect result = new TDoubleRect();
            TLocalMinima lm = m_localMinimaList;
            if (lm == null)
            {
                return nullRect;
            }
            result.left = -infinite;
            result.top = -infinite;
            result.right = infinite;
            result.bottom = infinite;
            while (lm != null)
            {
                if (lm.leftBound.y > result.bottom) result.bottom = lm.leftBound.y;
                TEdge e = lm.leftBound;
                while (e.nextInLML != null)
                {
                    if (e.x < result.left) result.left = e.x;
                    e = e.nextInLML;
                }
                if (e.x < result.left) result.left = e.x;
                else if (e.xtop < result.left) result.left = e.xtop;
                if (e.ytop < result.top) result.top = e.ytop;

                e = lm.rightBound;
                while (e.nextInLML != null)
                {
                    if (e.x > result.right) result.right = e.x;
                    e = e.nextInLML;
                }
                if (e.x > result.right) result.right = e.x;
                else if (e.xtop > result.right) result.right = e.xtop;

                lm = lm.nextLm;
            }
            return result;
        }

    }

    public class Clipper : ClipperBase
    {
        PolyPtList m_PolyPts;
        TClipType m_ClipType;
        TScanbeam m_Scanbeam;
        TEdge m_ActiveEdges;
        TEdge m_SortedEdges;
        TIntersectNode m_IntersectNodes;
        bool m_ExecuteLocked;
        bool m_ForceOrientation;
        TPolyFillType m_ClipFillType;
        TPolyFillType m_SubjFillType;
        double m_IntersectTolerance;
        bool m_HoleStatesPending;

        public Clipper()
        {
            m_Scanbeam = null;
            m_ActiveEdges = null;
            m_SortedEdges = null;
            m_IntersectNodes = null;
            m_ExecuteLocked = false;
            m_ForceOrientation = true;
            m_PolyPts = new PolyPtList();
        }
        
        internal void DisposeAllPolyPts()
        {
            for (int i = 0; i < m_PolyPts.Count; ++i)
                DisposePolyPts(m_PolyPts[i]);
            m_PolyPts.Clear();
        }
        
        void DisposeScanbeamList()
        {
            while (m_Scanbeam != null)
            {
                TScanbeam sb2 = m_Scanbeam.nextSb;
                m_Scanbeam = null;
                m_Scanbeam = sb2;
            }
        }
        
        public override void AddPolygon(TPolygon pg, TPolyType polyType)
        {
            base.AddPolygon(pg, polyType);
        }
        
        public override void AddPolyPolygon(TPolyPolygon ppg, TPolyType polyType)
        {
            base.AddPolyPolygon(ppg, polyType);
        }

        public static double PolygonArea(TPolygon poly)
        {
            int highI = poly.Count - 1;
            if (highI < 2) return 0;
            double result = 0;
            for (int i = 0; i < highI; ++i)
                result += (poly[i].X + poly[i + 1].X) * (poly[i].Y - poly[i + 1].Y);
            result += (poly[highI].X + poly[0].X) * (poly[highI].Y - poly[0].Y);
            result = result / 2;
            return result;
        }

        private static TDoublePoint GetUnitNormal(TDoublePoint pt1, TDoublePoint pt2)
        {
            double dx = (pt2.X - pt1.X);
            double dy = (pt2.Y - pt1.Y);
            if ((dx == 0) && (dy == 0))
                return DoublePoint(0, 0);

            //double f = 1 *1.0/ hypot( dx , dy );
            double f = 1 * 1.0 / Math.Sqrt(dx * dx + dy * dy);
            dx = dx * f;
            dy = dy * f;
            return DoublePoint(dy, -dx);
        }

        internal static bool ValidateOrientation(TPolyPt pt)
        {
            //compares the orientation (clockwise vs counter-clockwise) of a *simple*
            //polygon with its hole status (ie test whether an inner or outer polygon).
            //nb: complex polygons have indeterminate orientations.
            TPolyPt bottomPt = pt;
            TPolyPt ptStart = pt;
            pt = pt.next;
            while ((pt != ptStart))
            {
                if ((pt.pt.Y > bottomPt.pt.Y) ||
                  ((pt.pt.Y == bottomPt.pt.Y) && (pt.pt.X > bottomPt.pt.X)))
                    bottomPt = pt;
                pt = pt.next;
            }

            while (bottomPt.isHole == THoleState.sUndefined && bottomPt.next.pt.Y >= bottomPt.pt.Y)
                bottomPt = bottomPt.next;
            while (bottomPt.isHole == THoleState.sUndefined && bottomPt.prev.pt.Y >= bottomPt.pt.Y)
                bottomPt = bottomPt.prev;
            return (IsClockwise(pt) != (bottomPt.isHole == THoleState.sTrue));
        }

        public static TPolyPolygon OffsetPolygons(TPolyPolygon pts, double delta)
        {
            //a positive delta will offset each polygon edge towards its left, and
            //a negative delta will offset each polygon edge towards its right.

            //USE THIS FUNCTION WITH CAUTION. VERY OCCASIONALLY HOLES AREN'T PROPERLY
            //HANDLED. THEY MAY BE MISSING OR THE WRONG SIZE. (ie: work-in-progress.)

            TPolyPolygon result = new TPolyPolygon();
            result.Capacity = pts.Count;
            for (int j = 0; j < pts.Count; ++j)
            {
                result.Add(new TPolygon());
                int len = pts[j].Count;
                result[j].Capacity = len * 2;
                if (len == 0) continue;

                TPolygon normals = new TPolygon();
                normals.Capacity = len;
                normals.Add(GetUnitNormal(pts[j][len - 1], pts[j][0]));
                for (int i = 1; i < len; ++i)
                    normals.Add(GetUnitNormal(pts[j][i - 1], pts[j][i]));

                //to minimize artefacts when shrinking, strip out polygons where
                //abs(delta) is larger than half its diameter ...
                if (delta < 0)
                {
                    TDoubleRect rec = GetBounds(pts[j]);
                    if (-delta * 2 > (rec.right - rec.left) || -delta * 2 > (rec.bottom - rec.top)) len = 1;
                }

                for (int i = 0; i < len - 1; ++i)
                {
                    result[j].Add(DoublePoint(pts[j][i].X - delta * normals[i].X,
                          pts[j][i].Y - delta * normals[i].Y));
                    result[j].Add(DoublePoint(pts[j][i].X - delta * normals[i + 1].X,
                          pts[j][i].Y - delta * normals[i + 1].Y));
                }
                result[j].Add(DoublePoint(pts[j][len - 1].X - delta * normals[len - 1].X,
                        pts[j][len - 1].Y - delta * normals[len - 1].Y));
                result[j].Add(DoublePoint(pts[j][len - 1].X - delta * normals[0].X,
                        pts[j][len - 1].Y - delta * normals[0].Y));

                //round any convex corners ...
                if ((normals[len - 1].X * normals[0].Y - normals[0].X * normals[len - 1].Y) * delta < 0)
                {
                    double a1 = Math.Atan2(normals[len - 1].Y, normals[len - 1].X);
                    double a2 = Math.Atan2(normals[0].Y, normals[0].X);
                    if (delta < 0 && a2 < a1) a2 = a2 + Math.PI * 2;
                    else if (delta > 0 && a2 > a1) a2 = a2 - Math.PI * 2;
                    TPolygon arc = BuildArc(pts[j][len - 1], a1, a2, -delta);
                    result[j].InsertRange(len * 2 - 1, arc);
                }
                for (int i = len - 1; i > 0; --i)
                    if ((normals[i - 1].X * normals[i].Y - normals[i].X * normals[i - 1].Y) * delta < 0)
                    {
                        double a1 = Math.Atan2(normals[i - 1].Y, normals[i - 1].X);
                        double a2 = Math.Atan2(normals[i].Y, normals[i].X);
                        if (delta < 0 && a2 < a1) a2 = a2 + Math.PI * 2;
                        else if (delta > 0 && a2 > a1) a2 = a2 - Math.PI * 2;
                        TPolygon arc = BuildArc(pts[j][i - 1], a1, a2, -delta);
                        result[j].InsertRange((i - 1) * 2 + 1, arc);
                    }
            }

            //finally, clean up untidy corners ...
            Clipper c = new Clipper();
            c.AddPolyPolygon(result, TPolyType.ptSubject);
            if (delta > 0)
                c.Execute(TClipType.ctUnion, result, TPolyFillType.pftNonZero, TPolyFillType.pftNonZero);
            else
            {
                TDoubleRect r = c. GetBounds();
                TPolygon outer = new TPolygon();
                outer.Capacity = 4;
                outer.Add(DoublePoint(r.left - 10, r.top - 10));
                outer.Add(DoublePoint(r.right + 10, r.top - 10));
                outer.Add(DoublePoint(r.right + 10, r.bottom + 10));
                outer.Add(DoublePoint(r.left - 10, r.bottom + 10));
                c.AddPolygon(outer, TPolyType.ptSubject);
                c.Execute(TClipType.ctUnion, result, TPolyFillType.pftNonZero, TPolyFillType.pftNonZero);
                result.RemoveAt(0);
            }
            return result;
        }

        private static TPolygon BuildArc(TDoublePoint pt, double a1, double a2, double r)
        {
            int steps = (int)Math.Max(6, Math.Sqrt(Math.Abs(r)) * Math.Abs(a2 - a1));
            TPolygon result = new TPolygon();
            result.Capacity = steps;
            int n = steps - 1;
            double da = (a2 - a1) / n;
            double a = a1;
            for (int i = 0; i <= n; ++i)
            {
                double dy = Math.Sin(a) * r;
                double dx = Math.Cos(a) * r;
                result.Add(DoublePoint(pt.X + dx, pt.Y + dy));
                a = a + da;
            }
            return result;
        }

        public static TDoubleRect GetBounds(TPolygon poly)
        {
            if (poly.Count == 0)
            {
                TDoubleRect rec = new TDoubleRect { left = 0, top = 0, right = 0, bottom = 0 };
                return rec;
            }
            TDoubleRect result = new TDoubleRect { left = poly[0].X, top = poly[0].Y, right = poly[0].X, bottom = poly[0].Y };
            for (int i = 1; i < poly.Count; ++i)
            {
                if (poly[i].X < result.left) result.left = poly[i].X;
                else if (poly[i].X > result.right) result.right = poly[i].X;
                if (poly[i].Y < result.top) result.top = poly[i].Y;
                else if (poly[i].Y > result.bottom) result.bottom = poly[i].Y;
            }
            return result;
        }

        private static bool IsClockwise(TPolyPt pt)
        {
            double area = 0;
            TPolyPt startPt = pt;
            do
            {
                area = area + (pt.pt.X + pt.next.pt.X) * (pt.pt.Y - pt.next.pt.Y);
                pt = pt.next;
            }
            while (pt != startPt);
            //area = area /2;
            return area >= 0;
        }

        private bool InitializeScanbeam()
        {
            DisposeScanbeamList();
            if (!Reset())
                return false;
            //add all the local minima into a fresh fScanbeam list ...
            TLocalMinima lm = m_CurrentLM;
            while (lm != null)
            {
                InsertScanbeam(lm.Y);
                InsertScanbeam(lm.leftBound.ytop); //this is necessary too!
                lm = lm.nextLm;
            }
            return true;
        }

        private void InsertScanbeam(double Y)
        {
            if (m_Scanbeam == null)
            {
                m_Scanbeam = new TScanbeam { Y = Y, nextSb = null };
            }
            else if (Y > m_Scanbeam.Y)
            {
                m_Scanbeam = new TScanbeam { Y = Y, nextSb = m_Scanbeam };
            }
            else
            {
                TScanbeam sb2 = m_Scanbeam;
                while (sb2.nextSb != null && (Y <= sb2.nextSb.Y))
                    sb2 = sb2.nextSb;
                if (Y == sb2.Y)
                    return; //ie ignores duplicates
                TScanbeam newSb = new TScanbeam { Y = Y, nextSb = sb2.nextSb };
                sb2.nextSb = newSb;
            }
        }

        private double PopScanbeam()
        {
            double Y = m_Scanbeam.Y;
            TScanbeam sb2 = m_Scanbeam;
            m_Scanbeam = m_Scanbeam.nextSb;
            return Y;
        }

        private void UpdateHoleStates()
        {
            //unfortunately this needs to be done in batches after the current operation
            //in ExecuteInternal has finished. If hole states are calculated at the time
            //new output polygons are started, we occasionally get the wrong state.
            m_HoleStatesPending = false;
            TEdge e = m_ActiveEdges;
            while (e != null)
            {
                if (e.outIdx >= 0 && m_PolyPts[e.outIdx].isHole == THoleState.sPending)
                {
                    bool isAHole = false;
                    TEdge e2 = m_ActiveEdges;
                    while (e2 != e)
                    {
                        if (e2.outIdx >= 0) isAHole = !isAHole;
                        e2 = e2.nextInAEL;
                    }

                    if (isAHole)
                        m_PolyPts[e.outIdx].isHole = THoleState.sTrue;
                    else
                        m_PolyPts[e.outIdx].isHole = THoleState.sFalse;
                }
                e = e.nextInAEL;
            }
        }

        private void SetWindingDelta(TEdge edge)
        {
            if (!IsNonZeroFillType(edge))
                edge.windDelta = 1;
            else if (edge.nextAtTop)
                edge.windDelta = 1;
            else 
                edge.windDelta = -1;
        }

        private void SetWindingCount(TEdge edge)
        {
            TEdge e = edge.prevInAEL;
            //find the edge of the same polytype that immediately preceeds 'edge' in AEL
            while (e != null && e.polyType != edge.polyType)
                e = e.prevInAEL;
            if (e == null)
            {
                edge.windCnt = edge.windDelta;
                edge.windCnt2 = 0;
                e = m_ActiveEdges; //ie get ready to calc windCnt2
            }
            else if (IsNonZeroFillType(edge))
            {
                //nonZero filling ...
                if (e.windCnt * e.windDelta < 0)
                {
                    if (Math.Abs(e.windCnt) > 1)
                    {
                        if (e.windDelta * edge.windDelta < 0) 
                            edge.windCnt = e.windCnt;
                        else 
                            edge.windCnt = e.windCnt + edge.windDelta;
                    }
                    else
                        edge.windCnt = e.windCnt + e.windDelta + edge.windDelta;
                }
                else
                {
                    if (Math.Abs(e.windCnt) > 1 && e.windDelta * edge.windDelta < 0)
                        edge.windCnt = e.windCnt;
                    else if (e.windCnt + edge.windDelta == 0)
                        edge.windCnt = e.windCnt;
                    else 
                        edge.windCnt = e.windCnt + edge.windDelta;
                }
                edge.windCnt2 = e.windCnt2;
                e = e.nextInAEL; //ie get ready to calc windCnt2
            }
            else
            {
                //even-odd filling ...
                edge.windCnt = 1;
                edge.windCnt2 = e.windCnt2;
                e = e.nextInAEL; //ie get ready to calc windCnt2
            }

            //update windCnt2 ...
            if (IsNonZeroAltFillType(edge))
            {
                //nonZero filling ...
                while (e != edge)
                {
                    edge.windCnt2 += e.windDelta;
                    e = e.nextInAEL;
                }
            }
            else
            {
                //even-odd filling ...
                while (e != edge)
                {
                    edge.windCnt2 = (edge.windCnt2 == 0) ? 1 : 0;
                    e = e.nextInAEL;
                }
            }
        }

        private bool IsNonZeroFillType(TEdge edge)
        {
            switch (edge.polyType)
            {
                case TPolyType.ptSubject:
                    return m_SubjFillType == TPolyFillType.pftNonZero;
                default:
                    return m_ClipFillType == TPolyFillType.pftNonZero;
            }
        }

        private bool IsNonZeroAltFillType(TEdge edge)
        {
            switch (edge.polyType)
            {
                case TPolyType.ptSubject:
                    return m_ClipFillType == TPolyFillType.pftNonZero;
                default: 
                    return m_SubjFillType == TPolyFillType.pftNonZero;
            }
        }

        private static bool Edge2InsertsBeforeEdge1(TEdge e1, TEdge e2)
        {
            if (e2.xbot - tolerance > e1.xbot) 
                return false;
            if (e2.xbot + tolerance < e1.xbot) 
                return true;
            if (IsHorizontal(e2)) 
                return false;
            return (e2.dx > e1.dx);
        }
        private void InsertEdgeIntoAEL(TEdge edge)
        {
            edge.prevInAEL = null;
            edge.nextInAEL = null;
            if (m_ActiveEdges == null)
            {
                m_ActiveEdges = edge;
            }
            else if (Edge2InsertsBeforeEdge1(m_ActiveEdges, edge))
            {
                edge.nextInAEL = m_ActiveEdges;
                m_ActiveEdges.prevInAEL = edge;
                m_ActiveEdges = edge;
            }
            else
            {
                TEdge e = m_ActiveEdges;
                while (e.nextInAEL != null && !Edge2InsertsBeforeEdge1(e.nextInAEL, edge))
                    e = e.nextInAEL;
                edge.nextInAEL = e.nextInAEL;
                if (e.nextInAEL != null)
                    e.nextInAEL.prevInAEL = edge;
                edge.prevInAEL = e;
                e.nextInAEL = edge;
            }
        }

        private void InsertLocalMinimaIntoAEL(double botY)
        {
            while (m_CurrentLM != null && (m_CurrentLM.Y == botY))
            {
                InsertEdgeIntoAEL(m_CurrentLM.leftBound);
                InsertScanbeam(m_CurrentLM.leftBound.ytop);
                InsertEdgeIntoAEL(m_CurrentLM.rightBound);

                SetWindingDelta(m_CurrentLM.leftBound);
                if (IsNonZeroFillType(m_CurrentLM.leftBound))
                    m_CurrentLM.rightBound.windDelta =
                      -m_CurrentLM.leftBound.windDelta;
                else
                    m_CurrentLM.rightBound.windDelta = 1;

                SetWindingCount(m_CurrentLM.leftBound);
                m_CurrentLM.rightBound.windCnt =
                  m_CurrentLM.leftBound.windCnt;
                m_CurrentLM.rightBound.windCnt2 =
                  m_CurrentLM.leftBound.windCnt2;

                if (IsHorizontal(m_CurrentLM.rightBound))
                {
                    //nb: only rightbounds can have a horizontal bottom edge
                    AddEdgeToSEL(m_CurrentLM.rightBound);
                    InsertScanbeam(m_CurrentLM.rightBound.nextInLML.ytop);
                }
                else
                    InsertScanbeam(m_CurrentLM.rightBound.ytop);

                TLocalMinima lm = m_CurrentLM;
                if (IsContributing(lm.leftBound))
                    AddLocalMinPoly(lm.leftBound, lm.rightBound, DoublePoint(lm.leftBound.xbot, lm.Y));

                if (lm.leftBound.nextInAEL != lm.rightBound)
                {
                    TEdge e = lm.leftBound.nextInAEL;
                    TDoublePoint pt = DoublePoint(lm.leftBound.xbot, lm.leftBound.ybot);
                    while (e != lm.rightBound)
                    {
                        if (e == null) 
                            throw new clipperException("AddLocalMinima: missing rightbound!");
                        TEdge edgeRef = lm.rightBound;
                        IntersectEdges(edgeRef, e, pt, 0); //order important here
                        e = e.nextInAEL;
                    }
                }
                PopLocalMinima();
            }
        }

        private void AddEdgeToSEL(TEdge edge)
        {
            //SEL pointers in PEdge are reused to build a list of horizontal edges.
            //However, we don't need to worry about order with horizontal edge processing.
            if (m_SortedEdges == null)
            {
                m_SortedEdges = edge;
                edge.prevInSEL = null;
                edge.nextInSEL = null;
            }
            else
            {
                edge.nextInSEL = m_SortedEdges;
                edge.prevInSEL = null;
                m_SortedEdges.prevInSEL = edge;
                m_SortedEdges = edge;
            }
        }
        
        private void CopyAELToSEL()
        {
            TEdge e = m_ActiveEdges;
            m_SortedEdges = e;
            if (m_ActiveEdges == null)
                return;
            m_SortedEdges.prevInSEL = null;
            e = e.nextInAEL;
            while (e != null)
            {
                e.prevInSEL = e.prevInAEL;
                e.prevInSEL.nextInSEL = e;
                e.nextInSEL = null;
                e = e.nextInAEL;
            }
        }

        private void SwapPositionsInAEL(TEdge edge1, TEdge edge2)
        {
            if (edge1.nextInAEL == null && edge1.prevInAEL == null)
                return;
            if (edge2.nextInAEL == null && edge2.prevInAEL == null)
                return;

            if (edge1.nextInAEL == edge2)
            {
                TEdge next = edge2.nextInAEL;
                if (next != null)
                    next.prevInAEL = edge1;
                TEdge prev = edge1.prevInAEL;
                if (prev != null)
                    prev.nextInAEL = edge2;
                edge2.prevInAEL = prev;
                edge2.nextInAEL = edge1;
                edge1.prevInAEL = edge2;
                edge1.nextInAEL = next;
            }
            else if (edge2.nextInAEL == edge1)
            {
                TEdge next = edge1.nextInAEL;
                if (next != null)
                    next.prevInAEL = edge2;
                TEdge prev = edge2.prevInAEL;
                if (prev != null)
                    prev.nextInAEL = edge1;
                edge1.prevInAEL = prev;
                edge1.nextInAEL = edge2;
                edge2.prevInAEL = edge1;
                edge2.nextInAEL = next;
            }
            else
            {
                TEdge next = edge1.nextInAEL;
                TEdge prev = edge1.prevInAEL;
                edge1.nextInAEL = edge2.nextInAEL;
                if (edge1.nextInAEL != null)
                    edge1.nextInAEL.prevInAEL = edge1;
                edge1.prevInAEL = edge2.prevInAEL;
                if (edge1.prevInAEL != null)
                    edge1.prevInAEL.nextInAEL = edge1;
                edge2.nextInAEL = next;
                if (edge2.nextInAEL != null)
                    edge2.nextInAEL.prevInAEL = edge2;
                edge2.prevInAEL = prev;
                if (edge2.prevInAEL != null)
                    edge2.prevInAEL.nextInAEL = edge2;
            }

            if (edge1.prevInAEL == null)
                m_ActiveEdges = edge1;
            else if (edge2.prevInAEL == null)
                m_ActiveEdges = edge2;
        }
        
        private void SwapPositionsInSEL(TEdge edge1, TEdge edge2)
        {
            if (edge1.nextInSEL == null && edge1.prevInSEL == null)
                return;
            if (edge2.nextInSEL == null && edge2.prevInSEL == null)
                return;

            if (edge1.nextInSEL == edge2)
            {
                TEdge next = edge2.nextInSEL;
                if (next != null)
                    next.prevInSEL = edge1;
                TEdge prev = edge1.prevInSEL;
                if (prev != null)
                    prev.nextInSEL = edge2;
                edge2.prevInSEL = prev;
                edge2.nextInSEL = edge1;
                edge1.prevInSEL = edge2;
                edge1.nextInSEL = next;
            }
            else if (edge2.nextInSEL == edge1)
            {
                TEdge next = edge1.nextInSEL;
                if (next != null)
                    next.prevInSEL = edge2;
                TEdge prev = edge2.prevInSEL;
                if (prev != null)
                    prev.nextInSEL = edge1;
                edge1.prevInSEL = prev;
                edge1.nextInSEL = edge2;
                edge2.prevInSEL = edge1;
                edge2.nextInSEL = next;
            }
            else
            {
                TEdge next = edge1.nextInSEL;
                TEdge prev = edge1.prevInSEL;
                edge1.nextInSEL = edge2.nextInSEL;
                if (edge1.nextInSEL != null)
                    edge1.nextInSEL.prevInSEL = edge1;
                edge1.prevInSEL = edge2.prevInSEL;
                if (edge1.prevInSEL != null)
                    edge1.prevInSEL.nextInSEL = edge1;
                edge2.nextInSEL = next;
                if (edge2.nextInSEL != null)
                    edge2.nextInSEL.prevInSEL = edge2;
                edge2.prevInSEL = prev;
                if (edge2.prevInSEL != null)
                    edge2.prevInSEL.nextInSEL = edge2;
            }

            if (edge1.prevInSEL == null)
                m_SortedEdges = edge1;
            else if (edge2.prevInSEL == null)
                m_SortedEdges = edge2;
        }

        private TEdge GetNextInAEL(TEdge e, TDirection Direction)
        {
            if (Direction == TDirection.dLeftToRight)
                return e.nextInAEL;
            else
                return e.prevInAEL;
        }

        private TEdge GetPrevInAEL(TEdge e, TDirection Direction)
        {
            if (Direction == TDirection.dLeftToRight)
                return e.prevInAEL;
            else return e.nextInAEL;
        }

        private bool IsMinima(TEdge e)
        {
            return e != null && (e.prev.nextInLML != e) && (e.next.nextInLML != e);
        }

        private bool IsMaxima(TEdge e, double Y)
        {
            return e != null && Math.Abs(e.ytop - Y) < tolerance && e.nextInLML == null;
        }

        private bool IsIntermediate(TEdge e, double Y)
        {
            return Math.Abs(e.ytop - Y) < tolerance && e.nextInLML != null;
        }

        private TEdge GetMaximaPair(TEdge e)
        {
            if (!IsMaxima(e.next, e.ytop) || (e.next.xtop != e.xtop))
                return e.prev;
            else
                return e.next;
        }

        private void DoMaxima(TEdge e, double topY)
        {
            TEdge eMaxPair = GetMaximaPair(e);
            double X = e.xtop;
            TEdge eNext = e.nextInAEL;
            while (eNext != eMaxPair)
            {
                IntersectEdges(e, eNext, DoublePoint(X, topY), ipLeft | ipRight);
                eNext = eNext.nextInAEL;
            }
            if ((e.outIdx < 0) && (eMaxPair.outIdx < 0))
            {
                DeleteFromAEL(e);
                DeleteFromAEL(eMaxPair);
            }
            else if ((e.outIdx >= 0) && (eMaxPair.outIdx >= 0))
            {
                IntersectEdges(e, eMaxPair, DoublePoint(X, topY), 0);
            }
            else 
                throw new clipperException("DoMaxima error");
        }

        private void ProcessHorizontals()
        {
            TEdge horzEdge = m_SortedEdges;
            while (horzEdge != null)
            {
                DeleteFromSEL(horzEdge);
                ProcessHorizontal(horzEdge);
                horzEdge = m_SortedEdges;
            }
        }

        private bool IsTopHorz(TEdge horzEdge, double XPos)
        {
            TEdge e = m_SortedEdges;
            while (e != null)
            {
                if ((XPos >= Math.Min(e.xbot, e.xtop)) && (XPos <= Math.Min(e.xbot, e.xtop)))
                    return false;
                e = e.nextInSEL;
            }
            return true;
        }

        private void ProcessHorizontal(TEdge horzEdge)
        {
            TDirection Direction;
            double horzLeft, horzRight;

            if (horzEdge.xbot < horzEdge.xtop)
            {
                horzLeft = horzEdge.xbot;
                horzRight = horzEdge.xtop;
                Direction = TDirection.dLeftToRight;
            }
            else
            {
                horzLeft = horzEdge.xtop;
                horzRight = horzEdge.xbot;
                Direction = TDirection.dRightToLeft;
            }

            TEdge eMaxPair;
            if (horzEdge.nextInLML != null)
                eMaxPair = null;
            else
                eMaxPair = GetMaximaPair(horzEdge);

            TEdge e = GetNextInAEL(horzEdge, Direction);
            while (e != null)
            {
                TEdge eNext = GetNextInAEL(e, Direction);
                if ((e.xbot >= horzLeft - tolerance) && (e.xbot <= horzRight + tolerance))
                {
                    //ok, so far it looks like we're still in range of the horizontal edge
                    if (Math.Abs(e.xbot - horzEdge.xtop) < tolerance &&
                        horzEdge.nextInLML != null &&
                        (SlopesEqual(e, horzEdge.nextInLML) || (e.dx < horzEdge.nextInLML.dx)))
                    {
                        //we really have gone past the end of intermediate horz edge so quit.
                        //nb: More -ve slopes follow more +ve slopes *above* the horizontal.
                        break;
                    }
                    else if (e == eMaxPair)
                    {
                        //horzEdge is evidently a maxima horizontal and we've arrived at its end.
                        if (Direction == TDirection.dLeftToRight)
                            IntersectEdges(horzEdge, e, DoublePoint(e.xbot, horzEdge.ybot), 0);
                        else
                            IntersectEdges(e, horzEdge, DoublePoint(e.xbot, horzEdge.ybot), 0);
                        return;
                    }
                    else if (IsHorizontal(e) && !IsMinima(e) && !(e.xbot > e.xtop))
                    {
                        if (Direction == TDirection.dLeftToRight)
                            IntersectEdges(horzEdge, e, DoublePoint(e.xbot, horzEdge.ybot),
                              (IsTopHorz(horzEdge, e.xbot)) ? ipLeft : ipLeft | ipRight);
                        else
                            IntersectEdges(e, horzEdge, DoublePoint(e.xbot, horzEdge.ybot),
                              (IsTopHorz(horzEdge, e.xbot)) ? ipRight : ipLeft | ipRight);
                    }
                    else if (Direction == TDirection.dLeftToRight)
                    {
                        IntersectEdges(horzEdge, e, DoublePoint(e.xbot, horzEdge.ybot),
                          (IsTopHorz(horzEdge, e.xbot)) ? ipLeft : ipLeft | ipRight);
                    }
                    else
                    {
                        IntersectEdges(e, horzEdge, DoublePoint(e.xbot, horzEdge.ybot),
                          (IsTopHorz(horzEdge, e.xbot)) ? ipRight : ipLeft | ipRight);
                    }
                    SwapPositionsInAEL(horzEdge, e);
                }
                else if ((Direction == TDirection.dLeftToRight) &&
                  (e.xbot > horzRight + tolerance) && horzEdge.nextInSEL == null) 
                    break;
                else if ((Direction == TDirection.dRightToLeft) &&
                  (e.xbot < horzLeft - tolerance) && horzEdge.nextInSEL == null) 
                    break;
                e = eNext;
            } //end while ( e )

            if (horzEdge.nextInLML != null)
            {
                if (horzEdge.outIdx >= 0)
                    AddPolyPt(horzEdge, DoublePoint(horzEdge.xtop, horzEdge.ytop));
                UpdateEdgeIntoAEL(ref horzEdge);
            }
            else
            {
                if (horzEdge.outIdx >= 0)
                    IntersectEdges(horzEdge, eMaxPair,
                      DoublePoint(horzEdge.xtop, horzEdge.ybot), ipLeft | ipRight);
                DeleteFromAEL(eMaxPair);
                DeleteFromAEL(horzEdge);
            }
        }

        private void AddPolyPt(TEdge e, TDoublePoint pt)
        {
            bool ToFront = (e.side == TEdgeSide.esLeft);
            if (e.outIdx < 0)
            {
                TPolyPt newPolyPt = new TPolyPt();
                newPolyPt.pt = pt;
                m_PolyPts.Add(newPolyPt);
                newPolyPt.next = newPolyPt;
                newPolyPt.prev = newPolyPt;
                newPolyPt.isHole = THoleState.sUndefined;
                e.outIdx = m_PolyPts.Count - 1;
            }
            else
            {
                TPolyPt pp = m_PolyPts[e.outIdx];
                if ((ToFront && PointsEqual(pt, pp.pt)) ||
                  (!ToFront && PointsEqual(pt, pp.prev.pt))) return;
                TPolyPt newPolyPt = new TPolyPt();
                newPolyPt.pt = pt;
                newPolyPt.isHole = THoleState.sUndefined;
                newPolyPt.next = pp;
                newPolyPt.prev = pp.prev;
                newPolyPt.prev.next = newPolyPt;
                pp.prev = newPolyPt;
                if (ToFront) m_PolyPts[e.outIdx] = newPolyPt;
            }
        }

        private void ProcessIntersections(double topY)
        {
          if( m_ActiveEdges == null)
                return;
          try {
            m_IntersectTolerance = tolerance;
            BuildIntersectList( topY );
            if (m_IntersectNodes == null)
                return;
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
                if (!TestIntersections()) 
                    throw new clipperException("Intersection error");
              }
            }
            ProcessIntersectList();
          }
          catch {
            m_SortedEdges = null;
            DisposeIntersectNodes();
            throw new clipperException("ProcessIntersections error");
          }
        }

        private void DisposeIntersectNodes()
        {
            while (m_IntersectNodes != null)
            {
                TIntersectNode iNode = m_IntersectNodes.next;
                m_IntersectNodes = null;
                m_IntersectNodes = iNode;
            }
        }

        private bool E1PrecedesE2inAEL(TEdge e1, TEdge e2)
        {
            while (e1 != null)
            {
                if (e1 == e2)
                    return true;
                else
                    e1 = e1.nextInAEL;
            }
            return false;
        }

        private bool Process1Before2(TIntersectNode Node1, TIntersectNode Node2)
        {
            if (Math.Abs(Node1.pt.Y - Node2.pt.Y) < m_IntersectTolerance)
            {
                if (Math.Abs(Node1.pt.X - Node2.pt.X) > precision)
                    return Node1.pt.X < Node2.pt.X;
                //a complex intersection (with more than 2 edges intersecting) ...
                if (Node1.edge1 == Node2.edge1 || SlopesEqual(Node1.edge1, Node2.edge1))
                {
                    if (Node1.edge2 == Node2.edge2)
                        //(N1.E1 & N2.E1 are co-linear) and (N1.E2 == N2.E2)  ...
                        return !E1PrecedesE2inAEL(Node1.edge1, Node2.edge1);
                    else if (SlopesEqual(Node1.edge2, Node2.edge2))
                        //(N1.E1 == N2.E1) and (N1.E2 & N2.E2 are co-linear) ...
                        return E1PrecedesE2inAEL(Node1.edge2, Node2.edge2);
                    else if //check if minima **
                      ((Math.Abs(Node1.edge2.y - Node1.pt.Y) < slope_precision ||
                      Math.Abs(Node2.edge2.y - Node2.pt.Y) < slope_precision) &&
                      (Node1.edge2.next == Node2.edge2 || Node1.edge2.prev == Node2.edge2))
                    {
                        if (Node1.edge1.dx < 0) return Node1.edge2.dx > Node2.edge2.dx;
                        else return Node1.edge2.dx < Node2.edge2.dx;
                    }
                    else if ((Node1.edge2.dx - Node2.edge2.dx) < precision)
                        return E1PrecedesE2inAEL(Node1.edge2, Node2.edge2);
                    else
                        return (Node1.edge2.dx < Node2.edge2.dx);

                }
                else if (Node1.edge2 == Node2.edge2 && //check if maxima ***
                  (Math.Abs(Node1.edge1.ytop - Node1.pt.Y) < slope_precision ||
                  Math.Abs(Node2.edge1.ytop - Node2.pt.Y) < slope_precision))
                    return (Node1.edge1.dx > Node2.edge1.dx);
                else
                    return (Node1.edge1.dx < Node2.edge1.dx);
            }
            else
                return (Node1.pt.Y > Node2.pt.Y);
            //**a minima that very slightly overlaps an edge can appear like
            //a complex intersection but it's not. (Minima can't have parallel edges.)
            //***a maxima that very slightly overlaps an edge can appear like
            //a complex intersection but it's not. (Maxima can't have parallel edges.)
        }
        
        private void AddIntersectNode(TEdge e1, TEdge e2, TDoublePoint pt)
        {
            TIntersectNode IntersectNode = new TIntersectNode { edge1 = e1, edge2 = e2, pt = pt, next = null, prev = null };
            if (m_IntersectNodes == null)
                m_IntersectNodes = IntersectNode;
            else if (Process1Before2(IntersectNode, m_IntersectNodes))
            {
                IntersectNode.next = m_IntersectNodes;
                m_IntersectNodes.prev = IntersectNode;
                m_IntersectNodes = IntersectNode;
            }
            else
            {
                TIntersectNode iNode = m_IntersectNodes;
                while (iNode.next != null && Process1Before2(iNode.next, IntersectNode))
                    iNode = iNode.next;
                if (iNode.next != null)
                    iNode.next.prev = IntersectNode;
                IntersectNode.next = iNode.next;
                IntersectNode.prev = iNode;
                iNode.next = IntersectNode;
            }
        }

        private void BuildIntersectList(double topY)
        {
            //prepare for sorting ...
            TEdge e = m_ActiveEdges;
            e.tmpX = TopX(e, topY);
            m_SortedEdges = e;
            m_SortedEdges.prevInSEL = null;
            e = e.nextInAEL;
            while (e != null)
            {
                e.prevInSEL = e.prevInAEL;
                e.prevInSEL.nextInSEL = e;
                e.nextInSEL = null;
                e.tmpX = TopX(e, topY);
                e = e.nextInAEL;
            }

            //bubblesort ...
            bool isModified = true;
            while (isModified && m_SortedEdges != null)
            {
                isModified = false;
                e = m_SortedEdges;
                while (e.nextInSEL != null)
                {
                    TEdge eNext = e.nextInSEL;
                    TDoublePoint pt = new TDoublePoint();
                    if ((e.tmpX > eNext.tmpX + tolerance) && IntersectPoint(e, eNext, pt))
                    {
                        AddIntersectNode(e, eNext, pt);
                        SwapPositionsInSEL(e, eNext);
                        isModified = true;
                    }
                    else
                        e = eNext;
                }
                if (e.prevInSEL != null)
                    e.prevInSEL.nextInSEL = null;
                else break;
            }
            m_SortedEdges = null;
        }
        
        private bool TestIntersections()
        {
            if (m_IntersectNodes == null)
                return true;
            //do the test sort using SEL ...
            CopyAELToSEL();
            TIntersectNode iNode = m_IntersectNodes;
            while (iNode != null)
            {
                SwapPositionsInSEL(iNode.edge1, iNode.edge2);
                iNode = iNode.next;
            }
            //now check that tmpXs are in the right order ...
            TEdge e = m_SortedEdges;
            while (e.nextInSEL != null)
            {
                if (e.nextInSEL.tmpX < e.tmpX - precision) return false;
                e = e.nextInSEL;
            }
            m_SortedEdges = null;
            return true;
        }

        private void ProcessIntersectList()
        {
            while (m_IntersectNodes != null)
            {
                TIntersectNode iNode = m_IntersectNodes.next;
                {
                    IntersectEdges(m_IntersectNodes.edge1,
                      m_IntersectNodes.edge2, m_IntersectNodes.pt, (ipLeft | ipRight));
                    SwapPositionsInAEL(m_IntersectNodes.edge1, m_IntersectNodes.edge2);
                }
                m_IntersectNodes = iNode;
            }
        }

        void DoEdge1(TEdge edge1, TEdge edge2, TDoublePoint pt)
        {
            AddPolyPt(edge1, pt);
            SwapSides(edge1, edge2);
            SwapPolyIndexes(edge1, edge2);
        }

        void DoEdge2(TEdge edge1, TEdge edge2, TDoublePoint pt)
        {
            AddPolyPt(edge2, pt);
            SwapSides(edge1, edge2);
            SwapPolyIndexes(edge1, edge2);
        }

        private void DoBothEdges(TEdge edge1, TEdge edge2, TDoublePoint pt)
        {
            AddPolyPt(edge1, pt);
            AddPolyPt(edge2, pt);
            SwapSides(edge1, edge2);
            SwapPolyIndexes(edge1, edge2);
        }

        private void IntersectEdges(TEdge e1, TEdge e2, TDoublePoint pt, int protects)
        {
            bool e1stops = !(Convert.ToBoolean(ipLeft & protects)) && e1.nextInLML == null &&
              (Math.Abs(e1.xtop - pt.X) < tolerance) && //nb: not precision
              (Math.Abs(e1.ytop - pt.Y) < precision);
            bool e2stops = !(Convert.ToBoolean(ipRight & protects)) && e2.nextInLML == null &&
              (Math.Abs(e2.xtop - pt.X) < tolerance) && //nb: not precision
              (Math.Abs(e2.ytop - pt.Y) < precision);
            bool e1Contributing = (e1.outIdx >= 0);
            bool e2contributing = (e2.outIdx >= 0);

            //update winding counts ...
            if (e1.polyType == e2.polyType)
            {
                if (IsNonZeroFillType(e1))
                {
                    if (e1.windCnt + e2.windDelta == 0) e1.windCnt = -e1.windCnt;
                    else e1.windCnt += e2.windDelta;
                    if (e2.windCnt - e1.windDelta == 0) e2.windCnt = -e2.windCnt;
                    else e2.windCnt -= e1.windDelta;
                }
                else
                {
                    int oldE1WindCnt = e1.windCnt;
                    e1.windCnt = e2.windCnt;
                    e2.windCnt = oldE1WindCnt;
                }
            }
            else
            {
                if (IsNonZeroFillType(e2)) e1.windCnt2 += e2.windDelta;
                else e1.windCnt2 = (e1.windCnt2 == 0) ? 1 : 0;
                if (IsNonZeroFillType(e1)) e2.windCnt2 -= e1.windDelta;
                else e2.windCnt2 = (e2.windCnt2 == 0) ? 1 : 0;
            }

            if (e1Contributing && e2contributing)
            {
                if (e1stops || e2stops || Math.Abs(e1.windCnt) > 1 ||
                  Math.Abs(e2.windCnt) > 1 ||
                  (e1.polyType != e2.polyType && m_ClipType != TClipType.ctXor))
                    AddLocalMaxPoly( e1, e2, pt);
                else
                    DoBothEdges(e1, e2, pt);
            }
            else if (e1Contributing)
            {
                if (m_ClipType == TClipType.ctIntersection)
                {
                    if ((e2.polyType == TPolyType.ptSubject || e2.windCnt2 != 0) &&
                        Math.Abs(e2.windCnt) < 2)
                        DoEdge1(e1, e2, pt);
                }
                else
                {
                    if (Math.Abs(e2.windCnt) < 2)
                        DoEdge1(e1, e2, pt);
                }
            }
            else if (e2contributing)
            {
                if (m_ClipType == TClipType.ctIntersection)
                {
                    if ((e1.polyType == TPolyType.ptSubject || e1.windCnt2 != 0) &&
                  Math.Abs(e1.windCnt) < 2) DoEdge2(e1, e2, pt);
                }
                else
                {
                    if (Math.Abs(e1.windCnt) < 2)
                        DoEdge2(e1, e2, pt);
                }
            }
            else if (Math.Abs(e1.windCnt) < 2 && Math.Abs(e2.windCnt) < 2) 
            {
                //neither edge is currently contributing ...
                if (e1.polyType != e2.polyType && !e1stops && !e2stops &&
                  Math.Abs(e1.windCnt) < 2 && Math.Abs(e2.windCnt) < 2)
                    AddLocalMinPoly(e1, e2, pt);
                else if (Math.Abs(e1.windCnt) == 1 && Math.Abs(e2.windCnt) == 1)
                    switch (m_ClipType)
                    {
                        case TClipType.ctIntersection:
                            {
                                if (Math.Abs(e1.windCnt2) > 0 && Math.Abs(e2.windCnt2) > 0)
                                    AddLocalMinPoly(e1, e2, pt);
                                break;
                            }
                        case TClipType.ctUnion:
                            {
                                if (e1.windCnt2 == 0 && e2.windCnt2 == 0)
                                    AddLocalMinPoly(e1, e2, pt);
                                break;
                            }
                        case TClipType.ctDifference:
                            {
                                if ((e1.polyType == TPolyType.ptClip && e2.polyType == TPolyType.ptClip &&
                              e1.windCnt2 != 0 && e2.windCnt2 != 0) ||
                              (e1.polyType == TPolyType.ptSubject && e2.polyType == TPolyType.ptSubject &&
                              e1.windCnt2 == 0 && e2.windCnt2 == 0))
                                    AddLocalMinPoly(e1, e2, pt);
                                break;
                            }
                        case TClipType.ctXor:
                            {
                                AddLocalMinPoly(e1, e2, pt);
                                break;
                            }
                    }
                else if (Math.Abs(e1.windCnt) < 2 && Math.Abs(e2.windCnt) < 2)
                    SwapSides(e1, e2);
            }

            if ((e1stops != e2stops) &&
              ((e1stops && (e1.outIdx >= 0)) || (e2stops && (e2.outIdx >= 0))))
            {
                SwapSides(e1, e2);
                SwapPolyIndexes(e1, e2);
            }

            //finally, delete any non-contributing maxima edges  ...
            if (e1stops) DeleteFromAEL(e1);
            if (e2stops) DeleteFromAEL(e2);
        }

        private void DeleteFromAEL(TEdge e)
        {
            TEdge AelPrev = e.prevInAEL;
            TEdge AelNext = e.nextInAEL;
            if (AelPrev == null && AelNext == null && (e != m_ActiveEdges))
                return; //already deleted
            if (AelPrev != null)
                AelPrev.nextInAEL = AelNext;
            else m_ActiveEdges = AelNext;
            if (AelNext != null)
                AelNext.prevInAEL = AelPrev;
            e.nextInAEL = null;
            e.prevInAEL = null;
        }

        private void DeleteFromSEL(TEdge e)
        {
            TEdge SelPrev = e.prevInSEL;
            TEdge SelNext = e.nextInSEL;
            if (SelPrev == null && SelNext == null && (e != m_SortedEdges))
                return; //already deleted
            if (SelPrev != null)
                SelPrev.nextInSEL = SelNext;
            else m_SortedEdges = SelNext;
            if (SelNext != null)
                SelNext.prevInSEL = SelPrev;
            e.nextInSEL = null;
            e.prevInSEL = null;
        }

        private void UpdateEdgeIntoAEL(ref TEdge e)
        {
            if (e.nextInLML == null)
                throw new clipperException("UpdateEdgeIntoAEL: invalid call");
            TEdge AelPrev = e.prevInAEL;
            TEdge AelNext = e.nextInAEL;
            e.nextInLML.outIdx = e.outIdx;
            if (AelPrev != null)
                AelPrev.nextInAEL = e.nextInLML;
            else m_ActiveEdges = e.nextInLML;
            if (AelNext != null)
                AelNext.prevInAEL = e.nextInLML;
            e.nextInLML.side = e.side;
            e.nextInLML.windDelta = e.windDelta;
            e.nextInLML.windCnt = e.windCnt;
            e.nextInLML.windCnt2 = e.windCnt2;
            e = e.nextInLML;
            e.prevInAEL = AelPrev;
            e.nextInAEL = AelNext;
            if (!IsHorizontal(e))
                InsertScanbeam(e.ytop);
        }
        
        private bool IsContributing(TEdge edge)
        {
            switch (m_ClipType)
            {
                case TClipType.ctIntersection:
                    if (edge.polyType == TPolyType.ptSubject)
                        return Math.Abs(edge.windCnt) == 1 && edge.windCnt2 != 0;
                    else
                        return Math.Abs(edge.windCnt2) > 0 && Math.Abs(edge.windCnt) == 1;
                case TClipType.ctUnion:
                    return Math.Abs(edge.windCnt) == 1 && edge.windCnt2 == 0;
                case TClipType.ctDifference:
                    if (edge.polyType == TPolyType.ptSubject)
                        return Math.Abs(edge.windCnt) == 1 && edge.windCnt2 == 0;
                    else
                        return Math.Abs(edge.windCnt) == 1 && edge.windCnt2 != 0;
                default: //case ctXor:
                    return Math.Abs(edge.windCnt) == 1;
            }
        }

        public bool Execute(TClipType clipType, TPolyPolygon solution, TPolyFillType subjFillType, TPolyFillType clipFillType)
        {
            m_SubjFillType = subjFillType;
            m_ClipFillType = clipFillType;

            solution.Clear();
            if (m_ExecuteLocked || !InitializeScanbeam())
                return false;
            try
            {
                m_ExecuteLocked = true;
                m_ActiveEdges = null;
                m_SortedEdges = null;
                m_ClipType = clipType;
                m_HoleStatesPending = false;

                double ybot = PopScanbeam();
                do
                {
                    InsertLocalMinimaIntoAEL(ybot);
                    if (m_HoleStatesPending) UpdateHoleStates();
                    ProcessHorizontals();
                    if (m_HoleStatesPending) UpdateHoleStates();
                    double ytop = PopScanbeam();
                    ProcessIntersections(ytop);
                    if (m_HoleStatesPending) UpdateHoleStates();
                    ProcessEdgesAtTopOfScanbeam(ytop);
                    if (m_HoleStatesPending) UpdateHoleStates();
                    ybot = ytop;
                } while (m_Scanbeam != null);

                //build the return polygons ...
                BuildResult(solution);
                DisposeAllPolyPts();
                m_ExecuteLocked = false;
                return true;
            }
            catch
            {
                //returns false ...
            }
            DisposeAllPolyPts();
            m_ExecuteLocked = false;
            return false;
        }

        private void FixupSolutionColinears(PolyPtList list, int idx)
        {
            //fixup any occasional 'empty' protrusions (ie adjacent parallel edges)
            bool ptDeleted;
            TPolyPt pp = list[idx];
            do
            {
                if (pp.prev == pp) return;
                //test for same slope ... (cross-product)
                if (Math.Abs((pp.pt.Y - pp.prev.pt.Y) * (pp.next.pt.X - pp.pt.X) -
                    (pp.pt.X - pp.prev.pt.X) * (pp.next.pt.Y - pp.pt.Y)) < precision)
                {
                    pp.prev.next = pp.next;
                    pp.next.prev = pp.prev;
                    TPolyPt tmp = pp;
                    if (list[idx] == pp)
                    {
                        list[idx] = pp.prev;
                        pp = pp.next;
                    }
                    else pp = pp.prev;
                    ptDeleted = true;
                }
                else
                {
                    pp = pp.next;
                    ptDeleted = false;
                }
            } while (ptDeleted || pp != list[idx]);
        }

        private void BuildResult(TPolyPolygon polypoly)
        {
            int k = 0;

            for (int i = 0; i < m_PolyPts.Count; ++i)
            {
                if (m_PolyPts[i] != null)
                {

                    FixupSolutionColinears(m_PolyPts, i);

                    TPolyPt pt = m_PolyPts[i];
                    int cnt = 0;
                    double y = pt.pt.Y;
                    bool isHorizontalOnly = true;
                    do
                    {
                        pt = pt.next;
                        if (isHorizontalOnly && Math.Abs(pt.pt.Y - y) > precision)
                            isHorizontalOnly = false;
                        ++cnt;
                    } while (pt != m_PolyPts[i]);
                    if (cnt < 3 || isHorizontalOnly) continue;

                    //validate the orientation of simple polygons ...
                    if (ForceOrientation() && !ValidateOrientation(pt))
                        ReversePolyPtLinks(pt);

                    polypoly.Add(new TPolygon());
                    for (int j = 0; j < cnt; ++j)
                    {
                        polypoly[k].Add(new TDoublePoint());
                        polypoly[k][j].X = pt.pt.X;
                        polypoly[k][j].Y = pt.pt.Y;
                        pt = pt.next;
                    }
                    ++k;
                }
            }
        }

        private bool ForceOrientation()
        {
            return m_ForceOrientation;
        }

        private void ForceOrientation(bool value)
        {
            m_ForceOrientation = value;
        }

        private TEdge BubbleSwap(TEdge edge)
        {
            int cnt = 1;
            TEdge result = edge.nextInAEL;
            while (result != null && (Math.Abs(result.xbot - edge.xbot) <= tolerance))
            {
                ++cnt;
                result = result.nextInAEL;
            }

            //let e = no edges in a complex intersection
            //let cnt = no intersection ops between those edges at that intersection
            //then ... e =1, cnt =0; e =2, cnt =1; e =3, cnt =3; e =4, cnt =6; ...
            //series s (where s = intersections per no edges) ... s = 0,1,3,6,10,15 ...
            //generalising: given i = e-1, and s[0] = 0, then ... cnt = i + s[i-1]
            //example: no. intersect ops required by 4 edges in a complex intersection ...
            //         cnt = 3 + 2 + 1 + 0 = 6 intersection ops
            if (cnt > 2)
            {
                //create the sort list ...
                try
                {
                    m_SortedEdges = edge;
                    edge.prevInSEL = null;
                    TEdge e = edge.nextInAEL;
                    for (int i = 2; i <= cnt; ++i)
                    {
                        e.prevInSEL = e.prevInAEL;
                        e.prevInSEL.nextInSEL = e;
                        if (i == cnt) e.nextInSEL = null;
                        e = e.nextInAEL;
                    }
                    while (m_SortedEdges != null && m_SortedEdges.nextInSEL != null)
                    {
                        e = m_SortedEdges;
                        while (e.nextInSEL != null)
                        {
                            if (e.nextInSEL.dx > e.dx)
                            {
                                IntersectEdges(e, e.nextInSEL, DoublePoint(e.xbot, e.ybot), (ipLeft | ipRight));
                                SwapPositionsInAEL(e, e.nextInSEL);
                                SwapPositionsInSEL(e, e.nextInSEL);
                            }
                            else
                                e = e.nextInSEL;
                        }
                        e.prevInSEL.nextInSEL = null; //removes 'e' from SEL
                    }
                }
                catch
                {
                    m_SortedEdges = null;
                    throw new clipperException("BubbleSwap error");
                }
                m_SortedEdges = null;
            }
            return result;
        }

        private void ProcessEdgesAtTopOfScanbeam(double topY)
        {
            TEdge e = m_ActiveEdges;
            while (e != null)
            {
                //1. process all maxima ...
                //   logic behind code - maxima are treated as if 'bent' horizontal edges
                if (IsMaxima(e, topY) && !IsHorizontal(GetMaximaPair(e)))
                {
                    //'e' might be removed from AEL, as may any following edges so ...
                    TEdge ePrior = e.prevInAEL;
                    DoMaxima(e, topY);
                    if (ePrior == null)
                        e = m_ActiveEdges;
                    else
                        e = ePrior.nextInAEL;
                }
                else
                {
                    //2. promote horizontal edges, otherwise update xbot and ybot ...
                    if (IsIntermediate(e, topY) && IsHorizontal(e.nextInLML))
                    {
                        if (e.outIdx >= 0) 
                            AddPolyPt(e, DoublePoint(e.xtop, e.ytop));
                        UpdateEdgeIntoAEL(ref e);
                        AddEdgeToSEL(e);
                    }
                    else
                    {
                        //this just simplifies horizontal processing ...
                        e.xbot = TopX(e, topY);
                        e.ybot = topY;
                    }
                    e = e.nextInAEL;
                }
            }

            //3. Process horizontals at the top of the scanbeam ...
            ProcessHorizontals();

            //4. Promote intermediate vertices ...
            e = m_ActiveEdges;
            while (e != null)
            {
                if (IsIntermediate(e, topY))
                {
                    if (e.outIdx >= 0) 
                        AddPolyPt(e, DoublePoint(e.xtop, e.ytop));
                    UpdateEdgeIntoAEL(ref e);
                }
                e = e.nextInAEL;
            }

            //5. Process (non-horizontal) intersections at the top of the scanbeam ...
            e = m_ActiveEdges;
            if (e !=null && e.nextInAEL == null)
                throw new clipperException("ProcessEdgesAtTopOfScanbeam() error");
            while (e != null)
            {
                if (e.nextInAEL == null)
                    break;
                if (e.nextInAEL.xbot < e.xbot - precision)
                    throw new clipperException("ProcessEdgesAtTopOfScanbeam() error");
                if (e.nextInAEL.xbot > e.xbot + tolerance)
                    e = e.nextInAEL;
                else
                    e = BubbleSwap(e);
            }
        }

        private void AddLocalMaxPoly(TEdge e1, TEdge e2, TDoublePoint pt)
        {
            AddPolyPt(e1, pt);
            if (EdgesShareSamePoly(e1, e2))
            {
                e1.outIdx = -1;
                e2.outIdx = -1;
            }
            else AppendPolygon(e1, e2);
        }

        private void AddLocalMinPoly(TEdge e1, TEdge e2, TDoublePoint pt)
        {
            AddPolyPt(e1, pt);
            e2.outIdx = e1.outIdx;

            if (IsHorizontal(e2) || (e1.dx > e2.dx))
            {
                e1.side = TEdgeSide.esLeft;
                e1.side = TEdgeSide.esLeft;
                e2.side = TEdgeSide.esRight;
            }
            else
            {
                e1.side = TEdgeSide.esRight;
                e2.side = TEdgeSide.esLeft;
            }

            if (m_ForceOrientation)
            {
                TPolyPt pp = m_PolyPts[e1.outIdx];
                pp.isHole = THoleState.sPending;
                m_HoleStatesPending = true;
            }
        }

        private void AppendPolygon(TEdge e1, TEdge e2)
        {
            if ((e1.outIdx < 0) || (e2.outIdx < 0))
                throw new clipperException("AppendPolygon error");

            //get the start and ends of both output polygons ...
            TPolyPt p1_lft = m_PolyPts[e1.outIdx];
            TPolyPt p1_rt = p1_lft.prev;
            TPolyPt p2_lft = m_PolyPts[e2.outIdx];
            TPolyPt p2_rt = p2_lft.prev;
            TEdgeSide side;

            //join e2 poly onto e1 poly and delete pointers to e2 ...
            if (e1.side == TEdgeSide.esLeft)
            {
                if (e2.side == TEdgeSide.esLeft)
                {
                    //z y x a b c
                    ReversePolyPtLinks(p2_lft);
                    p2_lft.next = p1_lft;
                    p1_lft.prev = p2_lft;
                    p1_rt.next = p2_rt;
                    p2_rt.prev = p1_rt;
                    m_PolyPts[e1.outIdx] = p2_rt;
                }
                else
                {
                    //x y z a b c
                    p2_rt.next = p1_lft;
                    p1_lft.prev = p2_rt;
                    p2_lft.prev = p1_rt;
                    p1_rt.next = p2_lft;
                    m_PolyPts[e1.outIdx] = p2_lft;
                }
                side = TEdgeSide.esLeft;
            }
            else
            {
                if (e2.side == TEdgeSide.esRight)
                {
                    //a b c z y x
                    ReversePolyPtLinks(p2_lft);
                    p1_rt.next = p2_rt;
                    p2_rt.prev = p1_rt;
                    p2_lft.next = p1_lft;
                    p1_lft.prev = p2_lft;
                }
                else
                {
                    //a b c x y z
                    p1_rt.next = p2_lft;
                    p2_lft.prev = p1_rt;
                    p1_lft.prev = p2_rt;
                    p2_rt.next = p1_lft;
                }
                side = TEdgeSide.esRight;
            }

            int ObsoleteIdx = e2.outIdx;
            e2.outIdx = -1;
            TEdge e = m_ActiveEdges;
            while (e != null)
            {
                if (e.
                outIdx == ObsoleteIdx)
                {
                    e.outIdx = e1.outIdx;
                    e.side = side;
                    break;
                }
                e = e.nextInAEL;
            }
            e1.outIdx = -1;
            m_PolyPts[ObsoleteIdx] = null;
        }
    }
    class clipperException : Exception
    {
        private string m_description;
        public clipperException(string description)
        {
            m_description = description;
            Console.WriteLine(m_description);
            throw new Exception(m_description);
        }
    }
}

 