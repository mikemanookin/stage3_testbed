#include <mex.h>

#ifdef __APPLE__
#include <sys/types.h>
#include <sys/sysctl.h>
#include <mach/mach_init.h>
#include <mach/thread_act.h>
#elif defined _WIN32 || defined _WIN64
#include <windows.h>
#elif defined(__linux__) || defined(__unix__) || defined(__posix__)
#include <pthread.h>
#include <sched.h>
#include <sys/resource.h>
#include <errno.h>
#include <string.h>
#endif

#ifdef __APPLE__
void setMaxPriority()
{
    int mib[2];
    int busFreq;
    size_t len;
    thread_time_constraint_policy_data_t policy;
    kern_return_t result;
    
    mib[0] = CTL_HW;
    mib[1] = HW_BUS_FREQ;
    len = sizeof(busFreq);
    sysctl(mib, 2, &busFreq, &len, NULL, 0);
    
    policy.period = busFreq / 120;
    policy.computation = policy.period * 0.9;
    policy.constraint = policy.computation;
    policy.preemptible = 1;
    
    result = thread_policy_set(mach_thread_self(), THREAD_TIME_CONSTRAINT_POLICY, (thread_policy_t)&policy, THREAD_TIME_CONSTRAINT_POLICY_COUNT);
    if (result)
    {
        mexErrMsgIdAndTxt("priority:failed", "Failed to set max priority");
    }
}

#elif defined _WIN32 || defined _WIN64
void setMaxPriority()
{
	bool result;
	
    result = SetPriorityClass(GetCurrentProcess(), REALTIME_PRIORITY_CLASS);
    if (!result)
    {
        mexErrMsgIdAndTxt("priority:failed", "Failed to set max priority");
    }
	
	result = SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_TIME_CRITICAL);
	if (!result)
    {
        mexErrMsgIdAndTxt("priority:failed", "Failed to set max priority");
    }
}

#elif defined(__linux__) || defined(__unix__) || defined(__posix__)
/*
 * Linux high-priority boost.
 *
 * First try: SCHED_FIFO real-time scheduling at the highest
 * available priority for the current thread. Matches the intent of
 * the macOS THREAD_TIME_CONSTRAINT_POLICY and the Windows
 * REALTIME_PRIORITY_CLASS + THREAD_PRIORITY_TIME_CRITICAL on
 * the other branches.
 *
 * SCHED_FIFO requires CAP_SYS_NICE (or root). Most research rigs
 * run as root. Laptops and CI often don't have the capability —
 * fall back to a nice(-20) boost, which any user can request if
 * their rlimit (RLIMIT_NICE) allows it.
 *
 * If both fail, error out — MATLAB wraps calls to setMaxPriority
 * in try/catch (see RealtimePlayer.m), so the error is caught and
 * logged; the player continues without RT boost, only timing may
 * jitter more than usual.
 */
void setMaxPriority()
{
    struct sched_param param;
    int max_prio;
    int result;

    max_prio = sched_get_priority_max(SCHED_FIFO);
    if (max_prio < 0) {
        mexErrMsgIdAndTxt("priority:failed",
            "sched_get_priority_max(SCHED_FIFO) failed: %s",
            strerror(errno));
        return;
    }

    param.sched_priority = max_prio;
    result = pthread_setschedparam(pthread_self(), SCHED_FIFO, &param);
    if (result == 0) {
        return;  /* SCHED_FIFO set; highest-quality boost */
    }

    /* Fallback: nice(-20). Needs RLIMIT_NICE permissive. */
    if (setpriority(PRIO_PROCESS, 0, -20) == 0) {
        return;  /* partial boost, no real-time */
    }

    mexErrMsgIdAndTxt("priority:failed",
        "Unable to boost thread priority. SCHED_FIFO failed (errno=%d: %s); "
        "nice(-20) failed (errno=%d: %s). Run as root or grant CAP_SYS_NICE "
        "for best timing. Acquisition will continue without RT boost.",
        result, strerror(result),
        errno, strerror(errno));
}

#endif

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{    
    if (nrhs > 0)
    {
        mexErrMsgIdAndTxt("priority:usage", "Usage: setMaxPriority()");
        return;
    }
    
    setMaxPriority();
}