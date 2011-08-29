using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.IO;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
using ClipperLib;

namespace ClipperTest1
{
    using Polygon = List<IntPoint>;
    using Polygons = List<List<IntPoint>>;
    using ExPolygons = List<ExPolygon>;

    class Program
    {

        //a very simple class that builds an SVG file with any number of 
        //polygons of the specified formats ...
        class SVGBuilder
        {
            class PolyInfo
            {
                public Polygons polygons;
                public PolyFillType pft;
                public string brushClr;
                public double brushOpacity;
                public string penClr;
                public double penOpacity;
                public double penWidth;
                public Boolean showCoords;
                public PolyInfo(Polygons polygons, PolyFillType pft, string brushClrHtml,
                    int brushOpacity, string penClrHtml, int penOpacity, double penWidth, Boolean showCoords)
                {
                    this.polygons = polygons;
                    this.pft = pft;
                    this.brushClr = brushClrHtml;
                    if (brushOpacity < 0) brushOpacity = 0; else if (brushOpacity > 100) brushOpacity = 100;
                    this.brushOpacity = (double)brushOpacity / 100;
                    this.penClr = penClrHtml;
                    if (penOpacity < 0) penOpacity = 0; else if (penOpacity > 100) penOpacity = 100;
                    this.penOpacity = (double)penOpacity / 100;
                    if (penWidth < 0) penWidth = 0; else if (penWidth > 100) penWidth = 100;
                    this.penWidth = penWidth;
                    this.showCoords = showCoords;
                }
            }

            private List<PolyInfo> PolyInfoList;
            const string svg_header = "<?xml version=\"1.0\" standalone=\"no\"?>\n" +
              "<!DOCTYPE svg PUBLIC \"-//W3C//DTD SVG 1.0//EN\"\n" +
              "\"http://www.w3.org/TR/2001/REC-SVG-20010904/DTD/svg10.dtd\">\n\n" +
              "<svg width=\"{0}px\" height=\"{1}px\" viewBox=\"0 0 {2} {3}\" " +
              "version=\"1.1\" xmlns=\"http://www.w3.org/2000/svg\">\n\n";
            const string svg_path_format = "\"\n style=\"fill:{0};" +
                " fill-opacity:{1:f2}; fill-rule:{2}; stroke:{3};" +
                " stroke-opacity:{4:f2}; stroke-width:{5:f2};\"/>\n\n";

            public SVGBuilder()
            {
                PolyInfoList = new List<PolyInfo>();
            }

            public void AddPolygons(Polygons poly, PolyFillType pft, string brushClrHtml,
                int brushOpacityPercent, string penClrHtml, int penOpacityPercent, double penWidth, Boolean showCoords)
            {
                for (int i = poly.Count -1; i >= 0; i--)
                    if (poly[i].Count == 0) poly.Remove(poly[i]);
                if (poly.Count == 0) return;
                PolyInfoList.Add(new PolyInfo(poly, pft, brushClrHtml,
                    brushOpacityPercent, penClrHtml, penOpacityPercent, penWidth, showCoords));
            }

            public Boolean SaveToFile(string filename, double scale = 1.0, int margin = 10)
            {
                if (PolyInfoList.Count == 0) return false;
                if (scale == 0) scale = 1.0;
                if (margin < 0) margin = 0;
                //calculate the bounding rect ...
                IntRect rec = new IntRect();
                rec.left = PolyInfoList[0].polygons[0][0].X;
                rec.right = rec.left;
                rec.top = PolyInfoList[0].polygons[0][0].Y;
                rec.bottom = rec.top;
                foreach (PolyInfo pi in PolyInfoList)
                {
                    foreach (Polygon pg in pi.polygons)
                        foreach (IntPoint pt in pg)
                        {
                            if (pt.X < rec.left) rec.left = pt.X;
                            else if (pt.X > rec.right) rec.right = pt.X;
                            if (pt.Y < rec.top) rec.top = pt.Y;
                            else if (pt.Y > rec.bottom) rec.bottom = pt.Y;
                        }
                }

                rec.left = (Int64)((double)rec.left * scale);
                rec.top = (Int64)((double)rec.top * scale);
                rec.right = (Int64)((double)rec.right * scale);
                rec.bottom = (Int64)((double)rec.bottom * scale);
                Int64 offsetX = -rec.left + margin;
                Int64 offsetY = -rec.top + margin;

                StreamWriter writer = new StreamWriter(filename);
                if (writer == null) return false;
                writer.Write(svg_header,
                    (rec.right - rec.left) + margin * 2,
                    (rec.bottom - rec.top) + margin * 2,
                    (rec.right - rec.left) + margin * 2,
                    (rec.bottom - rec.top) + margin * 2);

                foreach (PolyInfo pi in PolyInfoList)
                {
                    writer.Write(" <path d=\"");
                    foreach (Polygon p in pi.polygons)
                    {
                        if (p.Count < 3) continue;
                        writer.Write(String.Format(NumberFormatInfo.InvariantInfo, " M {0:f2} {1:f2}",
                            (double)((double)p[0].X * scale + offsetX),
                            (double)((double)p[0].Y * scale + offsetY)));
                        for (int j = 1; j < p.Count; j++)
                        {
                            writer.Write(String.Format(NumberFormatInfo.InvariantInfo, " L {0:f2} {1:f2}",
                            (double)((double)p[j].X * scale + offsetX),
                            (double)((double)p[j].Y * scale + offsetY)));
                        }
                        writer.Write(" z");
                    }

                    writer.Write(String.Format(NumberFormatInfo.InvariantInfo, svg_path_format,
                    pi.brushClr,
                    pi.brushOpacity,
                    (pi.pft == PolyFillType.pftEvenOdd ? "evenodd" : "nonzero"),
                    pi.penClr,
                    pi.penOpacity,
                    pi.penWidth));

                    if (pi.showCoords)
                    {
                        writer.Write("<g font-family=\"Verdana\" font-size=\"11\" fill=\"black\">\n\n");
                        foreach (Polygon p in pi.polygons)
                        {
                            foreach (IntPoint pt in p)
                            {
                                Int64 x = pt.X;
                                Int64 y = pt.Y;
                                writer.Write(String.Format(
                                    "<text x=\"{0}\" y=\"{1}\">{2},{3}</text>\n",
                                    (int)(x * scale + offsetX), (int)(y * scale + offsetY), x, y));

                            }
                            writer.Write("\n");
                        }
                        writer.Write("</g>\n");
                    }
                }
                writer.Write("</svg>\n");
                writer.Close();
                return true;
            }
        }

        ////////////////////////////////////////////////

        static bool LoadFromFile(string filename, Polygons ppg, int dec_places, int xOffset = 0, int yOffset = 0)
        {
            double scaling;
            scaling = Math.Pow(10, dec_places);

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
                if (scaling > 0.999 & scaling < 1.001)
                    for (int j = 0; j < vertCnt; j++)
                    {
                        Int64 x, y;
                        if ((line = sr.ReadLine()) == null) return false;
                        char[] delimiters = new char[] { ',', ' ' };
                        string[] vals = line.Split(delimiters);
                        if (vals.Length < 2) return false;
                        if (!Int64.TryParse(vals[0], out x)) return false;
                        if (!Int64.TryParse(vals[1], out y))
                            if (vals.Length < 2 || !Int64.TryParse(vals[2], out y)) return false;
                        x = x + xOffset;
                        y = y + yOffset;
                        pg.Add(new IntPoint(x, y));
                    }
                else
                    for (int j = 0; j < vertCnt; j++)
                    {
                        double x, y;
                        if ((line = sr.ReadLine()) == null) return false;
                        char[] delimiters = new char[] { ',', ' ' };
                        string[] vals = line.Split(delimiters);
                        if (vals.Length < 2) return false;
                        if (!double.TryParse(vals[0], out x)) return false;
                        if (!double.TryParse(vals[1], out y))
                            if (vals.Length < 2 || !double.TryParse(vals[2], out y)) return false;
                        x = x * scaling + xOffset;
                        y = y * scaling + yOffset;
                        pg.Add(new IntPoint((Int64)Math.Round(x), (Int64)Math.Round(y)));
                    }
            }
            return true;
        }

        ////////////////////////////////////////////////
        static void SaveToFile(string filename, Polygons ppg, int dec_places)
        {
            double scaling = Math.Pow(10, dec_places);
            StreamWriter writer = new StreamWriter(filename);
            if (writer == null) return;
            writer.Write("{0}\r\n", ppg.Count);
            foreach (Polygon pg in ppg)
            {
                writer.Write("{0}\r\n", pg.Count);
                foreach (IntPoint ip in pg)
                    writer.Write("{0:0.####}, {1:0.####}\r\n", (double)ip.X / scaling, (double)ip.Y / scaling);
            }
            writer.Close();
        }

        ////////////////////////////////////////////////

        static void OutputFileFormat()
        {
            Console.WriteLine("The expected (text) file format is ...");
            Console.WriteLine("Polygon Count");
            Console.WriteLine("First polygon vertex count");
            Console.WriteLine("first X, Y coordinate of first polygon");
            Console.WriteLine("second X, Y coordinate of first polygon");
            Console.WriteLine("etc.");
            Console.WriteLine("Second polygon vertex count (if there is one)");
            Console.WriteLine("first X, Y coordinate of second polygon");
            Console.WriteLine("second X, Y coordinate of second polygon");
            Console.WriteLine("etc.");
        }

        ////////////////////////////////////////////////

        static Polygons ExPolygons2Polygons(ExPolygons epgs)
        {
            Polygons result = new Polygons();
            foreach (ExPolygon epg in epgs)
            {
                result.Add(epg.outer);
                foreach (Polygon hole in epg.holes)
                    result.Add(hole);
            }
            return result;
        }

        ////////////////////////////////////////////////

        static void Main(string[] args)
        {
            if (args.Length < 5)
            {
                string appname = System.Environment.GetCommandLineArgs()[0];
                appname = Path.GetFileName(appname);
                Console.WriteLine("");
                Console.WriteLine("Usage:");
                Console.WriteLine("  {0} CLIPTYPE s_file c_file INPUT_DEC_PLACES SVG_SCALE [S_FILL, C_FILL]", appname);
                Console.WriteLine("  where ...");
                Console.WriteLine("  CLIPTYPE = INTERSECTION|UNION|DIFFERENCE|XOR");
                Console.WriteLine("  FILLMODE = NONZERO|EVENODD");
                Console.WriteLine("  INPUT_DEC_PLACES = signific. decimal places for subject & clip coords.");
                Console.WriteLine("  SVG_SCALE = scale of SVG image as power of 10. (Fractions are accepted.)");
                Console.WriteLine("  both S_FILL and C_FILL are optional. The default is EVENODD.");
                Console.WriteLine("Example:");
                Console.WriteLine("  Intersect polygons, rnd to 4 dec places, SVG is 1/100 normal size ...");
                Console.WriteLine("  {0} INTERSECTION subjs.txt clips.txt 4 -2 NONZERO NONZERO", appname);
                return;
            }

            ClipType ct = ClipType.ctIntersection;
            if (String.Compare(args[0], "INTERSECTION", true) == 0) ct = ClipType.ctIntersection;
            else if (String.Compare(args[0], "UNION", true) == 0) ct = ClipType.ctUnion;
            else if (String.Compare(args[0], "DIFFERENCE", true) == 0) ct = ClipType.ctDifference;
            else if (String.Compare(args[0], "XOR", true) == 0) ct = ClipType.ctXor;
            else
            {
                Console.WriteLine("Error: invalid operation - {0}", args[0]);
                return;
            }

            string subjFilename = args[1];
            string clipFilename = args[2];
            if (!File.Exists(subjFilename))
            {
                Console.WriteLine("Error: file - {0} - does not exist.", subjFilename);
                return;
            }
            if (!File.Exists(clipFilename))
            {
                Console.WriteLine("Error: file - {0} - does not exist.", clipFilename);
                return;
            }

            int decimal_places = 0;
            if (!Int32.TryParse(args[3], out decimal_places))
            {
                Console.WriteLine("Error: invalid number of decimal places - {0}", args[3]);
                return;
            }
            if (decimal_places > 8) decimal_places = 8;
            else if (decimal_places < 0) decimal_places = 0;

            double svg_scale = 0;
            if (!double.TryParse(args[4], out svg_scale))
            {
                Console.WriteLine("Error: invalid value for SVG_SCALE - {0}", args[4]);
                return;
            }
            if (svg_scale < -18) svg_scale = -18;
            else if (svg_scale > 18) svg_scale = 18;
            svg_scale = Math.Pow(10, svg_scale - decimal_places);//nb: also compensate for decimal places


            PolyFillType pftSubj = PolyFillType.pftEvenOdd;
            PolyFillType pftClip = PolyFillType.pftEvenOdd;
            if (args.Length > 6)
            {
                if (String.Compare(args[5], "EVENODD", true) == 0) pftSubj = PolyFillType.pftEvenOdd;
                else if (String.Compare(args[5], "NONZERO", true) == 0) pftSubj = PolyFillType.pftNonZero;
                else
                {
                    Console.WriteLine("Error: invalid cliptype - {0}", args[5]);
                    return;
                }
                if (String.Compare(args[6], "EVENODD", true) == 0) pftClip = PolyFillType.pftEvenOdd;
                else if (String.Compare(args[6], "NONZERO", true) == 0) pftClip = PolyFillType.pftNonZero;
                else
                {
                    Console.WriteLine("Error: invalid cliptype - {0}", args[6]);
                    return;
                }
            }

            Polygons subjs = new Polygons();
            Polygons clips = new Polygons();
            if (!LoadFromFile(subjFilename, subjs, decimal_places))
            {
                Console.WriteLine("Error processing subject polygons file - {0} ", subjFilename);
                OutputFileFormat();
                return;
            }
            if (!LoadFromFile(clipFilename, clips, decimal_places))
            {
                Console.WriteLine("Error processing clip polygons file - {0} ", clipFilename);
                OutputFileFormat();
                return;
            }


            Console.WriteLine("wait ...");
            Clipper cp = new Clipper();
            cp.AddPolygons(subjs, PolyType.ptSubject);
            cp.AddPolygons(clips, PolyType.ptClip);

            Polygons solution = new Polygons();
            if (cp.Execute(ct, solution, pftSubj, pftClip))
            {
                SaveToFile("solution.txt", solution, decimal_places);

                SVGBuilder svg = new SVGBuilder();
                svg.AddPolygons(subjs, pftSubj, "#00009C", 6, "#D3D3DA", 95, 0.8, false);
                svg.AddPolygons(clips, pftClip, "#9C0000", 6, "#FFA07A", 95, 0.8, false);
                svg.AddPolygons(solution, PolyFillType.pftNonZero, "#80ff9C", 37, "#003300", 100, 0.8, false);
                svg.SaveToFile("solution.svg", svg_scale);
                Console.WriteLine("finished!");
            }
            else
            {
                Console.WriteLine("failed!");
            }
        }

    } //class Program
}
