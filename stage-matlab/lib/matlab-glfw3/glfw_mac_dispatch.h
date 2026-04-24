/*
 * glfw_mac_dispatch.h
 *
 * Run GLFW calls on the macOS main thread.
 *
 * Background
 * ----------
 * GLFW's macOS backend calls Cocoa APIs (TSM, Carbon HIToolbox, NSWindow,
 * NSOpenGLContext, CGDisplay, ...) that macOS 15+ (Sequoia) enforces must
 * run on the process's main thread. MATLAB runs user code on a worker
 * thread called the "MCR interpreter thread" — *not* the main thread —
 * so any direct call to `glfwInit()` etc. from a MEX fires a
 * `dispatch_assert_queue` assertion and crashes MATLAB with a trace trap.
 *
 * The fix: hop the GLFW call to the main queue via GCD when we're not
 * already on the main thread. `dispatch_sync` blocks the caller until
 * the main thread picks up the block and finishes it, so GLFW semantics
 * are preserved (the MEX still returns only after the GLFW call
 * completes).
 *
 * Requires: MATLAB's main thread must be actively draining its dispatch
 * queue. Regular MATLAB desktop mode satisfies this because the main
 * thread runs a Cocoa NSRunLoop which integrates with the main dispatch
 * queue. `matlab -batch` mode may not — tested OK in desktop mode on
 * macOS 15 / Apple Silicon / R2024b as of 2026-04-23.
 *
 * On non-macOS platforms the macros reduce to a plain call, so the same
 * source compiles cleanly everywhere without threading overhead.
 *
 * Usage
 * -----
 *
 *   // Plain call with no return value:
 *   GLFW_ON_MAIN({ glfwTerminate(); });
 *
 *   // Call with return value — the variable holding the result must
 *   // be declared with GLFW_BLOCK so blocks can write to it on macOS:
 *   GLFW_BLOCK int rc = 0;
 *   GLFW_ON_MAIN({ rc = glfwInit(); });
 *
 *   GLFW_BLOCK GLFWwindow *win = NULL;
 *   GLFW_ON_MAIN({ win = glfwCreateWindow(w, h, title, mon, share); });
 *
 * See spec/TASKS.md § TASK-008 for context.
 */

#ifndef GLFW_MAC_DISPATCH_H
#define GLFW_MAC_DISPATCH_H

#ifdef __APPLE__

#include <dispatch/dispatch.h>
#include <pthread.h>

/*
 * Run BLOCK_STMT on the main thread, synchronously. If we're already
 * on the main thread (rare from MATLAB — but possible if this MEX is
 * invoked from a uifigure callback), run inline to avoid self-deadlock.
 *
 * BLOCK_STMT must be braced, e.g. `{ x = glfwInit(); }`.
 */
#define GLFW_ON_MAIN(BLOCK_STMT)                                       \
    do {                                                               \
        if (pthread_main_np()) {                                       \
            BLOCK_STMT                                                 \
        } else {                                                       \
            dispatch_sync(dispatch_get_main_queue(), ^ BLOCK_STMT );   \
        }                                                              \
    } while (0)

/*
 * Storage-class qualifier for variables that are written inside a
 * GLFW_ON_MAIN block. On clang (macOS) this must be `__block` so the
 * block captures the variable by reference rather than value.
 */
#define GLFW_BLOCK __block

#else /* non-Apple */

#define GLFW_ON_MAIN(BLOCK_STMT) do BLOCK_STMT while (0)
#define GLFW_BLOCK /* nothing */

#endif /* __APPLE__ */

#endif /* GLFW_MAC_DISPATCH_H */
