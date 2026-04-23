#include <mex.h>
#include "avbin.h"

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    AVbinFile *file;
    
    if (nrhs != 1)
    {
        mexErrMsgIdAndTxt("avbin:usage", "Usage: avbin_close_file(file)");        
        return;
    }
    
    file = (AVbinFile *)*((uint64_t *)mxGetData(prhs[0]));
    
    avbin_close_file(file);
}