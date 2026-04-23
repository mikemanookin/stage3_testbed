#include <mex.h>
#include "avbin.h"

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    AVbinStream *stream;
    
    if (nrhs != 1)
    {
        mexErrMsgIdAndTxt("avbin:usage", "Usage: avbin_close_stream(stream)");        
        return;
    }
    
    stream = (AVbinStream *)*((uint64_t *)mxGetData(prhs[0]));
    
    avbin_close_stream(stream);
}