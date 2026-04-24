#include <mex.h>
#include "GLFW/glfw3.h"
#include <stdint.h>
#include "glfw_mac_dispatch.h"

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    GLFWwindow *window;
    int width = 0;
    int height = 0;

    if (nrhs != 1)
    {
        mexErrMsgIdAndTxt("glfw:usage", "Usage: [width, height] = glfwGetWindowSize(window)");
        return;
    }

    window = (GLFWwindow *)*((uint64_t *)mxGetData(prhs[0]));

    GLFW_ON_MAIN({ glfwGetWindowSize(window, &width, &height); });

    plhs[0] = mxCreateDoubleScalar(width);
    plhs[1] = mxCreateDoubleScalar(height);
}