#include <mex.h>
#include "GLFW/glfw3.h"
#include <stdint.h>
/*
 * Note: deliberately no main-thread dispatch here, even on macOS.
 * [NSOpenGLContext makeCurrentContext] is thread-safe and binds the
 * OpenGL context to the *calling* thread. For Stage we want the
 * context on MATLAB's MCR interpreter thread (which is where
 * moglcore's mexFunction runs), so this call must happen on that
 * thread. Dispatching it to the main thread would bind the context
 * there instead and every subsequent GL call from moglcore would
 * crash with a null glGetString/glewContextInit.
 *
 * See spec/TASKS.md § TASK-008 and Window.m's post-create fixup.
 */

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    GLFWwindow *window;

    if (nrhs != 1)
    {
        mexErrMsgIdAndTxt("glfw:usage", "Usage: glfwMakeContextCurrent(window)");
        return;
    }

    window = (GLFWwindow *)*((uint64_t *)mxGetData(prhs[0]));

    /* Run directly on caller's thread — no GLFW_ON_MAIN hop. */
    glfwMakeContextCurrent(window);
}