#include <mex.h>
#include "GLFW/glfw3.h"
#include <stdint.h>
#include "glfw_mac_dispatch.h"

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    GLFWwindow *window;

    if (nrhs != 1)
    {
        mexErrMsgIdAndTxt("glfw:usage", "Usage: glfwRestoreWindow(window)");
        return;
    }

    window = (GLFWwindow *)*((uint64_t *)mxGetData(prhs[0]));

    GLFW_ON_MAIN({ glfwRestoreWindow(window); });
}
