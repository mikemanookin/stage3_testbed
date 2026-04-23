#include <mex.h>
#include "avbin.h"

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    AVbinFile *file;
    int32_t index;
    AVbinStreamInfo info;
    AVbinResult result;
    const char *fieldNames[] = {"type", "width", "height"};
    mxArray *infoStruct;
    
    if (nrhs != 2)
    {
        mexErrMsgIdAndTxt("avbin:usage", "Usage: info = avbin_stream_info(file, index)");        
        return;
    }
    
    file = (AVbinFile *)*((uint64_t *)mxGetData(prhs[0]));
    index = mxGetScalar(prhs[1]);
    
    info.structure_size = sizeof(info);
    
    result = avbin_stream_info(file, index, &info);
    if (result == AVBIN_RESULT_ERROR)
    {
        mexErrMsgIdAndTxt("avbin:failed", "An error occurred");        
        return;
    }
    
    infoStruct = mxCreateStructMatrix(1, 1, sizeof(fieldNames) / sizeof(fieldNames[0]), fieldNames);
    mxSetField(infoStruct, 0, "type", mxCreateDoubleScalar(info.type));
    mxSetField(infoStruct, 0, "width", mxCreateDoubleScalar(info.video.width));
    mxSetField(infoStruct, 0, "height", mxCreateDoubleScalar(info.video.height));
    
    plhs[0] = infoStruct;
}