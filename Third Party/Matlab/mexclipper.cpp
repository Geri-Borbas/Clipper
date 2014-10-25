// mex clipper.cpp mexclipper.cpp
// 
// Modified 2014-10-24, Jari Repo (JR), University West, jari.repo@hv.se
// replaced "Polygons" to "Paths"
// replaced "AddPolygons" by "AddPaths"
// replaced the call to "OffsetPolygons" by use of the "ClipperOffset" class

#include "mex.h"
#include "clipper.hpp"

using namespace ClipperLib;

//void read_polygons_MATLAB(const mxArray *prhs, Polygons &poly)
void read_polygons_MATLAB(const mxArray *prhs, Paths &poly)
{
    int id_x, id_y;
    int num_contours;
    int nx, ny;
    long64 *x, *y;
    const mxArray *x_in, *y_in;
    
    /*  Checking if input is non empty Matlab-structure */
    if (!mxIsStruct(prhs))
        mexErrMsgTxt("Input needs to be structure.");
    if (!mxGetM(prhs) || !mxGetN(prhs))
        mexErrMsgTxt("Empty structure.");
    
    /*  Checking field names and data type  */
    id_x = mxGetFieldNumber(prhs,"x");
    if (id_x==-1)
        mexErrMsgTxt("Input structure must contain a field 'x'.");
    
    x_in = mxGetFieldByNumber(prhs, 0, id_x);
    if (!mxIsInt64(x_in))
        mexErrMsgTxt("Structure field 'x' must be of type INT64.");
    
    id_y = mxGetFieldNumber(prhs,"y");
    if (id_y==-1)
        mexErrMsgTxt("Input structure must contain a field 'y'.");
    y_in = mxGetFieldByNumber(prhs, 0, id_y);
    if (!mxIsInt64(y_in))
        mexErrMsgTxt("Structure field 'y' must be of type INT64.");
    
    num_contours = mxGetNumberOfElements(prhs);
    poly.resize(num_contours);
    for (unsigned i = 0; i < num_contours; i++){
        x_in = mxGetFieldByNumber(prhs, i, id_x);
        y_in = mxGetFieldByNumber(prhs, i, id_y);
        
        nx = mxGetNumberOfElements(x_in);
        ny = mxGetNumberOfElements(y_in);
        if (nx!=ny)
            mexErrMsgTxt("Structure fields x and y must be the same length.");
        
        poly[i].resize(nx);
        
        x = (long64*)mxGetData(x_in);
        y = (long64*)mxGetData(y_in);
        for (unsigned j = 0; j < nx; j++){
            poly[i][j].X = x[j];
            poly[i][j].Y = y[j];
        }
    }
}

//void write_polygons_MATLAB(mxArray *plhs, Polygons &solution)
void write_polygons_MATLAB(mxArray *plhs, Paths &solution)
{
    mxArray *x_out, *y_out;
    
    for (unsigned i = 0; i < solution.size(); ++i)
    {
        x_out = mxCreateDoubleMatrix(solution[i].size(),1,mxREAL);
        y_out = mxCreateDoubleMatrix(solution[i].size(),1,mxREAL);
        for (unsigned j = 0; j < solution[i].size(); ++j)
        {
            ((double*)mxGetPr(x_out))[j]=solution[i][j].X;
            ((double*)mxGetPr(y_out))[j]=solution[i][j].Y;
        }
        mxSetFieldByNumber(plhs,i,0,x_out);
        mxSetFieldByNumber(plhs,i,1,y_out);
    }
}


void mexFunction(int nlhs, mxArray *plhs[],
        int nrhs, const mxArray *prhs[])
{
    //Polygons subj, clip, solution;
    Paths subj, clip, solution;
    const char *field_names[] = {"x","y"};
    int dims[2];
    
    if (nrhs == 0) {
        mexPrintf("OutPol = clipper(RefPol, ClipPol, Method, [RefF], [ClipF]);\n");
        mexPrintf(" Clips polygons by Method:\n");
        mexPrintf("  0 - Difference (RefPol - ClipPol)\n");
        mexPrintf("  1 - Intersection\n");
        mexPrintf("  2 - Xor\n");
        mexPrintf("  3 - Union\n");
        mexPrintf(" Optionally specifying Fill Types for the polygons:\n");
        mexPrintf("  0 - Even-Odd (default)\n");
        mexPrintf("  1 - Non-Zero\n");
        mexPrintf("  2 - Positive\n");
        mexPrintf("  3 - Negative\n\n");
        mexPrintf("Or:\n\n");
        mexPrintf("OutPol = clipper(RefPol, Delta, MiterLimit);\n");
        mexPrintf(" Offsets RefPol by Delta (+: outset, -: inset).\n");
        mexPrintf("  MiterLimit * Delta = max distance of new vertex.\n");
        mexPrintf("  MiterLimit = 1 for square corners.\n");
        mexPrintf("  MiterLimit = 0 for round corners.\n\n");
        mexPrintf("Or:\n\n");
        mexPrintf("Orientation = clipper(RefPol);\n");
        mexPrintf(" Returns boolean orientations of polygons.\n\n");
        mexPrintf("All polygons are structures with the fields ...\n");
        mexPrintf("  .x:    x-coordinates of contour\n");
        mexPrintf("  .y:    y-coordinates of contour\n");
        mexPrintf("All polygons may contain several contours.\n");
        mexPrintf("\nPolygon Clipping Routine based on clipper v4.7.5.\n");
        mexPrintf(" Credit goes to Angus Johnson\n");
        mexPrintf(" http://www.angusj.com/delphi/clipper.php\n\n");
        return;}
    
    /*  Check number of arguments */
    
    if (nlhs != 1)
        mexErrMsgTxt("One output required.");
    
    if (nrhs == 1)
    {
        // Find the orientation of input polygons
        bool orient;
        read_polygons_MATLAB(prhs[0], subj);
        plhs[0] = mxCreateDoubleMatrix(subj.size(), 1, mxREAL);
        for (unsigned i = 0; i < subj.size(); ++i)
        {
            orient = Orientation(subj[i]);
            ((double*)mxGetPr(plhs[0]))[i] = (double)orient;
        }
    }
    else if (nrhs >= 3)
    {
        if (!mxIsDouble(prhs[2]) || mxGetM(prhs[2])!=1 || mxGetN(prhs[2])!=1)
            mexErrMsgTxt("Third input must be scalar.");
        if (mxIsStruct(prhs[1]))
        {
            // Clip two input polygons
            int ct;
            ClipType CT;
            PolyFillType SFT, CFT;
            ct=mxGetScalar(prhs[2]);
            switch (ct){
                case 0:
                    CT=ctDifference;
                    break;
                case 1:
                    CT=ctIntersection;
                    break;
                case 2:
                    CT=ctXor;
                    break;
                case 3:
                    CT=ctUnion;
                    break;
                default:
                    mexErrMsgTxt("Third input must be 0, 1, 2, or 3.");
            }
            
            if (nrhs >= 4)
            {
                if (!mxIsDouble(prhs[3]) || mxGetM(prhs[3])!=1 || mxGetN(prhs[3])!=1)
                    mexErrMsgTxt("Fourth input must be scalar if specified.");
                
                int sft;
    
                sft=mxGetScalar(prhs[3]);
                switch (sft){
                    case 0:
                        SFT = pftEvenOdd;
                        break;
                    case 1:
                        SFT = pftNonZero;
                        break;
                    case 2:
                        SFT = pftPositive;
                        break;
                    case 3:
                        SFT = pftNegative;
                        break;
                    default:
                        mexErrMsgTxt("Fourth input must be 0, 1, 2, or 3.");
                }
                
            }
            else
                SFT=pftEvenOdd;
            
            if (nrhs >= 5)
            {
                if (!mxIsDouble(prhs[4]) || mxGetM(prhs[4])!=1 || mxGetN(prhs[4])!=1)
                    mexErrMsgTxt("Fifth input must be scalar if specified.");
                
                int cft;
    
                cft=mxGetScalar(prhs[4]);
                switch (cft){
                    case 0:
                        CFT = pftEvenOdd;
                        break;
                    case 1:
                        CFT = pftNonZero;
                        break;
                    case 2:
                        CFT = pftPositive;
                        break;
                    case 3:
                        CFT = pftNegative;
                        break;
                    default:
                        mexErrMsgTxt("Fifth input must be 0, 1, 2, or 3.");
                }
                
            }
            else
                CFT=pftEvenOdd;
                
            /* Import polygons to structures */
            read_polygons_MATLAB(prhs[0], subj);
            read_polygons_MATLAB(prhs[1], clip);
            
            Clipper c;
            c.AddPaths(subj, ptSubject, true); //assume closed polygons
            c.AddPaths(clip, ptClip, true);
            
            if (c.Execute(CT, solution, SFT, CFT)){
                dims[0] = 1;
                dims[1] = solution.size();
                plhs[0] = mxCreateStructArray(2, dims, 2, field_names);
                write_polygons_MATLAB(plhs[0], solution);
            } else
                mexErrMsgTxt("Clipper Error.");
        }
        else
        {
            // Offset single input polygon
            if (!mxIsDouble(prhs[1]) || mxGetM(prhs[1])!=1 || mxGetN(prhs[1])!=1)
                mexErrMsgTxt("Second input must be either a structure or a scalar double.");
            
            if (nrhs > 3)
                mexPrintf("Ignoring fill type arguments for offsetting.\n");
            
            /* Import polygons to structures */
            read_polygons_MATLAB(prhs[0], subj);
            
            JoinType jt;
            double delta, ml;
            
            delta = mxGetScalar(prhs[1]);
            ml = mxGetScalar(prhs[2]);
            
            if (ml==0)
                jt = jtRound;
            else if (ml==1)
                jt = jtSquare;
            else
                jt = jtMiter;
            
            ClipperOffset offs( ml );
            //enum EndType {etClosedPolygon, etClosedLine, etOpenButt, etOpenSquare, etOpenRound};            
            offs.AddPaths(subj,jt,etClosedPolygon);
            offs.Execute(solution, delta);
            
            dims[0] = 1;
            dims[1] = solution.size();
            plhs[0] = mxCreateStructArray(2, dims, 2, field_names);
            write_polygons_MATLAB(plhs[0], solution);
            
            offs.Clear();
        }
    }
    else
        mexErrMsgTxt("One or three inputs required.");
}
