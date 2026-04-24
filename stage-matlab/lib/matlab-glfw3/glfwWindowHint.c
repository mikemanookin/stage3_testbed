#include <mex.h>
#include "GLFW/glfw3.h"
#include "glfw_mac_dispatch.h"

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    int target;
    int hint;

    if (nrhs != 2)
    {
        mexErrMsgIdAndTxt("glfw:usage", "Usage: glfwWindowHint(target, hint)");
        return;
    }

    target = mxGetScalar(prhs[0]);
    hint = mxGetScalar(prhs[1]);

    GLFW_ON_MAIN({ glfwWindowHint(target, hint); });
}