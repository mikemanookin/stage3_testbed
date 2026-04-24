#include <mex.h>
#include "GLFW/glfw3.h"
#include <stdint.h>
#include "glfw_mac_dispatch.h"

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    GLFWmonitor *monitor;
    float gamma;

    if (nrhs != 2)
    {
        mexErrMsgIdAndTxt("glfw:usage", "Usage: glfwSetGamma(monitor, gamma)");
        return;
    }

    monitor = (GLFWmonitor *)*((uint64_t *)mxGetData(prhs[0]));
    gamma = mxGetScalar(prhs[1]);

    GLFW_ON_MAIN({ glfwSetGamma(monitor, gamma); });
}