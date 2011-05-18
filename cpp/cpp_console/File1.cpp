//---------------------------------------------------------------------------

#pragma hdrstop

#include <cmath>
#include <stdlib>
#include <vector>
#include <iostream>
#include <fstream>
#include <string>
#include <stdio.h>
#include "clipper.hpp"

//---------------------------------------------------------------------------

using namespace clipper;
using namespace std;

void PolygonsToSVG(char * filename,
  Polygons *subj, Polygons *clip, Polygons *solution,
  PolyFillType subjFill = pftNonZero, PolyFillType clipFill = pftNonZero,
  double scale = 1, int margin = 10)
{
  Polygons* polys [] = {subj, clip, solution};
  //calculate the bounding rect ...
  IntRect rec;
  bool firstPending = true;
  int k = 0;
  while (k < 3)
  {
    if (polys[k])
      for (Polygons::size_type i = 0; i < (*polys[k]).size(); ++i)
        if ((*polys[k])[i].size() > 2)
        {
          //initialize rec with the very first polygon coordinate ...
          rec.left = (*polys[k])[i][0].X;
          rec.right = rec.left;
          rec.top = (*polys[k])[i][0].Y;
          rec.bottom = rec.top;
          firstPending = false;
        }
    if (firstPending) k++; else break;
  }
  if (firstPending) return; //no valid polygons found

  for ( ; k < 3; ++k)
    if (polys[k])
      for (Polygons::size_type i = 0; i < (*polys[k]).size(); ++i)
        for (clipper::Polygon::size_type j = 0; j < (*polys[k])[i].size(); ++j)
        {
          if ((*polys[k])[i][j].X < rec.left)
            rec.left = (*polys[k])[i][j].X;
          if ((*polys[k])[i][j].X > rec.right)
            rec.right = (*polys[k])[i][j].X;
          if ((*polys[k])[i][j].Y < rec.top)
            rec.top = (*polys[k])[i][j].Y;
          if ((*polys[k])[i][j].Y > rec.bottom)
            rec.bottom = (*polys[k])[i][j].Y;
        }

  if (scale == 0) scale = 1;
  rec.left *= scale;
  rec.top *= scale;
  rec.right *= scale;
  rec.bottom *= scale;

  long64 offsetX = -rec.left + margin;
  long64 offsetY = -rec.top + margin;

  const std::string svg_xml_start [] =
    {"<?xml version=\"1.0\" standalone=\"no\"?>\n"
     "<!DOCTYPE svg PUBLIC \"-//W3C//DTD SVG 1.1//EN\"\n"
     "\"http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd\">\n\n"
     "<svg width=\"",
     "\" height=\"",
     "\" viewBox=\"0 0 ",
     "\" version=\"1.1\" xmlns=\"http://www.w3.org/2000/svg\">\n\n"};
  const std::string poly_start =
    " <path d=\"\n";
  const std::string poly_end [] =
    {"\"\n style=\"fill:",
     "; fill-opacity:",
     "; fill-rule:",
     ";\n stroke:",
     "; stroke-opacity:",
     "; stroke-width:",
     ";\"/>\n\n"};
  const std::string svg_xml_end = "</svg>\n";

  ofstream file;
  file.open(filename);
  if (!file.is_open()) return;
  file.setf(ios::fixed);
  file.precision(0);
  file << svg_xml_start[0] <<
    (rec.right - rec.left) + margin*2 << "px" << svg_xml_start[1] <<
    (rec.bottom - rec.top) + margin*2 << "px" << svg_xml_start[2] <<
    (rec.right - rec.left) + margin*2 << " " <<
    (rec.bottom - rec.top) + margin*2 << svg_xml_start[3];

  setlocale(LC_NUMERIC, "C");
  file.precision(2);
  for (int k = 0; k < 3; k++)
  {
    if (!polys[k]) continue;
    file << poly_start;
    for (clipper::Polygons::size_type i = 0; i < (*polys[k]).size(); i++)
    {
      if ((*polys[k])[i].size() < 3) continue;
      file << " M " << (double)(*polys[k])[i][0].X * scale + offsetX << " "
        << (double)(*polys[k])[i][0].Y * scale + offsetY;
      for (clipper::Polygon::size_type j = 1; j < (*polys[k])[i].size(); j++)
      {
        double x = (double)(*polys[k])[i][j].X * scale;
        double y = (double)(*polys[k])[i][j].Y * scale;
        file << " L " << x + offsetX << " " << y + offsetY;
      }
      file << " z";
    }

    switch (k) {
      case 0:
        file << poly_end[0] << "#0000ff" /*fill color*/ <<
          poly_end[1] << 0.062 /*fill opacity*/ <<
          poly_end[2] << (subjFill == pftEvenOdd ? "evenodd" : "nonzero") <<
          poly_end[3] << "#0099ff" /*stroke color*/ <<
          poly_end[4] << 0.5 /*stroke opacity*/ <<
          poly_end[5] << 0.8 /*stroke width*/ << poly_end[6];
        break;
      case 1:
        file << poly_end[0] << "#ffff00" /*fill color*/ <<
          poly_end[1] << 0.062 /*fill opacity*/ <<
          poly_end[2] << (clipFill == pftEvenOdd ? "evenodd" : "nonzero") <<
          poly_end[3] << "#ff9900" /*stroke color*/ <<
          poly_end[4] << 0.5 /*stroke opacity*/ <<
          poly_end[5] << 0.8 /*stroke width*/ << poly_end[6];
        break;
      default:
        file << poly_end[0] << "#00ff00" /*fill color*/ <<
          poly_end[1] << 0.25 /*fill opacity*/ <<
          poly_end[2] << "nonzero" <<
          poly_end[3] << "#003300" /*stroke color*/ <<
          poly_end[4] << 1.0 /*stroke opacity*/ <<
          poly_end[5] << 0.8 /*stroke width*/ << poly_end[6];
    }
  }
  file << svg_xml_end;
  file.close();
  setlocale(LC_NUMERIC, "");
}
//------------------------------------------------------------------------------

inline long64 Round(double val)
{
  if ((val < 0)) return (long64)(val - 0.5); else return (long64)(val + 0.5);
}
//------------------------------------------------------------------------------

bool LoadFromFile(clipper::Polygons &ppg, char * filename, float scale= 1,
  int xOffset = 0, int yOffset = 0)
{
  ppg.clear();

  FILE *f = fopen(filename, "r");
  if (!f) return false;
  int polyCnt, vertCnt;
  char junk [80];
  double X, Y;
  if (fscanf(f, "%d", &polyCnt) == 1 && polyCnt > 0)
  {
    ppg.resize(polyCnt);
    for (int i = 0; i < polyCnt; i++) {
      if (fscanf(f, "%d", &vertCnt) != 1 || vertCnt <= 0) break;
      ppg[i].resize(vertCnt);
      for (int j = 0; j < vertCnt; j++) {
        if (fscanf(f, "%lf%*[, ]%lf", &X, &Y) != 2) break;
        ppg[i][j].X = Round((X + xOffset) * scale);
        ppg[i][j].Y = Round((Y + yOffset) * scale);
        fgets(junk, 80, f);
      }
    }
  }
  fclose(f);
  return true;
}
//------------------------------------------------------------------------------

void SaveToConsole(const string name, const clipper::Polygons &pp, float scale = 1)
{
  cout << '\n' << name << ":\n"
    << pp.size() << '\n';
  for (unsigned i = 0; i < pp.size(); ++i)
  {
    cout << pp[i].size() << '\n';
    for (unsigned j = 0; j < pp[i].size(); ++j)
      cout << pp[i][j].X /scale << ", " << pp[i][j].Y /scale << ",\n";
  }
  cout << "\n";
}
//---------------------------------------------------------------------------

void SaveToFile(char *filename, clipper::Polygons &pp, float scale = 1)
{
  FILE *f = fopen(filename, "w");
  fprintf(f, "%d\n", pp.size());
  for (unsigned i = 0; i < pp.size(); ++i)
  {
    fprintf(f, "%d\n", pp[i].size());
    for (unsigned j = 0; j < pp[i].size(); ++j)
      fprintf(f, "%.4lf, %.4lf,\n",
        (double)pp[i][j].X /scale, (double)pp[i][j].Y /scale);
  }
  fclose(f);
}
//---------------------------------------------------------------------------

#pragma argsused
int _tmain(int argc, _TCHAR* argv[])
{

  if (argc < 3)
  {
    cout << "\nUSAGE:\n"
      << "clipper.exe subject_file clip_file "
      << "[INTERSECTION | UNION | DIFFERENCE | XOR] "
      << "[EVENODD | NONZERO] [EVENODD | NONZERO] "
      << "[precision, in decimal places (def = 0)]\n";
    cout << "\nINPUT AND OUTPUT FILE FORMAT ([optional] {comments}):\n"
      << "Polygon Count\n"
      << "Vertex Count {first polygon}\n"
      << "X, Y[,] {first vertex}\n"
      << "X, Y[,] {next vertex}\n"
      << "{etc.}\n"
      << "Vertex Count {second polygon, if there is one}\n"
      << "X, Y[,] {first vertex of second polygon}\n"
      << "{etc.}\n\n";
    return 1;
  }

  int scaling = 0;
  char * dummy;
  if (argc > 6) scaling = strtol(argv[6], &dummy, 10);
  float scale = std::pow(double(10), scaling);

  Polygons subject, clip;
  if (!LoadFromFile(subject, argv[1], scale))
  {
    cerr << "\nCan't open the file " << argv[1]
      << " or the file format is invalid.\n";
    return 1;
  }
  if (!LoadFromFile(clip, argv[2], scale))
  {
    cerr << "\nCan't open the file " << argv[2]
      << " or the file format is invalid.\n";
    return 1;
  }

  ClipType clipType = ctIntersection;
  const string sClipType[] = {"INTERSECTION", "UNION", "DIFFERENCE", "XOR"};

  if (argc > 3)
  {
    if (stricmp(argv[3], "XOR") == 0) clipType = ctXor;
    else if (stricmp(argv[3], "UNION") == 0) clipType = ctUnion;
    else if (stricmp(argv[3], "DIFFERENCE") == 0) clipType = ctDifference;
    else clipType = ctIntersection;
  }

  PolyFillType subj_pft = pftNonZero, clip_pft = pftNonZero;
  if (argc > 5)
  {
    if (stricmp(argv[4], "EVENODD") == 0) subj_pft = pftEvenOdd;
    if (stricmp(argv[5], "EVENODD") == 0) clip_pft = pftEvenOdd;
  }

  Clipper c;
  c.AddPolygons(subject, ptSubject);
  c.AddPolygons(clip, ptClip);
  Polygons solution;

  bool succeeded = c.Execute(clipType, solution, subj_pft, clip_pft);
  string s = "Subjects (";
  s += (subj_pft == pftEvenOdd ? "EVENODD)" : "NONZERO)");

  //ie don't change the polygons back to the original size if we've
  //just down-sized them to a manageable (all-in-one-screen) size ...
  if (scale < 1) scale = 1;

  SaveToConsole(s, subject, scale);
  s = "Clips (";
  s += (clip_pft == pftEvenOdd ? "EVENODD)" : "NONZERO)");
  SaveToConsole(s, clip, scale);
  if (succeeded) {
    s = "Solution (using " + sClipType[clipType] + ")";
    SaveToConsole(s, solution, scale);
    SaveToFile("solution.txt", solution, scale);
    //let's see the result too ...
    PolygonsToSVG("solution.svg", &subject, &clip, &solution,
      subj_pft, clip_pft, scale);
  } else
      cout << sClipType[clipType] +" failed!\n\n";

  return 0;
}
//---------------------------------------------------------------------------
