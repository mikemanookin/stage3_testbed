#include <mex.h>
#include "GLFW/glfw3.h"
/*
 * Note: deliberately no main-thread dispatch here, even on macOS.
 * glfwSwapInterval uses GLFW's per-thread TLS to find the current
 * context, and configures NSOpenGLContext swap-interval. It must
 * run on the same thread as glfwMakeContextCurrent (the MCR
 * interpreter thread under our scheme). See glfwMakeContextCurrent.c
 * and spec/TASKS.md § TASK-008.
 */

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    int interval;

    if (nrhs != 1)
    {
        mexErrMsgIdAndTxt("glfw:usage", "Usage: glfwSwapInterval(interval)");
        return;
    }

    interval = mxGetScalar(prhs[0]);

    /* Run directly on caller's thread — no GLFW_ON_MAIN hop. */
    glfwSwapInterval(interval);
}