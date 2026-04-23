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
void setNormalPriority()
{
    thread_standard_policy_data_t policy;
    mach_msg_type_number_t count;
    boolean_t getDefault;
    kern_return_t result;
    
    count = THREAD_STANDARD_POLICY_COUNT;
    getDefault = true;
    result = thread_policy_get(mach_thread_self(), THREAD_STANDARD_POLICY, (thread_policy_t)&policy, &count, &getDefault);
    if (result)
    {
        mexErrMsgIdAndTxt("priority:failed", "Failed to get normal priority");
    }
    
    result = thread_policy_set(mach_thread_self(), THREAD_STANDARD_POLICY, (thread_policy_t)&policy, THREAD_STANDARD_POLICY_COUNT);
    if (result)
    {
        mexErrMsgIdAndTxt("priority:failed", "Failed to set normal priority");
    }
}

#elif defined _WIN32 || defined _WIN64
void setNormalPriority()
{
	bool result;
	
    result = SetPriorityClass(GetCurrentProcess(), NORMAL_PRIORITY_CLASS);
    if (!result)
    {
        mexErrMsgIdAndTxt("priority:failed", "Failed to set max priority");
    }
	
	result = SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_NORMAL);
	if (!result)
    {
        mexErrMsgIdAndTxt("priority:failed", "Failed to set max priority");
    }
}

#elif defined(__linux__) || defined(__unix__) || defined(__posix__)
/*
 * Linux priority reset.
 *
 * Unwinds whatever setMaxPriority did: revert the calling thread
 * to SCHED_OTHER (the default time-sharing scheduler) with
 * priority 0, and reset the process nice level to 0. Errors are
 * reported but in practice a failure here is benign — the worst
 * case is that a crashed or stopped presentation leaves its
 * thread at real-time for the remainder of the MATLAB session,
 * which is not dangerous on a rig machine.
 */
void setNormalPriority()
{
    struct sched_param param;
    int result;

    /* SCHED_OTHER requires priority 0; any other value is invalid. */
    param.sched_priority = 0;
    result = pthread_setschedparam(pthread_self(), SCHED_OTHER, &param);
    if (result != 0) {
        mexErrMsgIdAndTxt("priority:failed",
            "pthread_setschedparam(SCHED_OTHER) failed: errno=%d (%s)",
            result, strerror(result));
        return;
    }

    /* Best-effort reset of nice level. Do not error out if this
       fails; nice(-20) may never have been set if SCHED_FIFO
       succeeded on the way up. */
    setpriority(PRIO_PROCESS, 0, 0);
}

#endif

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{    
    if (nrhs > 0)
    {
        mexErrMsgIdAndTxt("priority:usage", "Usage: setNormalPriority()");
        return;
    }
    
    setNormalPriority();
}