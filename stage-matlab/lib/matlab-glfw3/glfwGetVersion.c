#include <mex.h>
#include "GLFW/glfw3.h"
#include "glfw_mac_dispatch.h"

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    /* GLFW_BLOCK required — see glfwGetWindowSize.c comment. */
    GLFW_BLOCK int major = 0;
    GLFW_BLOCK int minor = 0;
    GLFW_BLOCK int rev = 0;

    if (nrhs != 0)
    {
        mexErrMsgIdAndTxt("glfw:usage", "Usage: [major, minor, rev] = glfwGetVersion()");
        return;
    }

    GLFW_ON_MAIN({ glfwGetVersion(&major, &minor, &rev); });

    plhs[0] = mxCreateDoubleScalar(major);
    plhs[1] = mxCreateDoubleScalar(minor);
    plhs[2] = mxCreateDoubleScalar(rev);
}