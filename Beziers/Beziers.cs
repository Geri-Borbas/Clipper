/*******************************************************************************
*                                                                              *
* Author    :  Angus Johnson                                                   *
* Version   :  1.0                                                             *
* Date      :  27 August 2013                                                  *
* Website   :  http://www.angusj.com                                           *
* Copyright :  Angus Johnson 2010-2013                                         *
*                                                                              *
* License:                                                                     *
* Use, modification & distribution is subject to Boost Software License Ver 1. *
* http://www.boost.org/LICENSE_1_0.txt                                         *
*                                                                              *
*******************************************************************************/

using System;
using System.Collections.Generic;
using ClipperLib;

namespace BezierLib
{

  using Path = List<IntPoint>;
  using Paths = List<List<IntPoint>>;

  public enum BezierType { CubicBezier, QuadBezier };

  public class BezierList
  {
    private const double DefaultPrecision = 0.5;
    private List<Bezier> m_Beziers = new List<Bezier>();

    public BezierList(double precision = DefaultPrecision)
    {
      Precision = (precision <= 0 ? DefaultPrecision : precision);  
    }
    //------------------------------------------------------------------------------

    public void AddPath(Path ctrlPts, BezierType bezType)
    {
      Bezier bezier = new Bezier(ctrlPts, bezType, (ushort)m_Beziers.Count, Precision);
      m_Beziers.Add(bezier);
    }
    //------------------------------------------------------------------------------

    public void AddPaths(Paths ctrlPts, BezierType bezType)
    {
      int minCnt = (bezType == BezierType.CubicBezier ? 4 : 3);
      foreach (Path p in ctrlPts)
      {
        if (p.Count < minCnt) continue;
        Bezier bezier = new Bezier(p, bezType, (ushort)m_Beziers.Count, Precision);
        m_Beziers.Add(bezier);
      }
    }
    //------------------------------------------------------------------------------

    public void Clear()
    {
      m_Beziers.Clear();
    }
    //------------------------------------------------------------------------------

    public double Precision { get; set; }
    //------------------------------------------------------------------------------

    public BezierType GetBezierType(int index)
    {
      if (index < 0 || index >= m_Beziers.Count)
        throw new BezierException("BezierList: index out of range.");
      return m_Beziers[index].beziertype;
    }
    //------------------------------------------------------------------------------

    public Path GetCtrlPts(int index)
    {
      if (index < 0 || index >= m_Beziers.Count)
        throw new BezierException("BezierList: index out of range.");
      Path result = new Path(m_Beziers[index].path);
      return result;   
    }
    //------------------------------------------------------------------------------

    public Path GetFlattenedPath(int index)
    {
      if (index < 0 || index >= m_Beziers.Count)
        throw new BezierException("BezierList: index out of range.");
      Path result = new Path(m_Beziers[index].FlattenedPath());
      return result;
    }
    //------------------------------------------------------------------------------

    public Paths GetFlattenedPaths()
    {
      Paths result = new Paths(m_Beziers.Count);
      foreach (Bezier b in m_Beziers)
        result.Add(b.FlattenedPath());
      return result;
    }
    //------------------------------------------------------------------------------

    public static Path Flatten(Path path, BezierType bezType, double precision = DefaultPrecision)
    {
      if (path.Count < 4) return new Path();
      Bezier b = new Bezier(path, bezType, 0, precision);
      return b.FlattenedPath();       
    }
    //------------------------------------------------------------------------------

    public static Paths Flatten(Paths paths, BezierType bezType, double precision = DefaultPrecision)
    {
      int minCnt = (bezType == BezierType.CubicBezier ? 4 : 3);
      Paths result = new Paths(paths.Count);
      for (int i = 0; i < paths.Count; i++)
      {
        if (paths[i].Count < minCnt) continue;
        Bezier b = new Bezier(paths[i], bezType, 0, precision);
        result.Add(b.FlattenedPath());
      }
      return result;       
    }
    //------------------------------------------------------------------------------

    private static IntPoint MidPoint(IntPoint p1, IntPoint p2)
    {
      IntPoint result = new IntPoint((p1.X + p2.X) / 2, (p1.Y + p2.Y) / 2, 0);
      return result;
    }
    //------------------------------------------------------------------------------

    public static Path CSplineToCBezier(Path cSpline)
    {
      int len = cSpline.Count;
      if (len < 4) return new Path();
      if (len % 2 != 0) len--;
      int i = (len / 2) - 1;
      Path result = new Path(i * 3 + 1);
      result.Add(cSpline[0]);
      result.Add(cSpline[1]);
      result.Add(cSpline[2]);
      i = 3;
      int lenMin1 = len - 1;
      while (i < lenMin1)
      {
        result.Add(MidPoint(cSpline[i - 1], cSpline[i]));
        result.Add(cSpline[i]);
        result.Add(cSpline[i + 1]);
        i += 2;
      }
      result.Add(cSpline[lenMin1]);
      return result;
    }
    //------------------------------------------------------------------------------

    public static Path QSplineToQBezier(Path qSpline)
    {
      int len = qSpline.Count;
      if (len < 3) return new Path();
      if (len % 2 == 0) len--;
      int i = len - 2;
      Path result = new Path(i * 2 + 1);
      result.Add(qSpline[0]);
      result.Add(qSpline[1]);
      i = 2;
      int lenMin1 = len - 1;
      while (i < lenMin1)
      {
        result.Add(MidPoint(qSpline[i - 1], qSpline[i]));
        result.Add(qSpline[i++]);
      }
      result.Add(qSpline[lenMin1]);
      return result;
    }
    //------------------------------------------------------------------------------

    public Path Reconstruct(Int64 z1, Int64 z2)
    {
      Path result = new Path();
      UInt16 seg, refId;
      BezierType beztype;
      Bezier.UnMakeZ(z1, out beztype, out seg, out refId); //nb: just need refId
      if (refId >= 0 && refId < m_Beziers.Count)
        result = m_Beziers[refId].Reconstruct(z1, z2);
      return result;       
    }
    //------------------------------------------------------------------------------

  }

  internal class Bezier
  {
    internal const double half = 0.5;
    private int reference;
    internal BezierType beziertype;
    internal Path path = new Path(); //path of Control Pts
    //segments: ie supports poly-beziers (ie before flattening) with up to 16,383 segments 
    internal List<Segment> segments = new List<Segment>();

    internal static Int64 MakeZ(BezierType beziertype, UInt16 seg, UInt16 refId, UInt32 idx)
    {
      UInt32 hi = (UInt32)((UInt16)beziertype << 30 | seg << 16 | (refId + 1));
      return (Int64)((UInt64)hi << 32 | idx);
    }
    //------------------------------------------------------------------------------

    internal static UInt32 UnMakeZ(Int64 zval, 
      out BezierType beziertype, out UInt16 seg, out UInt16 refId)
    {
      UInt32 vals = (UInt32)((UInt64)zval >> 32); //the top 32 bits => vals
      beziertype = (BezierType)((vals >> 30) & 0x1);
      seg = (UInt16)((vals >> 16) & 0x3FFF);
      refId = (UInt16)((vals & 0xFFFF) - 1);
      return (UInt32)(zval & 0xFFFFFFFF);
    }
    //------------------------------------------------------------------------------

    internal class IntNode
    {
      internal int val;
      internal IntNode next;
      internal IntNode prev;
      internal IntNode(int val) { this.val = val;}
    }

    internal IntNode InsertInt(IntNode insertAfter, int val)
    {
      IntNode result = new IntNode(val);
      result.next = insertAfter.next;
      result.prev = insertAfter;
      if (insertAfter.next != null)
        insertAfter.next.prev = result;
      insertAfter.next = result;
      return result;
    }
    //------------------------------------------------------------------------------

    internal IntNode GetFirstIntNode(IntNode current)
    {
      if (current == null) return null;
      IntNode result = current;
      while (result.prev != null)
        result = result.prev;
      //now skip the very first (dummy) node ...
      return result.next;
    }
    //------------------------------------------------------------------------------

    internal DoublePoint MidPoint(IntPoint ip1, IntPoint ip2)
    {
      return new DoublePoint((double)(ip1.X + ip2.X) / 2, (double)(ip1.Y + ip2.Y) / 2);
    }
    //------------------------------------------------------------------------------

    internal UInt32 GetMostSignificantBit(UInt32 v) //index is zero based
    {
      UInt32[] b = {0x2, 0xC, 0xF0, 0xFF00, 0xFFFF0000};
      Int32[] s = {0x1, 0x2, 0x4, 0x8, 0x10};
      Int32 result = 0;
      for (int i = 4; i >= 0; --i)
        if ((v & b[i]) != 0) 
        {
          v = v >> s[i];
          result = result | s[i];
        }
      return (UInt32)result;
    }
    //------------------------------------------------------------------------------

    internal bool IsBitSet(UInt32 val, Int32 index)
    {
      return (val & (1 << (int)index)) != 0;
    }
    //------------------------------------------------------------------------------

    internal bool Odd(Int32 val)
    {
      return (val % 2) != 0;
    }
    //------------------------------------------------------------------------------

    internal bool Even(Int32 val)
    {
      return (val % 2) == 0;
    }
    //------------------------------------------------------------------------------

    internal static Int64 Round(double value)
    {
      return value < 0 ? (Int64)(value - 0.5) : (Int64)(value + 0.5);
    }

    //------------------------------------------------------------------------------
    //------------------------------------------------------------------------------

    internal class Segment
    {
      internal BezierType beziertype;
      internal UInt16 RefID;
      internal UInt16 SegID;
      internal UInt32 Index;
      internal DoublePoint[] Ctrls = new DoublePoint[4];
      internal Segment[] Childs = new Segment[2];
      internal Segment(UInt16 refID, UInt16 segID, UInt32 idx)
      {
        this.RefID = refID;
        this.SegID = segID;
        this.Index = idx;
      }

      internal void GetFlattenedPath(Path path, bool init)
      {
        if (init)
        {
          Int64 Z = MakeZ(beziertype, SegID, RefID, Index);
          path.Add(new IntPoint(Round(Ctrls[0].X), Round(Ctrls[0].Y), Z));
        }

        if (Childs[0] == null)
        {
          int CtrlIdx = (beziertype == BezierType.CubicBezier ? 3: 2);
          Int64 Z = MakeZ(beziertype, SegID, RefID, Index);
          path.Add(new IntPoint(Round(Ctrls[CtrlIdx].X), Round(Ctrls[CtrlIdx].Y), Z));
        }
        else
        {
          Childs[0].GetFlattenedPath(path, false);
          Childs[1].GetFlattenedPath(path, false);
        }
      }

      internal void AddCtrlPtsToPath(Path ctrlPts)
      {
        int firstDelta = (ctrlPts.Count == 0 ? 0 : 1);
        switch (beziertype)
        {
          case BezierType.CubicBezier:
            for (int i = firstDelta; i < 4; ++i)
            {
              ctrlPts.Add(new IntPoint(
                Round(Ctrls[i].X), Round(Ctrls[i].Y)));
            }
            break;
          case BezierType.QuadBezier:
            for (int i = firstDelta; i < 3; ++i)
            {
              ctrlPts.Add(new IntPoint(
                Round(Ctrls[i].X), Round(Ctrls[i].Y)));
            }
            break;
        }
      }

    } //end Segment
    //------------------------------------------------------------------------------

    private class CubicBez : Segment
    {
      internal CubicBez(DoublePoint pt1, DoublePoint pt2, DoublePoint pt3, DoublePoint pt4,
        UInt16 refID, UInt16 segID, UInt32 idx, double precision): base(refID, segID, idx)
      {

        beziertype = BezierType.CubicBezier;
        Ctrls[0] = pt1; Ctrls[1] = pt2; Ctrls[2] = pt3; Ctrls[3] = pt4;
        //assess curve flatness:
        //http://groups.google.com/group/comp.graphics.algorithms/tree/browse_frm/thread/d85ca902fdbd746e
        if (Math.Abs(pt1.X + pt3.X - 2*pt2.X) + Math.Abs(pt2.X + pt4.X - 2*pt3.X) +
          Math.Abs(pt1.Y + pt3.Y - 2*pt2.Y) + Math.Abs(pt2.Y + pt4.Y - 2*pt3.Y) < precision)
            return;

        //if not at maximum precision then (recursively) create sub-segments ...
        //, p23, p34, p123, p234, p1234;
        DoublePoint p12 = new DoublePoint((pt1.X + pt2.X) * half, (pt1.Y + pt2.Y) * half);
        DoublePoint p23 = new DoublePoint((pt2.X + pt3.X) * half, (pt2.Y + pt3.Y) * half);
        DoublePoint p34 = new DoublePoint((pt3.X + pt4.X) * half, (pt3.Y + pt4.Y) * half);
        DoublePoint p123 = new DoublePoint((p12.X + p23.X) * half, (p12.Y + p23.Y) * half);
        DoublePoint p234 = new DoublePoint((p23.X + p34.X) * half, (p23.Y + p34.Y) * half);
        DoublePoint p1234 = new DoublePoint((p123.X + p234.X) * half, (p123.Y + p234.Y) * half);
        idx = idx << 1;
        Childs[0] = new CubicBez(pt1, p12, p123, p1234, refID, segID, idx, precision);
        Childs[1] = new CubicBez(p1234, p234, p34, pt4, refID, segID, idx +1, precision);
      } //end CubicBez constructor
    } //end CubicBez

    private class QuadBez : Segment
    {
      internal QuadBez(DoublePoint pt1, DoublePoint pt2, DoublePoint pt3,
        UInt16 refID, UInt16 segID, UInt32 idx, double precision): base(refID, segID, idx)
      {

        beziertype = BezierType.QuadBezier;
        Ctrls[0] = pt1; Ctrls[1] = pt2; Ctrls[2] = pt3;
        //assess curve flatness:
        if (Math.Abs(pt1.X + pt3.X - 2*pt2.X) + Math.Abs(pt1.Y + pt3.Y - 2*pt2.Y) < precision) return;

        //if not at maximum precision then (recursively) create sub-segments ...
        //DoublePoint p12, p23, p123;
        DoublePoint p12 = new DoublePoint((pt1.X + pt2.X) * half, (pt1.Y + pt2.Y) * half);
        DoublePoint p23 = new DoublePoint((pt2.X + pt3.X) * half, (pt2.Y + pt3.Y) * half);
        DoublePoint p123 = new DoublePoint((p12.X + p23.X) * half, (p12.Y + p23.Y) * half);
        idx = idx << 1;
        Childs[0] = new QuadBez(pt1, p12, p123, refID, segID, idx, precision);
        Childs[1] = new QuadBez(p123, p23, pt3, refID, segID, idx +1, precision);
      } //end QuadBez constructor
    } //end QuadBez
    //------------------------------------------------------------------------------

    Bezier() { }
    //------------------------------------------------------------------------------

    ~Bezier() { Clear(); }
    //------------------------------------------------------------------------------

    internal void Clear()
    {
      segments.Clear();
    }
    //------------------------------------------------------------------------------

    internal Bezier(Path ctrlPts, BezierType beztype, UInt16 refID, double precision)
    {
      SetCtrlPoints(ctrlPts, beztype, refID, precision);
    }
    //------------------------------------------------------------------------------

    internal void SetCtrlPoints(Path ctrlPts, BezierType beztype, UInt16 refID, double precision)
    {
      //clean up any existing data ...
      segments.Clear();

      this.beziertype = beztype;
      this.reference = refID;
      this.path = ctrlPts;
      int highpts = ctrlPts.Count - 1;

      switch( beztype )
      {
        case BezierType.CubicBezier:
          if (highpts < 3)  throw new BezierException("CubicBezier: insuffient control points.");
          else highpts -= highpts % 3;
          break;
        case BezierType.QuadBezier:
          if (highpts < 2) throw new BezierException("QuadBezier: insuffient control points.");
          else highpts -= highpts % 2;
          break;
        default: throw new BezierException("Unsupported bezier type");
      }

      //now for each segment in the poly-bezier create a binary tree structure
      //and add it to SegmentList ...
      switch( beztype )
      {
        case BezierType.CubicBezier:
          for (UInt16 i = 0; i < ((UInt16)highpts / 3); ++i)
          {
            Segment s = new CubicBez(
                        new DoublePoint(ctrlPts[i*3]),
                        new DoublePoint(ctrlPts[i*3+1]),
                        new DoublePoint(ctrlPts[i*3+2]),
                        new DoublePoint(ctrlPts[i*3+3]),
                        refID, i, 1, precision);
            segments.Add(s);
          }
          break;
        case BezierType.QuadBezier:
          for (UInt16 i = 0; i < ((UInt16)highpts / 2); ++i)
          {
            Segment s = new QuadBez(
                        new DoublePoint(ctrlPts[i*2]),
                        new DoublePoint(ctrlPts[i*2+1]),
                        new DoublePoint(ctrlPts[i*2+2]),
                        refID, i, 1, precision);
            segments.Add(s);
          }
          break;
      }
    }
    //------------------------------------------------------------------------------

    internal Path FlattenedPath()
    {
      Path path = new Path();
      for (int i = 0; i < segments.Count; i++)
        segments[i].GetFlattenedPath(path, i == 0);
      IntPoint pt = path[0];
      pt.Z = (Int64)((UInt64)pt.Z | 0x8000000000000000); //StartOfPath flag
      path[0] = pt;
      return path;
    }

  //------------------------------------------------------------------------------

  internal Path Reconstruct(Int64 startZ, Int64 endZ)
  {
    Path out_poly = new Path();
    if (endZ == startZ) return out_poly;

    bool reversed = false;
    if (endZ < 0)
    {
      Int64 tmp = startZ;
      startZ = endZ;
      endZ = tmp;
      reversed = true;
    }

    BezierType bt1, bt2;
    UInt16 seg1, seg2;
    UInt16 ref1, ref2;
    startZ = UnMakeZ(startZ, out bt1, out seg1, out ref1);
    endZ = UnMakeZ(endZ, out bt2, out seg2, out ref2);

    if (bt1 != beziertype || bt1 != bt2 ||
      ref1 != reference || ref1 != ref2) return out_poly;

    if (seg1 >= segments.Count || seg2 >= segments.Count) return out_poly;

    if (seg1 > seg2)
    {
      UInt16 i = seg1;
      seg1 = seg2;
      seg2 = i;
      Int64 tmp = startZ;
      startZ = endZ;
      endZ = tmp;
    }

    //do further checks for reversal, in case reversal within a single segment ...
    if (!reversed && seg1 == seg2 && startZ != 1 && endZ != 1)
    {
      UInt32 i = GetMostSignificantBit((uint)startZ);
      UInt32 j = GetMostSignificantBit((uint)endZ);
      UInt32 k = Math.Max(i, j);
      //nb: we must compare Node indexes at the same level ...
      i = (uint)startZ << (int)(k - i);
      j = (uint)endZ << (int)(k - j);
      if (i > j)
      {
        Int64 tmp = startZ;
        startZ = endZ;
        endZ = tmp;
        reversed = true;
      }
    }

    while (seg1 <= seg2)
    {
      //create a dummy first IntNode for the Int List ...
      IntNode intList = new IntNode(0);
      IntNode intCurr = intList;

      if (seg1 != seg2)
        ReconstructInternal(seg1, (uint)startZ, 1, intCurr);
      else
        ReconstructInternal(seg1, (uint)startZ, (uint)endZ, intCurr);

      //IntList now contains the indexes of one or a series of sub-segments
      //that together define part of or the whole of the original segment.
      //We now append these sub-segments to the new list of control points ...

      intCurr = intList.next; //nb: skips the dummy IntNode
      while (intCurr != null)
      {
        Segment s = segments[seg1];
        UInt32 j = (UInt32)intCurr.val;
        Int32 k = (Int32)GetMostSignificantBit(j) - 1;
        while (k >= 0)
        {
          if (s.Childs[0] == null) break;
          if (IsBitSet(j, k--))
            s = s.Childs[1]; 
          else
            s = s.Childs[0];
        }
        s.AddCtrlPtsToPath(out_poly);
        intCurr = intCurr.next;
      } //while 

      intList = null;
      seg1++;
      startZ = 1;
    }
    if (reversed) out_poly.Reverse();
    return out_poly;
  }
  //------------------------------------------------------------------------------

  internal void ReconstructInternal(UInt16 segIdx, UInt32 startIdx, UInt32 endIdx, IntNode intCurr)
  {
    //get the maximum level ...
    UInt32 L1 = GetMostSignificantBit(startIdx);
    UInt32 L2 = GetMostSignificantBit(endIdx);
    UInt32 Level = Math.Max(L1, L2);

    if (Level == 0) 
    {
      InsertInt(intCurr, 1);
      return;
    }

    int L, R;
    //Right marker (R): EndIdx projected onto the bottom level ...
    if (endIdx == 1) 
    {
      R = (1 << (int)((Level +1))) - 1;
    } else
    {
      int k = (int)(Level - L2);
      R = ((int)endIdx << k) + (1 << k) - 1;
    }

    if (startIdx == 1) //special case
    {
      //Left marker (L) is bottom left of the binary tree ...
      L = (1 << (int)Level);
      L1 = Level;
    } else
    {
      //For any given Z value, its corresponding X & Y coords (created by
      //FlattenPath using De Casteljau's algorithm) refered to the ctrl[3] coords
      //of many tiny polybezier segments. Since ctrl[3] coords are identical to
      //ctrl[0] coords in the following node, we can safely increment StartIdx ...
      L = (int)startIdx + 1;
      if (L == (1 << (int)(Level + 1))) return; //loops around tree so already at the end
    }

    //now get blocks of nodes from the LEFT ...
    int j = (int)(Level - L1);
    do
    {
      //while next level up then down-right doesn't exceed L2 do ...
      while (Even(L) && ((L << j) + (1 << (j + 1)) - 1 <= R))
      {
        L = (L >> 1); //go up a level
        j++;
      }
      intCurr = InsertInt(intCurr, L); //nb: updates IntCurrent
      L++;
    } while (L != (3 << (int)(Level - j - 1)) && //ie crosses the ditch in the middle
      (L << j) + (1 << j) < R);      //or L is now over or to the right of R

    L = (L << j);

    //now get blocks of nodes from the RIGHT ...
    j = 0;
    if (R >= L)
      do
      {
        while (Odd(R) && ((R-1) << j >= L)) 
        {
          R = R >> 1; //go up a level
          j++;
        }
        InsertInt(intCurr, R); //nb: doesn't update IntCurrent
        R--;
      } while (R != (3 << (int)(Level - j)) -1 && ((R << j) > L));
    
  }
  //------------------------------------------------------------------------------

  } //end Bezier
  //------------------------------------------------------------------------------

  class BezierException : Exception
  {
      public BezierException(string description) : base(description){}
  }
}
