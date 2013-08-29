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

#include <vector>
#include "clipper.hpp"
#include "beziers.hpp"

namespace BezierLib {


  struct IntNode{
    int val;
    IntNode* next;
    IntNode* prev;
    IntNode(int _val): val(_val), next(0), prev(0){};
  };

  const double half = 0.5;

  //------------------------------------------------------------------------------
  // Miscellaneous helper functions ...
  //------------------------------------------------------------------------------

  //nb. The format (high to low) of the 64bit Z value returned in the path ...
  //Typ  (2): either CubicBezier, QuadBezier
  //Seg (14): segment index since a bezier may consist of multiple segments
  //Ref (16): reference value passed to TBezier owner object
  //Idx (32): binary index to sub-segment containing control points

  inline cInt MakeZ(BezierType beziertype, unsigned short seg, unsigned short ref, unsigned idx)
  {
    unsigned hi = beziertype << 30 | seg << 16 | (ref +1);
    return (cInt)hi << 32 | idx;
  };
  //------------------------------------------------------------------------------

  unsigned UnMakeZ(cInt zval, BezierType& beziertype, unsigned short& seg, unsigned short& ref)
  {
    unsigned vals = zval >> 32; //the top 32 bits => vals
    beziertype = BezierType((vals >> 30) & 0x1);
    seg = (vals >> 16) & 0x3FFF;
    ref = (vals & 0xFFFF) -1;
    return zval & 0xFFFFFFFF;
  };
  //------------------------------------------------------------------------------

  IntNode* InsertInt(IntNode* insertAfter, int val)
  {
    IntNode* result = new IntNode(val);
    result->next = insertAfter->next;
    result->prev = insertAfter;
    if (insertAfter->next)
      insertAfter->next->prev = result;
    insertAfter->next = result;
    return result;
  }
  //------------------------------------------------------------------------------

  IntNode* GetFirstIntNode(IntNode* current)
  {
    if (!current) return 0;
    IntNode* result = current;
    while (result->prev)
      result = result->prev;
    //now skip the very first (dummy) node ...
    return result->next;
  }
  //------------------------------------------------------------------------------

  void DisposeIntNodes(IntNode* intnodes)
  {
    if (!intnodes) return;
    while (intnodes->prev)
      intnodes = intnodes->prev;

    do {
      IntNode* intnode = intnodes;
      intnodes = intnodes->next;
      delete intnode;
    } while (intnodes);
  }
  //------------------------------------------------------------------------------

  inline IntPoint MidPoint(const IntPoint& pt1, const IntPoint& pt2)
  {
    return IntPoint((pt1.X + pt2.X)/2, (pt1.Y + pt2.Y)/2);
  }
  //------------------------------------------------------------------------------

  unsigned GetMostSignificantBit(unsigned v) //index is zero based
  {
    const unsigned b[5] = {0x2, 0xC, 0xF0, 0xFF00, 0xFFFF0000};
    const unsigned s[5] = {0x1, 0x2, 0x4, 0x8, 0x10};
    unsigned result = 0;
    for (int i = 4; i >= 0; --i)
      if ((v & b[i]) != 0) 
      {
        v = v >> s[i];
        result = result | s[i];
      }
    return result;
  };
  //------------------------------------------------------------------------------

  inline bool IsBitSet(unsigned val, unsigned index)
  {
    return (val & (1 << index)) != 0;
  };
  //------------------------------------------------------------------------------

  inline bool Odd(const unsigned val)
  {
    return (val % 2) != 0;
  };
  //------------------------------------------------------------------------------

  inline bool Even(const unsigned val)
  {
    return (val % 2) == 0;
  };
  //------------------------------------------------------------------------------

  inline cInt Round(double val)
  {
    return (val < 0) ? static_cast<cInt>(val - 0.5) : static_cast<cInt>(val + 0.5);
  }

  //------------------------------------------------------------------------------
  // Segment class
  //------------------------------------------------------------------------------

  class Segment
  {
  public:
    BezierType beziertype;
    unsigned short RefID;
    unsigned short SegID;
    unsigned Index;
    DoublePoint Ctrls[4];
    Segment* Childs[2];

    Segment(unsigned short ref, unsigned short seg, unsigned idx): 
        RefID(ref), SegID(seg), Index(idx) {
          Childs[0] = 0;
          Childs[1] = 0;
    }; 
    //--------------------------------------------------------------------------

    ~Segment()
    {
      if (Childs[0]) delete Childs[0];
      if (Childs[1]) delete Childs[1];
    }
    //--------------------------------------------------------------------------

    void GetFlattenedPath(Path& path, bool init)
    {
      if (init)
      {
        cInt Z = MakeZ(beziertype, SegID, RefID, Index);
        path.push_back(IntPoint(Round(Ctrls[0].X), Round(Ctrls[0].Y), Z));
      } 
      
      if (!Childs[0])
      {
        int CtrlIdx = 3;
        if (beziertype == QuadBezier) CtrlIdx = 2;
        cInt Z = MakeZ(beziertype, SegID, RefID, Index);
        path.push_back(IntPoint(Round(Ctrls[CtrlIdx].X), Round(Ctrls[CtrlIdx].Y), Z));
      } else
      {
        Childs[0]->GetFlattenedPath(path, false);
        Childs[1]->GetFlattenedPath(path, false);
      }
    }
    //--------------------------------------------------------------------------

    void AddCtrlPtsToPath(Path& ctrlPts)
    {
      int firstDelta = (ctrlPts.empty() ? 0 : 1);
      switch (beziertype)
      {
        case CubicBezier:
          for (int i = firstDelta; i < 4; ++i)
          {
            ctrlPts.push_back(IntPoint(
              Round(Ctrls[i].X), Round(Ctrls[i].Y)));
          }
          break;
        case QuadBezier:
          for (int i = firstDelta; i < 3; ++i)
          {
            ctrlPts.push_back(IntPoint(
              Round(Ctrls[i].X), Round(Ctrls[i].Y)));
          }
          break;
      }
    }
    //--------------------------------------------------------------------------
  };

  //------------------------------------------------------------------------------
  // CubicBez class
  //------------------------------------------------------------------------------

  class CubicBez: public Segment
  {
  public:
    CubicBez(const DoublePoint& pt1, const DoublePoint& pt2, 
      const DoublePoint& pt3, const DoublePoint& pt4,
      unsigned short ref, unsigned short seg, unsigned idx, double precision): Segment(ref, seg, idx)
    {
     
      beziertype = CubicBezier;
      Ctrls[0] = pt1; Ctrls[1] = pt2; Ctrls[2] = pt3; Ctrls[3] = pt4;
      //assess curve flatness:
      //http://groups.google.com/group/comp.graphics.algorithms/tree/browse_frm/thread/d85ca902fdbd746e
      if (abs(pt1.X + pt3.X - 2*pt2.X) + abs(pt2.X + pt4.X - 2*pt3.X) +
        abs(pt1.Y + pt3.Y - 2*pt2.Y) + abs(pt2.Y + pt4.Y - 2*pt3.Y) < precision)
          return;

      //if not at maximum precision then (recursively) create sub-segments ...
      DoublePoint p12, p23, p34, p123, p234, p1234;
      p12.X = (pt1.X + pt2.X) * half;
      p12.Y = (pt1.Y + pt2.Y) * half;
      p23.X = (pt2.X + pt3.X) * half;
      p23.Y = (pt2.Y + pt3.Y) * half;
      p34.X = (pt3.X + pt4.X) * half;
      p34.Y = (pt3.Y + pt4.Y) * half;
      p123.X = (p12.X + p23.X) * half;
      p123.Y = (p12.Y + p23.Y) * half;
      p234.X = (p23.X + p34.X) * half;
      p234.Y = (p23.Y + p34.Y) * half;
      p1234.X = (p123.X + p234.X) * half;
      p1234.Y = (p123.Y + p234.Y) * half;
      idx = idx << 1;
      Childs[0] = new CubicBez(pt1, p12, p123, p1234, ref, seg, idx, precision);
      Childs[1] = new CubicBez(p1234, p234, p34, pt4, ref, seg, idx +1, precision);
    }
  };

  //------------------------------------------------------------------------------
  // QuadBez class
  //------------------------------------------------------------------------------

  class QuadBez: public Segment
  {
  public:
    QuadBez(const DoublePoint& pt1, const DoublePoint& pt2, const DoublePoint& pt3,
      unsigned short ref, unsigned short seg, unsigned idx, double precision): Segment(ref, seg, idx)
    {
      beziertype = QuadBezier;
      Ctrls[0] = pt1; Ctrls[1] = pt2; Ctrls[2] = pt3;
      //assess curve flatness:
      if (std::abs(pt1.X + pt3.X - 2*pt2.X) + abs(pt1.Y + pt3.Y - 2*pt2.Y) < precision)
        return;

      //if not at maximum precision then (recursively) create sub-segments ...
      DoublePoint p12, p23, p123;
      p12.X = (pt1.X + pt2.X) * half;
      p12.Y = (pt1.Y + pt2.Y) * half;
      p23.X = (pt2.X + pt3.X) * half;
      p23.Y = (pt2.Y + pt3.Y) * half;
      p123.X = (p12.X + p23.X) * half;
      p123.Y = (p12.Y + p23.Y) * half;
      idx = idx << 1;
      Childs[0] = new QuadBez(pt1, p12, p123, ref, seg, idx, precision);
      Childs[1] = new QuadBez(p123, p23, pt3, ref, seg, idx +1, precision);
    }
  };

  //------------------------------------------------------------------------------
  // Bezier class
  //------------------------------------------------------------------------------

  class BezierList; //forward

  class Bezier
  {
  private:
    int        m_ref;
    BezierType m_beztype;
    Path       m_path;
    std::vector< Segment* > segments;
  public:

    friend class BezierList;

    Bezier(){};

    Bezier(
      const Path& ctrlPts,                  //CtrlPts: Bezier control points
      BezierType beztype,                   //CubicBezier or QuadBezier ...
      short ref,                            //Ref: user supplied identifier;
      double precision)                     //Precision of flattened path
    {
      SetCtrlPoints(ctrlPts, beztype, ref, precision);
    };
    //--------------------------------------------------------------------------

    ~Bezier()
    {
      Clear();
    };
    //--------------------------------------------------------------------------

    void Clear()
    {
      for (size_t i = 0; i < segments.size(); ++i)
        delete segments[i];
      segments.resize(0);
    };
    //--------------------------------------------------------------------------

    void SetCtrlPoints(const Path& ctrlPts,
      BezierType beztype, unsigned short ref, double precision)
    {
      //clean up any existing data ...
      Clear();
      size_t highpts = ctrlPts.size() -1;
      m_beztype = beztype;
      m_ref = ref;
      m_path = ctrlPts;

      switch( beztype )
      {
        case CubicBezier:
          if (highpts < 3) throw "CubicBezier: insuffient control points.";
          else highpts -= highpts % 3;
          break;
        case QuadBezier:
          if (highpts < 2) throw "QuadBezier: insuffient control points.";
          else highpts -= highpts % 2;
          break;
        default: throw "Unsupported bezier type";
      }

      //now for each segment in the poly-bezier create a binary tree structure
      //and add it to SegmentList ...
      switch( beztype )
      {
        case CubicBezier:
          for (int i = 0; i < ((int)highpts / 3); ++i)
          {
            Segment* s = new CubicBez(
                        DoublePoint(ctrlPts[i*3]),
                        DoublePoint(ctrlPts[i*3+1]),
                        DoublePoint(ctrlPts[i*3+2]),
                        DoublePoint(ctrlPts[i*3+3]),
                        ref, i, 1, precision);
            segments.push_back(s);
          }
          break;
        case QuadBezier:
          for (int i = 0; i < ((int)highpts / 2); ++i)
          {
            Segment* s = new QuadBez(
                        DoublePoint(ctrlPts[i*2]),
                        DoublePoint(ctrlPts[i*2+1]),
                        DoublePoint(ctrlPts[i*2+2]),
                        ref, i, 1, precision);
            segments.push_back(s);
          }
          break;
      }
    }
    //--------------------------------------------------------------------------

    void FlattenedPath(Path& out_poly)
    {
      out_poly.resize(0);
      for (size_t i = 0; i < segments.size(); ++i)
        segments[i]->GetFlattenedPath(out_poly, i == 0);
      out_poly[0].Z = (out_poly[0].Z | 0x8000000000000000); //StartOfPath flag
    }
    //--------------------------------------------------------------------------

    void Reconstruct(cInt startZ, cInt endZ, Path& out_poly)
    {
      out_poly.resize(0);
      if (endZ == startZ) return;

      bool reversed = false;
      if (endZ < 0) 
      {
        cInt tmp = startZ;
        startZ = endZ;
        endZ = tmp;
        reversed = true;
      }

      BezierType bt1, bt2;
      unsigned short seg1, seg2;
      unsigned short  ref1, ref2;
      startZ = UnMakeZ(startZ, bt1, seg1, ref1);
      endZ   = UnMakeZ(endZ,   bt2, seg2, ref2);

      if (bt1 != m_beztype || bt1 != bt2 ||
        ref1 != m_ref || ref1 != ref2) return;

      if (seg1 >= segments.size() || seg2 >= segments.size()) return;

      if (seg1 > seg2)
      {
        unsigned i = seg1;
        seg1 = seg2;
        seg2 = i;
        cInt tmp = startZ;
        startZ = endZ;
        endZ = tmp;
      }

      //do further checks for reversal, in case reversal within a single segment ...
      if (!reversed && seg1 == seg2 && startZ != 1 && endZ != 1)
      {
        unsigned i = GetMostSignificantBit((unsigned)startZ);
        unsigned j = GetMostSignificantBit((unsigned)endZ);
        unsigned k = std::max(i, j);
        //nb: we must compare Node indexes at the same level ...
        i = (unsigned)startZ << (k - i);
        j = (unsigned)endZ << (k - j);
        if (i > j)
        {
          cInt tmp = startZ;
          startZ = endZ;
          endZ = tmp;
          reversed = true;
        }
      }

      while (seg1 <= seg2)
      {
        //create a dummy first IntNode for the Int List ...
        IntNode* intList = new IntNode(0);
        IntNode* intCurr = intList;

        if (seg1 != seg2)
          ReconstructInternal(seg1, (unsigned)startZ, 1, intCurr);
        else
          ReconstructInternal(seg1, (unsigned)startZ, (unsigned)endZ, intCurr);

        //IntList now contains the indexes of one or a series of sub-segments
        //that together define part of or the whole of the original segment.
        //We now append these sub-segments to the new list of control points ...

        intCurr = intList->next; //nb: skips the dummy IntNode
        while (intCurr)
        {
          Segment* s = segments[seg1];
          int j = intCurr->val;
          int k = GetMostSignificantBit(j) -1;
          while (k >= 0)
          {
            if (!s->Childs[0]) break;
            if (IsBitSet(j, k--))
              s = s->Childs[1]; 
            else
              s = s->Childs[0];
          }
          s->AddCtrlPtsToPath(out_poly);
          intCurr = intCurr->next;
        } //while 

        DisposeIntNodes(intList);
        seg1++;
        startZ = 1;
      }
      if (reversed)
        ReversePolygon(out_poly);
    }
    //--------------------------------------------------------------------------

    void ReconstructInternal(unsigned short segIdx, 
      unsigned startIdx, unsigned endIdx, IntNode* intCurr)
    {
      //get the maximum level ...
      unsigned L1 = GetMostSignificantBit(startIdx);
      unsigned L2 = GetMostSignificantBit(endIdx);
      int Level = std::max(L1, L2);

      if (Level == 0) 
      {
        InsertInt(intCurr, 1);
        return;
      }

      int L, R;
      //Right marker (R): EndIdx projected onto the bottom level ...
      if (endIdx == 1) 
      {
        R = (1 << (Level +1)) - 1;
      } else
      {
        int j = (Level - L2);
        R = (endIdx << j) + (1 << j) -1;
      }

      if (startIdx == 1) //special case
      {
        //Left marker (L) is bottom left of the binary tree ...
        L = (1 << Level);
        L1 = Level;
      } else
      {
        //For any given Z value, its corresponding X & Y coords (created by
        //FlattenPath using De Casteljau's algorithm) refered to the ctrl[3] coords
        //of many tiny polybezier segments. Since ctrl[3] coords are identical to
        //ctrl[0] coords in the following node, we can safely increment StartIdx ...
        L = startIdx +1;
        if (L == (1 << (Level +1))) return; //loops around tree so already at the end
      }

      //now get blocks of nodes from the LEFT ...
      int j = Level - L1;
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
      } while (L != (3 << (Level - j - 1)) &&  //ie middle not crossed
        (L << j) + (1 << j) < R);              //and levelled L < R

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
        } while (R != (3 << (Level - j)) -1 && ((R << j) > L));
    }
    //--------------------------------------------------------------------------
  };
  
  //------------------------------------------------------------------------------
  // BezierList class
  //------------------------------------------------------------------------------

  BezierList::BezierList(double precision)
  {
    if (precision <= 0) precision = DefaultPrecision;
    m_Precision = precision;
  }
  //------------------------------------------------------------------------------
    
  BezierList::~BezierList()
  {
    Clear();
  }
  //------------------------------------------------------------------------------

  void BezierList::AddPath(const Path ctrlPts, BezierType bezType)
  {
    Bezier* NewBez = new Bezier(ctrlPts, bezType, m_Beziers.size(), m_Precision);
    m_Beziers.push_back(NewBez);
  }
  //------------------------------------------------------------------------------

  void BezierList::AddPaths(const Paths ctrlPts, BezierType bezType)
  {
    size_t minCnt = (bezType == CubicBezier ? 4 : 3);
    for (size_t i = 0; i < ctrlPts.size(); ++i)
    {
      if (ctrlPts[i].size() < minCnt) continue;
      Bezier* NewBez = new Bezier(ctrlPts[i], bezType, m_Beziers.size(), m_Precision);
      m_Beziers.push_back(NewBez);
    }
  }
  //------------------------------------------------------------------------------

  void BezierList::Clear()
  {
    for (size_t i = 0; i < m_Beziers.size(); ++i)
      delete m_Beziers[i];
    m_Beziers.clear();
  }
  //------------------------------------------------------------------------------

  void BezierList::GetCtrlPts(int index, Path& path)
  {
    if (index < 0 || index >= (int)m_Beziers.size()) 
      throw "BezierList: index out of range";
    path = m_Beziers[index]->m_path;
  }
  //------------------------------------------------------------------------------

  BezierType BezierList::GetBezierType(int index)
  {
    if (index < 0 || index >= (int)m_Beziers.size()) 
      throw "BezierList: index out of range";
    return m_Beziers[index]->m_beztype;
  }
  //------------------------------------------------------------------------------

  void BezierList::GetFlattenedPath(int index, Path& path)
  {
    if (index < 0 || index >= (int)m_Beziers.size()) 
      throw "BezierList: index out of range";
    m_Beziers[index]->FlattenedPath(path);
  }
  //------------------------------------------------------------------------------

  void BezierList::GetFlattenedPaths(Paths& paths)
  {
    paths.clear();
    paths.resize(m_Beziers.size());
    for (size_t i = 0; i < m_Beziers.size(); ++i)
      m_Beziers[i]->FlattenedPath(paths[i]);
  }
  //------------------------------------------------------------------------------

  void BezierList::Flatten(const Path& in_path, 
    Path& out_path, BezierType bezType, double precision)
  {
    out_path.clear();
    size_t minCnt = (bezType == CubicBezier ? 4 : 3);
    if (in_path.size() < minCnt) return;
    Bezier b(in_path, bezType, 0, precision);
    b.FlattenedPath(out_path);
  }
  //------------------------------------------------------------------------------

  void BezierList::Flatten(const Paths& in_paths, 
    Paths& out_paths, BezierType bezType, double precision)
  {
    out_paths.clear();
    out_paths.resize(in_paths.size());
    size_t minCnt = (bezType == CubicBezier ? 4 : 3);
    for (size_t i = 0; i < in_paths.size(); ++i)
    {
      if (in_paths[i].size() < minCnt) continue;
      Bezier b(in_paths[i], bezType, 0, precision);
      b.FlattenedPath(out_paths[i]);
    }
  }
  //------------------------------------------------------------------------------

  void BezierList::CSplineToCBezier(const Path& in_path, Path& out_path)
  {
    out_path.clear();
    size_t len = in_path.size();
    if (len < 4) return;
    if (len % 2 != 0) len--;
    size_t i = (len / 2) - 1;
    out_path.reserve(i * 3 + 1);
    out_path.push_back(in_path[0]);
    out_path.push_back(in_path[1]);
    out_path.push_back(in_path[2]);
    i = 3;
    size_t lenMin1 = len - 1;
    while (i < lenMin1) 
    {
      out_path.push_back(MidPoint(in_path[i-1], in_path[i]));
      out_path.push_back(in_path[i++]);
      out_path.push_back(in_path[i++]);
    }
    out_path.push_back(in_path[lenMin1]);
  }
  //------------------------------------------------------------------------------

    void BezierList::QSplineToQBezier(const Path& in_path, Path& out_path)
  {
    out_path.clear();
    size_t len = in_path.size();
    if (len < 3) return;
    if (len % 2 == 0) len--;
    size_t i = len - 2;
    out_path.reserve(i * 2 + 1);
    out_path.push_back(in_path[0]);
    out_path.push_back(in_path[1]);
    i = 2;
    size_t lenMin1 = len - 1;
    while (i < lenMin1) 
    {
      out_path.push_back(MidPoint(in_path[i-1], in_path[i]));
      out_path.push_back(in_path[i++]);
    }
    out_path.push_back(in_path[lenMin1]);
  }
  //------------------------------------------------------------------------------

  void BezierList::Reconstruct(cInt z1, cInt z2, Path& path)
  {
    unsigned short seg, ref;
    BezierType beztype;
    UnMakeZ(z1, beztype, seg, ref); //UnMakeZ() here just for ref
    if (ref >= 0 && ref < m_Beziers.size())
      m_Beziers[ref]->Reconstruct(z1, z2, path);
    else
      path.clear();
  }
  //------------------------------------------------------------------------------
  
  double BezierList::Precision()
  {
    return m_Precision;
  }
  //------------------------------------------------------------------------------

  void BezierList::Precision(double value)
  {
    m_Precision = value;
  }
  //------------------------------------------------------------------------------

} //end namespace