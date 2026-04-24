#include <mex.h>
#include "GLFW/glfw3.h"
#include "glfw_mac_dispatch.h"

/*
 * mexAtExit callback. glfwTerminate must also run on macOS main
 * thread (it tears down the same Cocoa objects glfwInit created).
 */
void cleanup(void)
{
    GLFW_ON_MAIN({ glfwTerminate(); });
}

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    GLFW_BLOCK int result = GL_FALSE;

    if (nrhs != 0)
    {
        mexErrMsgIdAndTxt("glfw:usage", "Usage: glfwInit()");
        return;
    }
    mexAtExit(cleanup);

    /* On macOS, run glfwInit on the main thread. Cocoa/TSM APIs
       called by glfwInit assert they're on the main dispatch queue
       under macOS 15+. See spec/TASKS.md § TASK-008. */
    GLFW_ON_MAIN({ result = glfwInit(); });

    if (result == GL_FALSE)
    {
        mexErrMsgIdAndTxt("glfw:failed", "An error occurred");
        return;
    }
}
