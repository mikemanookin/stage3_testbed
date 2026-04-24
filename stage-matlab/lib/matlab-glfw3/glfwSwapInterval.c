#include <mex.h>
#include "GLFW/glfw3.h"
#include "glfw_mac_dispatch.h"

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    int interval;

    if (nrhs != 1)
    {
        mexErrMsgIdAndTxt("glfw:usage", "Usage: glfwSwapInterval(interval)");
        return;
    }

    interval = mxGetScalar(prhs[0]);

    GLFW_ON_MAIN({ glfwSwapInterval(interval); });
}