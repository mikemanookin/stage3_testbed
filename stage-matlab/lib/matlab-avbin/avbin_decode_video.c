#include <mex.h>
#include "avbin.h"

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    AVbinStream *stream;
    uint8_t *data_in;
    size_t size_in;
    int width;
    int height;
    uint8_t *data_out;
    int32_t size_used;
    
    if (nrhs != 4)
    {
        mexErrMsgIdAndTxt("avbin:usage", "Usage: data = avbin_decode_video(stream, data, width, height)");        
        return;
    }
    
    stream = (AVbinStream *)*((uint64_t *)mxGetData(prhs[0]));
    data_in = (uint8_t *)mxGetData(prhs[1]);
    width = mxGetScalar(prhs[2]);
    height = mxGetScalar(prhs[3]);
    
    size_in = mxGetN(prhs[1]) * sizeof(data_in[0]);
    data_out = mxMalloc(width * height * 3 * sizeof(uint8_t));
    
    size_used = avbin_decode_video(stream, data_in, size_in, data_out);
    if (size_used == -1)
    {
        mxFree(data_out);
        mexErrMsgIdAndTxt("avbin:failed", "An error occurred");        
        return;
    }
    
    plhs[0] = mxCreateNumericMatrix(0, 0, mxUINT8_CLASS, mxREAL);
    mxSetData(plhs[0], data_out);
    mxSetM(plhs[0], width * height * 3);
    mxSetN(plhs[0], 1);
}