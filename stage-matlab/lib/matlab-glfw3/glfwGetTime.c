#include <mex.h>
#include "GLFW/glfw3.h"
#include "glfw_mac_dispatch.h"

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    GLFW_BLOCK double time = 0.0;

    if (nrhs != 0)
    {
        mexErrMsgIdAndTxt("glfw:usage", "Usage: time = glfwGetTime()");
        return;
    }

    GLFW_ON_MAIN({ time = glfwGetTime(); });

    plhs[0] = mxCreateDoubleScalar(time);
}