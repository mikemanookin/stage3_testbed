#include <mex.h>
#include "avbin.h"

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    AVbinFile *file;
    AVbinFileInfo info;
    AVbinResult result;
    const char *fieldNames[] = {"n_streams", "start_time", "duration", "title"};
    mxArray *infoStruct;
    
    if (nrhs != 1)
    {
        mexErrMsgIdAndTxt("avbin:usage", "Usage: info = avbin_file_info(file)");        
        return;
    }
    
    file = (AVbinFile *)*((uint64_t *)mxGetData(prhs[0]));
    
    info.structure_size = sizeof(info);
    
    result = avbin_file_info(file, &info);
    if (result == AVBIN_RESULT_ERROR)
    {
        mexErrMsgIdAndTxt("avbin:failed", "An error occurred");        
        return;
    }
    
    infoStruct = mxCreateStructMatrix(1, 1, sizeof(fieldNames) / sizeof(fieldNames[0]), fieldNames);
    mxSetField(infoStruct, 0, "n_streams", mxCreateDoubleScalar(info.n_streams));
    mxSetField(infoStruct, 0, "start_time", mxCreateDoubleScalar(info.start_time));
    mxSetField(infoStruct, 0, "duration", mxCreateDoubleScalar(info.duration));
    mxSetField(infoStruct, 0, "title", mxCreateString(info.title));
    
    plhs[0] = infoStruct;
}