#include <mex.h>
#include "GLFW/glfw3.h"
#include <stdint.h>
#include "glfw_mac_dispatch.h"

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    GLFWwindow *window;
    /*
     * GLFW_BLOCK (expands to __block on clang) is REQUIRED here.
     * Without it, `&width` inside the dispatch block yields the
     * address of the block's captured COPY of width, not the
     * outer stack variable — so glfwGetWindowSize writes into a
     * copy that is discarded when the block returns, and the
     * outer width stays 0. Same for height.
     */
    GLFW_BLOCK int width = 0;
    GLFW_BLOCK int height = 0;

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