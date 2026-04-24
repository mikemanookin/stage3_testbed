#include <mex.h>
#include "GLFW/glfw3.h"
#include <stdint.h>
#include "glfw_mac_dispatch.h"

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    GLFW_BLOCK int count = 0;
    GLFW_BLOCK GLFWmonitor **monitors = NULL;
    mxArray *monitorAddrs;
    uint64_t *addrs;
    int i;

    if (nrhs != 0)
    {
        mexErrMsgIdAndTxt("glfw:usage", "Usage: monitors = glfwGetMonitors()");
        return;
    }

    GLFW_ON_MAIN({ monitors = glfwGetMonitors(&count); });

    monitorAddrs = mxCreateNumericMatrix(1, count, mxUINT64_CLASS, mxREAL);
    addrs = (uint64_t *)mxGetData(monitorAddrs);
    for(i = 0; i < count; i++)
    {
        addrs[i] = (uint64_t)monitors[i];
    }

    plhs[0] = monitorAddrs;
}