#include <mex.h>
#include "GLFW/glfw3.h"
#include "glfw_mac_dispatch.h"

/*
 * mexAtExit callback. glfwTerminate must also run on macOS main thread
 * (it tears down the same Cocoa/TSM objects glfwInit created), so we
 * route it through the same dispatcher. See glfw_mac_dispatch.h.
 */
void cleanup(void)
{
    GLFW_RUN_ON_MAIN_VOID(glfwTerminate());
}

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    int result = GL_FALSE;

    if (nrhs != 0)
    {
        mexErrMsgIdAndTxt("glfw:usage", "Usage: glfwInit()");
        return;
    }
    mexAtExit(cleanup);

    /* On macOS, run glfwInit on the main thread via dispatch_sync;
       otherwise the Cocoa TSM assertion at dispatch_assert_queue
       fires and crashes MATLAB. See spec/TASKS.md § TASK-008. */
    GLFW_RUN_ON_MAIN_INT(result, glfwInit());

    if (result == GL_FALSE)
    {
        mexErrMsgIdAndTxt("glfw:failed", "An error occurred");
        return;
    }
}
