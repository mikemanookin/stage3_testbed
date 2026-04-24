#include <mex.h>
#include "GLFW/glfw3.h"
#include <stdint.h>
#include "glfw_mac_dispatch.h"

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    GLFWmonitor *monitor;
    GLFW_BLOCK const char *name = NULL;

    if (nrhs != 1)
    {
        mexErrMsgIdAndTxt("glfw:usage", "Usage: name = glfwGetMonitorName(monitor)");
        return;
    }

    monitor = (GLFWmonitor *)*((uint64_t *)mxGetData(prhs[0]));

    GLFW_ON_MAIN({ name = glfwGetMonitorName(monitor); });

    plhs[0] = mxCreateString(name);
}