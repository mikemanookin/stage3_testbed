#include <mex.h>
#include "GLFW/glfw3.h"
#include <stdint.h>
#include "glfw_mac_dispatch.h"

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    GLFWmonitor *monitor;
    /* GLFW_BLOCK required — see glfwGetWindowSize.c comment. */
    GLFW_BLOCK int width = 0;
    GLFW_BLOCK int height = 0;

    if (nrhs != 1)
    {
        mexErrMsgIdAndTxt("glfw:usage", "Usage: [width, height] = glfwGetMonitorPhysicalSize(monitor)");
        return;
    }

    monitor = (GLFWmonitor *)*((uint64_t *)mxGetData(prhs[0]));

    GLFW_ON_MAIN({ glfwGetMonitorPhysicalSize(monitor, &width, &height); });

    plhs[0] = mxCreateDoubleScalar(width);
    plhs[1] = mxCreateDoubleScalar(height);
}