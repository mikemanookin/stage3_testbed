#include <mex.h>
#include "GLFW/glfw3.h"
#include "glfw_mac_dispatch.h"

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    GLFW_BLOCK const char *version = NULL;

    if (nrhs != 0)
    {
        mexErrMsgIdAndTxt("glfw:usage", "Usage: version = glfwGetVersionString()");
        return;
    }

    GLFW_ON_MAIN({ version = glfwGetVersionString(); });

    plhs[0] = mxCreateString(version);
}