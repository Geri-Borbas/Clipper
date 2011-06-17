/*******************************************************************************
*                                                                              *
* Author    :  Angus Johnson                                                   *
* Version   :  4.3.0                                                           *
* Date      :  16 June 2011                                                    *
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
*******************************************************************************/

/*******************************************************************************
*                                                                              *
* This is a translation of the Delphi Clipper library and the naming style     *
* used has retained a Delphi flavour.                                          *
*                                                                              *
*******************************************************************************/

using System;
using System.Collections.Generic;
//using System.Text; //for Int128.AsString() & StringBuilder

namespace clipper
{

    using Polygon = List<IntPoint>;
    using Polygons = List<List<IntPoint>>;
    using ExPolygons = List<ExPolygon>;
        
    //------------------------------------------------------------------------------
    // Int128 class (enables safe math on signed 64bit integers)
    // eg Int128 val1((Int64)9223372036854775807); //ie 2^63 -1
    //    Int128 val2((Int64)9223372036854775807);
    //    Int128 val3 = val1 * val2;
    //    val3.ToString => "85070591730234615847396907784232501249" (8.5e+37)
    //------------------------------------------------------------------------------

    internal class Int128
    {
        private Int64 hi;
        private Int64 lo;
    
        public Int128(Int64 _lo = 0)
        {
            hi = 0;
            lo = Math.Abs(_lo);
            if (_lo < 0) Negate(this);
        }

        public Int128(Int128 val)
        {
            Assign(val);
        }

        public void Assign(Int128 val)
        {
            hi = val.hi; lo = val.lo;
        }

        static private void Negate(Int128 val)
        {
            if (val.lo == 0)
            {
            if( val.hi == 0) return;
            val.lo = ~val.lo;
            val.hi = ~val.hi +1;
            }
            else
            {
            val.lo = ~val.lo +1;
            val.hi = ~val.hi;
            }
        }

        public static bool operator== (Int128 val1, Int128 val2)
        {
            if ((object)val1 == (object)val2) return true;
            else if ((object)val1 == null || (object)val2 == null) return false;
            return (val1.hi == val2.hi && val1.lo == val2.lo);
        }

        public static bool operator!= (Int128 val1, Int128 val2) 
        { 
            return !(val1 == val2); 
        }

        public override bool Equals(System.Object obj)
        {
            if (obj == null) return false;
            Int128 i128 = obj as Int128;
            if (i128 == null) return false;
            return (i128.hi == hi && i128.lo == lo);
        }

        public override int GetHashCode()
        {
            return hi.GetHashCode() ^ lo.GetHashCode();
        }

        public static bool operator> (Int128 val1, Int128 val2) 
        {
            if (System.Object.ReferenceEquals(val1, val2)) return false;
            else if (val2 == null) return true;
            else if (val1 == null) return false;
            else if (val1.hi > val2.hi) return true;
            else if (val1.hi < val2.hi) return false;
            else if (val1.hi >= 0) return (UInt64)val1.lo > (UInt64)val2.lo;
            else return (UInt64)val1.lo < (UInt64)val2.lo;
        }

        public static bool operator< (Int128 val1, Int128 val2) 
        {
            if (System.Object.ReferenceEquals(val1, val2)) return false;
            else if (val2 == null) return false;
            else if (val1 == null) return true;
            if (val1.hi < val2.hi) return true;
            else if (val1.hi > val2.hi) return false;
            else if (val1.hi >= 0) return (UInt64)val1.lo < (UInt64)val2.lo;
            else return (UInt64)val1.lo > (UInt64)val2.lo;
        }

        public static Int128 operator+ (Int128 lhs, Int128 rhs) 
        {
            Int64 xlo = lhs.lo;
            lhs.hi += rhs.hi; lhs.lo += rhs.lo;
            if((xlo < 0 && rhs.lo < 0) || (((xlo < 0) != (rhs.lo < 0)) && lhs.lo >= 0)) lhs.hi++;
            return lhs;
        }

        public static Int128 operator- (Int128 lhs, Int128 rhs) 
        {
            Int128 tmp = new Int128(rhs);
            Negate(tmp);
            lhs += tmp;
            return lhs;
        }

        //nb: Constructing two new Int128 objects every time we want to multiply Int64s  
        //is slow. So, although calling the Int128Mul method doesn't look as clean, the 
        //code runs significantly faster than if we'd used the * operator.
        //public static Int128 operator *(Int128 lhs, Int128 rhs)
        //{
        //    if (!(lhs.hi == 0 || lhs.hi == -1) || !(rhs.hi == 0 || rhs.hi == -1))
        //        throw new Exception("Int128 operator*: overflow error");
        //    return Int128Mul(lhs.lo, rhs.lo);
        //}
        
        public static Int128 Int128Mul(Int64 lhs, Int64 rhs)
        {
            bool negate = (lhs < 0) != (rhs < 0);
            if (lhs < 0) lhs = -lhs;
            if (rhs < 0) rhs = -rhs;
            UInt64 int1Hi = (UInt64)lhs >> 32;
            UInt64 int1Lo = (UInt64)lhs & 0xFFFFFFFF;
            UInt64 int2Hi = (UInt64)rhs >> 32;
            UInt64 int2Lo = (UInt64)rhs & 0xFFFFFFFF;

            //nb: see comments in clipper.pas
            UInt64 a = int1Hi * int2Hi;
            UInt64 b = int1Lo * int2Lo;
            UInt64 c = int1Hi * int2Lo + int1Lo * int2Hi; //nb avoid karatsuba

            Int128 result = new Int128();
            result.lo = (Int64)(c << 32);
            result.hi = (Int64)(a + (c >> 32));
            bool hiBitSet = (result.lo < 0);
            result.lo += (Int64)b;
            if ((hiBitSet && ((Int64)b < 0)) ||
            ((hiBitSet != ((Int64)b < 0)) && (result.lo >= 0))) result.hi++;
            if (negate) Negate(result);
            return result;
        }

        public static Int128 operator /(Int128 lhs, Int128 rhs)
        {
            if (rhs.lo == 0 && rhs.hi == 0)
                throw new Exception("Int128 operator/: divide by zero");
            bool negate = (rhs.hi < 0) != (lhs.hi < 0);
            Int128 result = new Int128(lhs), denom = new Int128(rhs);
            if (result.hi < 0) Negate(result);
            if (denom.hi < 0) Negate(denom);
            if (denom > result) return new Int128(0); //result is only a fraction of 1
            Negate(denom);

            Int128 p = new Int128(0), p2 = new Int128(0);
            for (int i = 0; i < 128; ++i)
            {
                p.hi = p.hi << 1;
                if (p.lo < 0) p.hi++;
                p.lo = (Int64)p.lo << 1;
                if (result.hi < 0) p.lo++;
                result.hi = result.hi << 1;
                if (result.lo < 0) result.hi++;
                result.lo = (Int64)result.lo << 1;
                p2.Assign(p);
                p += denom;
                if (p.hi < 0) p.Assign(p2);
                else result.lo++;
            }
            if (negate) Negate(result);
            return result;
        }

        public double ToDouble()
        {
            const double shift64 = 18446744073709551616.0; //2^64
            if (hi < 0)
            {
                Int128 tmp = new Int128(this);
                Negate(tmp);
                return -((double)tmp.lo + (double)tmp.hi * shift64);
            }
            else return (double)lo + (double)hi * shift64;
        }

        ////for bug testing ...
        //public string ToString()
        //{
        //    int r = 0;
        //    Int128 tmp = new Int128(0), val = new Int128(this);
        //    if (hi < 0) Negate(val);
        //    StringBuilder builder = new StringBuilder(50);
        //    while (val.hi != 0 || val.lo != 0)
        //    {
        //        Div10(val, ref tmp, ref r);
        //        builder.Insert(0, (char)('0' + r));
        //        val.Assign(tmp);
        //    }
        //    if (hi < 0) return '-' + builder.ToString();
        //    if (builder.Length == 0) return "0";
        //    return builder.ToString();
        //}

        ////debugging only ...
        //private void Div10(Int128 val, ref Int128 result, ref int remainder)
        //{
        //    remainder = 0;
        //    result = new Int128(0);
        //    for (int i = 63; i >= 0; --i)
        //    {
        //    if ((val.hi & ((Int64)1 << i)) != 0)
        //        remainder = (remainder * 2) + 1; else
        //        remainder *= 2;
        //    if (remainder >= 10)
        //    {
        //        result.hi += ((Int64)1 << i);
        //        remainder -= 10;
        //    }
        //    }
        //    for (int i = 63; i >= 0; --i)
        //    {
        //    if ((val.lo & ((Int64)1 << i)) != 0)
        //        remainder = (remainder * 2) + 1; else
        //        remainder *= 2;
        //    if (remainder >= 10)
        //    {
        //        result.lo += ((Int64)1 << i);
        //        remainder -= 10;
        //    }
        //    }
        //}
    };

    //------------------------------------------------------------------------------
    //------------------------------------------------------------------------------
   
    public class IntPoint
    {
        public Int64 X { get; set; }
        public Int64 Y { get; set; }
        public IntPoint(Int64 X = 0, Int64 Y = 0)
        {
            this.X = X; this.Y = Y;
        }
        public IntPoint(IntPoint pt)
        {
            this.X = pt.X; this.Y = pt.Y;
        }
    }

    public class IntRect
    {
        public Int64 left { get; set; }
        public Int64 top { get; set; }
        public Int64 right { get; set; }
        public Int64 bottom { get; set; }
        public IntRect(Int64 l = 0, Int64 t = 0, Int64 r = 0, Int64 b = 0)
        {
            this.left = l; this.top = t;
            this.right = r; this.bottom = b;
        }
    }

    public class ExPolygon
    {
        public Polygon outer;
        public Polygons holes;
    }

    public enum ClipType { ctIntersection, ctUnion, ctDifference, ctXor };
    public enum PolyType { ptSubject, ptClip };
    public enum PolyFillType { pftEvenOdd, pftNonZero };


    internal enum EdgeSide { esLeft, esRight };
    internal enum Direction { dRightToLeft, dLeftToRight };
    [Flags]
    internal enum Protects { ipNone = 0, ipLeft = 1, ipRight = 2, ipBoth = 3 };

    internal class TEdge {
        public Int64 xbot;
        public Int64 ybot;
        public Int64 xcurr;
        public Int64 ycurr;
        public Int64 xtop;
        public Int64 ytop;
        public double dx;
        public Int64 tmpX;
        public PolyType polyType;
        public EdgeSide side;
        public int windDelta; //1 or -1 depending on winding direction
        public int windCnt;
        public int windCnt2; //winding count of the opposite polytype
        public int outIdx;
        public TEdge next;
        public TEdge prev;
        public TEdge nextInLML;
        public TEdge nextInAEL;
        public TEdge prevInAEL;
        public TEdge nextInSEL;
        public TEdge prevInSEL;
    };

    internal class IntersectNode
    {
        public TEdge edge1;
        public TEdge edge2;
        public IntPoint pt;
        public IntersectNode next;
    };

    internal class LocalMinima
    {
        public Int64 Y;
        public TEdge leftBound;
        public TEdge rightBound;
        public LocalMinima next;
    };

    internal class Scanbeam
    {
        public Int64 Y;
        public Scanbeam next;
    };


    internal class OutRec
    {
        public int idx;
        public bool isHole;
        public OutRec FirstLeft;
        public OutRec AppendLink;
        public OutPt pts;
        public OutPt bottomPt;
    };

    internal class OutPt
    {
        public int idx;
        public IntPoint pt;
        public OutPt next;
        public OutPt prev;
    };

    internal class JoinRec
    {
        public IntPoint pt1a;
        public IntPoint pt1b;
        public int poly1Idx;
        public IntPoint pt2a;
        public IntPoint pt2b;
        public int poly2Idx;
    };

    internal class HorzJoinRec
    {
        public TEdge edge;
        public int savedIdx;
    };

    public class ClipperBase
    {
        protected const double horizontal = -3.4E+38;
        internal LocalMinima m_MinimaList;
        internal LocalMinima m_CurrentLM;
        internal List<List<TEdge>> m_edges = new List<List<TEdge>>();
        internal bool m_UseFullRange;

        //------------------------------------------------------------------------------

        protected bool PointsEqual(IntPoint pt1, IntPoint pt2)
        {
          return ( pt1.X == pt2.X && pt1.Y == pt2.Y );
        }
        //------------------------------------------------------------------------------

        internal bool PointIsVertex(IntPoint pt, OutPt pp)
        {
          OutPt pp2 = pp;
          do
          {
            if (PointsEqual(pp2.pt, pt)) return true;
            pp2 = pp2.next;
          }
          while (pp2 != pp);
          return false;
        }
        //------------------------------------------------------------------------------

        internal bool PointInPolygon(IntPoint pt, OutPt pp, bool UseFullInt64Range)
        {
          OutPt pp2 = pp;
          bool result = false;
          if (UseFullInt64Range)
          {
              do
              {
                  if ((((pp2.pt.Y <= pt.Y) && (pt.Y < pp2.prev.pt.Y)) ||
                      ((pp2.prev.pt.Y <= pt.Y) && (pt.Y < pp2.pt.Y))) &&
                      new Int128(pt.X - pp2.pt.X) < 
                      Int128.Int128Mul(pp2.prev.pt.X - pp2.pt.X,  pt.Y - pp2.pt.Y) / 
                      new Int128(pp2.prev.pt.Y - pp2.pt.Y))
                        result = !result;
                  pp2 = pp2.next;
              }
              while (pp2 != pp);
          }
          else
          {
              do
              {
                  if ((((pp2.pt.Y <= pt.Y) && (pt.Y < pp2.prev.pt.Y)) ||
                    ((pp2.prev.pt.Y <= pt.Y) && (pt.Y < pp2.pt.Y))) &&
                    (pt.X - pp2.pt.X < (pp2.prev.pt.X - pp2.pt.X) * (pt.Y - pp2.pt.Y) /
                    (pp2.prev.pt.Y - pp2.pt.Y))) result = !result;
                  pp2 = pp2.next;
              }
              while (pp2 != pp);
          }
          return result;
        }
        //------------------------------------------------------------------------------

        internal bool SlopesEqual(TEdge e1, TEdge e2, bool UseFullInt64Range)
        {
            if (e1.ybot == e1.ytop) return (e2.ybot == e2.ytop);
            else if (e1.xbot == e1.xtop) return (e2.xbot == e2.xtop);
            else if (UseFullInt64Range)
              return Int128.Int128Mul(e1.ytop - e1.ybot, e2.xtop - e2.xbot) ==
                  Int128.Int128Mul(e1.xtop - e1.xbot, e2.ytop - e2.ybot);
            else return (Int64)(e1.ytop - e1.ybot) * (e2.xtop - e2.xbot) -
              (Int64)(e1.xtop - e1.xbot)*(e2.ytop - e2.ybot) == 0;
        }
        //------------------------------------------------------------------------------

        protected bool SlopesEqual(IntPoint pt1, IntPoint pt2,
            IntPoint pt3, bool UseFullInt64Range)
        {
            if (pt1.Y == pt2.Y) return (pt2.Y == pt3.Y);
            else if (pt1.X == pt2.X) return (pt2.X == pt3.X);
            else if (UseFullInt64Range)
                return Int128.Int128Mul(pt1.Y - pt2.Y, pt2.X - pt3.X) ==
                  Int128.Int128Mul(pt1.X - pt2.X, pt2.Y - pt3.Y);
            else return
              (Int64)(pt1.Y - pt2.Y) * (pt2.X - pt3.X) - (Int64)(pt1.X - pt2.X) * (pt2.Y - pt3.Y) == 0;
        }
        //------------------------------------------------------------------------------

        protected bool SlopesEqual(IntPoint pt1, IntPoint pt2,
            IntPoint pt3, IntPoint pt4, bool UseFullInt64Range)
        {
            if (pt1.Y == pt2.Y) return (pt3.Y == pt4.Y);
            else if (pt1.X == pt2.X) return (pt3.X == pt4.X);
            else if (UseFullInt64Range)
                return Int128.Int128Mul(pt1.Y - pt2.Y, pt3.X - pt4.X) ==
                  Int128.Int128Mul(pt1.X - pt2.X, pt3.Y - pt4.Y);
            else return
              (Int64)(pt1.Y - pt2.Y) * (pt3.X - pt4.X) - (Int64)(pt1.X - pt2.X) * (pt3.Y - pt4.Y) == 0;
        }
        //------------------------------------------------------------------------------

        internal ClipperBase() //constructor (nb: no external instantiation)
        {
            m_MinimaList = null;
            m_CurrentLM = null;
            m_UseFullRange = true; //ie default for UseFullCoordinateRange == true
        }
        //------------------------------------------------------------------------------

        ~ClipperBase() //destructor
        {
            Clear();
        }
        //------------------------------------------------------------------------------

        public bool UseFullCoordinateRange
        {
            get { return m_UseFullRange; }
            set 
            {
                if (m_edges.Count > 0 && value == true)
                    throw new Exception("UseFullCoordinateRange() can't be changed "+      
                        "until the Clipper object has been cleared.");
                m_UseFullRange = value; 
            }
        }
        //------------------------------------------------------------------------------

        public virtual void Clear()
        {
            DisposeLocalMinimaList();
            for (int i = 0; i < m_edges.Count; ++i)
            {
                for (int j = 0; j < m_edges[i].Count; ++j) m_edges[i][j] = null;
                m_edges[i].Clear();
            }
            m_edges.Clear();
        }
        //------------------------------------------------------------------------------

        private void DisposeLocalMinimaList()
        {
            while( m_MinimaList != null )
            {
                LocalMinima tmpLm = m_MinimaList.next;
                m_MinimaList = null;
                m_MinimaList = tmpLm;
            }
            m_CurrentLM = null;
        }
        //------------------------------------------------------------------------------

        public bool AddPolygons(Polygons ppg, PolyType polyType)
        {
            bool result = false;
            for (int i = 0; i < ppg.Count; ++i)
                if (AddPolygon(ppg[i], polyType)) result = true;
            return result;
        }
        //------------------------------------------------------------------------------

        public bool AddPolygon(Polygon pg, PolyType polyType)
        {
            int len = pg.Count;
            if (len < 3) return false;
            Polygon p = new Polygon(len);
            p.Add(new IntPoint(pg[0].X, pg[0].Y));
            int j = 0;
            for (int i = 1; i < len; ++i)
            {
                const Int64 MaxVal = 1500000000; //~ Sqrt(2^63)/2 => 1.5e+9 (see SlopesEqual)
                if (!m_UseFullRange && 
                    (Math.Abs(pg[i].X) > MaxVal || Math.Abs(pg[i].Y) > MaxVal))
                        throw new ClipperException("Integer exceeds range bounds");
                
                if (PointsEqual(p[j], pg[i])) continue;
                else if (j > 0 && SlopesEqual(p[j-1], p[j], pg[i], m_UseFullRange))
                {
                    if (PointsEqual(p[j-1], pg[i])) j--;
                } else j++;
                if (j < p.Count)
                    p[j] = pg[i]; else
                    p.Add(new IntPoint(pg[i].X, pg[i].Y));
            }
            if (j < 2) return false;

            len = j+1;
            for (;;)
            {
            //nb: test for point equality before testing slopes ...
            if (PointsEqual(p[j], p[0])) j--;
            else if (PointsEqual(p[0], p[1]) || SlopesEqual(p[j], p[0], p[1], m_UseFullRange))
                p[0] = p[j--];
            else if (SlopesEqual(p[j-1], p[j], p[0], m_UseFullRange)) j--;
            else if (SlopesEqual(p[0], p[1], p[2], m_UseFullRange))
            {
                for (int i = 2; i <= j; ++i) p[i-1] = p[i];
                j--;
            }
            //exit loop if nothing is changed or there are too few vertices ...
            if (j == len-1 || j < 2) break;
            len = j +1;
            }
            if (len < 3) return false;

            //create a new edge array ...
            List<TEdge> edges = new List<TEdge>(len);
            for (int i = 0; i < len; i++) edges.Add(new TEdge());
            m_edges.Add(edges);

            //convert vertices to a double-linked-list of edges and initialize ...
            edges[0].xcurr = p[0].X;
            edges[0].ycurr = p[0].Y;
            InitEdge(edges[len-1], edges[0], edges[len-2], p[len-1], polyType);
            for (int i = len-2; i > 0; --i)
            InitEdge(edges[i], edges[i+1], edges[i-1], p[i], polyType);
            InitEdge(edges[0], edges[1], edges[len-1], p[0], polyType);

            //reset xcurr & ycurr and find 'eHighest' (given the Y axis coordinates
            //increase downward so the 'highest' edge will have the smallest ytop) ...
            TEdge e = edges[0];
            TEdge eHighest = e;
            do
            {
            e.xcurr = e.xbot;
            e.ycurr = e.ybot;
            if (e.ytop < eHighest.ytop) eHighest = e;
            e = e.next;
            }
            while ( e != edges[0]);

            //make sure eHighest is positioned so the following loop works safely ...
            if (eHighest.windDelta > 0) eHighest = eHighest.next;
            if (eHighest.dx == horizontal) eHighest = eHighest.next;

            //finally insert each local minima ...
            e = eHighest;
            do {
            e = AddBoundsToLML(e);
            }
            while( e != eHighest );
            return true;
        }
        //------------------------------------------------------------------------------

        private void InitEdge(TEdge e, TEdge eNext,
          TEdge ePrev, IntPoint pt, PolyType polyType)
        {
          e.next = eNext;
          e.prev = ePrev;
          e.xcurr = pt.X;
          e.ycurr = pt.Y;
          if (e.ycurr >= e.next.ycurr)
          {
            e.xbot = e.xcurr;
            e.ybot = e.ycurr;
            e.xtop = e.next.xcurr;
            e.ytop = e.next.ycurr;
            e.windDelta = 1;
          } else
          {
            e.xtop = e.xcurr;
            e.ytop = e.ycurr;
            e.xbot = e.next.xcurr;
            e.ybot = e.next.ycurr;
            e.windDelta = -1;
          }
          SetDx(e);
          e.polyType = polyType;
          e.outIdx = -1;
        }
        //------------------------------------------------------------------------------

        private void SetDx(TEdge e)
        {
          if (e.ybot == e.ytop) e.dx = horizontal;
          else e.dx = (double)(e.xtop - e.xbot)/(e.ytop - e.ybot);
        }
        //---------------------------------------------------------------------------

        TEdge AddBoundsToLML(TEdge e)
        {
          //Starting at the top of one bound we progress to the bottom where there's
          //a local minima. We then go to the top of the next bound. These two bounds
          //form the left and right (or right and left) bounds of the local minima.
          e.nextInLML = null;
          e = e.next;
          for (;;)
          {
            if ( e.dx == horizontal )
            {
              //nb: proceed through horizontals when approaching from their right,
              //    but break on horizontal minima if approaching from their left.
              //    This ensures 'local minima' are always on the left of horizontals.
              if (e.next.ytop < e.ytop && e.next.xbot > e.prev.xbot) break;
              if (e.xtop != e.prev.xbot) SwapX(e);
              e.nextInLML = e.prev;
            }
            else if (e.ycurr == e.prev.ycurr) break;
            else e.nextInLML = e.prev;
            e = e.next;
          }

          //e and e.prev are now at a local minima ...
          LocalMinima newLm = new LocalMinima();
          newLm.next = null;
          newLm.Y = e.prev.ybot;

          if ( e.dx == horizontal ) //horizontal edges never start a left bound
          {
            if (e.xbot != e.prev.xbot) SwapX(e);
            newLm.leftBound = e.prev;
            newLm.rightBound = e;
          } else if (e.dx < e.prev.dx)
          {
            newLm.leftBound = e.prev;
            newLm.rightBound = e;
          } else
          {
            newLm.leftBound = e;
            newLm.rightBound = e.prev;
          }
          newLm.leftBound.side = EdgeSide.esLeft;
          newLm.rightBound.side = EdgeSide.esRight;
          InsertLocalMinima( newLm );

          for (;;)
          {
            if ( e.next.ytop == e.ytop && e.next.dx != horizontal ) break;
            e.nextInLML = e.next;
            e = e.next;
            if ( e.dx == horizontal && e.xbot != e.prev.xtop) SwapX(e);
          }
          return e.next;
        }
        //------------------------------------------------------------------------------

        private void InsertLocalMinima(LocalMinima newLm)
        {
          if( m_MinimaList == null )
          {
            m_MinimaList = newLm;
          }
          else if( newLm.Y >= m_MinimaList.Y )
          {
            newLm.next = m_MinimaList;
            m_MinimaList = newLm;
          } else
          {
            LocalMinima tmpLm = m_MinimaList;
            while( tmpLm.next != null  && ( newLm.Y < tmpLm.next.Y ) )
              tmpLm = tmpLm.next;
            newLm.next = tmpLm.next;
            tmpLm.next = newLm;
          }
        }
        //------------------------------------------------------------------------------

        protected void PopLocalMinima()
        {
            if (m_CurrentLM == null) return;
            m_CurrentLM = m_CurrentLM.next;
        }
        //------------------------------------------------------------------------------

        private void SwapX(TEdge e)
        {
          //swap horizontal edges' top and bottom x's so they follow the natural
          //progression of the bounds - ie so their xbots will align with the
          //adjoining lower edge. [Helpful in the ProcessHorizontal() method.]
          e.xcurr = e.xtop;
          e.xtop = e.xbot;
          e.xbot = e.xcurr;
        }
        //------------------------------------------------------------------------------

        protected virtual void Reset()
        {
            m_CurrentLM = m_MinimaList;

            //reset all edges ...
            LocalMinima lm = m_MinimaList;
            while (lm != null)
            {
                TEdge e = lm.leftBound;
                while (e != null)
                {
                    e.xcurr = e.xbot;
                    e.ycurr = e.ybot;
                    e.side = EdgeSide.esLeft;
                    e.outIdx = -1;
                    e = e.nextInLML;
                }
                e = lm.rightBound;
                while (e != null)
                {
                    e.xcurr = e.xbot;
                    e.ycurr = e.ybot;
                    e.side = EdgeSide.esRight;
                    e.outIdx = -1;
                    e = e.nextInLML;
                }
                lm = lm.next;
            }
            return;
        }
        //------------------------------------------------------------------------------

        public IntRect GetBounds()
        {
          IntRect result = new IntRect();
          LocalMinima lm = m_MinimaList;
          if (lm == null) return result;
          result.left = lm.leftBound.xbot;
          result.top = lm.leftBound.ybot;
          result.right = lm.leftBound.xbot;
          result.bottom = lm.leftBound.ybot;
          while (lm != null)
          {
            if (lm.leftBound.ybot > result.bottom)
              result.bottom = lm.leftBound.ybot;
            TEdge e = lm.leftBound;
            for (;;) {
              while (e.nextInLML != null)
              {
                if (e.xbot < result.left) result.left = e.xbot;
                if (e.xbot > result.right) result.right = e.xbot;
                e = e.nextInLML;
              }
              if (e.xbot < result.left) result.left = e.xbot;
              if (e.xbot > result.right) result.right = e.xbot;
              if (e.xtop < result.left) result.left = e.xtop;
              if (e.xtop > result.right) result.right = e.xtop;
              if (e.ytop < result.top) result.top = e.ytop;

              if (e == lm.leftBound) e = lm.rightBound;
              else break;
            }
            lm = lm.next;
          }
          return result;
        }

    } //ClipperBase

    public class Clipper : ClipperBase
    {
    
        private List<OutRec> m_PolyOuts;
        private ClipType m_ClipType;
        private Scanbeam m_Scanbeam;
        private TEdge m_ActiveEdges;
        private TEdge m_SortedEdges;
        private IntersectNode m_IntersectNodes;
        private bool m_ExecuteLocked;
        private PolyFillType m_ClipFillType;
        private PolyFillType m_SubjFillType;
        private List<JoinRec> m_Joins;
        private List<HorzJoinRec> m_HorizJoins;

        public Clipper()
        {
            m_Scanbeam = null;
            m_ActiveEdges = null;
            m_SortedEdges = null;
            m_IntersectNodes = null;
            m_ExecuteLocked = false;
            m_PolyOuts = new List<OutRec>();
            m_Joins = new List<JoinRec>();
            m_HorizJoins = new List<HorzJoinRec>();
        }
        //------------------------------------------------------------------------------

        ~Clipper() //destructor
        {
            Clear();
            DisposeScanbeamList();
        }
        //------------------------------------------------------------------------------

        public override void Clear()
        {
            if (m_edges.Count == 0) return; //avoids problems with ClipperBase destructor
            DisposeAllPolyPts();
            base.Clear();
        }
        //------------------------------------------------------------------------------

        void DisposeScanbeamList()
        {
          while ( m_Scanbeam != null ) {
          Scanbeam sb2 = m_Scanbeam.next;
          m_Scanbeam = null;
          m_Scanbeam = sb2;
          }
        }
        //------------------------------------------------------------------------------

        protected override void Reset() 
        {
          base.Reset();
          m_Scanbeam = null;
          m_ActiveEdges = null;
          m_SortedEdges = null;
          DisposeAllPolyPts();
          LocalMinima lm = m_MinimaList;
          while (lm != null)
          {
            InsertScanbeam(lm.Y);
            InsertScanbeam(lm.leftBound.ytop);
            lm = lm.next;
          }
        }
        //------------------------------------------------------------------------------

        private void InsertScanbeam(Int64 Y)
        {
          if( m_Scanbeam == null )
          {
            m_Scanbeam = new Scanbeam();
            m_Scanbeam.next = null;
            m_Scanbeam.Y = Y;
          }
          else if(  Y > m_Scanbeam.Y )
          {
            Scanbeam newSb = new Scanbeam();
            newSb.Y = Y;
            newSb.next = m_Scanbeam;
            m_Scanbeam = newSb;
          } else
          {
            Scanbeam sb2 = m_Scanbeam;
            while( sb2.next != null  && ( Y <= sb2.next.Y ) ) sb2 = sb2.next;
            if(  Y == sb2.Y ) return; //ie ignores duplicates
            Scanbeam newSb = new Scanbeam();
            newSb.Y = Y;
            newSb.next = sb2.next;
            sb2.next = newSb;
          }
        }
        //------------------------------------------------------------------------------

        public bool Execute(ClipType clipType, Polygons solution,
            PolyFillType subjFillType, PolyFillType clipFillType)
        {
            if (m_ExecuteLocked) return false;
            m_ExecuteLocked = true;
            solution.Clear();
            m_SubjFillType = subjFillType;
            m_ClipFillType = clipFillType;
            m_ClipType = clipType;
            bool succeeded = ExecuteInternal(false);
            //build the return polygons ...
            if (succeeded) BuildResult(solution);
            m_ExecuteLocked = false;
            return succeeded;
        }
        //------------------------------------------------------------------------------

        public bool Execute(ClipType clipType, ExPolygons solution,
            PolyFillType subjFillType, PolyFillType clipFillType)
        {
            if (m_ExecuteLocked) return false;
            m_ExecuteLocked = true;
            solution.Clear();
            m_SubjFillType = subjFillType;
            m_ClipFillType = clipFillType;
            m_ClipType = clipType;
            bool succeeded = ExecuteInternal(true);
            //build the return polygons ...
            if (succeeded) BuildResultEx(solution);
            m_ExecuteLocked = false;
            return succeeded;
        }
        //------------------------------------------------------------------------------

        internal int PolySort(OutRec or1, OutRec or2)
        {
          if (or1 == or2) return 0;
          else if (or1.pts == null || or2.pts == null)
          {
            if ((or1.pts == null) != (or2.pts == null))
            {
                if (or1.pts != null) return -1; else return 1;
            }
            else return 0;          
          }
          int i1, i2;
          if (or1.isHole)
            i1 = or1.FirstLeft.idx; else
            i1 = or1.idx;
          if (or2.isHole)
            i2 = or2.FirstLeft.idx; else
            i2 = or2.idx;
          int result = i1 - i2;
          if (result == 0 && (or1.isHole != or2.isHole))
          {
              if (or1.isHole) return 1;
              else return -1;
          }
          return result;
        }
        //------------------------------------------------------------------------------

        internal OutRec FindAppendLinkEnd(OutRec outRec)
        {
          while (outRec.AppendLink != null) outRec = outRec.AppendLink;
          return outRec;
        }
        //------------------------------------------------------------------------------

        internal void FixHoleLinkage(OutRec outRec)
        {
            OutRec tmp;
            if (outRec.bottomPt != null) 
                tmp = m_PolyOuts[outRec.bottomPt.idx].FirstLeft; else
                tmp = outRec.FirstLeft;
            //avoid a very rare endless loop (via recursion) ...
            if (outRec == tmp) 
            {
                outRec.FirstLeft = null;
                outRec.AppendLink = null;
                outRec.isHole = false;
                return;
            }

            if (tmp != null) 
            {
                if (tmp.AppendLink != null) tmp = FindAppendLinkEnd(tmp);
                if (tmp == outRec) tmp = null;
                else if (tmp.isHole)
                {
                    FixHoleLinkage(tmp);
                    tmp = tmp.FirstLeft;
                }
            }
            outRec.FirstLeft = tmp;
            if (tmp == null) outRec.isHole = false;
            outRec.AppendLink = null;
        }
        //------------------------------------------------------------------------------

        private bool ExecuteInternal(bool fixHoleLinkages)
        {
            bool succeeded;
            try
            {
                Reset();
                if (m_CurrentLM == null) return true;
                Int64 botY = PopScanbeam();
                do
                {
                    InsertLocalMinimaIntoAEL(botY);
                    m_HorizJoins.Clear();
                    ProcessHorizontals();
                    Int64 topY = PopScanbeam();
                    succeeded = ProcessIntersections(topY);
                    if (!succeeded) break;
                    ProcessEdgesAtTopOfScanbeam(topY);
                    botY = topY;
                } while (m_Scanbeam != null);
            }
            catch { succeeded = false; }

            if (succeeded)
            { 
                //tidy up output polygons and fix orientations where necessary ...
                foreach (OutRec outRec in m_PolyOuts)
                {
                  if (outRec.pts == null) continue;
                  FixupOutPolygon(outRec);
                  if (outRec.pts == null) continue;
                  if (outRec.isHole && fixHoleLinkages) FixHoleLinkage(outRec);
                  if (outRec.isHole == IsClockwise(outRec, m_UseFullRange))
                    ReversePolyPtLinks(outRec.pts);
                }

                JoinCommonEdges();
                if (fixHoleLinkages) m_PolyOuts.Sort(new Comparison<OutRec>(PolySort));
            }
            m_Joins.Clear();
            m_HorizJoins.Clear();
            return succeeded;
        }
        //------------------------------------------------------------------------------

        private Int64 PopScanbeam()
        {
          Int64 Y = m_Scanbeam.Y;
          Scanbeam sb2 = m_Scanbeam;
          m_Scanbeam = m_Scanbeam.next;
          sb2 = null;
          return Y;
        }
        //------------------------------------------------------------------------------

        private void DisposeAllPolyPts(){
          for (int i = 0; i < m_PolyOuts.Count; ++i) DisposeOutRec(i, false);
          m_PolyOuts.Clear();
        }
        //------------------------------------------------------------------------------

        void DisposeOutRec(int index, bool ignorePts)
        {
          OutRec outRec = m_PolyOuts[index];
          if (!ignorePts && outRec.pts != null) DisposeOutPts(outRec.pts);
          outRec = null;
          m_PolyOuts[index] = null;
        }
        //------------------------------------------------------------------------------

        private void DisposeOutPts(OutPt pp)
        {
            if (pp == null) return;
            OutPt tmpPp = null;
            pp.prev.next = null;
            while (pp != null)
            {
                tmpPp = pp;
                pp = pp.next;
                tmpPp = null;
            }
        }
        //------------------------------------------------------------------------------

        private void AddJoin(TEdge e1, TEdge e2, int e1OutIdx = -1, int e2OutIdx = -1)
        {
            JoinRec jr = new JoinRec();
            if (e1OutIdx >= 0)
                jr.poly1Idx = e1OutIdx; else
            jr.poly1Idx = e1.outIdx;
            jr.pt1a = new IntPoint(e1.xcurr, e1.ycurr);
            jr.pt1b = new IntPoint(e1.xtop, e1.ytop);
            if (e2OutIdx >= 0)
                jr.poly2Idx = e2OutIdx; else
                jr.poly2Idx = e2.outIdx;
            jr.pt2a = new IntPoint(e2.xcurr, e2.ycurr);
            jr.pt2b = new IntPoint(e2.xtop, e2.ytop);
            m_Joins.Add(jr);
        }
        //------------------------------------------------------------------------------

        private void AddHorzJoin(TEdge e, int idx)
        {
            HorzJoinRec hj = new HorzJoinRec();
            hj.edge = e;
            hj.savedIdx = idx;
            m_HorizJoins.Add(hj);
        }
        //------------------------------------------------------------------------------

        private void InsertLocalMinimaIntoAEL(Int64 botY)
        {
          while(  m_CurrentLM != null  && ( m_CurrentLM.Y == botY ) )
          {
            TEdge lb = m_CurrentLM.leftBound;
            TEdge rb = m_CurrentLM.rightBound;

            InsertEdgeIntoAEL( lb );
            InsertScanbeam( lb.ytop );
            InsertEdgeIntoAEL( rb );

            if ( IsNonZeroFillType( lb) )
              rb.windDelta = -lb.windDelta;
            else
            {
              lb.windDelta = 1;
              rb.windDelta = 1;
            }
            SetWindingCount( lb );
            rb.windCnt = lb.windCnt;
            rb.windCnt2 = lb.windCnt2;

            if(  rb.dx == horizontal )
            {
              //nb: only rightbounds can have a horizontal bottom edge
              AddEdgeToSEL( rb );
              InsertScanbeam( rb.nextInLML.ytop );
            }
            else
              InsertScanbeam( rb.ytop );

            if( IsContributing(lb) )
                AddLocalMinPoly(lb, rb, new IntPoint(lb.xcurr, m_CurrentLM.Y));


            //if output polygons share an edge, they'll need joining later ...
            if (lb.outIdx >= 0 && lb.prevInAEL != null &&
              lb.prevInAEL.outIdx >= 0 && lb.prevInAEL.xcurr == lb.xbot &&
               SlopesEqual(lb, lb.prevInAEL, m_UseFullRange))
                AddJoin(lb, lb.prevInAEL);

            //if any output polygons share an edge, they'll need joining later ...
            if (rb.outIdx >= 0)
            {
                if (rb.dx == horizontal)
                {
                    for (int i = 0; i < m_HorizJoins.Count; i++)
                    {
                        IntPoint pt = new IntPoint(), pt2 = new IntPoint(); //used as dummy params.
                        HorzJoinRec hj = m_HorizJoins[i];
                        //if horizontals rb and hj.edge overlap, flag for joining later ...
                        if (GetOverlapSegment(new IntPoint(hj.edge.xbot, hj.edge.ybot),
                            new IntPoint(hj.edge.xtop, hj.edge.ytop),
                            new IntPoint(rb.xbot, rb.ybot),
                            new IntPoint(rb.xtop, rb.ytop), 
                            ref pt, ref pt2))
                                AddJoin(hj.edge, rb, hj.savedIdx);
                    }
                }
            }


            if( lb.nextInAEL != rb )
            {
                if (rb.outIdx >= 0 && rb.prevInAEL.outIdx >= 0 && 
                    SlopesEqual(rb.prevInAEL, rb, m_UseFullRange))
                    AddJoin(rb, rb.prevInAEL);

              TEdge e = lb.nextInAEL;
              IntPoint pt = new IntPoint(lb.xcurr, lb.ycurr);
              while( e != rb )
              {
                if(e == null) 
                    throw new ClipperException("InsertLocalMinimaIntoAEL: missing rightbound!");
                //nb: For calculating winding counts etc, IntersectEdges() assumes
                //that param1 will be to the right of param2 ABOVE the intersection ...
                IntersectEdges( rb , e , pt , Protects.ipNone); //order important here
                e = e.nextInAEL;
              }
            }
            PopLocalMinima();
          }
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
          else if( E2InsertsBeforeE1(m_ActiveEdges, edge) )
          {
            edge.nextInAEL = m_ActiveEdges;
            m_ActiveEdges.prevInAEL = edge;
            m_ActiveEdges = edge;
          } else
          {
            TEdge e = m_ActiveEdges;
            while (e.nextInAEL != null && !E2InsertsBeforeE1(e.nextInAEL, edge))
              e = e.nextInAEL;
            edge.nextInAEL = e.nextInAEL;
            if (e.nextInAEL != null) e.nextInAEL.prevInAEL = edge;
            edge.prevInAEL = e;
            e.nextInAEL = edge;
          }
        }
        //----------------------------------------------------------------------

        private bool E2InsertsBeforeE1(TEdge e1, TEdge e2)
        {
          if (e2.xcurr == e1.xcurr) return e2.dx > e1.dx;
          else return e2.xcurr < e1.xcurr;
        }
        //------------------------------------------------------------------------------

        private bool IsNonZeroFillType(TEdge edge) 
        {
          if (edge.polyType == PolyType.ptSubject)
            return m_SubjFillType == PolyFillType.pftNonZero; else
            return m_ClipFillType == PolyFillType.pftNonZero;
        }
        //------------------------------------------------------------------------------

        private bool IsNonZeroAltFillType(TEdge edge) 
        {
          if (edge.polyType == PolyType.ptSubject)
            return m_ClipFillType == PolyFillType.pftNonZero; else
            return m_SubjFillType == PolyFillType.pftNonZero;
        }
        //------------------------------------------------------------------------------

        private bool IsContributing(TEdge edge)
        {
            switch (m_ClipType)
            {
                case ClipType.ctIntersection:
                    if (edge.polyType == PolyType.ptSubject)
                        return Math.Abs(edge.windCnt) == 1 && edge.windCnt2 != 0;
                    else
                        return Math.Abs(edge.windCnt2) > 0 && Math.Abs(edge.windCnt) == 1;
                case ClipType.ctUnion:
                    return Math.Abs(edge.windCnt) == 1 && edge.windCnt2 == 0;
                case ClipType.ctDifference:
                    if (edge.polyType == PolyType.ptSubject)
                        return Math.Abs(edge.windCnt) == 1 && edge.windCnt2 == 0;
                    else
                        return Math.Abs(edge.windCnt) == 1 && edge.windCnt2 != 0;
                default: //case ctXor:
                    return Math.Abs(edge.windCnt) == 1;
            }
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


        private void AddLocalMaxPoly(TEdge e1, TEdge e2, IntPoint pt)
        {
            AddOutPt(e1, pt);
            if (e1.outIdx == e2.outIdx)
            {
                e1.outIdx = -1;
                e2.outIdx = -1;
            }
            else AppendPolygon(e1, e2);
        }
        //------------------------------------------------------------------------------

        private void AddLocalMinPoly(TEdge e1, TEdge e2, IntPoint pt)
        {
            if (e2.dx == horizontal || (e1.dx > e2.dx))
            {
                AddOutPt(e1, pt);
                e2.outIdx = e1.outIdx;
                e1.side = EdgeSide.esLeft;
                e2.side = EdgeSide.esRight;
            }
            else
            {
                AddOutPt(e2, pt);
                e1.outIdx = e2.outIdx;
                e1.side = EdgeSide.esRight;
                e2.side = EdgeSide.esLeft;
            }
        }
        //------------------------------------------------------------------------------

        private OutRec CreateOutRec()
        {
          OutRec result = new OutRec();
          result.idx = -1;
          result.isHole = false;
          result.FirstLeft = null;
          result.AppendLink = null;
          result.pts = null;
          return result;
        }
        //------------------------------------------------------------------------------

        private void AddOutPt(TEdge e, IntPoint pt)
        {
          bool ToFront = (e.side == EdgeSide.esLeft);
          if(  e.outIdx < 0 )
          {
              OutRec outRec = CreateOutRec();
              m_PolyOuts.Add(outRec);
              outRec.idx = m_PolyOuts.Count -1;
              e.outIdx = outRec.idx;
              OutPt op = new OutPt();
              outRec.pts = op;
              outRec.bottomPt = op;
              op.pt = pt;
              op.idx = outRec.idx;
              op.next = op;
              op.prev = op;
              SetHoleState(e, outRec);
          } else
          {
              OutRec outRec = m_PolyOuts[e.outIdx];
              OutPt op = outRec.pts;
              if (ToFront && PointsEqual(pt, op.pt) || 
                  (!ToFront && PointsEqual(pt, op.prev.pt))) return;
              OutPt op2 = new OutPt();
              op2.pt = pt;
              op2.idx = outRec.idx;
              if (op2.pt.Y == outRec.bottomPt.pt.Y &&
                op2.pt.X < outRec.bottomPt.pt.X) outRec.bottomPt = op2;
              op2.next = op;
              op2.prev = op.prev;
              op2.prev.next = op2;
              op.prev = op2;
              if (ToFront) outRec.pts = op2;
          }
        }
        //------------------------------------------------------------------------------


        internal void SwapPoints(ref IntPoint pt1, ref IntPoint pt2)
        {
            IntPoint tmp = pt1;
            pt1 = pt2;
            pt2 = tmp;
        }
        //------------------------------------------------------------------------------

        private bool GetOverlapSegment(IntPoint pt1a, IntPoint pt1b, IntPoint pt2a,
            IntPoint pt2b, ref IntPoint pt1, ref IntPoint pt2)
        {
            //precondition: segments are colinear.
            if ( pt1a.Y == pt1b.Y || Math.Abs((pt1a.X - pt1b.X)/(pt1a.Y - pt1b.Y)) > 1 )
            {
            if (pt1a.X > pt1b.X) SwapPoints(ref pt1a, ref pt1b);
            if (pt2a.X > pt2b.X) SwapPoints(ref pt2a, ref pt2b);
            if (pt1a.X > pt2a.X) pt1 = pt1a; else pt1 = pt2a;
            if (pt1b.X < pt2b.X) pt2 = pt1b; else pt2 = pt2b;
            return pt1.X < pt2.X;
            } else
            {
            if (pt1a.Y < pt1b.Y) SwapPoints(ref pt1a, ref pt1b);
            if (pt2a.Y < pt2b.Y) SwapPoints(ref pt2a, ref pt2b);
            if (pt1a.Y < pt2a.Y) pt1 = pt1a; else pt1 = pt2a;
            if (pt1b.Y > pt2b.Y) pt2 = pt1b; else pt2 = pt2b;
            return pt1.Y > pt2.Y;
            }
        }
        //------------------------------------------------------------------------------

        private OutPt PolygonBottom(OutPt pp)
        {
            OutPt p = pp.next;
            OutPt result = pp;
            while (p != pp)
            {
            if (p.pt.Y > result.pt.Y) result = p;
            else if (p.pt.Y == result.pt.Y && p.pt.X < result.pt.X) result = p;
            p = p.next;
            }
            return result;
        }
        //------------------------------------------------------------------------------

        private bool FindSegment(ref OutPt pp, ref IntPoint pt1, ref IntPoint pt2)
        {
            if (pp == null) return false;
            OutPt pp2 = pp;
            IntPoint pt1a = new IntPoint(pt1);
            IntPoint pt2a = new IntPoint(pt2);
            do
            {
                if (SlopesEqual(pt1a, pt2a, pp.pt, pp.prev.pt, true) &&
                    SlopesEqual(pt1a, pt2a, pp.pt, true) &&
                    GetOverlapSegment(pt1a, pt2a, pp.pt, pp.prev.pt, ref pt1, ref pt2))
                        return true;
            pp = pp.next;
            }
            while (pp != pp2);
            return false;
        }
        //------------------------------------------------------------------------------

        internal bool Pt3IsBetweenPt1AndPt2(IntPoint pt1, IntPoint pt2, IntPoint pt3)
        {
            if (PointsEqual(pt1, pt3) || PointsEqual(pt2, pt3)) return true;
            else if (pt1.X != pt2.X) return (pt1.X < pt3.X) == (pt3.X < pt2.X);
            else return (pt1.Y < pt3.Y) == (pt3.Y < pt2.Y);
        }
        //------------------------------------------------------------------------------

        private OutPt InsertPolyPtBetween(OutPt p1, OutPt p2, IntPoint pt)
        {
            OutPt result = new OutPt();
            result.pt = pt;
            if (p2 == p1.next)
            {
                p1.next = result;
                p2.prev = result;
                result.next = p2;
                result.prev = p1;
            } else
            {
                p2.next = result;
                p1.prev = result;
                result.next = p1;
                result.prev = p2;
            }
            return result;
        }
        //------------------------------------------------------------------------------

        private void SetHoleState(TEdge e, OutRec outRec)
        {
            bool isHole = false;
            TEdge e2 = e.prevInAEL;
            while (e2 != null)
            {
                if (e2.outIdx >= 0)
                {
                    isHole = !isHole;
                    if (outRec.FirstLeft == null)
                        outRec.FirstLeft = m_PolyOuts[e2.outIdx];
                }
                e2 = e2.prevInAEL;
            }
            if (isHole) outRec.isHole = true;
        }
        //------------------------------------------------------------------------------

    private double GetDx(IntPoint pt1, IntPoint pt2)
    {
        if (pt1.Y == pt2.Y) return horizontal;
        else return (double)(pt2.X - pt1.X) / (double)(pt2.Y - pt1.Y);
    }
    //---------------------------------------------------------------------------

    bool GetNextNonDupOutPt(OutPt pp, out OutPt next)
    {
      next = pp.next;
      while (next != pp && PointsEqual(pp.pt, next.pt))
        next = next.next;
      return next != pp;
    }
    //------------------------------------------------------------------------------

    bool GetPrevNonDupOutPt(OutPt pp, out OutPt prev)
    {
      prev = pp.prev;
      while (prev != pp && PointsEqual(pp.pt, prev.pt))
        prev = prev.prev;
      return prev != pp;
    }
    //------------------------------------------------------------------------------

    private void AppendPolygon(TEdge e1, TEdge e2)
        {
          //get the start and ends of both output polygons ...
          OutRec outRec1 = m_PolyOuts[e1.outIdx];
          OutRec outRec2 = m_PolyOuts[e2.outIdx];

          //work out which polygon fragment has the correct hole state ...
          OutRec holeStateRec;
          OutPt next1, next2, prev1, prev2;
          OutPt bPt1 = outRec1.bottomPt;
          OutPt bPt2 = outRec2.bottomPt;
          if (bPt1.pt.Y > bPt2.pt.Y) holeStateRec = outRec1;
          else if (bPt1.pt.Y < bPt2.pt.Y) holeStateRec = outRec2;
          else if (bPt1.pt.X < bPt2.pt.X) holeStateRec = outRec1;
          else if (bPt1.pt.X > bPt2.pt.X) holeStateRec = outRec2;
          else if (!GetNextNonDupOutPt(bPt1, out next1)) holeStateRec = outRec2;
          else if (!GetNextNonDupOutPt(bPt2, out next2)) holeStateRec = outRec1;
          else
          {
              GetPrevNonDupOutPt(bPt1, out prev1);
              GetPrevNonDupOutPt(bPt2, out prev2);
              double dx1 = GetDx(bPt1.pt, next1.pt);
              double dx2 = GetDx(bPt1.pt, prev1.pt);
              if (dx2 > dx1) dx1 = dx2;
              dx2 = GetDx(bPt2.pt, next2.pt);
              if (dx2 > dx1) holeStateRec = outRec2;
              else
              {
                  dx2 = GetDx(bPt2.pt, prev2.pt);
                  if (dx2 > dx1) holeStateRec = outRec2;
                  else holeStateRec = outRec1;
              }
          }

          //fixup hole status ...
          if (outRec1.isHole != outRec2.isHole)
              if (holeStateRec == outRec2)
                  outRec1.isHole = outRec2.isHole; else
                  outRec2.isHole = outRec1.isHole;

          OutPt p1_lft = outRec1.pts;
          OutPt p1_rt = p1_lft.prev;
          OutPt p2_lft = outRec2.pts;
          OutPt p2_rt = p2_lft.prev;

        EdgeSide side;
          //join e2 poly onto e1 poly and delete pointers to e2 ...
          if(  e1.side == EdgeSide.esLeft )
          {
            if (e2.side == EdgeSide.esLeft)
            {
              //z y x a b c
              ReversePolyPtLinks(p2_lft);
              p2_lft.next = p1_lft;
              p1_lft.prev = p2_lft;
              p1_rt.next = p2_rt;
              p2_rt.prev = p1_rt;
              outRec1.pts = p2_rt;
            } else
            {
              //x y z a b c
              p2_rt.next = p1_lft;
              p1_lft.prev = p2_rt;
              p2_lft.prev = p1_rt;
              p1_rt.next = p2_lft;
              outRec1.pts = p2_lft;
            }
            side = EdgeSide.esLeft;
          } else
          {
            if (e2.side == EdgeSide.esRight)
            {
              //a b c z y x
              ReversePolyPtLinks( p2_lft );
              p1_rt.next = p2_rt;
              p2_rt.prev = p1_rt;
              p2_lft.next = p1_lft;
              p1_lft.prev = p2_lft;
            } else
            {
              //a b c x y z
              p1_rt.next = p2_lft;
              p2_lft.prev = p1_rt;
              p1_lft.prev = p2_rt;
              p2_rt.next = p1_lft;
            }
            side = EdgeSide.esRight;
          }

          if (holeStateRec == outRec2)
            outRec1.bottomPt = outRec2.bottomPt;
          outRec2.pts = null;
          outRec2.bottomPt = null;
          outRec2.AppendLink = outRec1;
          int OKIdx = e1.outIdx;
          int ObsoleteIdx = e2.outIdx;

          e1.outIdx = -1; //nb: safe because we only get here via AddLocalMaxPoly
          e2.outIdx = -1;

          TEdge e = m_ActiveEdges;
          while( e != null )
          {
            if( e.outIdx == ObsoleteIdx )
            {
              e.outIdx = OKIdx;
              e.side = side;
              break;
            }
            e = e.nextInAEL;
          }


          for (int i = 0; i < m_Joins.Count; ++i)
          {
              if (m_Joins[i].poly1Idx == ObsoleteIdx) m_Joins[i].poly1Idx = OKIdx;
              if (m_Joins[i].poly2Idx == ObsoleteIdx) m_Joins[i].poly2Idx = OKIdx;
          }

          for (int i = 0; i < m_HorizJoins.Count; ++i)
          {
              if (m_HorizJoins[i].savedIdx == ObsoleteIdx)
                m_HorizJoins[i].savedIdx = OKIdx;
          }

        }
        //------------------------------------------------------------------------------

        private void ReversePolyPtLinks(OutPt pp)
        {
            OutPt pp1;
            OutPt pp2;
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

        private static void SwapSides(TEdge edge1, TEdge edge2)
        {
            EdgeSide side = edge1.side;
            edge1.side = edge2.side;
            edge2.side = side;
        }
        //------------------------------------------------------------------------------

        private static void SwapPolyIndexes(TEdge edge1, TEdge edge2)
        {
            int outIdx = edge1.outIdx;
            edge1.outIdx = edge2.outIdx;
            edge2.outIdx = outIdx;
        }
        //------------------------------------------------------------------------------

        private void DoEdge1(TEdge edge1, TEdge edge2, IntPoint pt)
        {
            AddOutPt(edge1, pt);
            SwapSides(edge1, edge2);
            SwapPolyIndexes(edge1, edge2);
        }
        //------------------------------------------------------------------------------

        private void DoEdge2(TEdge edge1, TEdge edge2, IntPoint pt)
        {
            AddOutPt(edge2, pt);
            SwapSides(edge1, edge2);
            SwapPolyIndexes(edge1, edge2);
        }
        //------------------------------------------------------------------------------

        private void DoBothEdges(TEdge edge1, TEdge edge2, IntPoint pt)
        {
            AddOutPt(edge1, pt);
            AddOutPt(edge2, pt);
            SwapSides(edge1, edge2);
            SwapPolyIndexes(edge1, edge2);
        }
        //------------------------------------------------------------------------------

        private void IntersectEdges(TEdge e1, TEdge e2, IntPoint pt, Protects protects)
        {
            //e1 will be to the left of e2 BELOW the intersection. Therefore e1 is before
            //e2 in AEL except when e1 is being inserted at the intersection point ...

            bool e1stops = (Protects.ipLeft & protects) == 0 && e1.nextInLML == null &&
              e1.xtop == pt.X && e1.ytop == pt.Y;
            bool e2stops = (Protects.ipRight & protects) == 0 && e2.nextInLML == null &&
              e2.xtop == pt.X && e2.ytop == pt.Y;
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
                  (e1.polyType != e2.polyType && m_ClipType != ClipType.ctXor))
                    AddLocalMaxPoly(e1, e2, pt);
                else
                    DoBothEdges(e1, e2, pt);
            }
            else if (e1Contributing)
            {
                if (m_ClipType == ClipType.ctIntersection)
                {
                    if ((e2.polyType == PolyType.ptSubject || e2.windCnt2 != 0) &&
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
                if (m_ClipType == ClipType.ctIntersection)
                {
                    if ((e1.polyType == PolyType.ptSubject || e1.windCnt2 != 0) &&
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
                        case ClipType.ctIntersection:
                            {
                                if (Math.Abs(e1.windCnt2) > 0 && Math.Abs(e2.windCnt2) > 0)
                                    AddLocalMinPoly(e1, e2, pt);
                                break;
                            }
                        case ClipType.ctUnion:
                            {
                                if (e1.windCnt2 == 0 && e2.windCnt2 == 0)
                                    AddLocalMinPoly(e1, e2, pt);
                                break;
                            }
                        case ClipType.ctDifference:
                            {
                                if ((e1.polyType == PolyType.ptClip && e2.polyType == PolyType.ptClip &&
                              e1.windCnt2 != 0 && e2.windCnt2 != 0) ||
                              (e1.polyType == PolyType.ptSubject && e2.polyType == PolyType.ptSubject &&
                              e1.windCnt2 == 0 && e2.windCnt2 == 0))
                                    AddLocalMinPoly(e1, e2, pt);
                                break;
                            }
                        case ClipType.ctXor:
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
                throw new ClipperException("UpdateEdgeIntoAEL: invalid call");
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
            if (e.dx != horizontal) InsertScanbeam(e.ytop);
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

        private void ProcessHorizontal(TEdge horzEdge)
        {
            Direction Direction;
            Int64 horzLeft, horzRight;

            if (horzEdge.xcurr < horzEdge.xtop)
            {
                horzLeft = horzEdge.xcurr;
                horzRight = horzEdge.xtop;
                Direction = Direction.dLeftToRight;
            }
            else
            {
                horzLeft = horzEdge.xtop;
                horzRight = horzEdge.xcurr;
                Direction = Direction.dRightToLeft;
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
                if (e.xcurr >= horzLeft && e.xcurr <= horzRight)
                {
                    //ok, so far it looks like we're still in range of the horizontal edge
                    if (e.xcurr == horzEdge.xtop && horzEdge.nextInLML != null)
                    {
                        if (SlopesEqual(e, horzEdge.nextInLML, m_UseFullRange))
                        {
                            //if output polygons share an edge, they'll need joining later ...
                            if (horzEdge.outIdx >= 0 && e.outIdx >= 0)
                                AddJoin(horzEdge.nextInLML, e, horzEdge.outIdx);
                            break; //we've reached the end of the horizontal line
                        }
                        else if (e.dx < horzEdge.nextInLML.dx)
                            //we really have got to the end of the intermediate horz edge so quit.
                            //nb: More -ve slopes follow more +ve slopes ABOVE the horizontal.
                            break;
                    }

                    if (e == eMaxPair)
                    {
                        //horzEdge is evidently a maxima horizontal and we've arrived at its end.
                        if (Direction == Direction.dLeftToRight)
                            IntersectEdges(horzEdge, e, new IntPoint(e.xcurr, horzEdge.ycurr), 0);
                        else
                            IntersectEdges(e, horzEdge, new IntPoint(e.xcurr, horzEdge.ycurr), 0);
                        return;
                    }
                    else if (e.dx == horizontal && !IsMinima(e) && !(e.xcurr > e.xtop))
                    {
                        if (Direction == Direction.dLeftToRight)
                            IntersectEdges(horzEdge, e, new IntPoint(e.xcurr, horzEdge.ycurr),
                              (IsTopHorz(horzEdge, e.xcurr)) ? Protects.ipLeft : Protects.ipBoth);
                        else
                            IntersectEdges(e, horzEdge, new IntPoint(e.xcurr, horzEdge.ycurr),
                              (IsTopHorz(horzEdge, e.xcurr)) ? Protects.ipRight : Protects.ipBoth);
                    }
                    else if (Direction == Direction.dLeftToRight)
                    {
                        IntersectEdges(horzEdge, e, new IntPoint(e.xcurr, horzEdge.ycurr),
                          (IsTopHorz(horzEdge, e.xcurr)) ? Protects.ipLeft : Protects.ipBoth);
                    }
                    else
                    {
                        IntersectEdges(e, horzEdge, new IntPoint(e.xcurr, horzEdge.ycurr),
                          (IsTopHorz(horzEdge, e.xcurr)) ? Protects.ipRight : Protects.ipBoth);
                    }
                    SwapPositionsInAEL(horzEdge, e);
                }
                else if (Direction == Direction.dLeftToRight && 
                      e.xcurr > horzRight && horzEdge.nextInSEL == null) break;
                else if ((Direction == Direction.dRightToLeft) &&
                  e.xcurr < horzLeft && horzEdge.nextInSEL == null) break;
                e = eNext;
            } //end while ( e )

            if (horzEdge.nextInLML != null)
            {
                if (horzEdge.outIdx >= 0)
                    AddOutPt(horzEdge, new IntPoint(horzEdge.xtop, horzEdge.ytop));
                UpdateEdgeIntoAEL(ref horzEdge);
            }
            else
            {
                if (horzEdge.outIdx >= 0)
                    IntersectEdges(horzEdge, eMaxPair, 
                        new IntPoint(horzEdge.xtop, horzEdge.ycurr), Protects.ipBoth);
                DeleteFromAEL(eMaxPair);
                DeleteFromAEL(horzEdge);
            }
        }
        //------------------------------------------------------------------------------

        private bool IsTopHorz(TEdge horzEdge, double XPos)
        {
            TEdge e = m_SortedEdges;
            while (e != null)
            {
                if ((XPos >= Math.Min(e.xcurr, e.xtop)) && (XPos <= Math.Max(e.xcurr, e.xtop)))
                    return false;
                e = e.nextInSEL;
            }
            return true;
        }
        //------------------------------------------------------------------------------

        private TEdge GetNextInAEL(TEdge e, Direction Direction)
        {
            if (Direction == Direction.dLeftToRight) return e.nextInAEL;
            else return e.prevInAEL;
        }
        //------------------------------------------------------------------------------

        private bool IsMinima(TEdge e)
        {
            return e != null && (e.prev.nextInLML != e) && (e.next.nextInLML != e);
        }
        //------------------------------------------------------------------------------

        private bool IsMaxima(TEdge e, double Y)
        {
            return (e != null && e.ytop == Y && e.nextInLML == null);
        }
        //------------------------------------------------------------------------------

        private bool IsIntermediate(TEdge e, double Y)
        {
            return (e.ytop == Y && e.nextInLML != null);
        }
        //------------------------------------------------------------------------------

        private TEdge GetMaximaPair(TEdge e)
        {
            if (!IsMaxima(e.next, e.ytop) || (e.next.xtop != e.xtop))
                return e.prev; else
                return e.next;
        }
        //------------------------------------------------------------------------------

        private bool ProcessIntersections(Int64 topY)
        {
          if( m_ActiveEdges == null ) return true;
          try {
            BuildIntersectList(topY);
            if ( m_IntersectNodes == null) return true;
            if ( FixupIntersections() ) ProcessIntersectList();
            else return false;
          }
          catch {
            m_SortedEdges = null;
            DisposeIntersectNodes();
            throw new ClipperException("ProcessIntersections error");
          }
          return true;
        }
        //------------------------------------------------------------------------------

        private void BuildIntersectList(Int64 topY)
        {
          if ( m_ActiveEdges == null ) return;

          //prepare for sorting ...
          TEdge e = m_ActiveEdges;
          e.tmpX = TopX( e, topY );
          m_SortedEdges = e;
          m_SortedEdges.prevInSEL = null;
          e = e.nextInAEL;
          while( e != null )
          {
            e.prevInSEL = e.prevInAEL;
            e.prevInSEL.nextInSEL = e;
            e.nextInSEL = null;
            e.tmpX = TopX( e, topY );
            e = e.nextInAEL;
          }

          //bubblesort ...
          bool isModified = true;
          while( isModified && m_SortedEdges != null )
          {
            isModified = false;
            e = m_SortedEdges;
            while( e.nextInSEL != null )
            {
              TEdge eNext = e.nextInSEL;
              IntPoint pt = new IntPoint();
              if(e.tmpX > eNext.tmpX && IntersectPoint(e, eNext, ref pt))
              {
                AddIntersectNode( e, eNext, pt );
                SwapPositionsInSEL(e, eNext);
                isModified = true;
              }
              else
                e = eNext;
            }
            if( e.prevInSEL != null ) e.prevInSEL.nextInSEL = null;
            else break;
          }
          m_SortedEdges = null;
        }
        //------------------------------------------------------------------------------

        private bool FixupIntersections()
        {
          if ( m_IntersectNodes.next == null ) return true;

          CopyAELToSEL();
          IntersectNode int1 = m_IntersectNodes;
          IntersectNode int2 = m_IntersectNodes.next;
          while (int2 != null)
          {
            TEdge e1 = int1.edge1;
            TEdge e2;
            if (e1.prevInSEL == int1.edge2) e2 = e1.prevInSEL;
            else if (e1.nextInSEL == int1.edge2) e2 = e1.nextInSEL;
            else
            {
              //The current intersection is out of order, so try and swap it with
              //a subsequent intersection ...
              while (int2 != null)
              {
                if (int2.edge1.nextInSEL == int2.edge2 ||
                  int2.edge1.prevInSEL == int2.edge2) break;
                else int2 = int2.next;
              }
              if (int2 == null) return false; //oops!!!

              //found an intersect node that can be swapped ...
              SwapIntersectNodes(int1, int2);
              e1 = int1.edge1;
              e2 = int1.edge2;
            }
            SwapPositionsInSEL(e1, e2);
            int1 = int1.next;
            int2 = int1.next;
          }

          m_SortedEdges = null;

          //finally, check the last intersection too ...
          return (int1.edge1.prevInSEL == int1.edge2 || int1.edge1.nextInSEL == int1.edge2);
        }
        //------------------------------------------------------------------------------

        private void ProcessIntersectList()
        {
          while( m_IntersectNodes != null )
          {
            IntersectNode iNode = m_IntersectNodes.next;
            {
              IntersectEdges( m_IntersectNodes.edge1 ,
                m_IntersectNodes.edge2 , m_IntersectNodes.pt, Protects.ipBoth );
              SwapPositionsInAEL( m_IntersectNodes.edge1 , m_IntersectNodes.edge2 );
            }
            m_IntersectNodes = null;
            m_IntersectNodes = iNode;
          }
        }
        //------------------------------------------------------------------------------

        private static Int64 Round(double value)
        {
            if ((value < 0)) return (Int64)(value - 0.5); else return (Int64)(value + 0.5);
        }
        //------------------------------------------------------------------------------

        private static Int64 TopX(TEdge edge, Int64 currentY)
        {
            if (currentY == edge.ytop)
                return edge.xtop;
            return edge.xbot + Round(edge.dx *(currentY - edge.ybot));
        }
        //------------------------------------------------------------------------------

        private Int64 TopX(IntPoint pt1, IntPoint pt2, Int64 currentY)
        {
          //preconditions: pt1.Y <> pt2.Y and pt1.Y > pt2.Y
          if (currentY >= pt1.Y) return pt1.X;
          else if (currentY == pt2.Y) return pt2.X;
          else if (pt1.X == pt2.X) return pt1.X;
          else
          {
            double q = (pt1.X-pt2.X)/(pt1.Y-pt2.Y);
            return (Int64)(pt1.X + (currentY - pt1.Y) * q);
          }
        }
        //------------------------------------------------------------------------------

        private void AddIntersectNode(TEdge e1, TEdge e2, IntPoint pt)
        {
          IntersectNode newNode = new IntersectNode();
          newNode.edge1 = e1;
          newNode.edge2 = e2;
          newNode.pt = pt;
          newNode.next = null;
          if (m_IntersectNodes == null) m_IntersectNodes = newNode;
          else if( Process1Before2(newNode, m_IntersectNodes) )
          {
            newNode.next = m_IntersectNodes;
            m_IntersectNodes = newNode;
          }
          else
          {
            IntersectNode iNode = m_IntersectNodes;
            while( iNode.next != null  && Process1Before2(iNode.next, newNode) )
                iNode = iNode.next;
            newNode.next = iNode.next;
            iNode.next = newNode;
          }
        }
        //------------------------------------------------------------------------------

        private bool Process1Before2(IntersectNode node1, IntersectNode node2)
        {
          bool result;
          if (node1.pt.Y == node2.pt.Y)
          {
            if (node1.edge1 == node2.edge1 || node1.edge2 == node2.edge1)
            {
              result = node2.pt.X > node1.pt.X;
              if (node2.edge1.dx > 0) return !result; else return result;
            }
            else if (node1.edge1 == node2.edge2 || node1.edge2 == node2.edge2)
            {
              result = node2.pt.X > node1.pt.X;
              if (node2.edge2.dx > 0) return !result; else return result;
            }
            else return node2.pt.X > node1.pt.X;
          }
          else return node1.pt.Y > node2.pt.Y;
        }
        //------------------------------------------------------------------------------

        private void SwapIntersectNodes(IntersectNode int1, IntersectNode int2)
        {
          TEdge e1 = int1.edge1;
          TEdge e2 = int1.edge2;
          IntPoint p = int1.pt;
          int1.edge1 = int2.edge1;
          int1.edge2 = int2.edge2;
          int1.pt = int2.pt;
          int2.edge1 = e1;
          int2.edge2 = e2;
          int2.pt = p;
        }
        //------------------------------------------------------------------------------

        private bool IntersectPoint(TEdge edge1, TEdge edge2, ref IntPoint ip)
        {
          double b1, b2;
          if (SlopesEqual(edge1, edge2, m_UseFullRange)) return false;
          else if (edge1.dx == 0)
          {
            ip.X = edge1.xbot;
            if (edge2.dx == horizontal)
            {
              ip.Y = edge2.ybot;
            } else
            {
              b2 = edge2.ybot - (edge2.xbot/edge2.dx);
              ip.Y = Round(ip.X/edge2.dx + b2);
            }
          }
          else if (edge2.dx == 0)
          {
            ip.X = edge2.xbot;
            if (edge1.dx == horizontal)
            {
              ip.Y = edge1.ybot;
            } else
            {
              b1 = edge1.ybot - (edge1.xbot/edge1.dx);
              ip.Y = Round(ip.X/edge1.dx + b1);
            }
          } else
          {
            b1 = edge1.xbot - edge1.ybot * edge1.dx;
            b2 = edge2.xbot - edge2.ybot * edge2.dx;
            b2 = (b2-b1)/(edge1.dx - edge2.dx);
            ip.Y = Round(b2);
            ip.X = Round(edge1.dx * b2 + b1);
          }

          return
            //can be *so close* to the top of one edge that the rounded Y equals one ytop ...
            (ip.Y == edge1.ytop && ip.Y >= edge2.ytop && edge1.tmpX > edge2.tmpX) ||
            (ip.Y == edge2.ytop && ip.Y >= edge1.ytop && edge1.tmpX > edge2.tmpX) ||
            (ip.Y > edge1.ytop && ip.Y > edge2.ytop);
        }
        //------------------------------------------------------------------------------

        private void DisposeIntersectNodes()
        {
          while ( m_IntersectNodes != null )
          {
            IntersectNode iNode = m_IntersectNodes.next;
            m_IntersectNodes = null;
            m_IntersectNodes = iNode;
          }
        }
        //------------------------------------------------------------------------------

        private void ProcessEdgesAtTopOfScanbeam(Int64 topY)
        {
          TEdge e = m_ActiveEdges;
          while( e != null )
          {
            //1. process maxima, treating them as if they're 'bent' horizontal edges,
            //   but exclude maxima with horizontal edges. nb: e can't be a horizontal.
            if( IsMaxima(e, topY) && GetMaximaPair(e).dx != horizontal )
            {
              //'e' might be removed from AEL, as may any following edges so ...
              TEdge ePrior = e.prevInAEL;
              DoMaxima(e, topY);
              if( ePrior == null ) e = m_ActiveEdges;
              else e = ePrior.nextInAEL;
            }
            else
            {
              //2. promote horizontal edges, otherwise update xcurr and ycurr ...
              if(  IsIntermediate(e, topY) && e.nextInLML.dx == horizontal )
              {
                if (e.outIdx >= 0)
                {
                    AddOutPt(e, new IntPoint(e.xtop, e.ytop));

                    for (int i = 0; i < m_HorizJoins.Count; ++i)
                    {
                        IntPoint pt = new IntPoint(), pt2 = new IntPoint();
                        HorzJoinRec hj = m_HorizJoins[i];
                        if (GetOverlapSegment(new IntPoint(hj.edge.xbot, hj.edge.ybot),
                            new IntPoint(hj.edge.xtop, hj.edge.ytop),
                            new IntPoint(e.nextInLML.xbot, e.nextInLML.ybot),
                            new IntPoint(e.nextInLML.xtop, e.nextInLML.ytop), ref pt, ref pt2))
                                AddJoin(hj.edge, e.nextInLML, hj.savedIdx, e.outIdx);
                    }

                    AddHorzJoin(e.nextInLML, e.outIdx);
                }
                UpdateEdgeIntoAEL(ref e);
                AddEdgeToSEL(e);
              } 
              else
              {
                //this just simplifies horizontal processing ...
                e.xcurr = TopX( e, topY );
                e.ycurr = topY;
              }
              e = e.nextInAEL;
            }
          }

          //3. Process horizontals at the top of the scanbeam ...
          ProcessHorizontals();

          //4. Promote intermediate vertices ...
          e = m_ActiveEdges;
          while( e != null )
          {
            if( IsIntermediate( e, topY ) )
            {
                if (e.outIdx >= 0) AddOutPt(e, new IntPoint(e.xtop, e.ytop));
              UpdateEdgeIntoAEL(ref e);

              //if output polygons share an edge, they'll need joining later ...
              if (e.outIdx >= 0 && e.prevInAEL != null && e.prevInAEL.outIdx >= 0 &&
                e.prevInAEL.xcurr == e.xbot && e.prevInAEL.ycurr == e.ybot &&
                SlopesEqual(new IntPoint(e.xbot, e.ybot), new IntPoint(e.xtop, e.ytop),
                  new IntPoint(e.xbot, e.ybot),
                  new IntPoint(e.prevInAEL.xtop, e.prevInAEL.ytop), m_UseFullRange))
              {
                  AddOutPt(e.prevInAEL, new IntPoint(e.xbot, e.ybot));
                  AddJoin(e, e.prevInAEL);
              }
              else if (e.outIdx >= 0 && e.nextInAEL != null && e.nextInAEL.outIdx >= 0 &&
                e.nextInAEL.ycurr > e.nextInAEL.ytop &&
                e.nextInAEL.ycurr < e.nextInAEL.ybot &&
                e.nextInAEL.xcurr == e.xbot && e.nextInAEL.ycurr == e.ybot &&
                SlopesEqual(new IntPoint(e.xbot, e.ybot), new IntPoint(e.xtop, e.ytop),
                  new IntPoint(e.xbot, e.ybot),
                  new IntPoint(e.nextInAEL.xtop, e.nextInAEL.ytop), m_UseFullRange))
              {
                  AddOutPt(e.nextInAEL, new IntPoint(e.xbot, e.ybot));
                  AddJoin(e, e.nextInAEL);
              }

            }
            e = e.nextInAEL;
          }
        }
        //------------------------------------------------------------------------------

        private void DoMaxima(TEdge e, Int64 topY)
        {
          TEdge eMaxPair = GetMaximaPair(e);
          Int64 X = e.xtop;
          TEdge eNext = e.nextInAEL;
          while( eNext != eMaxPair )
          {
            if (eNext == null) throw new ClipperException("DoMaxima error");
            IntersectEdges( e, eNext, new IntPoint(X, topY), Protects.ipBoth );
            eNext = eNext.nextInAEL;
          }
          if( e.outIdx < 0 && eMaxPair.outIdx < 0 )
          {
            DeleteFromAEL( e );
            DeleteFromAEL( eMaxPair );
          }
          else if( e.outIdx >= 0 && eMaxPair.outIdx >= 0 )
          {
              IntersectEdges(e, eMaxPair, new IntPoint(X, topY), Protects.ipNone);
          }
          else throw new ClipperException("DoMaxima error");
        }
        //------------------------------------------------------------------------------

        public static bool IsClockwise(Polygon poly, bool UseFullInt64Range = true)
        {
          int highI = poly.Count -1;
          if (highI < 2) return false;
          if (UseFullInt64Range)
          {
              Int128 area;
              area = Int128.Int128Mul(poly[highI].X, poly[0].Y) -
                Int128.Int128Mul(poly[0].X, poly[highI].Y);
              for (int i = 0; i < highI; ++i)
                  area += Int128.Int128Mul(poly[i].X, poly[i + 1].Y) -
                    Int128.Int128Mul(poly[i + 1].X, poly[i].Y);
              return area.ToDouble() > 0;
          }
          else
          {

              double area;
              area = (double)poly[highI].X * (double)poly[0].Y -
                  (double)poly[0].X * (double)poly[highI].Y;
              for (int i = 0; i < highI; ++i)
                  area += (double)poly[i].X * (double)poly[i + 1].Y -
                      (double)poly[i + 1].X * (double)poly[i].Y;
              //area := area/2;
              return area > 0; //reverse of normal formula because assuming Y axis inverted
          }
        }
        //------------------------------------------------------------------------------

        private bool IsClockwise(OutRec outRec, bool UseFullInt64Range)
        {
            OutPt startPt = outRec.pts;
            OutPt op = startPt;
            if (UseFullInt64Range)
            {
                Int128 area = new Int128(0);
                do
                {
                    area += Int128.Int128Mul(op.pt.X, op.next.pt.Y) -
                        Int128.Int128Mul(op.next.pt.X, op.pt.Y);
                    op = op.next;
                }
                while (op != startPt);
                return area.ToDouble() > 0;
            }
            else
            {

                double area = 0;
                do
                {
                    area += (double)op.pt.X * (double)op.next.pt.Y -
                        (double)op.next.pt.X * (double)op.pt.Y;
                    op = op.next;
                }
                while (op != startPt);
                //area = area /2;
                return area > 0; //reverse of normal formula because assuming Y axis inverted
                }
        }
        //------------------------------------------------------------------------------

        private int PointCount(OutPt pts)
        {
            if (pts == null) return 0;
            int result = 0;
            OutPt p = pts;
            do
            {
                result++;
                p = p.next;
            }
            while (p != pts);
            return result;
        }
        //------------------------------------------------------------------------------

        private void BuildResult(Polygons polyg)
        {
            polyg.Clear();
            polyg.Capacity = m_PolyOuts.Count;
            foreach (OutRec outRec in m_PolyOuts)
            {
                if (outRec.pts == null) continue;
                OutPt p = outRec.pts;
                int cnt = PointCount(p);
                if (cnt < 3) continue;
                Polygon pg = new Polygon(cnt);
                for (int j = 0; j < cnt; j++)
                {
                    pg.Add(p.pt);
                    p = p.next;
                }
                polyg.Add(pg);
            }
        }
        //------------------------------------------------------------------------------

        private void BuildResultEx(ExPolygons polyg)
        {         
            polyg.Clear();
            polyg.Capacity = m_PolyOuts.Count;
            int i = 0;
            while (i < m_PolyOuts.Count)
            {
                OutRec outRec = m_PolyOuts[i++];
                if (outRec.pts == null) break; //nb: already sorted here
                OutPt p = outRec.pts;
                int cnt = PointCount(p);
                if (cnt < 3) continue;
                ExPolygon epg = new ExPolygon();
                epg.outer = new Polygon(cnt);
                epg.holes = new Polygons();
                for (int j = 0; j < cnt; j++)
                {
                    epg.outer.Add(p.pt);
                    p = p.next;
                }
                while (i < m_PolyOuts.Count)
                {
                    outRec = m_PolyOuts[i];
                    if (outRec.pts == null || !outRec.isHole) break;
                    Polygon pg = new Polygon();
                    p = outRec.pts;
                    do
                    {
                        pg.Add(p.pt);
                        p = p.next;
                    } while (p != outRec.pts);
                    epg.holes.Add(pg);
                    i++;
                }
                polyg.Add(epg);
            }
        }
        //------------------------------------------------------------------------------

        private void FixupOutPolygon(OutRec outRec)
        {
            //FixupOutPolygon() - removes duplicate points and simplifies consecutive
            //parallel edges by removing the middle vertex.
            OutPt lastOK = null;
            outRec.pts = outRec.bottomPt;
            OutPt pp = outRec.bottomPt;
            for (;;)
            {
                if (pp.prev == pp || pp.prev == pp.next)
                {
                    DisposeOutPts(pp);
                    outRec.pts = null;
                    outRec.bottomPt = null;
                    return;
                }
                //test for duplicate points and for same slope (cross-product) ...
                if (PointsEqual(pp.pt, pp.next.pt) ||
                  SlopesEqual(pp.prev.pt, pp.pt, pp.next.pt, m_UseFullRange))
                {
                    lastOK = null;
                    OutPt tmp = pp;
                    if (pp == outRec.bottomPt)
                    {
                        if (tmp.prev.pt.Y > tmp.next.pt.Y)
                          outRec.bottomPt = tmp.prev; else
                          outRec.bottomPt = tmp.next;
                        outRec.pts = outRec.bottomPt;
                    }
                    pp.prev.next = pp.next;
                    pp.next.prev = pp.prev;
                    pp = pp.prev;
                    tmp = null;
                }
                else if (pp == lastOK) break;
                else
                {
                    if (lastOK == null) lastOK = pp;
                    pp = pp.next;
                }
            }
        }
        //------------------------------------------------------------------------------
        
        private void JoinCommonEdges()
        {
          for (int i = 0; i < m_Joins.Count; i++)
          {
            JoinRec j = m_Joins[i];
            OutRec outRec1 = m_PolyOuts[j.poly1Idx];
            OutPt pp1a = outRec1.pts;
            OutRec outRec2 = m_PolyOuts[j.poly2Idx];
            OutPt pp2a = outRec2.pts;
            IntPoint pt1 = new IntPoint(j.pt2a);
            IntPoint pt2 = new IntPoint(j.pt2b);
            IntPoint pt3 = new IntPoint(j.pt1a);
            IntPoint pt4 = new IntPoint(j.pt1b);
            if (!FindSegment(ref pp1a, ref pt1, ref pt2)) continue;
            if (j.poly1Idx == j.poly2Idx)
            {
                //we're searching the same polygon for overlapping segments so
                //segment 2 mustn't be the same as segment 1 ...
                pp2a = pp1a.next;
                if (!FindSegment(ref pp2a, ref pt3, ref pt4) || (pp2a == pp1a)) continue;
            }
            else if (!FindSegment(ref pp2a, ref pt3, ref pt4)) continue;

            if (!GetOverlapSegment(pt1, pt2, pt3, pt4, ref pt1, ref pt2)) continue;

            OutPt p1, p2, p3, p4;
            OutPt prev = pp1a.prev;
            //get p1 & p2 polypts - the overlap start & endpoints on poly1
            
            if (PointsEqual(pp1a.pt, pt1)) p1 = pp1a;
            else if (PointsEqual(prev.pt, pt1)) p1 = prev;
            else p1 = InsertPolyPtBetween(pp1a, prev, pt1);

            if (PointsEqual(pp1a.pt, pt2)) p2 = pp1a;
            else if (PointsEqual(prev.pt, pt2)) p2 = prev;
            else if ((p1 == pp1a) || (p1 == prev))
                p2 = InsertPolyPtBetween(pp1a, prev, pt2);
            else if (Pt3IsBetweenPt1AndPt2(pp1a.pt, p1.pt, pt2))
                p2 = InsertPolyPtBetween(pp1a, p1, pt2); 
            else
                p2 = InsertPolyPtBetween(p1, prev, pt2);

            //get p3 & p4 polypts - the overlap start & endpoints on poly2
            prev = pp2a.prev;
            if (PointsEqual(pp2a.pt, pt1)) p3 = pp2a;
            else if (PointsEqual(prev.pt, pt1)) p3 = prev;
            else p3 = InsertPolyPtBetween(pp2a, prev, pt1);

            if (PointsEqual(pp2a.pt, pt2)) p4 = pp2a;
            else if (PointsEqual(prev.pt, pt2)) p4 = prev;
            else if ((p3 == pp2a) || (p3 == prev))
                p4 = InsertPolyPtBetween(pp2a, prev, pt2);
            else if (Pt3IsBetweenPt1AndPt2(pp2a.pt, p3.pt, pt2))
                p4 = InsertPolyPtBetween(pp2a, p3, pt2);
            else
                p4 = InsertPolyPtBetween(p3, prev, pt2);

            //p1.pt should equal p3.pt and p2.pt should equal p4.pt here, so ...
            //join p1 to p3 and p2 to p4 ...
            if (p1.next == p2 && p3.prev == p4)
            {
                p1.next = p3;
                p3.prev = p1;
                p2.prev = p4;
                p4.next = p2;
            }
            else if (p1.prev == p2 && p3.next == p4)
            {
                p1.prev = p3;
                p3.next = p1;
                p2.next = p4;
                p4.prev = p2;
            }
            else
                continue; //an orientation is probably wrong

            if (j.poly2Idx == j.poly1Idx)
            {
                //instead of joining two polygons, we've just created a new one by
                //splitting one polygon into two.
                //However, make sure the longer (and presumed larger) polygon is attached
                //to outRec1 in case it also owns some holes ...
                if (PointCount(p1) > PointCount(p2))
                {
                    outRec1.pts = PolygonBottom(p1);
                    outRec1.bottomPt = outRec1.pts;
                    outRec2 = CreateOutRec();
                    m_PolyOuts.Add(outRec2);
                    outRec2.idx = m_PolyOuts.Count - 1;
                    j.poly2Idx = outRec2.idx;
                    outRec2.pts = PolygonBottom(p2);
                    outRec2.bottomPt = outRec2.pts;
                }
                else 
                {
                    outRec1.pts = PolygonBottom(p2);
                    outRec1.bottomPt = outRec1.pts;
                    outRec2 = CreateOutRec();
                    m_PolyOuts.Add(outRec2);
                    outRec2.idx = m_PolyOuts.Count - 1;
                    j.poly2Idx = outRec2.idx;
                    outRec2.pts = PolygonBottom(p1);
                    outRec2.bottomPt = outRec2.pts;
                }


                if (PointInPolygon(outRec2.pts.pt, outRec1.pts, m_UseFullRange))
                {
                    outRec2.isHole = !outRec1.isHole;
                    outRec2.FirstLeft = outRec1;
                    if (outRec2.isHole = IsClockwise(outRec2, m_UseFullRange)) 
                      ReversePolyPtLinks(outRec2.pts);
                }
                else if (PointInPolygon(outRec1.pts.pt, outRec2.pts, m_UseFullRange))
                {
                    outRec2.isHole = outRec1.isHole;
                    outRec1.isHole = !outRec2.isHole;
                    outRec2.FirstLeft = outRec1.FirstLeft;
                    outRec1.FirstLeft = outRec2;
                    if (outRec1.isHole = IsClockwise(outRec1, m_UseFullRange))
                      ReversePolyPtLinks(outRec1.pts);
                }
                else
                {
                    //I'm assuming that if outRec1 contain any holes, it still does after
                    //the split and that none are now contained by the new outRec2.
                    //In a perfect world, I'd PointInPolygon() every hole owned by outRec1
                    //to make sure it's still owned by outRec1 and not now owned by outRec2.
                    outRec2.isHole = outRec1.isHole;
                    outRec2.FirstLeft = outRec1.FirstLeft;
                }

                //now fixup any subsequent m_Joins that match this polygon
                for (int k = i + 1; k < m_Joins.Count; k++)
                {
                    JoinRec j2 = m_Joins[k];
                    if (j2.poly1Idx == j.poly1Idx && PointIsVertex(j2.pt1a, p2))
                        j2.poly1Idx = j.poly2Idx;
                    if (j2.poly2Idx == j.poly1Idx && PointIsVertex(j2.pt2a, p2))
                        j2.poly2Idx = j.poly2Idx;
                }
            }
            else
            {
                //having joined 2 polygons together, delete the obsolete pointer ...
                outRec2.pts = null;
                outRec2.bottomPt = null;
                outRec2.AppendLink = outRec1;
                if (outRec1.isHole && !outRec2.isHole) outRec1.isHole = false;

                //now fixup any subsequent joins that match this polygon
                for (int k = i + 1; k < m_Joins.Count; k++)
                {
                    JoinRec j2 = m_Joins[k];
                    if (j2.poly1Idx == j.poly2Idx) j2.poly1Idx = j.poly1Idx;
                    if (j2.poly2Idx == j.poly2Idx) j2.poly2Idx = j.poly1Idx;
                }
                j.poly2Idx = j.poly1Idx;
            }
            //now cleanup redundant edges too ...
            FixupOutPolygon(outRec1);
            if (j.poly2Idx != j.poly1Idx) FixupOutPolygon(outRec2);
          }
        }

        //------------------------------------------------------------------------------
        // OffsetPolygon functions ...
        //------------------------------------------------------------------------------

        public static double Area(Polygon poly, bool UseFullInt64Range = true)
        {
            int highI = poly.Count -1;
            if (highI < 2) return 0;
            if (UseFullInt64Range)
            {
                Int128 a = new Int128(0);
                a = Int128.Int128Mul(poly[highI].X, poly[0].Y) -
                    Int128.Int128Mul(poly[0].X, poly[highI].Y);
                for (int i = 0; i < highI; ++i)
                    a += Int128.Int128Mul(poly[i].X, poly[i + 1].Y) -
                    Int128.Int128Mul(poly[i + 1].X, poly[i].Y);
                return a.ToDouble() / 2;
            }
            else
            {
                double area = (double)poly[highI].X * (double)poly[0].Y -
                    (double)poly[0].X * (double)poly[highI].Y;
                for (int i = 0; i < highI; ++i)
                    area += (double)poly[i].X * (double)poly[i + 1].Y -
                        (double)poly[i + 1].X * (double)poly[i].Y;
                return area / 2;
            }
        }
        //------------------------------------------------------------------------------

        internal class DoublePoint
        {
            public double X { get; set; }
            public double Y { get; set; }
            public DoublePoint(double x = 0, double y = 0)
            {
                this.X = x; this.Y = y;
            }
        };
        //------------------------------------------------------------------------------


        internal static Polygon BuildArc(IntPoint pt, double a1, double a2, double r)
        {
          int steps = Math.Max(6, (int)(Math.Sqrt(Math.Abs(r)) * Math.Abs(a2 - a1)));
          Polygon result = new Polygon(steps);
          int n = steps - 1;
          double da = (a2 - a1) / n;
          double a = a1;
          for (int i = 0; i < steps; ++i)
          {
              result.Add(new IntPoint(pt.X + Round(Math.Cos(a) * r), pt.Y + Round(Math.Sin(a) * r)));
            a += da;
          }
          return result;
        }
        //------------------------------------------------------------------------------

        internal static DoublePoint GetUnitNormal(IntPoint pt1, IntPoint pt2)
        {
          double dx = ( pt2.X - pt1.X );
          double dy = ( pt2.Y - pt1.Y );
          if(  ( dx == 0 ) && ( dy == 0 ) ) return new DoublePoint();

          double f = 1 *1.0/ Math.Sqrt( dx*dx + dy*dy );
          dx *= f;
          dy *= f;
          return new DoublePoint(dy, -dx);
        }
        //------------------------------------------------------------------------------

        public static Polygons OffsetPolygons(Polygons pts, double delta)
        {
          if (delta == 0) return pts;
          double deltaSq = delta*delta;
          Polygons result = new Polygons(pts.Count);

          for (int j = 0; j < pts.Count; ++j)
          {
            int highI = pts[j].Count -1;
            //to minimize artefacts, strip out those polygons where
            //it's shrinking and where its area < Sqr(delta) ...
            double a1 = Area(pts[j], true);
            if (delta < 0) { if (a1 > 0 && a1 < deltaSq) highI = 0;}
            else if (a1 < 0 && -a1 < deltaSq) highI = 0; //nb: a hole if area < 0

            if (highI < 2 && delta <= 0) continue;
            if (highI == 0)
            {
                Polygon arc = BuildArc(pts[j][highI], 0, 2 * Math.PI, delta);
                result.Add(arc);
                continue;
            }

            Polygon pg = new Polygon(highI * 2 + 2);

            List<DoublePoint> normals = new List<DoublePoint>(highI+1);
            normals.Add(GetUnitNormal(pts[j][highI], pts[j][0]));
            for (int i = 1; i <= highI; ++i)
              normals.Add(GetUnitNormal(pts[j][i-1], pts[j][i]));

            for (int i = 0; i < highI; ++i)
            {
              pg.Add(new IntPoint(Round(pts[j][i].X + delta *normals[i].X),
                Round(pts[j][i].Y + delta *normals[i].Y)));
              pg.Add(new IntPoint(Round(pts[j][i].X + delta * normals[i + 1].X),
                Round(pts[j][i].Y + delta *normals[i+1].Y)));
            }
            pg.Add(new IntPoint(Round(pts[j][highI].X + delta * normals[highI].X),
              Round(pts[j][highI].Y + delta *normals[highI].Y)));
            pg.Add(new IntPoint(Round(pts[j][highI].X + delta * normals[0].X),
              Round(pts[j][highI].Y + delta *normals[0].Y)));

            //round off reflex angles (ie > 180 deg) unless it's almost flat (ie < 10deg angle) ...
            //cross product normals < 0 . reflex angle; dot product normals == 1 . no angle
            if ((normals[highI].X *normals[0].Y - normals[0].X *normals[highI].Y) *delta >= 0 &&
            (normals[0].X *normals[highI].X + normals[0].Y *normals[highI].Y) < 0.985)
            {
              double at1 = Math.Atan2(normals[highI].Y, normals[highI].X);
              double at2 = Math.Atan2(normals[0].Y, normals[0].X);
              if (delta > 0 && at2 < at1) at2 = at2 + Math.PI*2;
              else if (delta < 0 && at2 > at1) at2 = at2 - Math.PI*2;
              Polygon arc = BuildArc(pts[j][highI], at1, at2, delta);
              pg.InsertRange(highI * 2 + 1, arc);
            }
            for (int i = highI; i > 0; --i)
              if ((normals[i-1].X*normals[i].Y - normals[i].X*normals[i-1].Y) *delta >= 0 &&
              (normals[i].X*normals[i-1].X + normals[i].Y*normals[i-1].Y) < 0.985)
              {
                double at1 = Math.Atan2(normals[i-1].Y, normals[i-1].X);
                double at2 = Math.Atan2(normals[i].Y, normals[i].X);
                if (delta > 0 && at2 < at1) at2 = at2 + Math.PI*2;
                else if (delta < 0 && at2 > at1) at2 = at2 - Math.PI*2;
                Polygon arc = BuildArc(pts[j][i-1], at1, at2, delta);
                pg.InsertRange((i - 1) * 2 + 1, arc);
              }
            result.Add(pg);
          }

          //finally, clean up untidy corners ...
          Clipper clpr = new Clipper();
          clpr.AddPolygons(result, PolyType.ptSubject);
          if (delta > 0){
            if(!clpr.Execute(ClipType.ctUnion, result, PolyFillType.pftNonZero, PolyFillType.pftNonZero))
              result.Clear();
          }
          else
          {
            IntRect r = clpr.GetBounds();
            Polygon outer = new Polygon(4);
                outer.Add(new IntPoint(r.left - 10, r.bottom + 10));
                outer.Add(new IntPoint(r.right + 10, r.bottom + 10));
                outer.Add(new IntPoint(r.right + 10, r.top - 10));
                outer.Add(new IntPoint(r.left - 10, r.top - 10));
                clpr.AddPolygon(outer, PolyType.ptSubject);
                if (clpr.Execute(ClipType.ctUnion, result, PolyFillType.pftNonZero, PolyFillType.pftNonZero))
                    result.RemoveAt(0);
                else
                    result.Clear();
          }
          return result;
        }
        //------------------------------------------------------------------------------


    } //clipper namespace
  
    class ClipperException : Exception
    {
        private string m_description;
        public ClipperException(string description)
        {
            m_description = description;
            Console.WriteLine(m_description);
            throw new Exception(m_description);
        }
    }
    //------------------------------------------------------------------------------
}
