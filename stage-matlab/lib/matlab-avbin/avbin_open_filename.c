#include <mex.h>
#include "avbin.h"

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    size_t filenameLen;
    char *filename;
    AVbinFile *file;
    mxArray *fileAddr;
    
    if (nrhs != 1)
    {
        mexErrMsgIdAndTxt("avbin:usage", "Usage: file = avbin_open_filename(filename)");        
        return;
    }
    
    filenameLen = mxGetN(prhs[0]) * sizeof(mxChar) + 1;
    filename = mxMalloc(filenameLen);
    mxGetString(prhs[0], filename, (mwSize)filenameLen);
        
    file = avbin_open_filename(filename);
    if (file == NULL)
    {
        mexErrMsgIdAndTxt("avbin:failed", "The file could not be opened, or is not of a recognized file format");        
        return;
    }
    
    fileAddr = mxCreateNumericMatrix(1, 1, mxUINT64_CLASS, mxREAL);
    *((uint64_t *)mxGetData(fileAddr)) = (uint64_t)file;
    
    plhs[0] = fileAddr;
    
    mxFree(filename);
}