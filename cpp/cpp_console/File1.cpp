//---------------------------------------------------------------------------

#pragma hdrstop

#include <cmath>
#include <stdlib>
#include <vector>
#include <iostream>
#include <string>
#include <stdio.h>
#include "clipper.hpp"

//---------------------------------------------------------------------------

using namespace clipper;
using namespace std;

inline long64 Round(double val)
{
  if ((val < 0)) return (long64)(val - 0.5); else return (long64)(val + 0.5);
}
//------------------------------------------------------------------------------

bool LoadFromFile(clipper::Polygons &ppg, char * filename, int scale= 1,
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

void SaveToConsole(const string name, const clipper::Polygons &pp, int scale = 1)
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

void SaveToFile(char *filename, clipper::Polygons &pp, int scale = 1)
{
  FILE *f = fopen(filename, "w");
  fprintf(f, "%d\n", pp.size());
  for (unsigned i = 0; i < pp.size(); ++i)
  {
    fprintf(f, "%d\n", pp[i].size());
    if (scale > 1)
      for (unsigned j = 0; j < pp[i].size(); ++j)
        fprintf(f, "%.4lf, %.4lf,\n",
          (double)pp[i][j].X /scale, (double)pp[i][j].Y /scale);
    else
      for (unsigned j = 0; j < pp[i].size(); ++j)
        fprintf(f, "%d, %d,\n", (int)pp[i][j].X, (int)pp[i][j].Y);
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
  if (argc == 7) scaling = argv[6][0] - '0';
  double scale = std::pow(double(10), scaling);

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
  SaveToConsole(s, subject, scale);
  s = "Clips (";
  s += (clip_pft == pftEvenOdd ? "EVENODD)" : "NONZERO)");
  SaveToConsole(s, clip);
  if (succeeded) {
    s = "Solution (using " + sClipType[clipType] + ")";
    SaveToConsole(s, solution, scale);
    SaveToFile("solution.txt", solution, scale);
  } else
      cout << sClipType[clipType] +" failed!\n\n";

  return 0;
}
//---------------------------------------------------------------------------
