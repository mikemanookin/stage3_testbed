#include <mex.h>
#include "GLFW/glfw3.h"
#include <stdint.h>
/*
 * Note: deliberately no main-thread dispatch here, even on macOS.
 * [NSOpenGLContext flushBuffer] must run on the thread where the
 * GL context is current. Under our scheme the context is bound to
 * MATLAB's MCR interpreter thread (see glfwMakeContextCurrent.c
 * and Window.m's post-create fixup), so the swap must also run on
 * the MCR thread. Dispatching to the main thread would flush
 * against a context that isn't current there.
 */

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    GLFWwindow *window;

    if (nrhs != 1)
    {
        mexErrMsgIdAndTxt("glfw:usage", "Usage: glfwSwapBuffers(window)");
        return;
    }

    window = (GLFWwindow *)*((uint64_t *)mxGetData(prhs[0]));

    /* Run directly on caller's thread — no GLFW_ON_MAIN hop. */
    glfwSwapBuffers(window);
}