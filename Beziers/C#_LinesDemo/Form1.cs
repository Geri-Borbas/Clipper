using System;
using System.Collections.Generic;
using System.Windows.Forms;
using System.Drawing;
using System.Drawing.Drawing2D;
using ClipperLib;
using BezierLib;

namespace Clipper_Lines_Demo
{

  using Path = List<IntPoint>;
  using Paths = List<List<IntPoint>>;
  using cInt = Int64;

  public partial class MainForm : Form
  {

    const int scale = 10;

    public Paths subjLines = new Paths();
    public Paths subjBeziers = new Paths();
    public Paths subjPolygons = new Paths();
    public Paths clipPolygons = new Paths();
    public Bitmap bmp = null;
    public Graphics bmpGraphics = null;
    
    public MainForm()
    {
      InitializeComponent();
    }
    //------------------------------------------------------------------------------

    private static void ClipCallback(cInt Z1, cInt Z2, ref IntPoint pt)
    {
      pt.Z = -1; //intersection flag 
    }
    //------------------------------------------------------------------------------

    private void BmpUpdateNeeded()
    {
      if (bmpGraphics == null) return;
      bmpGraphics.Clear(Color.White);
      FillMode fm = (mEvenOdd.Checked ? FillMode.Alternate : FillMode.Winding);

      Paths ap = GetActivePaths();
      if (ap == subjBeziers)
        DrawBezierCtrlLines(bmpGraphics, subjBeziers);
      Paths paths = MakeCtrlButtons(ap);
      DrawButtons(bmpGraphics, paths);
      DrawPath(bmpGraphics, subjLines, false, 0x0, 0xFFAAAAAA, fm, 1.0);
      DrawPath(bmpGraphics, subjPolygons, true, 0x20808080, 0xFFAAAAAA, fm, 1.0);
      DrawPath(bmpGraphics, clipPolygons, true, 0x10FF6600, 0x99FF6600, fm, 1.0);
      //draw beziers ...
      BezierList beziers = new BezierList();
      beziers.AddPaths(subjBeziers, BezierType.CubicBezier);
      //paths = BezierList.Flatten(subjBeziers, BezierType.CubicBezier);
      paths = beziers.GetFlattenedPaths();
      DrawPath(bmpGraphics, paths, false, 0x0, 0xFFAAAAAA, fm, 1.0);

      if (!mNone.Checked)
      {
        PolyFillType pft = (mEvenOdd.Checked ? PolyFillType.pftEvenOdd : PolyFillType.pftNonZero);
        ClipType ct;
        if (mUnion.Checked) ct = ClipType.ctUnion;
        else if (mDifference.Checked) ct = ClipType.ctDifference;
        else if (mXor.Checked) ct = ClipType.ctXor;
        else ct = ClipType.ctIntersection;

        //CLIPPING DONE HERE ...
        Clipper c = new Clipper();
        c.ZFillFunction = ClipCallback; //callback function that's called at intersections
        c.AddPaths(subjLines, PolyType.ptSubject, false);
        c.AddPaths(paths, PolyType.ptSubject, false); //paths == flattened beziers
        c.AddPaths(subjPolygons, PolyType.ptSubject, true);
        c.AddPaths(clipPolygons, PolyType.ptClip, true);
        PolyTree polytree = new PolyTree();
        Paths solution;
        c.Execute(ct, polytree, pft, pft); //EXECUTE CLIP
        solution = Clipper.ClosedPathsFromPolyTree(polytree);
        DrawPath(bmpGraphics, solution, true, 0x2033AA00, 0xFF33AA00, fm, 2.0);
        solution = Clipper.OpenPathsFromPolyTree(polytree);
        DrawPath(bmpGraphics, solution, false, 0x0, 0xFF33AA00, fm, 2.0);
        
        //now to show off reconstructing beziers ...
        if (cbReconstBez.Checked)
        {
          cInt z1, z2;
          paths.Clear();
          foreach (Path p in solution)
          {
            //nb: paths with p[x].Z == 0 aren't beziers and 
            //vertices at intersections will have p[x].Z == -1.
            int cnt = p.Count;
            if (cnt < 2 || p[0].Z == 0 || p[1].Z == 0) continue;
            //get each bezier's new endpoints but ignoring the
            //intersection points (Z == -1) to simplify the demo ...
            z1 = (p[0].Z == -1 ? p[1].Z : p[0].Z);
            z2 = (p[cnt - 1].Z == -1 ? p[cnt - 2].Z : p[cnt - 1].Z);
            //and reconstruct each bezier ...
            Path CtrlPts = beziers.Reconstruct(z1, z2);

            if (cbShowCtrls.Enabled && cbShowCtrls.Checked)
            {
              //show CtrlPts as buttons too ...
              Paths tmp = new Paths(1);
              tmp.Add(CtrlPts);
              tmp = MakeCtrlButtons(tmp);
              DrawButtons(bmpGraphics, tmp);
            }
            
            paths.Add(CtrlPts);
          }
          //now flatten the reconstructed beziers just to show that they're accurate ...
          paths = BezierList.Flatten(paths, BezierType.CubicBezier);
          DrawPath(bmpGraphics, paths, false, 0x0, 0xFFFF0000, fm, 2.0);
        }
      }

      string s = "  ";
      if (mIntersection.Checked) s += "INTERSECTION";
      else if (mUnion.Checked) s += "UNION";
      else if (mDifference.Checked) s += "DIFFERENCE";
      else if (mXor.Checked) s += "XOR";
      else s += "NO CLIPPING";
      s += " with ";
      if (mEvenOdd.Checked) s += "EVENODD fill.";
      else s += "NONZERO fill.";
      toolStripStatusLabel2.Text = s;
      DisplayPanel.Invalidate();
    }
    //------------------------------------------------------------------------------

    private void DisplayPanel_Paint(object sender, PaintEventArgs e)
    {
      if (bmp == null) return;
      var g = e.Graphics;
      g.DrawImage(bmp,0,0);
    }
    //------------------------------------------------------------------------------

    private void mExit_Click(object sender, EventArgs e)
    {
      Close();
    }
    //------------------------------------------------------------------------------

    private static Color MakeColor(uint color)
    {
      return Color.FromArgb((int)color);
    }
    //------------------------------------------------------------------------------

    private static void ClipperPathToGraphicsPath(Path path, GraphicsPath gp, bool Closed)
    {
      if (path.Count == 0) return;
      PointF[] pts = new PointF[path.Count];
      for (int i = 0; i < path.Count; ++i)
      {
        pts[i].X = (float)path[i].X / scale;
        pts[i].Y = (float)path[i].Y / scale;
      }
      if (Closed && path.Count > 2) 
        gp.AddPolygon(pts);
      else 
      {
        gp.StartFigure();
        gp.AddLines(pts);
      }
    }
    //------------------------------------------------------------------------------

    private static Paths MakeCtrlButtons(Paths paths)
    {
      if (paths.Count == 0) return new Paths();
      const int btnRadius = 3 * scale;
      const int q = 2 * scale;
      //make buttons for each IntPoint in the last path of paths
      int i = paths.Count -1;
      int len = paths[i].Count;
      Paths result = new Paths(len);
      for (int j = 0; j < len; ++j)
      {
        Path p = new Path(8);
        cInt x = paths[i][j].X;
        cInt y = paths[i][j].Y;
        p.Add(new IntPoint(x-btnRadius+q, y-btnRadius));
        p.Add(new IntPoint(x + btnRadius - q, y - btnRadius));
        p.Add(new IntPoint(x+btnRadius, y-btnRadius+q));
        p.Add(new IntPoint(x+btnRadius, y+btnRadius-q));
        p.Add(new IntPoint(x+btnRadius-q, y+btnRadius));
        p.Add(new IntPoint(x-btnRadius+q, y+btnRadius));
        p.Add(new IntPoint(x-btnRadius, y+btnRadius-q));
        p.Add(new IntPoint(x-btnRadius, y-btnRadius+q));
        result.Add(p);
      }
      return result;
    }
    //------------------------------------------------------------------------------

    private static void DrawButtons(Graphics graphics, Paths paths,
      FillMode fillMode = FillMode.Alternate, double penWidth = 1.0)
    {
      if (paths.Count == 0) return;
      SolidBrush midBrush = new SolidBrush(MakeColor(0x20808080));
      SolidBrush startBrush = new SolidBrush(MakeColor(0x9980FF80));
      SolidBrush endBrush = new SolidBrush(MakeColor(0x99FA8072));
      Pen pen = new Pen(Color.Black, (float)penWidth);
      GraphicsPath gpath = new GraphicsPath(fillMode);
      int highI = paths.Count - 1;
      for (int i = 0; i <= highI; ++i)
        ClipperPathToGraphicsPath(paths[i], gpath, true);
      graphics.FillPath(midBrush, gpath);
      graphics.DrawPath(pen, gpath);

      gpath.Reset();
      ClipperPathToGraphicsPath(paths[0], gpath, true);
      graphics.FillPath(startBrush, gpath);
      if (highI > 0)
      {
        gpath.Reset();
        ClipperPathToGraphicsPath(paths[highI], gpath, true);
        graphics.FillPath(endBrush, gpath);
      }
      midBrush.Dispose();
      startBrush.Dispose();
      endBrush.Dispose();
      pen.Dispose();
      gpath.Dispose();
    }
    //------------------------------------------------------------------------------

    private static void DrawBezierCtrlLines(Graphics graphics, Paths paths)
    {
      if (paths.Count == 0) return;
      Pen pen = new Pen(MakeColor(0xFFEEEEEE));
      GraphicsPath gpath = new GraphicsPath();
      int highI = paths.Count - 1;
      PointF[] pts = new PointF[2];
      for (int i = 0; i <= highI; ++i)
      {
        int j = paths[i].Count;
        if (j < 2) continue;
        pts[0].X = (float)paths[i][0].X / scale;
        pts[0].Y = (float)paths[i][0].Y / scale;
        pts[1].X = (float)paths[i][1].X / scale;
        pts[1].Y = (float)paths[i][1].Y / scale;
        gpath.StartFigure();
        gpath.AddLines(pts);
        int k = 2;
        while (k < j -1)
        {
          pts[0].X = (float)paths[i][k].X / scale;
          pts[0].Y = (float)paths[i][k].Y / scale;
          pts[1].X = (float)paths[i][k + 1].X / scale;
          pts[1].Y = (float)paths[i][k + 1].Y / scale;
          gpath.StartFigure();
          gpath.AddLines(pts);
          k += (k % 3 == 0 ? 2 : 1);
        }
      }
      graphics.DrawPath(pen, gpath);
      gpath.Reset();
      pen.Dispose();
      gpath.Dispose();
    }
    //------------------------------------------------------------------------------

    private static void DrawPath(Graphics graphics, Paths paths, bool closed, 
      uint brushClr, uint penClr,
      FillMode fillMode = FillMode.Alternate, double penWidth = 1.0)
    {
      if (paths.Count == 0) return;
      SolidBrush brush = new SolidBrush (MakeColor(brushClr));
      Pen pen = new Pen(MakeColor(penClr), (float)penWidth);
      GraphicsPath gpath = new GraphicsPath(fillMode);
      for (int i = 0; i < paths.Count; ++i)
        ClipperPathToGraphicsPath(paths[i], gpath, closed);
      if (closed) graphics.FillPath(brush, gpath);
      graphics.DrawPath(pen, gpath);
      
      brush.Dispose();
      pen.Dispose();
      gpath.Dispose();
    }
    //------------------------------------------------------------------------------

    private Paths GetActivePaths()
    {
      Paths p;
      if (rbSubjLine.Checked) p = subjLines;
      else if (rbSubjBezier.Checked) p = subjBeziers;
      else if (rbSubjPoly.Checked) p = subjPolygons;
      else p = clipPolygons;
      return p;
    }
    //------------------------------------------------------------------------------

    private void DisplayPanel_MouseDown(object sender, MouseEventArgs e)
    {
      if (e.Button == MouseButtons.Right)
      {
        mNewPath_Click(sender, e);
        return;
      }
      Paths p = GetActivePaths();
      if (p.Count == 0) p.Add(new Path());
      int i = p.Count;
      p[i - 1].Add(new IntPoint(e.X * scale, e.Y * scale));
      i = p[i - 1].Count;
      UpdateBtnAndMenuState();
      BmpUpdateNeeded();
    }
    //------------------------------------------------------------------------------

    private void MainForm_KeyDown(object sender, KeyEventArgs e)
    {
      if (e.KeyValue == (int)Keys.Escape) Close();
      else if (e.KeyValue == (int)Keys.Z && e.Control) mUndo_Click(sender, e);
    }
    //------------------------------------------------------------------------------

    private void UpdateBtnAndMenuState()
    {
      mClear.Enabled = subjLines.Count > 0 || subjBeziers.Count > 0 || 
        subjPolygons.Count > 0 || clipPolygons.Count > 0;
      Paths p = GetActivePaths();
      int i = p.Count;
      if (i == 0)
      {
        mUndo.Enabled = false;
        mNewPath.Enabled = false;
        bNewPath.Enabled = false;
        return;
      }
      int j = p[i - 1].Count;
      mUndo.Enabled = (i > 1 || j > 0);
      if (p == subjLines) bNewPath.Enabled = (j > 1);
      else if (p == subjBeziers) bNewPath.Enabled = (j > 3);
      else bNewPath.Enabled = (j > 2);
      mNewPath.Enabled = bNewPath.Enabled;
    }
    //------------------------------------------------------------------------------

    private void mClipType_Click(object sender, EventArgs e)
    {
      mIntersection.Checked = (sender == mIntersection);
      mUnion.Checked = (sender == mUnion);
      mDifference.Checked = (sender == mDifference);
      mXor.Checked = (sender == mXor);
      mNone.Checked = (sender == mNone);
      BmpUpdateNeeded();
    }
    //------------------------------------------------------------------------------

    private void mFillType_Clicked(object sender, EventArgs e)
    {
      mEvenOdd.Checked = (sender == mEvenOdd);
      mNonZero.Checked = (sender == mNonZero);
      BmpUpdateNeeded();
    }
    //------------------------------------------------------------------------------

    private void mUndo_Click(object sender, EventArgs e)
    {
      Paths p = GetActivePaths();
      int i = p.Count - 1;
      if (i < 0) return;
      int j = p[i].Count - 1;
      if (j >= 0) p[i].RemoveAt(j);
      else p.RemoveAt(i);
      UpdateBtnAndMenuState();
      BmpUpdateNeeded();
    }
    //------------------------------------------------------------------------------

    private void mClear_Click(object sender, EventArgs e)
    {
      subjLines.Clear();
      subjBeziers.Clear();
      subjPolygons.Clear();
      clipPolygons.Clear();
      UpdateBtnAndMenuState();
      BmpUpdateNeeded();
    }
    //------------------------------------------------------------------------------

    private void mNewPath_Click(object sender, EventArgs e)
    {
      Paths p = GetActivePaths();
      int i = p.Count;
      if (i == 0) return;

      i = p[i-1].Count;
      if (p == subjLines)
      {
        if (i > 1) p.Add(new Path());
      }
      else if (p == subjBeziers)
      {
        if (i > 3)
        {
          int j = (i - 1) % 3; //nb: cubic bezier
          if (i != 0) p[i-1].RemoveRange(i-j-1, j);
          p.Add(new Path());
        }
      }
      else if (p == subjPolygons)
      {
        if (i > 2) p.Add(new Path());
      }
      else if (p == clipPolygons)
      {
        if (i > 2) p.Add(new Path());
      }
      UpdateBtnAndMenuState();
      BmpUpdateNeeded();
    }
    //------------------------------------------------------------------------------

    private void rbAdd_Click(object sender, EventArgs e)
    {
      UpdateBtnAndMenuState();
      BmpUpdateNeeded();
    }
    //------------------------------------------------------------------------------

    private void OnLoadResize(bool isLoading)
    {
      if (bmp != null) bmp.Dispose();
      if (bmpGraphics != null) bmpGraphics.Dispose();
      Rectangle r = DisplayPanel.ClientRectangle;
      bmp = new Bitmap(r.Right, r.Height);
      bmpGraphics = Graphics.FromImage(bmp);
      bmpGraphics.SmoothingMode = SmoothingMode.AntiAlias;
      bmpGraphics.InterpolationMode = InterpolationMode.HighQualityBicubic;

      toolStripStatusLabel2.Width = statusStrip1.ClientSize.Width -
        toolStripStatusLabel1.Width - statusStrip1.ClientSize.Height;

      if (!isLoading) BmpUpdateNeeded();
    }
    //------------------------------------------------------------------------------

    private void MainForm_Resize(object sender, EventArgs e)
    {
      OnLoadResize(false);
    }
    //------------------------------------------------------------------------------

    private void MainForm_Load(object sender, EventArgs e)
    {
      OnLoadResize(true);
      cbReconstBez.Text = "Show &Reconstructed\nBeziers in Red.";
    }
    //------------------------------------------------------------------------------

    private void MainForm_FormClosed(object sender, FormClosedEventArgs e)
    {
      if (bmp != null) bmp.Dispose();
      if (bmpGraphics != null) bmpGraphics.Dispose();
    }
    //------------------------------------------------------------------------------

    private void quickTipsToolStripMenuItem_Click(object sender, EventArgs e)
    {
      MessageBox.Show(this, 
			  "Ctrl+I - for Intersection operations\n" +
        "Ctrl+U - for Union operations       \n" +
        "Ctrl+D - for Difference operations  \n" +
        "Ctrl+X - for XOR operations         \n" +
        "Ctrl+Q - clipping off  \n" + 
			  "------------------------------  \n" +
        "Ctrl+E - for EvenOdd fills          \n" +
        "Ctrl+N - for NonZero fills          \n" +
        "------------------------------  \n" +
        "Ctrl+P or RightClick - start new path \n" +
        "Ctrl+Z - Undo last Button entry \n" +
        "Ctrl+C - Clear \n" +
        "------------------------------  \n" +
        "F1 - to see these tips again   \n" +
			  "Esc - to quit                  \n",
        this.Text);
    }
    //------------------------------------------------------------------------------

    private void cbReconstBez_Click(object sender, EventArgs e)
    {
      cbShowCtrls.Enabled = cbReconstBez.Checked;
      if (subjBeziers.Count > 0 && clipPolygons.Count > 0)
        BmpUpdateNeeded();
    }
    //------------------------------------------------------------------------------

    private void cbShowCtrls_Click(object sender, EventArgs e)
    {
      BmpUpdateNeeded();
    }
    //------------------------------------------------------------------------------

  }
}
