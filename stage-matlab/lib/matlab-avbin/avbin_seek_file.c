#include <mex.h>
#include "avbin.h"

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    AVbinFile *file;
    AVbinTimestamp timestamp;
    AVbinResult result;
    
    if (nrhs != 2)
    {
        mexErrMsgIdAndTxt("avbin:usage", "Usage: avbin_seek_file(file, timestamp)");        
        return;
    }
    
    file = (AVbinFile *)*((uint64_t *)mxGetData(prhs[0]));
    timestamp = mxGetScalar(prhs[1]);
        
    result = avbin_seek_file(file, timestamp);
    if (result == AVBIN_RESULT_ERROR)
    {
        mexErrMsgIdAndTxt("avbin:failed", "An error occurred");        
        return;
    }
}