# Monitor timing

**Status:** Draft
**Owner:** Stage core
**Related:** [PLAYER_LIFECYCLE.md](PLAYER_LIFECYCLE.md), [TASK-002](../TASKS.md#task-002)

---

## Purpose

The refresh rate reported to clients and consumed by players must be accurate to ≤ 0.02 Hz. Frame counts and per-frame schedules are derived from this value; a 1 % error over a 30 s epoch accumulates to ~300 ms of displayed-vs-intended drift.

## Why GLFW's default is insufficient

`glfwGetVideoMode()` returns a `GLFWvidmode` struct whose `refreshRate` field is an **integer**. On NTSC-era and refresh-derived panels the true rate is non-integer:

| Panel nominal | GLFW integer | True rate |
|---|---:|---:|
| 60 Hz VGA / DVI | 60 | 60.000 Hz |
| 59.94 Hz NTSC-derived | 59 | 59.94006 Hz |
| 119.88 Hz NTSC-derived | 119 | 119.88012 Hz |
| 144 Hz gaming | 144 | 143.98 Hz (typ.) |
| 165 Hz adaptive | 165 | 164.88 Hz (typ.) |

The floor operation biases low. Downstream code uses the rate in three places:

1. **Prerender sizing** — `nFrames = floor(duration × refreshRate)` undershoots the intended frame count.
2. **Player state.frameTime** — derived from frame / rate; stays self-consistent but predicts the wrong wall time.
3. **Symphony-side `getMonitorRefreshRate()`** — protocols read this for stimulus-duration math; integer drift propagates into every protocol that computes times from the rate.

## Measurement procedure

`stage.core.Monitor.measureRefreshRate(window, nFrames)` drives the actual hardware and inverts the timing:

```
1. Assume glfwSwapInterval(1) is set (Canvas constructor guarantees this).
2. 5 warm-up flips  — discards compositor transient, ensures vsync is locked
3. Snapshot t₀ = glfwGetTime()
4. For i = 1..nFrames:
     window.flip()
     timestamps(i+1) = glfwGetTime()
5. intervals = diff(timestamps)
6. medianPeriod = median(intervals)   # rejects OS-scheduling outliers
7. rate = 1 / medianPeriod
8. Cache rate on the Monitor: getRefreshRateFcn = @(~) rate
```

**Why median, not mean.** Under Windows scheduler pressure the occasional flip takes 2×-3× the vsync period. Mean is pulled high by these outliers, giving a refresh-rate undercount. Median is robust as long as fewer than half the flips are stalled, which is always true under normal load.

**Why a closure, not a numeric property.** `Monitor.refreshRate` is a dependent property backed by `getRefreshRateFcn`. Swapping the function is atomic from the caller's perspective — every existing caller (`canvas.window.monitor.refreshRate`, the wire `getMonitorRefreshRate` event, etc.) picks up the measured value with no API change.

## Integration point

`StageServer.start()` calls `window.monitor.measureRefreshRate(window)` immediately after creating the Canvas and doing the initial clear+flip. This is the one-shot measurement point:

- The window is visible and the GL context is current.
- No clients have connected yet, so the ~2 s measurement cost doesn't block a client request.
- The result is cached on the Monitor for the server's lifetime.

Headless callers that skip `StageServer.start()` can call `measureRefreshRate` directly against any visible Window.

## Invariants

1. **Measured value returned, not integer.** After a successful `measureRefreshRate` call, `Monitor.refreshRate` returns a double. The integer-from-GLFW fallback is only seen on Monitors where `measureRefreshRate` was never called or threw.
2. **Accuracy ≤ 0.02 Hz** on any monitor where the compositor is not actively capping the window (visible, foreground, DWM disabled on Windows).
3. **No API change to callers.** Existing callers of `refreshRate` (player prerender, `VideoDevice.getMonitorRefreshRate()` on the Symphony side) pick up the accurate value without code changes.
4. **Idempotent.** Re-calling `measureRefreshRate` on an already-measured Monitor re-runs the measurement and replaces the cache.
5. **Failure-tolerant.** If `measureRefreshRate` throws (no window, GL lost, compositor capping), the Monitor stays on the integer fallback and the server logs a stderr warning. The server still starts.

## Known failure modes

- **Occluded / minimized window.** DWM (Windows) or the WM (Linux) caps buffer swaps to the compositor's rate, not the panel's. Measurement reads the cap rate. Mitigation: disable DWM (`disableDwm = true`, default in Canvas) and keep the Stage window visible and in the foreground during measurement.
- **Variable refresh rate panels.** G-Sync / FreeSync displays can vary their rate at runtime. The measurement captures the rate at server start; runtime drift is not compensated. For neuroscience-grade timing, disable VRR at the display and driver level.
- **Laptop lid closed / headless monitor.** No pixels go to a panel; compositor falls back to a software rate. Do not run Stage measurements in this state.

## Open questions

- Should the server re-measure on a `getMonitorRefreshRate` wire event with a `force = true` flag? Low value, deferred.
- Should the measurement log the raw intervals alongside the median to aid post-hoc diagnosis of jittery rigs? Maybe as a `verbose` flag. Deferred.
