#include <mex.h>
#include <windows.h>
#include "dwmapi.h"

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    BOOL enabled;
	HRESULT result = S_OK;
    
    if (nrhs != 0)
    {
        mexErrMsgIdAndTxt("Dwm:usage", "Usage: enabled = DwmIsCompositionEnabled()");        
        return;
    }
    
    DwmIsCompositionEnabled(&enabled);
	if (!SUCCEEDED(result))
	{
        mexErrMsgIdAndTxt("Dwm:failed", "Failed to get state of composition");        
        return;
	}
	
	plhs[0] = mxCreateLogicalScalar(enabled);
}