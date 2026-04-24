/*
 * glfw_mac_dispatch.h
 *
 * Run GLFW calls on the macOS main thread.
 *
 * Background
 * ----------
 * GLFW's macOS backend calls Cocoa APIs (TSM, Carbon HIToolbox, NSWindow,
 * NSOpenGLContext, ...) that macOS 15 (Sequoia) enforces must run on the
 * process's main thread. MATLAB runs user code on a worker thread called
 * the "MCR interpreter thread" — *not* the main thread — so any direct
 * call to `glfwInit()` etc. from a MEX function fires a
 * `dispatch_assert_queue` assertion and crashes MATLAB.
 *
 * This header provides two macros that hop the call to the main queue
 * via GCD when we're not already on the main thread. `dispatch_sync`
 * blocks the caller until the main thread picks up the block and
 * finishes it, so the GLFW semantics are preserved (the MEX still
 * returns only after glfwInit has completed).
 *
 * Requires: MATLAB's main thread be actively draining its dispatch
 * queue. Regular MATLAB desktop mode satisfies this because the main
 * thread runs a Cocoa NSRunLoop, which integrates with the main
 * dispatch queue. `matlab -batch` mode may not — needs verification.
 *
 * On non-macOS platforms these macros reduce to a plain call, so the
 * same source compiles cleanly everywhere.
 *
 * Usage
 * -----
 *
 *   void f(void)            { GLFW_RUN_ON_MAIN_VOID(glfwTerminate()); }
 *   int  g(void) { int r;     GLFW_RUN_ON_MAIN_INT(r, glfwInit());    return r; }
 *
 * See spec/TASKS.md § TASK-008 for context.
 */

#ifndef GLFW_MAC_DISPATCH_H
#define GLFW_MAC_DISPATCH_H

#ifdef __APPLE__

#include <dispatch/dispatch.h>
#include <pthread.h>

/* Run CALL once. If we're on the main thread, run it inline. Else
   block-dispatch to the main queue and wait for it to finish. */
#define GLFW_RUN_ON_MAIN_VOID(CALL)                                    \
    do {                                                               \
        if (pthread_main_np()) {                                       \
            CALL;                                                      \
        } else {                                                       \
            dispatch_sync(dispatch_get_main_queue(), ^{ CALL; });      \
        }                                                              \
    } while (0)

/* Same, but CALL returns an int that we want to capture into RESULT.
   __block is required so the block's assignment is visible outside. */
#define GLFW_RUN_ON_MAIN_INT(RESULT, CALL)                             \
    do {                                                               \
        if (pthread_main_np()) {                                       \
            (RESULT) = (CALL);                                         \
        } else {                                                       \
            __block int _glfw_rc = 0;                                  \
            dispatch_sync(dispatch_get_main_queue(), ^{                \
                _glfw_rc = (CALL);                                     \
            });                                                        \
            (RESULT) = _glfw_rc;                                       \
        }                                                              \
    } while (0)

#else /* non-Apple: plain call, no threading constraint */

#define GLFW_RUN_ON_MAIN_VOID(CALL)        do { CALL; } while (0)
#define GLFW_RUN_ON_MAIN_INT(RESULT, CALL) do { (RESULT) = (CALL); } while (0)

#endif /* __APPLE__ */

#endif /* GLFW_MAC_DISPATCH_H */
