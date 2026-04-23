#include <mex.h>
#include <windows.h>
#include "dwmapi.h"

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    UINT action;
	HRESULT result = S_OK;
    
    if (nrhs != 1)
    {
        mexErrMsgIdAndTxt("Dwm:usage", "Usage: DwmEnableComposition(action)");        
        return;
    }
	
	action = (UINT)floor(mxGetScalar(prhs[0]));
		
    result = DwmEnableComposition(action);
	if (!SUCCEEDED(result))
	{
        mexErrMsgIdAndTxt("Dwm:failed", "Failed to set state of composition");        
        return;
	}
}