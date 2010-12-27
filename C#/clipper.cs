/*******************************************************************************
*                                                                              *
* Author    :  Angus Johnson                                                   *
* Version   :  2.95                                                            *
* Date      :  27 December 2010                                                *
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
* Initial C# translation was kindly provided by                                *
* Olivier Lejeune <Olivier.Lejeune@2020.net>                                   *
*                                                                              *
*******************************************************************************/

using System;
using System.Collections.Generic;

namespace Clipper
{
    using TPolygon = List<TDoublePoint>;
    using PolyPtList = List<TPolyPt>;
    using JoinList = List<TJoinRec>;
    using TPolyPolygon = List<List<TDoublePoint>>;

    public enum TClipType { ctIntersection, ctUnion, ctDifference, ctXor };
    public enum TPolyType { ptSubject, ptClip };
    public enum TPolyFillType { pftEvenOdd, pftNonZero };

    //used internally ...
    enum TEdgeSide { esLeft, esRight };
    enum TTriState { sFalse, sTrue, sUndefined };
    enum TDirection { dRightToLeft, dLeftToRight };
    [Flags]
    enum TProtects { ipNone = 0, ipLeft = 1, ipRight = 2, ipBoth = 3 };

    public class TDoublePoint
    {
        public double X { get; set; }
        public double Y { get; set; }
        public TDoublePoint(double _X = 0, double _Y = 0)
        {
            X = _X; Y = _Y;
        }
    };

    public class TDoubleRect
    {
        public double left { get; set; }
        public double top { get; set; }
        public double right { get; set; }
        public double bottom { get; set; }
        public TDoubleRect(double _left = 0, double _top = 0, double _right = 0, double _bottom = 0)
        {
            left = _left; top = _top; right = _right; bottom = _bottom;
        }
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
        internal TTriState isHole;
    };

    internal class TJoinRec
    {
        internal TDoublePoint pt;
        internal int idx1;
        internal int idx2;
        internal TPolyPt outPPt; //horiz joins only
    }

    //------------------------------------------------------------------------------
    //------------------------------------------------------------------------------

    public class TClipperBase
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

        internal TLocalMinima m_localMinimaList;
        internal TLocalMinima m_CurrentLM;
        internal List<TEdge> m_edges = new List<TEdge>();

        internal static bool PointsEqual(TDoublePoint pt1, TDoublePoint pt2)
        {
            return (Math.Abs(pt1.X - pt2.X) < precision + tolerance && 
                Math.Abs(pt1.Y - pt2.Y) < precision + tolerance);
        }
        //------------------------------------------------------------------------------

        protected internal static bool PointsEqual(double pt1x, double pt1y, double pt2x, double pt2y)
        {
            return (Math.Abs(pt1x - pt2x) < precision + tolerance && 
                Math.Abs(pt1y - pt2y) < precision + tolerance);
        }
        //------------------------------------------------------------------------------

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
        //------------------------------------------------------------------------------

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
        //------------------------------------------------------------------------------

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
        //------------------------------------------------------------------------------

        internal static bool IsHorizontal(TEdge e)
        {
            return (e != null) && (e.dx < almost_infinite);
        }
        //------------------------------------------------------------------------------

        internal static void SwapSides(TEdge edge1, TEdge edge2)
        {
            TEdgeSide side = edge1.side;
            edge1.side = edge2.side;
            edge2.side = side;
        }
        //------------------------------------------------------------------------------

        internal static void SwapPolyIndexes(TEdge edge1, TEdge edge2)
        {
            int outIdx = edge1.outIdx;
            edge1.outIdx = edge2.outIdx;
            edge2.outIdx = outIdx;
        }
        //------------------------------------------------------------------------------

        internal static double TopX(TEdge edge, double currentY)
        {
            if (currentY == edge.ytop)
                return edge.xtop;
            return edge.x + edge.dx * (currentY - edge.y);
        }
        //------------------------------------------------------------------------------

        internal static bool EdgesShareSamePoly(TEdge e1, TEdge e2)
        {
            return (e1 != null) && (e2 != null) && (e1.outIdx == e2.outIdx);
        }
        //------------------------------------------------------------------------------

        internal static bool SlopesEqual(TEdge e1, TEdge e2)
        {
            if (IsHorizontal(e1))
                return IsHorizontal(e2);
            if (IsHorizontal(e2))
                return false;
            return Math.Abs((e1.ytop - e1.y) * (e2.xtop - e2.x) - 
                (e1.xtop - e1.x) * (e2.ytop - e2.y)) < slope_precision;
        }
        //------------------------------------------------------------------------------

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
        //------------------------------------------------------------------------------

        private static void InitEdge(TEdge e, TEdge eNext, TEdge ePrev, TDoublePoint pt)
        {
            e.x = pt.X;
            e.y = pt.Y;
            e.next = eNext;
            e.prev = ePrev;
            SetDx(e);
        }
        //------------------------------------------------------------------------------

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
        //------------------------------------------------------------------------------

        internal static bool SlopesEqualInternal(TEdge e1, TEdge e2)
        {
            if (IsHorizontal(e1))
                return IsHorizontal(e2);
            if (IsHorizontal(e2)) 
                return false;
            return Math.Abs((e1.y - e1.next.y) * (e2.x - e2.next.x) - 
                (e1.x - e1.next.x) * (e2.y - e2.next.y)) < slope_precision;
        }
        //------------------------------------------------------------------------------

        private static bool FixupForDupsAndColinear(ref TEdge e, TEdge edges)
        {
            bool result = false;
            while (e.next != e.prev && 
                (PointsEqual(e.prev.x, e.prev.y, e.x, e.y) || SlopesEqualInternal(e.prev, e)))
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
        //------------------------------------------------------------------------------

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
        //------------------------------------------------------------------------------

        public TClipperBase() //constructor
        {
            m_localMinimaList = null;
            m_CurrentLM = null;
        }
        //------------------------------------------------------------------------------

        ~TClipperBase() //destructor
        {
            Clear();
        }
        //------------------------------------------------------------------------------

        private bool LocalMinima2InsertsBefore1(TLocalMinima lm1, TLocalMinima lm2)
        {
            if (lm2.Y < lm1.Y) return false;
            if (lm2.Y > lm1.Y) return true;
            if (IsHorizontal(lm2.rightBound) && !IsHorizontal(lm1.rightBound)) return true;
            return false;
        }
        //----------------------------------------------------------------------

        void InsertLocalMinima(TLocalMinima newLm)
        {
            //nb: we'll make sure horizontal minima are sorted below other minima 
            //    of equal Y so that windings will be properly calculated ...
            if (m_localMinimaList == null)
                m_localMinimaList = newLm;
            else if (LocalMinima2InsertsBefore1(m_localMinimaList, newLm))
            {
                newLm.nextLm = m_localMinimaList;
                m_localMinimaList = newLm;
            }
            else
            {
                TLocalMinima tmpLm = m_localMinimaList;
                while (tmpLm.nextLm != null && LocalMinima2InsertsBefore1(newLm, tmpLm.nextLm))
                    tmpLm = tmpLm.nextLm;
                newLm.nextLm = tmpLm.nextLm;
                tmpLm.nextLm = newLm;
            }
        }
        //------------------------------------------------------------------------------
        
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
        //------------------------------------------------------------------------------

        private static TDoublePoint RoundToPrecision(TDoublePoint pt)
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
        //------------------------------------------------------------------------------

        public virtual void AddPolygon(TPolygon pg, TPolyType polyType)
        {
            int highI = pg.Count - 1;
            TPolygon p = new TPolygon(highI + 1);
            for (int i = 0; i <= highI; ++i)
                p.Add(RoundToPrecision(pg[i]));
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
        //------------------------------------------------------------------------------

        public virtual void AddPolyPolygon(TPolyPolygon ppg, TPolyType polyType)
        {
            for (int i = 0; i < ppg.Count; ++i)
                AddPolygon(ppg[i], polyType);
        }
        //------------------------------------------------------------------------------
    
        public void Clear()
        {
            DisposeLocalMinimaList();
            m_edges.Clear();
        }
        //------------------------------------------------------------------------------

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
        //------------------------------------------------------------------------------
        
        protected internal void PopLocalMinima()
        {
            if (m_CurrentLM == null)
                return;
            m_CurrentLM = m_CurrentLM.nextLm;
        }
        //------------------------------------------------------------------------------
        
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
        //------------------------------------------------------------------------------

        protected TDoubleRect GetBounds()
        {
            TLocalMinima lm = m_localMinimaList;
            if (lm == null) return new TDoubleRect(0, 0, 0, 0);
            
            TDoubleRect result = new TDoubleRect(-infinite, -infinite, infinite, infinite);
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
        //------------------------------------------------------------------------------

    }
    //------------------------------------------------------------------------------
    //------------------------------------------------------------------------------

    public class TClipper : TClipperBase
    {

        public static TDoubleRect GetBounds(TPolygon poly)
        {
            if (poly.Count == 0) return new TDoubleRect(0, 0, 0, 0);
            
            TDoubleRect result = new TDoubleRect(poly[0].X, poly[0].Y, poly[0].X, poly[0].Y);
            for (int i = 1; i < poly.Count; ++i)
            {
                if (poly[i].X < result.left) result.left = poly[i].X;
                else if (poly[i].X > result.right) result.right = poly[i].X;
                if (poly[i].Y < result.top) result.top = poly[i].Y;
                else if (poly[i].Y > result.bottom) result.bottom = poly[i].Y;
            }
            return result;
        }
        //------------------------------------------------------------------------------

        public static double Area(TPolygon poly)
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
        //------------------------------------------------------------------------------

        public static TPolyPolygon OffsetPolygons(TPolyPolygon pts, double delta)
        {

            //A positive delta will offset each polygon edge towards its left, so
            //polygons orientated clockwise (ie outer polygons) will expand but
            //inner polyons (holes) will shrink. Conversely, negative deltas will
            //offset polygon edges towards their right so outer polygons will shrink
            //and inner polygons will expand.

            double deltaSq = delta*delta;
            TPolyPolygon result = new TPolyPolygon(pts.Count);
            for (int j = 0; j < pts.Count; ++j)
            {

                int highI = pts[j].Count - 1;

                TPolygon pg = new TPolygon(highI *2 +2);
                result.Add(pg);
                
                //to minimize artefacts, strip out those polygons where
                //it's shrinking and where its area < Sqr(delta) ...
                double area = Area(pts[j]);
                if (delta < 0) { if (area > 0 && area < deltaSq) highI = 0;}
                else if (area < 0 && -area < deltaSq) highI = 0; //nb: a hole if area < 0

                if (highI < 2) continue;

                TPolygon normals = new TPolygon(highI+1);

                normals.Add(GetUnitNormal(pts[j][highI], pts[j][0]));
                for (int i = 1; i <= highI; ++i)
                    normals.Add(GetUnitNormal(pts[j][i - 1], pts[j][i]));
                for (int i = 0; i < highI; ++i)
                {
                    pg.Add(new TDoublePoint(pts[j][i].X + delta * normals[i].X,
                          pts[j][i].Y + delta * normals[i].Y));
                    pg.Add(new TDoublePoint(pts[j][i].X + delta * normals[i + 1].X,
                          pts[j][i].Y + delta * normals[i + 1].Y));
                }
                pg.Add(new TDoublePoint(pts[j][highI].X + delta * normals[highI].X,
                        pts[j][highI].Y + delta * normals[highI].Y));
                pg.Add(new TDoublePoint(pts[j][highI].X + delta * normals[0].X,
                        pts[j][highI].Y + delta * normals[0].Y));

                //round off reflex angles (ie > 180 deg) unless it's almost flat (ie < 10deg angle) ...
                //cross product normals < 0 . reflex angle; dot product normals == 1 . no angle
                if ((normals[highI].X * normals[0].Y - normals[0].X * normals[highI].Y) * delta > 0 &&
                  (normals[0].X * normals[highI].X + normals[0].Y * normals[highI].Y) < 0.985)
                {
                    double a1 = Math.Atan2(normals[highI].Y, normals[highI].X);
                    double a2 = Math.Atan2(normals[0].Y, normals[0].X);
                    if (delta > 0 && a2 < a1) a2 = a2 + Math.PI * 2;
                    else if (delta < 0 && a2 > a1) a2 = a2 - Math.PI * 2;
                    TPolygon arc = BuildArc(pts[j][highI], a1, a2, delta);
                    pg.InsertRange(highI * 2 + 1, arc);
                }
                for (int i = highI; i > 0; --i)
                    if ((normals[i - 1].X * normals[i].Y - normals[i].X * normals[i - 1].Y) * delta > 0 &&
                    (normals[i].X * normals[i - 1].X + normals[i].Y * normals[i - 1].Y) < 0.985)
                    {
                        double a1 = Math.Atan2(normals[i - 1].Y, normals[i - 1].X);
                        double a2 = Math.Atan2(normals[i].Y, normals[i].X);
                        if (delta > 0 && a2 < a1) a2 = a2 + Math.PI * 2;
                        else if (delta < 0 && a2 > a1) a2 = a2 - Math.PI * 2;
                        TPolygon arc = BuildArc(pts[j][i - 1], a1, a2, delta);
                        pg.InsertRange((i - 1) * 2 + 1, arc);
                    }
            }

            //finally, clean up untidy corners ...
            TClipper c = new TClipper();
            c.AddPolyPolygon(result, TPolyType.ptSubject);
            if (delta > 0)
            {
                if (!c.Execute(TClipType.ctUnion, result,
                    TPolyFillType.pftNonZero, TPolyFillType.pftNonZero)) result.Clear();
            }
            else
            {
                TDoubleRect r = c.GetBounds();
                TPolygon outer = new TPolygon(4);
                outer.Add(new TDoublePoint(r.left - 10, r.bottom + 10));
                outer.Add(new TDoublePoint(r.right + 10, r.bottom + 10));
                outer.Add(new TDoublePoint(r.right + 10, r.top - 10));
                outer.Add(new TDoublePoint(r.left - 10, r.top - 10));
                c.AddPolygon(outer, TPolyType.ptSubject);
                if (c.Execute(TClipType.ctUnion, result, TPolyFillType.pftNonZero, TPolyFillType.pftNonZero))
                    result.RemoveAt(0);
                else
                    result.Clear();

            }
            return result;
        }
        //------------------------------------------------------------------------------

        public static bool IsClockwise(TPolygon poly)
        {
          int highI = poly.Count -1;
          if (highI < 2) return false;
          double area = poly[highI].X * poly[0].Y - poly[0].X * poly[highI].Y;
          for (int i = 0; i < highI; ++i)
            area += poly[i].X * poly[i+1].Y - poly[i+1].X * poly[i].Y;
          //area := area/2;
          return area > 0; //ie reverse of normal formula because Y axis inverted
        }
        //------------------------------------------------------------------------------
        //------------------------------------------------------------------------------

        private PolyPtList m_PolyPts;
        private JoinList m_Joins;
        private JoinList m_CurrentHorizontals;
        private TClipType m_ClipType;
        private TScanbeam m_Scanbeam;
        private TEdge m_ActiveEdges;
        private TEdge m_SortedEdges;
        private TIntersectNode m_IntersectNodes;
        private bool m_ExecuteLocked;
        private bool m_ForceOrientation; //****DEPRECATED****
        private TPolyFillType m_ClipFillType;
        private TPolyFillType m_SubjFillType;
        private double m_IntersectTolerance;

        //------------------------------------------------------------------------------

        public TClipper()
        {
            m_Scanbeam = null;
            m_ActiveEdges = null;
            m_SortedEdges = null;
            m_IntersectNodes = null;
            m_ExecuteLocked = false;
            m_ForceOrientation = true;
            m_PolyPts = new PolyPtList();
            m_Joins = new JoinList();
            m_CurrentHorizontals = new JoinList();
        }
        //------------------------------------------------------------------------------
        
        internal void DisposeAllPolyPts()
        {
            for (int i = 0; i < m_PolyPts.Count; ++i)
                DisposePolyPts(m_PolyPts[i]);
            m_PolyPts.Clear();
        }
        //------------------------------------------------------------------------------

        internal void DisposeScanbeamList()
        {
            while (m_Scanbeam != null)
            {
                TScanbeam sb2 = m_Scanbeam.nextSb;
                m_Scanbeam = null;
                m_Scanbeam = sb2;
            }
        }
        //------------------------------------------------------------------------------
        
        public override void AddPolygon(TPolygon pg, TPolyType polyType)
        {
            base.AddPolygon(pg, polyType);
        }
        //------------------------------------------------------------------------------
        
        public override void AddPolyPolygon(TPolyPolygon ppg, TPolyType polyType)
        {
            base.AddPolyPolygon(ppg, polyType);
        }
        //------------------------------------------------------------------------------

        private static TDoublePoint GetUnitNormal(TDoublePoint pt1, TDoublePoint pt2)
        {
            double dx = (pt2.X - pt1.X);
            double dy = (pt2.Y - pt1.Y);
            if ((dx == 0) && (dy == 0))
                return new TDoublePoint(0, 0);

            //double f = 1 *1.0/ hypot( dx , dy );
            double f = 1 * 1.0 / Math.Sqrt(dx * dx + dy * dy);
            dx = dx * f;
            dy = dy * f;
            return new TDoublePoint(dy, -dx);
        }
        //------------------------------------------------------------------------------

        internal static bool ValidateOrientation(TPolyPt pt)
        {
            //first, find the hole state of the bottom-most point
            //(because the hole state of other points may not be reliable) ...
            TPolyPt bottomPt = pt;
            TPolyPt ptStart = pt;
            pt = pt.next;
            while ((pt != ptStart))
            {
                if (pt.pt.Y > bottomPt.pt.Y ||
                  (pt.pt.Y == bottomPt.pt.Y && pt.isHole != TTriState.sUndefined))
                    bottomPt = pt;
                pt = pt.next;
            }

            //check that orientation matches the hole status ...
            while (bottomPt.isHole == TTriState.sUndefined && bottomPt.next.pt.Y >= bottomPt.pt.Y)
                bottomPt = bottomPt.next;
            while (bottomPt.isHole == TTriState.sUndefined && bottomPt.prev.pt.Y >= bottomPt.pt.Y)
                bottomPt = bottomPt.prev;
            return (IsClockwise(pt) == (bottomPt.isHole != TTriState.sTrue));
        }
        //------------------------------------------------------------------------------

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
                result.Add(new TDoublePoint(pt.X + dx, pt.Y + dy));
                a = a + da;
            }
            return result;
        }
        //------------------------------------------------------------------------------

        private static bool IsClockwise(TPolyPt pt)
        {
            double area = 0;
            TPolyPt startPt = pt;
            do
            {
                area = area + (pt.pt.X * pt.next.pt.Y) - (pt.next.pt.X * pt.pt.Y);
                pt = pt.next;
            }
            while (pt != startPt);
            //area = area /2;
            return area > 0; //ie reverse of normal formula because Y axis inverted
        }
        //------------------------------------------------------------------------------

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
        //------------------------------------------------------------------------------

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
        //------------------------------------------------------------------------------

        private double PopScanbeam()
        {
            double Y = m_Scanbeam.Y;
            TScanbeam sb2 = m_Scanbeam;
            m_Scanbeam = m_Scanbeam.nextSb;
            return Y;
        }
        //------------------------------------------------------------------------------

        private void SetWindingDelta(TEdge edge)
        {
            if (!IsNonZeroFillType(edge))
                edge.windDelta = 1;
            else if (edge.nextAtTop)
                edge.windDelta = 1;
            else 
                edge.windDelta = -1;
        }
        //------------------------------------------------------------------------------

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
        //------------------------------------------------------------------------------

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
        //------------------------------------------------------------------------------

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
        //------------------------------------------------------------------------------

        private static bool Edge2InsertsBeforeEdge1(TEdge e1, TEdge e2)
        {
            if (e2.xbot - tolerance > e1.xbot) 
                return false;
            if (e2.xbot + tolerance < e1.xbot) 
                return true;
            if (IsHorizontal(e2)) 
                return false;
            return (e2.dx >= e1.dx);
        }
        //------------------------------------------------------------------------------

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
        //------------------------------------------------------------------------------

        bool HorizOverlap(double h1a, double h1b, double h2a, double h2b)
        {
            //returns true if (h1a between h2a and h2b) or
            //  (h1a == min2 and h1b > min2) or (h1a == max2 and h1b < max2)
            double min2, max2;
            if (h2a < h2b)
            {
                min2 = h2a;
                max2 = h2b;
            }
            else
            {
                min2 = h2b;
                max2 = h2a;
            }
            return (h1a > min2 + tolerance && h1a < max2 - tolerance) ||
              (Math.Abs(h1a - min2) < tolerance && h1b > min2 + tolerance) ||
              (Math.Abs(h1a - max2) < tolerance && h1b < max2 - tolerance);
        }
        //------------------------------------------------------------------------------

        private void InsertLocalMinimaIntoAEL(double botY, bool horizontals)
        {
            while (m_CurrentLM != null && (m_CurrentLM.Y == botY) &&
                  (!horizontals || IsHorizontal(m_CurrentLM.rightBound)))
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
                    AddLocalMinPoly(lm.leftBound, lm.rightBound, new TDoublePoint(lm.leftBound.xbot, lm.Y));

                //flag polygons that share colinear edges, so they can be merged later ...
                if (lm.leftBound.outIdx >= 0 && lm.leftBound.prevInAEL != null &&
                  lm.leftBound.prevInAEL.outIdx >= 0 &&
                  Math.Abs(lm.leftBound.prevInAEL.xbot - lm.leftBound.x) < tolerance &&
                  SlopesEqual(lm.leftBound, lm.leftBound.prevInAEL))
                {
                    TDoublePoint pt = new TDoublePoint(lm.leftBound.x, lm.leftBound.y);
                    TJoinRec polyPtRec = new TJoinRec();
                    AddPolyPt(lm.leftBound.prevInAEL, pt);
                    polyPtRec.idx1 = lm.leftBound.outIdx;
                    polyPtRec.idx2 = lm.leftBound.prevInAEL.outIdx;
                    m_Joins.Add(polyPtRec);
                }

                if (lm.rightBound.outIdx >= 0 && IsHorizontal(lm.rightBound))
                {
                    //check for overlap with m_CurrentHorizontals
                    for (int i = 0; i < m_CurrentHorizontals.Count; ++i)
                    {
                        int hIdx = m_CurrentHorizontals[i].idx1;
                        TDoublePoint hPt = m_CurrentHorizontals[i].outPPt.pt;
                        TDoublePoint hPt2 = m_CurrentHorizontals[i].pt;
                        TPolyPt p = m_CurrentHorizontals[i].outPPt;

                        TPolyPt p2;
                        if (IsHorizontal(p, p.prev) && (p.prev.pt.X == hPt2.X)) p2 = p.prev;
                        else if (IsHorizontal(p, p.next) && (p.next.pt.X == hPt2.X)) p2 = p.next;
                        else continue;

                        if (HorizOverlap(hPt.X, p2.pt.X, lm.rightBound.x, lm.rightBound.xtop))
                        {
                            AddPolyPt(lm.rightBound, hPt);
                            TJoinRec polyPtRec = new TJoinRec();
                            polyPtRec.idx1 = hIdx;
                            polyPtRec.idx2 = lm.rightBound.outIdx;
                            polyPtRec.pt = hPt;
                            m_Joins.Add(polyPtRec);
                        }
                        else if (HorizOverlap(lm.rightBound.x, lm.rightBound.xtop, hPt.X, hPt2.X))
                        {
                            TDoublePoint pt = new TDoublePoint(lm.rightBound.x, lm.rightBound.y);
                            TJoinRec polyPtRec = new TJoinRec();
                            if (!PointsEqual(pt, p.pt) && !PointsEqual(pt, p2.pt))
                                InsertPolyPtBetween(pt, p, p2);
                            polyPtRec.idx1 = hIdx;
                            polyPtRec.idx2 = lm.rightBound.outIdx;
                            polyPtRec.pt = pt;
                            m_Joins.Add(polyPtRec);                            
                        }
                    }
                }


                if (lm.leftBound.nextInAEL != lm.rightBound)
                {
                    TEdge e = lm.leftBound.nextInAEL;
                    TDoublePoint pt = new TDoublePoint(lm.leftBound.xbot, lm.leftBound.ybot);
                    while (e != lm.rightBound)
                    {
                        if (e == null)
                            throw new clipperException("InsertLocalMinimaIntoAEL: missing rightbound!");
                        //nb: For calculating winding counts etc, IntersectEdges() assumes
                        //that param1 will be to the right of param2 ABOVE the intersection ...
                        TEdge edgeRef = lm.rightBound;
                        IntersectEdges(edgeRef, e, pt, 0); //order important here
                        e = e.nextInAEL;
                    }
                }
                PopLocalMinima();
            }
            m_CurrentHorizontals.Clear();
        }
        //------------------------------------------------------------------------------

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
        //------------------------------------------------------------------------------
        
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
        //------------------------------------------------------------------------------

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
        //------------------------------------------------------------------------------
        
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
        //------------------------------------------------------------------------------

        private TEdge GetNextInAEL(TEdge e, TDirection Direction)
        {
            if (Direction == TDirection.dLeftToRight)
                return e.nextInAEL;
            else
                return e.prevInAEL;
        }
        //------------------------------------------------------------------------------

        private TEdge GetPrevInAEL(TEdge e, TDirection Direction)
        {
            if (Direction == TDirection.dLeftToRight)
                return e.prevInAEL;
            else return e.nextInAEL;
        }
        //------------------------------------------------------------------------------

        private bool IsMinima(TEdge e)
        {
            return e != null && (e.prev.nextInLML != e) && (e.next.nextInLML != e);
        }
        //------------------------------------------------------------------------------

        private bool IsMaxima(TEdge e, double Y)
        {
            return e != null && Math.Abs(e.ytop - Y) < tolerance && e.nextInLML == null;
        }
        //------------------------------------------------------------------------------

        private bool IsIntermediate(TEdge e, double Y)
        {
            return Math.Abs(e.ytop - Y) < tolerance && e.nextInLML != null;
        }
        //------------------------------------------------------------------------------

        private TEdge GetMaximaPair(TEdge e)
        {
            if (!IsMaxima(e.next, e.ytop) || (e.next.xtop != e.xtop))
                return e.prev;
            else
                return e.next;
        }
        //------------------------------------------------------------------------------

        private void DoMaxima(TEdge e, double topY)
        {
            TEdge eMaxPair = GetMaximaPair(e);
            double X = e.xtop;
            TEdge eNext = e.nextInAEL;
            while (eNext != eMaxPair)
            {
                if (eNext == null) throw new clipperException("DoMaxima error");
                IntersectEdges(e, eNext, new TDoublePoint(X, topY), TProtects.ipBoth);
                eNext = eNext.nextInAEL;
            }
            if ((e.outIdx < 0) && (eMaxPair.outIdx < 0))
            {
                DeleteFromAEL(e);
                DeleteFromAEL(eMaxPair);
            }
            else if ((e.outIdx >= 0) && (eMaxPair.outIdx >= 0))
            {
                IntersectEdges(e, eMaxPair, new TDoublePoint(X, topY), 0);
            }
            else 
                throw new clipperException("DoMaxima error");
        }
        //------------------------------------------------------------------------------

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
        //------------------------------------------------------------------------------

        bool IsHorizontal(TPolyPt pp1, TPolyPt pp2)
        {
            return (Math.Abs(pp1.pt.X - pp2.pt.X) > precision &&
              Math.Abs(pp1.pt.Y - pp2.pt.Y) < precision);
        }
        //------------------------------------------------------------------------------

        private bool IsTopHorz(TEdge horzEdge, double XPos)
        {
            TEdge e = m_SortedEdges;
            while (e != null)
            {
                if ((XPos >= Math.Min(e.xbot, e.xtop)) && (XPos <= Math.Max(e.xbot, e.xtop)))
                    return false;
                e = e.nextInSEL;
            }
            return true;
        }
        //------------------------------------------------------------------------------

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
                    if (Math.Abs(e.xbot - horzEdge.xtop) < tolerance && horzEdge.nextInLML != null)
                    {
                        if (SlopesEqual(e, horzEdge.nextInLML))
                        {
                            //we've got 2 colinear edges at the end of the horz. line ...
                            if (horzEdge.outIdx >= 0 && e.outIdx >= 0)
                            {
                                TDoublePoint pt = new TDoublePoint(horzEdge.xtop, horzEdge.ytop);
                                TJoinRec polyPtRec = new TJoinRec();
                                AddPolyPt(horzEdge, pt);
                                AddPolyPt(e, pt);
                                polyPtRec.idx1 = horzEdge.outIdx;
                                polyPtRec.idx2 = e.outIdx;
                                polyPtRec.pt = pt;
                                m_Joins.Add(polyPtRec);                            
                            }
                            break; //we've reached the end of the horizontal line
                        }
                        else if (e.dx < horzEdge.nextInLML.dx)
                            break; //we've reached the end of the horizontal line
                    }
                        
                    if (e == eMaxPair)
                    {
                        //horzEdge is evidently a maxima horizontal and we've arrived at its end.
                        if (Direction == TDirection.dLeftToRight)
                            IntersectEdges(horzEdge, e, new TDoublePoint(e.xbot, horzEdge.ybot), 0);
                        else
                            IntersectEdges(e, horzEdge, new TDoublePoint(e.xbot, horzEdge.ybot), 0);
                        return;
                    }
                    else if (IsHorizontal(e) && !IsMinima(e) && !(e.xbot > e.xtop))
                    {
                        if (Direction == TDirection.dLeftToRight)
                            IntersectEdges(horzEdge, e, new TDoublePoint(e.xbot, horzEdge.ybot),
                              (IsTopHorz(horzEdge, e.xbot)) ? TProtects.ipLeft : TProtects.ipBoth);
                        else
                            IntersectEdges(e, horzEdge, new TDoublePoint(e.xbot, horzEdge.ybot),
                              (IsTopHorz(horzEdge, e.xbot)) ? TProtects.ipRight : TProtects.ipBoth);
                    }
                    else if (Direction == TDirection.dLeftToRight)
                    {
                        IntersectEdges(horzEdge, e, new TDoublePoint(e.xbot, horzEdge.ybot),
                          (IsTopHorz(horzEdge, e.xbot)) ? TProtects.ipLeft : TProtects.ipBoth);
                    }
                    else
                    {
                        IntersectEdges(e, horzEdge, new TDoublePoint(e.xbot, horzEdge.ybot),
                          (IsTopHorz(horzEdge, e.xbot)) ? TProtects.ipRight : TProtects.ipBoth);
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
                    AddPolyPt(horzEdge, new TDoublePoint(horzEdge.xtop, horzEdge.ytop));
                UpdateEdgeIntoAEL(ref horzEdge);
            }
            else
            {
                if (horzEdge.outIdx >= 0)
                    IntersectEdges(horzEdge, eMaxPair,
                      new TDoublePoint(horzEdge.xtop, horzEdge.ybot), TProtects.ipBoth);
                DeleteFromAEL(eMaxPair);
                DeleteFromAEL(horzEdge);
            }
        }
        //------------------------------------------------------------------------------

        TPolyPt InsertPolyPtBetween(TDoublePoint pt, TPolyPt pp1, TPolyPt pp2)
        {
            TPolyPt pp = new TPolyPt();
            pp.pt = pt;
            pp.isHole = TTriState.sUndefined;
            if (pp2 == pp1.next)
            {
                pp.next = pp2;
                pp.prev = pp1;
                pp1.next = pp;
                pp2.prev = pp;
            }
            else if (pp1 == pp2.next)
            {
                pp.next = pp1;
                pp.prev = pp2;
                pp2.next = pp;
                pp1.prev = pp;
            }
            else throw new clipperException("InsertPolyPtBetween error");
            return pp;
        }
        //------------------------------------------------------------------------------

        private TPolyPt AddPolyPt(TEdge e, TDoublePoint pt)
        {
            bool ToFront = (e.side == TEdgeSide.esLeft);
            if (e.outIdx < 0)
            {
                TPolyPt newPolyPt = new TPolyPt();
                newPolyPt.pt = pt;
                m_PolyPts.Add(newPolyPt);
                newPolyPt.next = newPolyPt;
                newPolyPt.prev = newPolyPt;
                newPolyPt.isHole = TTriState.sUndefined;
                e.outIdx = m_PolyPts.Count - 1;
                return newPolyPt;
            }
            else
            {
                TPolyPt pp = m_PolyPts[e.outIdx];
                if (ToFront && PointsEqual(pt, pp.pt)) return pp;
                if (!ToFront && PointsEqual(pt, pp.prev.pt)) return pp.prev;
                TPolyPt newPolyPt = new TPolyPt();
                newPolyPt.pt = pt;
                newPolyPt.isHole = TTriState.sUndefined;
                newPolyPt.next = pp;
                newPolyPt.prev = pp.prev;
                newPolyPt.prev.next = newPolyPt;
                pp.prev = newPolyPt;
                if (ToFront) m_PolyPts[e.outIdx] = newPolyPt;
                return newPolyPt;
            }
        }
        //------------------------------------------------------------------------------

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
        //------------------------------------------------------------------------------

        private void DisposeIntersectNodes()
        {
            while (m_IntersectNodes != null)
            {
                TIntersectNode iNode = m_IntersectNodes.next;
                m_IntersectNodes = null;
                m_IntersectNodes = iNode;
            }
        }
        //------------------------------------------------------------------------------

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
        //------------------------------------------------------------------------------

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
        //------------------------------------------------------------------------------
        
        private void AddIntersectNode(TEdge e1, TEdge e2, TDoublePoint pt)
        {
            TIntersectNode IntersectNode = 
                new TIntersectNode { edge1 = e1, edge2 = e2, pt = pt, next = null, prev = null };
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
        //------------------------------------------------------------------------------

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
        //------------------------------------------------------------------------------
        
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
        //------------------------------------------------------------------------------

        private void ProcessIntersectList()
        {
            while (m_IntersectNodes != null)
            {
                TIntersectNode iNode = m_IntersectNodes.next;
                {
                    IntersectEdges(m_IntersectNodes.edge1,
                      m_IntersectNodes.edge2, m_IntersectNodes.pt, TProtects.ipBoth);
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
        //------------------------------------------------------------------------------

        void DoEdge2(TEdge edge1, TEdge edge2, TDoublePoint pt)
        {
            AddPolyPt(edge2, pt);
            SwapSides(edge1, edge2);
            SwapPolyIndexes(edge1, edge2);
        }
        //------------------------------------------------------------------------------

        private void DoBothEdges(TEdge edge1, TEdge edge2, TDoublePoint pt)
        {
            AddPolyPt(edge1, pt);
            AddPolyPt(edge2, pt);
            SwapSides(edge1, edge2);
            SwapPolyIndexes(edge1, edge2);
        }
        //------------------------------------------------------------------------------

        private void IntersectEdges(TEdge e1, TEdge e2, TDoublePoint pt, TProtects protects)
        {
            //e1 will be to the left of e2 BELOW the intersection. Therefore e1 is before
            //e2 in AEL except when e1 is being inserted at the intersection point ...

            bool e1stops = (TProtects.ipLeft & protects) == 0 && e1.nextInLML == null &&
              (Math.Abs(e1.xtop - pt.X) < tolerance) && //nb: not precision
              (Math.Abs(e1.ytop - pt.Y) < precision);
            bool e2stops = (TProtects.ipRight & protects) == 0 && e2.nextInLML == null &&
              (Math.Abs(e2.xtop - pt.X) < tolerance) && //nb: not precision
              (Math.Abs(e2.ytop - pt.Y) < precision);
            bool e1Contributing = (e1.outIdx >= 0);
            bool e2contributing = (e2.outIdx >= 0);

            //update winding counts...
            //assumes that e1 will be to the right of e2 ABOVE the intersection
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
        //------------------------------------------------------------------------------

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
        //------------------------------------------------------------------------------

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
        //------------------------------------------------------------------------------

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
            {
                InsertScanbeam(e.ytop);

                //if output polygons share an edge, they'll need joining later ...
                if (e.outIdx >= 0 && AelPrev != null && AelPrev.outIdx >= 0 &&
                  Math.Abs(AelPrev.xbot - e.x) < tolerance && SlopesEqual(e, AelPrev))
                {
                    TDoublePoint pt = new TDoublePoint(e.x, e.y);
                    TJoinRec polyPtRec = new TJoinRec();
                    AddPolyPt(AelPrev, pt);
                    AddPolyPt(e, pt);
                    polyPtRec.idx1 = AelPrev.outIdx;
                    polyPtRec.idx2 = e.outIdx;
                    polyPtRec.pt = pt;
                    m_Joins.Add(polyPtRec);                            
                }
            }
        }
        //------------------------------------------------------------------------------
        
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
        //------------------------------------------------------------------------------

        public bool Execute(TClipType clipType, TPolyPolygon solution, 
            TPolyFillType subjFillType, TPolyFillType clipFillType)
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
                m_Joins.Clear();
                m_CurrentHorizontals.Clear();
                double ybot = PopScanbeam();
                do
                {
                    //insert horizontals first to ensure winding counts are accurate ...
                    InsertLocalMinimaIntoAEL(ybot, true);
                    ProcessHorizontals();
                    //now insert other non-horizontal local minima ...
                    InsertLocalMinimaIntoAEL(ybot, false);
                    double ytop = PopScanbeam();
                    ProcessIntersections(ytop);
                    ProcessEdgesAtTopOfScanbeam(ytop);
                    ybot = ytop;
                } while (m_Scanbeam != null);

                //build the return polygons ...
                BuildResult(solution);
            }
            catch
            {
                return false;
            }
            finally
            {
                m_Joins.Clear();
                DisposeAllPolyPts();
                m_ExecuteLocked = false;
            }
            return true;
        }
        //------------------------------------------------------------------------------

        private TPolyPt FixupOutPolygon(TPolyPt p, bool stripPointyEdgesOnly = false)
        {
            //FixupOutPolygon() - removes duplicate points and simplifies consecutive
            //parallel edges by removing the middle vertex.
            //stripPointyEdgesOnly: removes the middle vertex only when consecutive
            //parallel edges reflect back on themselves ('pointy' edges). However, it
            //doesn't remove the middle vertex when edges are parallel continuations.
            //Given 3 consecutive vertices - o, *, and o ...
            //the form of 'non-pointy' parallel edges is : o--*----------o
            //the form of 'pointy' parallel edges is     : o--o----------*
            //(While merging polygons that share common edges, it's necessary to
            //temporarily retain 'non-pointy' parallel edges.)

            bool ptDeleted;
            bool firstPass = true;

            if (p == null) return null;
            TPolyPt pp = p, result = p;
            for (;;)
            {
                if (pp.prev == pp)
                {
                    pp = null;
                    return null;
                }
                //test for duplicate points and for same slope (cross-product) ...
                if ( PointsEqual(pp.pt, pp.next.pt) ||
                    (Math.Abs((pp.pt.Y - pp.prev.pt.Y)*(pp.next.pt.X - pp.pt.X) -
                    (pp.pt.X - pp.prev.pt.X)*(pp.next.pt.Y - pp.pt.Y)) < precision &&
                    (!stripPointyEdgesOnly ||
                    ((pp.pt.X - pp.prev.pt.X > 0) != (pp.next.pt.X - pp.pt.X > 0)) ||
                    ((pp.pt.Y - pp.prev.pt.Y > 0) != (pp.next.pt.Y - pp.pt.Y > 0)))))
                {
                    if (pp.isHole != TTriState.sUndefined && 
                        pp.next.isHole == TTriState.sUndefined) 
                          pp.next.isHole = pp.isHole;
                    pp.prev.next = pp.next;
                    pp.next.prev = pp.prev;
                    TPolyPt tmp = pp;
                    if (pp == result)
                    {
                        firstPass = true;
                        result = pp.prev;
                    }
                    pp = pp.prev;
                    tmp = null;
                    ptDeleted = true;
                }
                else
                {
                    pp = pp.next;
                    ptDeleted = false;
                }
                if (!firstPass) break;
                if (pp == result && !ptDeleted) firstPass = false;
            }
            return result;
        }
        //------------------------------------------------------------------------------

        private void BuildResult(TPolyPolygon polypoly)
        {
            int k = 0;

            MergePolysWithCommonEdges();
            for (int i = 0; i < m_PolyPts.Count; ++i)
            {
                if (m_PolyPts[i] != null)
                {
                    m_PolyPts[i] = FixupOutPolygon(m_PolyPts[i]);
                    if (m_PolyPts[i] == null) continue;

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
        //------------------------------------------------------------------------------

        private bool ForceOrientation()
        {
            return m_ForceOrientation;
        }
        //------------------------------------------------------------------------------

        private void ForceOrientation(bool value)
        {
            m_ForceOrientation = value;
        }
        //------------------------------------------------------------------------------

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
                                IntersectEdges(e, e.nextInSEL,  //param order important here
                                    new TDoublePoint(e.xbot, e.ybot), TProtects.ipBoth);
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
        //------------------------------------------------------------------------------

        private void ProcessEdgesAtTopOfScanbeam(double topY)
        {
            TEdge e = m_ActiveEdges;
            while (e != null)
            {
                //1. process maxima, treating them as if they're 'bent' horizontal edges,
                //   but exclude maxima with horizontal edges. nb: e can't be a horizontal.
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
                        {
                            TPolyPt pp = AddPolyPt(e, new TDoublePoint(e.xtop, e.ytop));
                            //add the polyPt to a list that later checks for overlaps with
                            //contributing horizontal minima since they'll need joining...
                            TJoinRec ch = new TJoinRec();
                            ch.idx1 = e.outIdx;
                            ch.pt = new TDoublePoint(e.nextInLML.xtop, e.nextInLML.ytop);
                            ch.outPPt = pp;
                            m_CurrentHorizontals.Add(ch);
                        }

                        //very rarely an edge just below a horizontal edge in a contour
                        //intersects with another edge at the very top of a scanbeam.
                        //If this happens that intersection must be managed first ...
                        if (e.prevInAEL != null && e.prevInAEL.xbot > e.xtop + tolerance)
                        {
                            IntersectEdges(e.prevInAEL, e, new TDoublePoint(e.prevInAEL.xbot,
                              e.prevInAEL.ybot), TProtects.ipBoth);
                            SwapPositionsInAEL(e.prevInAEL, e);
                            UpdateEdgeIntoAEL(ref e);
                            AddEdgeToSEL(e);
                            e = e.nextInAEL;
                            UpdateEdgeIntoAEL(ref e);
                            AddEdgeToSEL(e);
                        }
                        else if (e.nextInAEL != null && e.xtop > TopX(e.nextInAEL, topY) + tolerance)
                        {
                            e.nextInAEL.xbot = TopX(e.nextInAEL, topY);
                            e.nextInAEL.ybot = topY;
                            IntersectEdges(e, e.nextInAEL, new TDoublePoint(e.nextInAEL.xbot,
                              e.nextInAEL.ybot), TProtects.ipBoth);
                            SwapPositionsInAEL(e, e.nextInAEL);
                            UpdateEdgeIntoAEL(ref e);
                            AddEdgeToSEL(e);
                        }
                        else
                        {
                            UpdateEdgeIntoAEL(ref e);
                            AddEdgeToSEL(e);
                        }
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
                        AddPolyPt(e, new TDoublePoint(e.xtop, e.ytop));
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
        //------------------------------------------------------------------------------

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
                bool isAHole = false;
                TEdge e = m_ActiveEdges;
                while (e != null)
                {
                  if ( e.outIdx < 0 || e == e1 ) ; //ie do nothing
                  else if ( IsHorizontal( e ) && e.x < e1.x ) isAHole = !isAHole;
                  else 
                  {
                    double eX = TopX(e,pp.pt.Y);
                    if ( eX < pp.pt.X - precision || 
                        (Math.Abs(eX - pp.pt.X) < tolerance  && e.dx >= e1.dx) )
                            isAHole = !isAHole;
                  }
                  e = e.nextInAEL;
                }
                if (isAHole) pp.isHole = TTriState.sTrue; else pp.isHole = TTriState.sFalse;
            }
            e2.outIdx = e1.outIdx;
        }
        //------------------------------------------------------------------------------

        private void AppendPolygon(TEdge e1, TEdge e2)
        {
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

            int OKIdx = e1.outIdx;
            int ObsoleteIdx = e2.outIdx;
            m_PolyPts[ObsoleteIdx] = null;

            for (int i = 0; i < m_Joins.Count; ++i)
            {
                if (m_Joins[i].idx1 == ObsoleteIdx) m_Joins[i].idx1 = OKIdx;
                if (m_Joins[i].idx2 == ObsoleteIdx) m_Joins[i].idx2 = OKIdx;
            }
            for (int i = 0; i < m_CurrentHorizontals.Count; ++i)
                if (m_CurrentHorizontals[i].idx1 == ObsoleteIdx)
                    m_CurrentHorizontals[i].idx1 = OKIdx;

            e1.outIdx = -1;
            e2.outIdx = -1;
            TEdge e = m_ActiveEdges;
            while (e != null)
            {
                if (e.outIdx == ObsoleteIdx)
                {
                    e.outIdx = OKIdx;
                    e.side = side;
                    break;
                }
                e = e.nextInAEL;
            }
        }
        //------------------------------------------------------------------------------

        private bool SlopesEqual(TDoublePoint pt1a, TDoublePoint pt1b,
          TDoublePoint pt2a, TDoublePoint pt2b)
        {
          return Math.Abs((pt1b.Y - pt1a.Y) * (pt2b.X - pt2a.X) -
            (pt1b.X - pt1a.X) * (pt2b.Y - pt2a.Y)) < slope_precision;
        }
        //------------------------------------------------------------------------------

        private TPolyPt InsertPolyPt(TPolyPt afterPolyPt, TDoublePoint pt)
        {
          TPolyPt polyPt = new TPolyPt();
          polyPt.pt = pt;
          polyPt.prev = afterPolyPt;
          polyPt.next = afterPolyPt.next;
          afterPolyPt.next.prev = polyPt;
          afterPolyPt.next = polyPt;
          polyPt.isHole = TTriState.sUndefined;
          return polyPt;
        }
        //------------------------------------------------------------------------------

        bool PtInPoly(TDoublePoint pt, ref TPolyPt polyStartPt)
        {
          if (polyStartPt == null) return false;
          TPolyPt p = polyStartPt;
          do {
            if (PointsEqual(pt, polyStartPt.pt)) return true;
            polyStartPt = polyStartPt.next;
          }
          while (polyStartPt != p);
          return false;
        }
        //------------------------------------------------------------------------------

        void FixupJoins(int joinIdx)
        {
            int oldIdx = m_Joins[joinIdx].idx2;
            int newIdx = m_Joins[joinIdx].idx1;
            for (int i = joinIdx + 1; i < m_Joins.Count; ++i)
                if (m_Joins[i].idx1 == oldIdx) m_Joins[i].idx1 = newIdx;
                else if (m_Joins[i].idx2 == oldIdx) m_Joins[i].idx2 = newIdx;
        }
        //------------------------------------------------------------------------------

        void MergePolysWithCommonEdges()
        {
          for (int i = 0; i < m_Joins.Count; ++i)
          {
            //It's problematic merging overlapping edges in the same output polygon.
            //While creating 2 polygons from one would be straightforward,
            //FixupJoins() would no longer work safely ...
            if (m_Joins[i].idx1 == m_Joins[i].idx2) continue;

            TPolyPt p1 = m_PolyPts[m_Joins[i].idx1];
            p1 = FixupOutPolygon(p1, true);
            m_PolyPts[m_Joins[i].idx1] = p1;

            TPolyPt p2 = m_PolyPts[m_Joins[i].idx2];
            p2 = FixupOutPolygon(p2, true);
            m_PolyPts[m_Joins[i].idx2] = p2;

            if (!PtInPoly(m_Joins[i].pt, ref p1) || !PtInPoly(m_Joins[i].pt, ref p2)) continue;

            //nb: p1.pt == p2.pt;

            if (((p1.next.pt.X > p1.pt.X && p2.next.pt.X > p2.pt.X) || 
                (p1.next.pt.Y < p1.pt.Y && p2.next.pt.Y < p2.pt.Y)) &&
                SlopesEqual(p1.pt, p1.next.pt, p2.pt, p2.next.pt))
            {
              TPolyPt pp1 = InsertPolyPt(p1, p1.pt);
              TPolyPt pp2 = InsertPolyPt(p2, p2.pt);
              ReversePolyPtLinks( p2 );
              pp1.prev = pp2;
              pp2.next = pp1;
              p1.next = p2;
              p2.prev = p1;
            }
            else if (((p1.next.pt.X > p1.pt.X && p2.prev.pt.X > p2.pt.X) ||
                (p1.next.pt.Y < p1.pt.Y && p2.prev.pt.Y < p2.pt.Y)) &&
                SlopesEqual(p1.pt, p1.next.pt, p2.pt, p2.prev.pt))
            {
              TPolyPt pp1 = InsertPolyPt(p1, p1.pt);
              TPolyPt pp2 = InsertPolyPt(p2.prev, p2.pt);
              p1.next = p2;
              p2.prev = p1;
              pp2.next = pp1;
              pp1.prev = pp2;
            }
            else if (((p1.prev.pt.X > p1.pt.X && p2.next.pt.X > p2.pt.X) ||
                (p1.prev.pt.Y < p1.pt.Y && p2.next.pt.Y < p2.pt.Y)) &&
                SlopesEqual(p1.pt, p1.prev.pt, p2.pt, p2.next.pt))
            {
              TPolyPt pp1 = InsertPolyPt(p1.prev, p1.pt);
              TPolyPt pp2 = InsertPolyPt(p2, p2.pt);
              pp1.next = pp2;
              pp2.prev = pp1;
              p1.prev = p2;
              p2.next = p1;
            }
            else if (((p1.prev.pt.X > p1.pt.X && p2.prev.pt.X > p2.pt.X) ||
                (p1.prev.pt.Y < p1.pt.Y && p2.prev.pt.Y < p2.pt.Y)) &&
                SlopesEqual(p1.pt, p1.prev.pt, p2.pt, p2.prev.pt))
            {
              TPolyPt pp1 = InsertPolyPt(p1.prev, p1.pt);
              TPolyPt pp2 = InsertPolyPt(p2.prev, p2.pt);
              ReversePolyPtLinks(p2);
              p1.prev = p2;
              p2.next = p1;
              pp1.next = pp2;
              pp2.prev = pp1;
            }
            else
              continue;

            //When polygons are joined, pointers referencing a 'deleted' polygon
            //must point to the merged polygon ...
            m_PolyPts[m_Joins[i].idx2] = null;
            FixupJoins(i);
          }
        }
        //------------------------------------------------------------------------------
    }
    //------------------------------------------------------------------------------
    //------------------------------------------------------------------------------
    
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
    //------------------------------------------------------------------------------
}

 