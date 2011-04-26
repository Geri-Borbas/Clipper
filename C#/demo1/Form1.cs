using System;
using System.Text;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Reflection;
using System.Linq;
using System.Windows.Forms;
using clipper;


namespace WindowsFormsApplication1
{

    using Polygon = List<IntPoint>;
    using Polygons = List<List<IntPoint>>;

    public partial class Form1 : Form
    {

        Assembly _assembly;
        Stream polyStream;

        private Bitmap mybitmap;
        private Polygons subjects;
        private Polygons clips;
        private Polygons solution;

        //Here we are scaling all coordinates up by 100 when they're passed to Clipper 
        //via Polygon (or Polygons) objects because Clipper no longer accepts floating  
        //point values. Likewise when Clipper returns a solution in a Polygons object, 
        //we need to scale down these returned values by the same amount before displaying.
        private int scale = 100; //or 1 or 10 or 10000 etc for lesser or greater precision.

        //---------------------------------------------------------------------
        //---------------------------------------------------------------------

        void PolygonsToSVG(string filename,
          Polygons subj, Polygons clip, Polygons solution,
          PolyFillType subjFill = PolyFillType.pftNonZero, 
          PolyFillType clipFill = PolyFillType.pftNonZero,
          double scale = 1, int margin = 10)
        {
          Polygons [] polys = {subj, clip, solution};
          //calculate the bounding rect ...
          IntRect rec = new IntRect();
          bool firstPending = true;
          int k = 0;
          while (k < 3)
          {
            if (polys[k] != null)
              for (int i = 0; i < polys[k].Count; ++i)
                if (polys[k][i].Count > 2)
                {
                  //initialize rec with the very first polygon coordinate ...
                  rec.left = polys[k][i][0].X;
                  rec.right = rec.left;
                  rec.top = polys[k][i][0].Y;
                  rec.bottom = rec.top;
                  firstPending = false;
                }
            if (firstPending) k++; else break;
          }
          if (firstPending) return; //no valid polygons found

          for (; k < 3; ++k)
            if (polys[k] != null)
              for (int i = 0; i < polys[k].Count; ++i)
                for (int j = 0; j < polys[k][i].Count; ++j)
                {
                  if (polys[k][i][j].X < rec.left)
                    rec.left = polys[k][i][j].X;
                  if (polys[k][i][j].X > rec.right)
                    rec.right = polys[k][i][j].X;
                  if (polys[k][i][j].Y < rec.top)
                    rec.top = polys[k][i][j].Y;
                  if (polys[k][i][j].Y > rec.bottom)
                    rec.bottom = polys[k][i][j].Y;
                }

          if (scale == 0) scale = 1;
          rec.left = (Int64)((double)rec.left * scale);
          rec.top = (Int64)((double)rec.top * scale);
          rec.right = (Int64)((double)rec.right * scale);
          rec.bottom = (Int64)((double)rec.bottom * scale);

          Int64 offsetX = -rec.left + margin;
          Int64 offsetY = -rec.top + margin;

          string svg_header = "<?xml version=\"1.0\" standalone=\"no\"?>\n"+
            "<!DOCTYPE svg PUBLIC \"-//W3C//DTD SVG 1.1//EN\"\n"+
            "\"http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd\">\n\n"+
            "<svg width=\"{0}px\" height=\"{1}px\" viewBox=\"0 0 {2} {3}\" "+     
            "version=\"1.1\" xmlns=\"http://www.w3.org/2000/svg\">\n\n";

          StreamWriter writer = new StreamWriter(filename);
          if (writer == null) return;
          writer.Write(svg_header, 
              (rec.right - rec.left) + margin*2,
              (rec.bottom - rec.top) + margin*2,
              (rec.right - rec.left) + margin*2,
              (rec.bottom - rec.top) + margin*2);

          for (k = 0; k < 3; k++)
          {
            if (polys[k] == null) continue;
            writer.Write(" <path d=\""); 
            for (int i = 0; i < polys[k].Count; i++)
            {
              if (polys[k][i].Count < 3) continue;
              writer.Write(" M {0:f2} {1:f2}",
                  (double)((double)polys[k][i][0].X * scale + offsetX),
                  (double)((double)polys[k][i][0].Y * scale + offsetY));
              for (int j = 1; j < polys[k][i].Count; j++)
              {
                  writer.Write(" L {0:f2} {1:f2}",
                  (double)((double)polys[k][i][j].X * scale + offsetX),
                  (double)((double)polys[k][i][j].Y * scale + offsetY));
              }
              writer.Write(" z");
            }

            const string svg_path_format = "\"\n style=\"fill:{0};"+
                " fill-opacity:{1:f2}; fill-rule:{2}; stroke:{3};"+
                " stroke-opacity:{4:f2}; stroke-width:{5:f2};\"/>\n\n";

            switch (k) {
              case 0:
                writer.Write(svg_path_format,
                    "#00009C"   /*fill color*/,
                    0.062       /*fill opacity*/,
                    (subjFill == PolyFillType.pftEvenOdd ? "evenodd" : "nonzero"),
                    "#D3D3DA"   /*stroke color*/,
                    0.95         /*stroke opacity*/,
                    0.8         /*stroke width*/);
                break;
              case 1:
                writer.Write(svg_path_format,
                    "#9C0000"   /*fill color*/,
                    0.062       /*fill opacity*/,
                    (clipFill == PolyFillType.pftEvenOdd ? "evenodd" : "nonzero"),
                    "#FFA07A"   /*stroke color*/,
                    0.95         /*stroke opacity*/,
                    0.8         /*stroke width*/);
                break;
              default:
                writer.Write(svg_path_format,
                    "#80ff9C"   /*fill color*/,
                    0.37       /*fill opacity*/,
                    "nonzero",
                    "#003300"   /*stroke color*/,
                    1.0         /*stroke opacity*/,
                    0.8         /*stroke width*/);
                break;
            }
          }
          writer.Write("</svg>\n");
          writer.Close();
        }
        //------------------------------------------------------------------------------
        //------------------------------------------------------------------------------

        static private System.Drawing.PointF[] PolygonToPointFArray(Polygon pg, int scale)
        {
            System.Drawing.PointF[] result = new System.Drawing.PointF[pg.Count];
            for (int i = 0; i < pg.Count; ++i)
            {
                result[i].X = (float)pg[i].X / scale;
                result[i].Y = (float)pg[i].Y / scale;
            }
            return result;
        }
        //---------------------------------------------------------------------

        public Form1()
        {
            InitializeComponent();
            this.MouseWheel += new MouseEventHandler(Form1_MouseWheel);
        }
        //---------------------------------------------------------------------

        private void Form1_MouseWheel(object sender, MouseEventArgs e)
        {
            if (e.Delta > 0 && nudOffset.Value < 10) nudOffset.Value += (decimal)0.5;
            else if (e.Delta < 0 && nudOffset.Value > -10) nudOffset.Value -= (decimal)0.5;
        }
        //---------------------------------------------------------------------

        private void bRefresh_Click(object sender, EventArgs e)
        {
            DrawBitmap();
        }
        //---------------------------------------------------------------------

        private void GenerateAustPlusRandomEllipses(int count)
        {
            subjects.Clear();
            //load map of Australia from resource ...
            _assembly = Assembly.GetExecutingAssembly();
            polyStream = _assembly.GetManifestResourceStream("ClipperCSharpDemo1.australia.bin");
            int len = (int)polyStream.Length;
            byte[] b = new byte[len];
            polyStream.Read(b, 0, len);
            int polyCnt = BitConverter.ToInt32(b, 0);
            int k = 4;
            for (int i = 0; i < polyCnt; ++i)
            {
                int vertCnt = BitConverter.ToInt32(b, k);
                k += 4;
                Polygon pg = new Polygon(vertCnt);
                for (int j = 0; j < vertCnt; ++j)
                {
                    float x = BitConverter.ToSingle(b, k) * scale;
                    float y = BitConverter.ToSingle(b, k + 4) * scale;
                    k += 8;
                    pg.Add(new IntPoint((int)x, (int)y));
                }
                subjects.Add(pg);
            }

            clips.Clear();
            Random rand = new Random();
            GraphicsPath path = new GraphicsPath();
            Point pt = new Point();

            const int ellipse_size = 100, margin = 10;
            for (int i = 0; i < count; ++i)
            {
                int w = pictureBox1.ClientRectangle.Width - ellipse_size - margin *2;
                int h = pictureBox1.ClientRectangle.Height - ellipse_size - margin * 2 - statusStrip1.Height;

                pt.X = rand.Next(w) + margin;
                pt.Y = rand.Next(h) + margin;
                int size = rand.Next(ellipse_size - 20) + 20;
                path.Reset();
                path.AddEllipse(pt.X, pt.Y, size, size);
                path.Flatten();
                Polygon clip = new Polygon(path.PathPoints.Count());
                foreach (PointF p in path.PathPoints)
                    clip.Add(new IntPoint((int)(p.X * scale), (int)(p.Y * scale)));
                clips.Add(clip);
            }
        }
        //---------------------------------------------------------------------

        private IntPoint GenerateRandomPoint(int l, int t, int r, int b, Random rand)
        {
            IntPoint newPt = new IntPoint();
            newPt.X = (rand.Next(r / 20) * 20 + l + 10) * scale;
            newPt.Y = (rand.Next(b / 20) * 20 + t + 10) * scale;
            return newPt;
        }
        //---------------------------------------------------------------------

        private void GenerateRandomPolygon(int count)
        {
            Random rand = new Random();
            int l = 10;
            int t = 10;
            int r = (pictureBox1.ClientRectangle.Width - 20)/10 *10;
            int b = (pictureBox1.ClientRectangle.Height - 20)/10 *10;

            subjects.Clear();
            clips.Clear();

            Polygon subj = new Polygon(count);
            for (int i = 0; i < count; ++i)
                subj.Add(GenerateRandomPoint(l, t, r, b, rand));
            subjects.Add(subj);

            Polygon clip = new Polygon(count);
            for (int i = 0; i < count; ++i)
                clip.Add(GenerateRandomPoint(l, t, r, b, rand));
            clips.Add(clip);
        }
        //---------------------------------------------------------------------

        ClipType GetClipType()
        {
            if (rbIntersect.Checked) return ClipType.ctIntersection;
            if (rbUnion.Checked) return ClipType.ctUnion;
            if (rbDifference.Checked) return ClipType.ctDifference;
            else return ClipType.ctXor;
        }
        //---------------------------------------------------------------------

        PolyFillType GetPolyFillType()
        {
            if (rbNonZero.Checked) return PolyFillType.pftNonZero;
            else return PolyFillType.pftEvenOdd;
        }
        //---------------------------------------------------------------------

        bool LoadFromFile(string filename, Polygons ppg, double scale = 0,
          int xOffset = 0, int yOffset = 0)
        {
            double scaling = Math.Pow(10, scale);
            ppg.Clear();
            if (!File.Exists(filename)) return false;
            StreamReader sr = new StreamReader(filename);
            if (sr == null) return false;
            string line;
            if ((line = sr.ReadLine()) == null) return false;
            int polyCnt, vertCnt;
            if (!Int32.TryParse(line, out polyCnt) || polyCnt < 0) return false;
            ppg.Capacity = polyCnt;
            for (int i = 0; i < polyCnt; i++)
            {
                if ((line = sr.ReadLine()) == null) return false;
                if (!Int32.TryParse(line, out vertCnt) || vertCnt < 0) return false;
                Polygon pg = new Polygon(vertCnt);
                ppg.Add(pg);
                for (int j = 0; j < vertCnt; j++)
                {
                    double x, y;
                    if ((line = sr.ReadLine()) == null) return false;
                    char[] delimiters = new char[] { ',', ' ' };
                    string [] vals = line.Split(delimiters);
                    if (vals.Length < 2) return false;
                    if (!double.TryParse(vals[0], out x)) return false;
                    if (!double.TryParse(vals[1], out y))
                        if (vals.Length < 2 || !double.TryParse(vals[2], out y)) return false;
                    x = x * scaling + xOffset;
                    y = y * scaling + yOffset;
                    pg.Add(new IntPoint((int)Math.Round(x), (int)Math.Round(y)));
                }
            }
            return true;
        }
        //------------------------------------------------------------------------------

        void SaveToFile(string filename, Polygons ppg, int scale = 0)
        {
            double scaling = Math.Pow(10, scale);
            StreamWriter writer = new StreamWriter(filename);
            if (writer == null) return;
            writer.Write("{0}\n", ppg.Count);
            for (int i = 0; i < ppg.Count; i++)
            {
                writer.Write("{0}\n", ppg[i].Count);
                for (int j = 0; j < ppg.Count; j++)
                    writer.Write("{0:0.0000}, {1:0.0000}\n", 
                        (double)ppg[i][j].X/scaling, (double)ppg[i][j].Y/scaling);
            }
            writer.Close();
        }
        //---------------------------------------------------------------------------

        private void DrawBitmap(bool justClip = false)
        {

            if (!justClip)
            {
                if (rbTest2.Checked)
                    GenerateAustPlusRandomEllipses((int)nudCount.Value);
                else
                    GenerateRandomPolygon((int)nudCount.Value);
            }

            Cursor.Current = Cursors.WaitCursor;
            Graphics newgraphic;
            newgraphic = Graphics.FromImage(mybitmap);
            newgraphic.SmoothingMode = SmoothingMode.AntiAlias;
            newgraphic.Clear(Color.WhiteSmoke);
            Pen myPen = new Pen(Color.FromArgb(32, 0, 0, 0), (float)0.6);
            SolidBrush myBrush = new SolidBrush(Color.FromArgb(16, 0, 0, 156));
            
            GraphicsPath path = new GraphicsPath();
            if (rbNonZero.Checked) path.FillMode = FillMode.Winding;

            foreach (Polygon pg in subjects)
            {
                PointF[] pts = PolygonToPointFArray(pg, scale);
                path.AddPolygon(pts);
                pts = null;
            }
            newgraphic.FillPath(myBrush, path);
            newgraphic.DrawPath(myPen, path);
            path.Reset();
            if (rbNonZero.Checked) path.FillMode = FillMode.Winding;
            foreach (Polygon pg in clips)
            {
                PointF[] pts = PolygonToPointFArray(pg, scale);
                path.AddPolygon(pts);
                pts = null;
            }
            myPen.Color = Color.LightSalmon;
            myBrush.Color = Color.FromArgb(16, 156, 0, 0);
            newgraphic.FillPath(myBrush, path);
            newgraphic.DrawPath(myPen, path);

            //do the clipping ...
            if ((clips.Count > 0 || subjects.Count > 0) && !rbNone.Checked)
            {
                clipper.Clipper c = new clipper.Clipper();
                c.AddPolygons(subjects, PolyType.ptSubject);
                c.AddPolygons(clips, PolyType.ptClip);
                bool succeeded = c.Execute(GetClipType(), solution, GetPolyFillType(), GetPolyFillType());
                if (succeeded)
                {
                    PolygonsToSVG("debug.svg", subjects, clips, solution,
                        GetPolyFillType(), GetPolyFillType(), 1.0 / scale, 10);

                    myBrush.Color = Color.Black;
                    path.Reset();

                    //It really shouldn't matter what FillMode is used for solution
                    //polygons because none of the solution polygons overlap. 
                    //However, FillMode.Winding will show any orientation errors where 
                    //holes will be stroked (outlined) correctly but filled incorrectly  ...
                    path.FillMode = FillMode.Winding;

                    //or for something fancy ...
                    Polygons solution2;
                    if (nudOffset.Value != 0)
                        solution2 = clipper.Clipper.OffsetPolygons(solution, (double)nudOffset.Value * scale);
                    else
                        solution2 = new Polygons(solution);

                    foreach (Polygon pg in solution2)
                    {
                        PointF[] pts = PolygonToPointFArray(pg, scale);
                        if (pts.Count() > 2)
                            path.AddPolygon(pts);
                        pts = null;
                    }
                    myBrush.Color = Color.FromArgb(96, 128, 255, 156);
                    myPen.Color = Color.Black;
                    myPen.Width = 1.0f;
                    newgraphic.FillPath(myBrush, path);
                    newgraphic.DrawPath(myPen, path);

                    //now do some fancy testing ...
                    Font f = new Font("Arial", 8);
                    SolidBrush b = new SolidBrush(Color.Navy);
                    double a1 = 0, a2 = 0, a3 = 0, a4 = 0;
                    c.Clear();
                    c.AddPolygons(subjects, PolyType.ptSubject);
                    c.Execute(ClipType.ctUnion, solution2, GetPolyFillType(), GetPolyFillType());
                    foreach (Polygon pg in solution2) a1 += clipper.Clipper.Area(pg);
                    c.Clear();
                    c.AddPolygons(clips, PolyType.ptClip);
                    c.Execute(ClipType.ctUnion, solution2, GetPolyFillType(), GetPolyFillType());
                    foreach (Polygon pg in solution2) a2 += clipper.Clipper.Area(pg);
                    c.AddPolygons(subjects, PolyType.ptSubject);
                    c.Execute(ClipType.ctIntersection, solution2, GetPolyFillType(), GetPolyFillType());
                    foreach (Polygon pg in solution2) a3 += clipper.Clipper.Area(pg);
                    c.Execute(ClipType.ctUnion, solution2, GetPolyFillType(), GetPolyFillType());
                    foreach (Polygon pg in solution2) a4 += clipper.Clipper.Area(pg);

                    StringFormat lftStringFormat = new StringFormat();
                    lftStringFormat.Alignment = StringAlignment.Near;
                    lftStringFormat.LineAlignment = StringAlignment.Near;
                    StringFormat rtStringFormat = new StringFormat();
                    rtStringFormat.Alignment = StringAlignment.Far;
                    rtStringFormat.LineAlignment = StringAlignment.Near;
                    Rectangle rec = new Rectangle(pictureBox1.ClientSize.Width - 108, 
                        pictureBox1.ClientSize.Height - 116, 104, 106);
                    newgraphic.FillRectangle(new SolidBrush(Color.FromArgb(196, Color.WhiteSmoke)), rec);
                    newgraphic.DrawRectangle(myPen, rec);
                    rec.Inflate(new Size(-2, 0));
                    newgraphic.DrawString("Areas", f, b, rec, rtStringFormat);
                    rec.Offset(new Point(0, 14));
                    newgraphic.DrawString("subj: ", f, b, rec, lftStringFormat);
                    newgraphic.DrawString((a1 / 100000).ToString("0,0"), f, b, rec, rtStringFormat);
                    rec.Offset(new Point(0, 12));
                    newgraphic.DrawString("clip: ", f, b, rec, lftStringFormat);
                    newgraphic.DrawString((a2 / 100000).ToString("0,0"), f, b, rec, rtStringFormat);
                    rec.Offset(new Point(0, 12));
                    newgraphic.DrawString("intersect: ", f, b, rec, lftStringFormat);
                    newgraphic.DrawString((a3 / 100000).ToString("0,0"), f, b, rec, rtStringFormat);
                    rec.Offset(new Point(0, 12));
                    newgraphic.DrawString("---------", f, b, rec, rtStringFormat);
                    rec.Offset(new Point(0, 10));
                    newgraphic.DrawString("s + c - i: ", f, b, rec, lftStringFormat);
                    newgraphic.DrawString(((a1 + a2 - a3) / 100000).ToString("0,0"), f, b, rec, rtStringFormat);
                    rec.Offset(new Point(0, 10));
                    newgraphic.DrawString("---------", f, b, rec, rtStringFormat);
                    rec.Offset(new Point(0, 10));
                    newgraphic.DrawString("union: ", f, b, rec, lftStringFormat);
                    newgraphic.DrawString((a4 / 100000).ToString("0,0"), f, b, rec, rtStringFormat);
                    rec.Offset(new Point(0, 10));
                    newgraphic.DrawString("---------", f, b, rec, rtStringFormat);
                } //end if succeeded
            } //end if something to clip

            pictureBox1.Image = mybitmap;
            newgraphic.Dispose();
            Cursor.Current = Cursors.Default;
        }
        //---------------------------------------------------------------------

        private void Form1_Load(object sender, EventArgs e)
        {
            mybitmap = new Bitmap(
                pictureBox1.ClientRectangle.Width,
                pictureBox1.ClientRectangle.Height,
                PixelFormat.Format32bppArgb);

            subjects = new Polygons(); 
            clips = new Polygons();
            solution = new Polygons();

            toolStripStatusLabel1.Text =
                "Tip: Use the mouse-wheel (or +,-,0) to adjust the offset of the solution polygons.";
            DrawBitmap();
        }
        //---------------------------------------------------------------------

        private void bClose_Click(object sender, EventArgs e)
        {
            Close();
        }
        //---------------------------------------------------------------------

        private void Form1_Resize(object sender, EventArgs e)
        {
            if (pictureBox1.ClientRectangle.Width == 0 || 
                pictureBox1.ClientRectangle.Height == 0) return;
            mybitmap.Dispose();
            mybitmap = new Bitmap(
                pictureBox1.ClientRectangle.Width,
                pictureBox1.ClientRectangle.Height,
                PixelFormat.Format32bppArgb);
            pictureBox1.Image = mybitmap;
            DrawBitmap();
        }
        //---------------------------------------------------------------------

        private void rbNonZero_Click(object sender, EventArgs e)
        {
            DrawBitmap(true);
        }
        //---------------------------------------------------------------------

        private void Form1_KeyDown(object sender, KeyEventArgs e)
        {
            switch (e.KeyCode)
            {
                case (Keys)27:
                    this.Close();
                    return;
                case Keys.F1:
                    MessageBox.Show(this.Text + "\nby Angus Johnson\nCopyright © 2010, 2011",
                    this.Text, MessageBoxButtons.OK, MessageBoxIcon.Information);
                    e.Handled = true;
                    return;
                case (Keys)187:
                case Keys.Add:
                    if (nudOffset.Value == 10) return;
                    nudOffset.Value += (decimal)0.5;
                    e.Handled = true;
                    break;
                case (Keys)189:
                case Keys.Subtract:
                    if (nudOffset.Value == -10) return;
                    nudOffset.Value -= (decimal)0.5;
                    e.Handled = true;
                    break;
                case Keys.NumPad0:
                case Keys.D0:
                    if (nudOffset.Value == 0) return;
                    nudOffset.Value = (decimal)0;
                    e.Handled = true;
                    break;
                default: return;
            }
            
        }
        //---------------------------------------------------------------------

        private void nudCount_ValueChanged(object sender, EventArgs e)
        {
            DrawBitmap(true);
        }
        //---------------------------------------------------------------------

        private void rbTest1_Click(object sender, EventArgs e)
        {
            if (rbTest1.Checked)
                lblCount.Text = "Vertex &Count:";
            else
                lblCount.Text = "Ellipse &Count:";
            DrawBitmap();
        }
        //---------------------------------------------------------------------

        private void bSave_Click(object sender, EventArgs e)
        {
            //save to SVG ...
            if (saveFileDialog1.ShowDialog() == DialogResult.OK)
            {
                PolygonsToSVG(saveFileDialog1.FileName, subjects, clips, 
                    solution, GetPolyFillType(), GetPolyFillType(), 1.0 / scale);
            }
        }
        //---------------------------------------------------------------------

    }
}
