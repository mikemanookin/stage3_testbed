# Stage — Active Tasks

Current work queue. Tasks are removed from this file when done and archived in git history.

**Priority key:** P0 = blocks release, P1 = current horizon, P2 = next horizon.
**Status key:** Open, In Progress, Blocked, Done — YYYY-MM-DD.

---

## TASK-001 — Mid-presentation stop from Symphony

**Spec:** [specs/WIRE_PROTOCOL.md](specs/WIRE_PROTOCOL.md) § stop, [specs/PLAYER_LIFECYCLE.md](specs/PLAYER_LIFECYCLE.md) § early termination
**ADR:** [decisions/0001-in-frame-stop-polling.md](decisions/0001-in-frame-stop-polling.md)
**Status:** Done — code complete, awaiting end-to-end hardware test
**Priority:** P1

When the user presses **Stop and Delete** on Symphony during an active streaming epoch, Stage should terminate the current presentation promptly instead of running out the full duration. Symphony reads the result via the existing `getPlayInfo` call, which now reports whether the stop was honored.

### When Stage stop IS triggered

- Stop and Delete button → "Save Partial" → `Controller.requestStopAndSavePartial()` → **stop Stage**
- Stop and Delete button → "Discard" → `Controller.requestStop()` → **stop Stage**
- Stop and Delete button → "Cancel" → nothing (user cancelled)

### When Stage stop is NOT triggered

- Protocol's `shouldContinueRun()` returns false naturally — **Stage plays to completion**
- Stop After Current Epoch (finish the in-flight epoch cleanly) — **Stage plays to completion**
- Protocol throws an error that stops acquisition — **Stage plays to completion** (the error handler shuts down the DAQ; Stage is independent)

The rule: Stage stop fires only on the operator-driven abort paths that already destroy in-flight epoch data. Natural completion and "finish current epoch" paths let Stage run out.

**Acceptance criteria:**
- [x] New `stop` event on the wire protocol — takes no arguments, responds `'ok'` on success
- [x] `Player.requestStop()` + `setStopChecker(fn)` + `checkForStop()` + `resetStopState()` methods on the base class
- [x] `RealtimePlayer.play()` frame loop breaks on next iteration when the flag is set
- [x] `PrerenderedPlayer.play()` and `RegenPlayer.play()` frame loops break similarly
- [x] Server polls the connection once per frame for incoming events and dispatches `stop` to the active player (only during a play — outside a play, `stop` returns an error)
- [x] Server's `stop` handler acknowledges the request BEFORE the frame loop notices the flag (ack within ~1 frame period)
- [x] `PlayInfo.stopped` field (boolean) reports true when play was cut short by stop, false when play completed naturally
- [x] `PlayInfo.flipDurations` contains durations for rendered frames up to the stop point
- [x] Symphony-side `StageClient.stop()` sends the event and waits for the ack
- [x] Symphony-side `VideoDevice.stop()` exposes a user-callable method; tolerates "no active play" by returning quietly
- [x] Symphony's `stopAndDeleteButtonPushed` calls `VideoDevice.stop()` on any `VideoDevice` in the current rig, in both "Save Partial" and "Discard" branches (not in "Cancel")
- [x] Natural epoch completion (`shouldContinueRun` returns false) does NOT call `VideoDevice.stop()` — Stage is left to run to completion
- [x] On stop, the player emits a terminal black frame so frame-tracker photodiodes see an "off" end-of-sweep edge (otherwise an early stop mid-toggle can leave the tracker in the "on"/white state). Invariant 7 in [specs/PLAYER_LIFECYCLE.md](specs/PLAYER_LIFECYCLE.md).

**Out of scope:**
- Interrupting a prerendering phase (before playback starts) — prerender runs in `play()` and completes before the frame loop begins; stop during prerender is deferred to a follow-up task
- Aborting individual stimuli (lower-level control)
- Timeout on stop (the frame loop polls every frame, so ack is bounded by ~1 frame period)

---

## TASK-002 — Accurate frame rate detection

**Spec:** [specs/PLAYER_LIFECYCLE.md](specs/PLAYER_LIFECYCLE.md) (§ frame state), [specs/MONITOR_TIMING.md](specs/MONITOR_TIMING.md)
**Status:** Done — 2026-04-23
**Priority:** P1

`stage.core.Monitor.refreshRate` calls `GLFW.glfwGetVideoMode()` → `refreshRate` field, which is an **integer** — a 59.94 Hz monitor reports as 59. Downstream code computes stimulus durations as `nFrames / frameRate` and frame timing as `state.time = frame / frameRate`; both inherit the floor error. Over a 30-second epoch the error accumulates to ~500 ms.

The fix is to **measure** the refresh rate empirically during server start and cache it. One practical approach: render `N` frames (N ≈ 120) at startup, time the interval between flips with a monotonic wall-clock, compute the median flip period, invert for refresh rate. Store the measured rate on `Monitor` and expose via `getMonitorRefreshRate` (existing wire event).

**Acceptance criteria:**

- [x] `stage.core.Monitor.refreshRate` returns a double (e.g. `59.94028`), not an integer
- [x] On a 59.94 Hz monitor, the returned value is within 0.02 Hz of true *(pending on-hardware confirmation; algorithm is median-of-120, which meets the spec under normal load)*
- [x] Measurement happens at server start (or first canvas creation) — not per-play *(StageServer.start calls Monitor.measureRefreshRate after initial flip)*
- [x] Existing users of `refreshRate` (prerender frame counts, player frame timing, `VideoDevice.getMonitorRefreshRate()`) pick up the accurate value without API change *(getRefreshRateFcn closure swap; zero caller-side changes)*
- [x] Fallback: if empirical measurement fails (e.g. no window yet), fall back to the OS-reported integer with a warning printed to stderr
- [x] New spec `specs/MONITOR_TIMING.md` documents the measurement procedure and the invariant that `Monitor.refreshRate` is accurate to ≤ 0.02 Hz

**Out of scope:**
- Compensating for runtime refresh-rate drift (monitors are stable to ≤ 0.001 Hz over minutes; not worth the complexity)
- Multi-monitor rigs with different refresh rates per monitor (today we assume a single canvas = single monitor)

---

## TASK-003 — Wall-clock `time` in frame state

**Spec:** [specs/PLAYER_LIFECYCLE.md](specs/PLAYER_LIFECYCLE.md) § Frame state
**Status:** Done — 2026-04-23
**Priority:** P1

The frame-state struct passed to stimulus controllers today sets `state.time = frame / frameRate`. This has two failure modes:

1. If `frameRate` is inaccurate (see TASK-002), every controller computing a waveform (`sin(2πft)`, ramps, LED calibration curves, etc.) drifts over the epoch.
2. If a frame is dropped — the rendering loop fell behind vsync — `state.time` still advances by `1/frameRate`, so the stimulus continues as if no frame were missed, even though ~16 ms more wall-clock time has actually elapsed. Result: later frames in the epoch are "behind" where the stimulus math thinks it is.

The fix is to maintain a monotonic wall-clock starting at the first flip and set `state.time = now - t0`. Frame-count-based time becomes a separate `state.frameTime = frame / frameRate` for controllers that actually want frame-indexed math (rare, but legitimate for noise seeds and similar).

**Acceptance criteria:**

- [x] `state.time` is wall-clock elapsed seconds since the first `canvas.window.flip()`, measured with `glfwGetTime()` — **not** `frame / frameRate` *(RealtimePlayer only; prerender loops in PrerenderedPlayer and RegenPlayer keep frame-indexed state.time because no flips happen during prerender — see PLAYER_LIFECYCLE.md § Frame state)*
- [x] `state.frame` still increments by 1 per rendered frame (existing semantics)
- [x] New `state.frameTime = frame / frameRate` for controllers that need frame-locked timing (noise-seed selection, etc.)
- [x] Existing controllers that read `state.time` pick up the new (correct) value with no user code changes
- [x] If a frame is dropped, `state.time` reflects the true elapsed time on the next rendered frame — stimuli "catch up" to where they should be
- [x] `PlayInfo` includes two arrays: `flipDurations` (unchanged) and new `flipTimestamps` (seconds relative to first flip for each flip), for post-hoc frame-timing analysis
- [x] `specs/PLAYER_LIFECYCLE.md` § state updated to reflect the two-clock model *(see new § Frame state)*

**Out of scope:**
- High-precision wall-clock alternatives (performance counter, CLOCK_MONOTONIC_RAW) — MATLAB's `tic`/`toc` resolution (~microseconds) is fine for our sample rates
- GPU-side timestamps (would be ideal but requires GL query objects; defer to a future task)

**Depends on:** TASK-002 for accuracy of `frameTime` (but `time` itself is independent of `frameRate`)

---

## TASK-004 — Port stage-server UI off deprecated Java Swing

**Spec:** N/A (UI layer is outside the current spec set — specs cover server core + wire protocol only)
**ADR:** [decisions/0002-cross-platform-direction.md](decisions/0002-cross-platform-direction.md) — Option A accepted, this task now active
**Status:** Code complete — 2026-04-23; awaiting on-rig visual verification
**Priority:** P1 (upgraded from P2 on 2026-04-23 after ADR-0002 was accepted as Option A)

The stage-server UI (`apps/stage-server/src/main/matlab/+stageui/*` + `apps/stage-server/lib/appbox`) is built on Java Swing via deprecated MATLAB APIs:

- `javacomponent` — used by `appbox.BusyView`, `appbox.Label`, and others
- `JavaFrame` — used by `findjobj` in `appbox.uix.Text`
- `findjobj_fast` — reaches into Swing internals

All of these will be removed in a future MATLAB release. Running `StartStage` today emits ~15 deprecation warnings, each announcing a separate component.

This is the same problem Symphony 3 solved (see Symphony's `spec/decisions/0005-uifigure-over-swing.md`). The solution on that project was a full port to MATLAB's `uifigure` framework.

### Context — this task may be superseded

If [ADR-0002 Cross-platform direction](decisions/0002-cross-platform-direction.md) lands as **Option B (C++ core)** or **Option C (C# core)**, the UI moves into that codebase (WPF / native / web front-end) and this port is wasted work. Do not start TASK-004 until ADR-0002 is accepted and the direction is Option A (stay in MATLAB).

If ADR-0002 is accepted as Option A, this task becomes P1 — the UI will break on the next MATLAB release that drops `javacomponent`, so we need the port before that happens.

### Workaround for testbed users (already available)

`StartStage('headless')` launches the server without the MATLAB UI, bypassing every deprecation warning. Recommended for anyone developing core server / player / wire-protocol code; the UI is only useful for interactive monitor-selection / port configuration, which the headless mode handles via command-line parameters.

**Acceptance criteria**:

- [x] `appbox.BusyPresenter` is no longer on the default startup path (removed from `StartStage`; only reachable via `StartStage('legacy')` which keeps the old Swing UI available for comparison). A `uiprogressdlg`-based replacement isn't needed because startup is fast enough that no busy indicator is necessary.
- [x] `appbox.Label` replaced with `uilabel` in the new `StageServerApp`. Old stageui package left intact as an archive.
- [x] `appbox.uix.BoxPanel` replaced with `uipanel`. The collapsible-Advanced behaviour wasn't reproduced — the advanced section is always expanded. Total window height only grows by ~50 px, and the lack of collapse is not worth the complexity.
- [x] No calls to `javacomponent`, `findjobj`, `findjobj_fast`, or `JavaFrame` in the new `StageServerApp`. Old `+stageui` package still uses them but is not loaded by default.
- [x] `StartStage` (default mode) now launches `StageServerApp` with zero deprecation warnings on the new app's code paths. `StartStage('legacy')` opt-in preserves the old UI.
- [x] `StartStage('headless')` continues to work unchanged.
- [ ] Visual verification on-rig (awaiting Windows/macOS/Linux sanity checks). The new app opens a window and its fields round-trip through `setpref/getpref`; that's the only non-code validation left.
- [ ] (Optional) Document the migration in `spec/decisions/0004-uifigure-for-stage-server-ui.md` — low priority since the change is small and self-explanatory.

**Out of scope:**
- Porting `appbox` generally (it's a larger library used by more than just stage-server)
- Cosmetic UI improvements beyond what's needed to replace deprecated components

---

## TASK-005 — Cross-platform support (macOS + Linux)

**Spec:** [decisions/0002-cross-platform-direction.md](decisions/0002-cross-platform-direction.md) (accepted as Option A on 2026-04-23; platform-role asymmetry added 2026-04-24)
**Status:** Open
**Priority:** P1

Stage runs only on Windows today, not because the MATLAB source or the OpenGL rendering is Windows-bound, but because the platform-specific **MEX binaries** and a single platform-specific **dependency** (AVbin) have never been built or replaced for macOS / Linux. The full survey is in ADR-0002 § Option A — scope reality check.

### Platform-role reminder (see ADR-0002)

- **Windows / Linux**: production experiment rigs. Frame-perfect timing required.
- **macOS**: development / preview only. Frame drops tolerable; no DAQ hardware involved.

Performance acceptance criteria differ between the production platforms and Mac:

| Criterion | Windows / Linux | macOS |
|---|---|---|
| Visible output matches the protocol | Required | Required |
| Vsync-locked frame timing | Required | Preferred but not required |
| Zero dropped frames under protocol load | Required | Tolerable up to ~5% dropped frames |
| Empirical refresh-rate accuracy ≤ 0.02 Hz | Required | Not required (integer from GLFW is fine) |
| Mid-presentation stop within ~1 frame | Required | Preferred but not tested |

Every Mac-specific workaround landed as of 2026-04-24 is either compile-time (`#ifdef __APPLE__`) or runtime (`if ismac`) gated, so it has zero effect on Win/Linux binaries.

### Phase 1 — Code changes (platform-independent, no host needed) ✅ complete 2026-04-23

- [x] Linux branch of `lib/matlab-priority/setMaxPriority.c` and `setNormalPriority.c` — implemented using `pthread_setschedparam(pthread_self(), SCHED_FIFO)` with a `setpriority(PRIO_PROCESS, 0, -20)` fallback for users without CAP_SYS_NICE. `setNormalPriority` reverts to `SCHED_OTHER` + nice=0.
- [x] ~~Replace `lib/matlab-avbin/VideoSource.m` with a `VideoReader`-backed implementation~~ — rolled back 2026-04-23; replaced with ffmpeg-subprocess backend (TASK-006, now shipping on Windows).
- [x] `StartStage.sh` (Linux) + `StartStage.command` (macOS) launchers parallel to `StartStage.bat`. Both resolve their own directory, honor `MATLAB_EXE` override, accept optional `headless` arg, print install-dependency hints in their headers. Must be `chmod +x`'d after checkout.
- [x] Confirmed `Canvas.m:41` DWM-disable is `ispc`-gated; no code change needed on the non-Windows branch.

### Phase 2 — Build binaries on each host (hardware needed)

- [ ] macOS Intel (`macos-13`): `brew install glfw`, then `cd lib/matlab-glfw3; make(true)`, `cd ../matlab-priority; make(true)`, `cd ../MOGL; make(true)`. Produces `.mexmaci64` files.
- [ ] macOS ARM (`macos-14`): same steps on Apple Silicon. Produces `.mexmaca64` files.
- [ ] Linux x64 (`ubuntu-22.04`): `apt install libglfw3-dev freeglut3-dev`, same make calls. Produces `.mexa64` files.
- [ ] Smoke test on each: open a fullscreen window, render a moving gradient for 5 seconds, print `Monitor.refreshRate` — value should be within 0.02 Hz of nominal, no crashes.

### Phase 3 — CI automation

- [ ] GitHub Actions workflow with matrix: `windows-latest`, `macos-13`, `macos-14`, `ubuntu-22.04`.
- [ ] Per-job: install deps, run MATLAB in batch mode to execute `make.m` scripts, upload MEX artifacts.
- [ ] Release job concatenates artifacts into per-OS zips for distribution.
- [ ] Consider running the matrix only on release tags + main pushes, not every PR, to keep CI minutes bounded.

### Phase 4 — Symphony end-to-end validation (per OS, hardware needed)

**Windows / Linux** (production rigs, real DAQ hardware):

- [ ] Full Symphony → Stage loop with a real DAQ or simulation-mode DAQ
- [ ] Monitor refresh rate measurement completes in < 3 s, accurate to ≤ 0.02 Hz
- [ ] A Movie stimulus plays cleanly (ffmpeg-subprocess backend)
- [ ] A realtime controller-driven stimulus (e.g. expandingSpot) runs **without frame drops** at native refresh
- [ ] `info.flipTimestamps` / `info.flipDurations` are populated correctly
- [ ] Mid-presentation stop (TASK-001 path) honors `stopRequested` within ~1 frame

**macOS** (simulation / preview only, no DAQ hardware):

- [ ] Stage server starts, window appears
- [ ] A client MATLAB can `client.connect()` and `client.play(player)` with a simple Presentation
- [ ] The stimulus is **visually correct** (shapes, colors, motion) on screen
- [ ] `info.flipTimestamps` is populated (content matters, perfect timing doesn't)

Frame drops on macOS are acceptable and do NOT block macOS validation.

### Phase 5 — AVbin cleanup (blocked on TASK-006)

Cannot proceed until a working cross-platform video backend lands.
When TASK-006 is complete:

- [ ] Delete `lib/matlab-avbin/*.c`, `*.h`, `*.mexw64`, and the `avbin.*` headers
- [ ] Delete `VideoSource_VideoReader.m.disabled` (or whatever investigative artifacts remain)
- [ ] Rename directory `lib/matlab-avbin/` → `lib/matlab-video/` (or similar)
- [ ] Update `StartStage.m` path block
- [ ] Update `lib/matlab-video/README.md`

### Acceptance criteria

- [ ] `StartStage.sh monitor` opens a Stage server on a fresh Ubuntu 22.04 LTS rig with no manual MEX compilation beyond `make.m`
- [ ] Same on macOS 14 (Apple Silicon) via `StartStage.command`
- [ ] All three OSs report `Monitor.refreshRate` within 0.02 Hz of nominal
- [ ] `Movie` stimulus plays at least one reference file (e.g. a DovesMovie frame sequence) with mean absolute pixel diff ≤ 1 LSB/channel vs current AVbin-on-Windows reference
- [ ] `setMaxPriority()` returns without error on a Linux rig with CAP_SYS_NICE; prints a graceful warning without it
- [ ] CI matrix builds all artifacts on tagged releases

### Out of scope

- Porting the **client** side (Symphony's acquisition pipeline) — a separate project with its own platform constraints (NI-DAQmx, HEKA ITC drivers) dictates the Symphony side.
- Replacing OpenGL with Metal or Vulkan on macOS — deferred unless OpenGL 4.1 stops working on a supported macOS version.
- Supporting ARM Linux — only x64 Linux is in scope (no known research-rig ARM Linux users).

### Risks tracked

1. **`VideoReader` pixel fidelity vs AVbin.** Color-space handling can differ by a few LSBs. Phase 4 validation explicitly diffs against an AVbin reference; any >1 LSB/channel gap is a blocker.
2. **`SCHED_FIFO` on Linux without CAP_SYS_NICE.** Rigs run as root typically; laptops may not. Graceful-warning fallback exists.
3. **Wayland compositor capping swap rate** on some Linux desktops. Phase 2 smoke test catches it; mitigation is to run under an Xorg session or document the Wayland limitation.
4. **macOS fullscreen / mission-control interactions.** Windows DWM-disable has no equivalent on macOS; rely on fullscreen-exclusive mode and document that external displays should be in "Separate Displays" (not mirrored) mode.
5. **MATLAB `VideoReader` codec availability on Linux.** Depends on GStreamer plugins. `gstreamer1.0-libav` or `gstreamer1.0-plugins-bad` may be required; document in install instructions.

---

## TASK-006 — Cross-platform video decoding for Movie stimulus

**Spec:** [decisions/0002-cross-platform-direction.md](decisions/0002-cross-platform-direction.md) § AVbin cleanup
**Status:** Open
**Priority:** P2 — blocks TASK-005 Phase 5 only; TASK-005 Phases 1-4 (everything except Movie stimuli) can ship without this

Separated out from TASK-005 on 2026-04-23 after the first attempted fix — replacing AVbin with MATLAB's built-in `VideoReader` — had to be rolled back.

### What we learned on 2026-04-23

- The original rig's Movie files are **MPEG-4 Simple Profile (ASP)** (`mpeg4 / mp4v / Simple Profile`), not H.264. AVbin handles these because it wraps libavcodec.
- `VideoReader` on Windows uses Media Foundation, which doesn't include an MPEG-4 ASP decoder. Calling `VideoReader('foo.mp4')` on one of these files threw "Unable to determine the required codec" — not a hang, a synchronous error.
- The exception was **silently swallowed** by `StageServer.onEventPlay`'s `catch x; info = x; end` block. Stage's frame loop never ran, no flips, no FrameTracker toggle, so the photodiode-based DAQ trigger never fired and the ITC stalled. The 10 s DAQ stall we saw was the downstream symptom, not the cause.
- After transcoding a sample file to H.264 Main Profile with `ffmpeg -movflags +faststart -c:v libx264 -profile:v main -pix_fmt yuv420p`, `VideoReader` **still** threw the same codec error. That means this machine's MATLAB install doesn't have H.264 decode working either (likely a missing Windows Media Feature Pack or codec-registration gap) — it's a system-level problem, not a codec-profile problem.
- Conclusion: Option 1 (`VideoReader` + transcode) is dead, at least on this rig. The `VideoReader` reference implementation is preserved at `lib/matlab-avbin/VideoSource_VideoReader.m.disabled` but is not the path forward.

### Problem

`stage.builtin.stimuli.Movie` ultimately needs to open MP4 (and possibly other) files, decode frames on demand (and optionally preload), and return RGB frames. The current implementation is AVbin, which is:

- Abandoned since 2012
- Windows-only — no macOS or Linux binaries, source no longer builds cleanly
- The only Windows-specific dependency remaining in Stage's `lib/` tree

### Options ranked (after 2026-04-23 findings)

1. **~~`VideoReader` with a codec workaround~~** — **ruled out.** This rig's MATLAB install can't open even transcoded H.264 Main Profile MP4s.
2. **FFmpeg subprocess** ⭐ recommended lead. `VideoSource` spawns `ffmpeg` once per movie in raw-frame output mode (`-f rawvideo -pix_fmt rgb24 -`), reads RGB bytes from stdout as frames are requested. Cross-platform (one `apt install` / `brew install` / `winget install` per OS), no MEX to build, no MATLAB codec dependency, handles every codec ffmpeg supports (including MPEG-4 ASP). Seek by restart-with-`-ss`. Expected per-frame latency is sub-millisecond for any modern CPU.
3. **FFmpeg MEX wrapper.** New MEX against modern libavcodec/libavformat. Higher performance ceiling than subprocess, but MEX build/maintenance across three OSs is real work. Only pursue if subprocess latency turns out to be a bottleneck, which is unlikely for our frame rates.
4. **Pre-decode to frame-sequence directory** (using ffmpeg offline). `ffmpeg -i movie.mp4 -f rawvideo -pix_fmt rgb24 movie.rgb` once, cache the result, memory-map at runtime. Simplest runtime code, biggest asset-pipeline change. Storage cost: `width × height × 3 × nFrames` bytes per movie (e.g. 610×610×3×3922 ≈ 4.4 GB for a 1-minute rig movie — prohibitive for a library of them).

### Investigation checklist for Option 2 (FFmpeg subprocess)

- [x] Prototype a subprocess-based `VideoSource` that matches the existing AVbin-backed API (`lib/matlab-avbin/VideoSource_FFmpeg.m`) — 2026-04-23
- [x] Measure cold-start latency on this rig: open + first frame ≈ 80 ms. Target was < 100 ms. ✅
- [x] Measure steady-state throughput: 2.26 ms/frame at 610×610 RGB24. Target was < 16.7 ms for 60 fps. ✅ 7× margin.
- [x] Verify seek works — ffmpeg -ss fast-seek returns in ~45 ms, first-frame timestamp matches seek target within 20 ms.
- [x] Verify FFmpeg produces correct frames vs AVbin: frame 1 mean |d| = 0.132 LSB/channel (edge-chroma-artifact scale), per-channel means match AVbin to 0.1 LSB. ✅
- [x] Confirm FRAME_BY_FRAME playback speed still works — 2026-04-23, end-to-end Movie protocol on the rig plays correctly ✅
- [x] `Movie.m` swapped to use `VideoSource_FFmpeg` — 2026-04-23. Rollback is a one-line edit if ever needed.
- [ ] Confirm preload path works — `preload()` method exists and drains the stream into VideoBuffer; end-to-end test of `setPreloading(true)` still pending
- [ ] Test on at least two different source codecs beyond the rig's MPEG-4 ASP (e.g. H.264 and a high-bitrate test file) — pending; not blocking
- [ ] Document ffmpeg install instructions per OS in `lib/matlab-avbin/README.md` — partial; Windows/macOS/Linux commands listed in the file header

### Side finding: AVbin `nextImage` direct-call bug (2026-04-23)

While A/B testing against AVbin we discovered that direct calls to `VideoSource.nextImage()` in a loop return the **same pixel content on every call** — the timestamp advances correctly (0 ms, 16.7 ms, 33.3 ms, ... at 60 Hz) but `d_vs_prev` is exactly 0.00 for all frames 2+. `readAndDecodeNextImage` reads a new packet via `avbin_read` but `avbin_decode_video` appears to return stale pixel data.

The Movie stimulus doesn't exhibit this in production because `VideoPlayer` drives the source through the `nextTimestamp` + `getImage(time)` path rather than bare `nextImage`, and that code path populates the `VideoBuffer` before the caller asks for pixels. The buffered frame is evidently correct; only the direct sequential-read interface is broken.

This is a pre-existing bug in AVbin, not something introduced by this task. It becomes irrelevant once TASK-006 completes and AVbin is retired, so it's documented here but not tracked separately.

### MATLAB/Java interop pitfalls discovered (2026-04-23)

For future reference if anyone writes MATLAB→Java pipe-reading code:

1. **Don't pass a MATLAB `int8`/`uint8` array to a Java method expecting `byte[]` for mutation** (e.g. `readFully(byte[])`). MATLAB passes a copy; mutations aren't visible on return. Silent all-zero data.
2. **`readNBytes(N)` can hang on large returns** (observed: 1 MB+ returns on this MATLAB R2024b build). Root cause not diagnosed; avoid.
3. **`ByteBuffer.allocate(N).array()` auto-converts to MATLAB `int8` at the `.array()` call site** — once you hold that int8, you're back in scenario (1) for any subsequent Java method call.
4. **The pattern that works**: hold a `java.nio.ByteBuffer` as a Java Object (MATLAB doesn't auto-convert Objects), fill it via `channel.read(ByteBuffer)`, then call `.array()` at the end to extract bytes. MATLAB auto-converts the fresh byte[] to int8 one time, with real data.
5. **Allocate a fresh ByteBuffer per frame** rather than reusing one — reusing exhibited a subtle issue where frames 2+ appeared to contain stale data. Per-frame allocation is < 1 ms on modern JVMs.

### Acceptance criteria

- [ ] Movie stimulus plays correctly on Windows, macOS, and Linux with no platform-specific code paths in `VideoSource.m`
- [ ] At least one protocol from `PresentMovies` / `DovesMovie` / `NaturalMovie` runs end-to-end on each OS
- [ ] Frame decode latency stays < 10 ms per frame at 1080p on reference hardware (no frame drops at 60 Hz)
- [ ] No MATLAB-session hangs on any of the MP4 files the rig currently uses

### Out of scope

- Real-time video encoding (recording what Stage shows)
- Audio — `Movie` explicitly doesn't support sound

---

## TASK-007 — Allow caller to override empirically-measured refresh rate

**Spec:** [specs/MONITOR_TIMING.md](specs/MONITOR_TIMING.md) (needs updating)
**Status:** Open
**Priority:** P2

TASK-002 measures the monitor's refresh rate by driving 120 empty flips at startup and taking the median flip interval. That's the right default, but there are cases where the caller already has a better number than we could measure:

- Symphony has its own rig-side timing measurement infrastructure (DAQ clock calibration against known sources). A value derived from that can be more accurate than our ~20 ms median-of-120 window.
- Some VRR displays or compositor-capped configurations don't let us measure the real rate reliably. A user who knows the panel's nominal rate should be able to tell Stage.
- Unit tests and deterministic replay want to set a known rate without requiring an actual display.

### Proposed API

**`StageServer.start(..., 'refreshRate', rate)`** — optional name-value parameter. When provided, `Monitor.getRefreshRateFcn` is pinned to the given double and `measureRefreshRate` is skipped entirely. When absent, current empirical measurement path runs.

**Wire event `setMonitorRefreshRate(rate)`** — optional, for clients that want to push a calibrated value after connection rather than at launch. Maps to `Monitor.getRefreshRateFcn = @(~) rate;` server-side. Rejected as an error if called mid-play.

**`StageClient.setMonitorRefreshRate(rate)`** — the Symphony-side companion.

### Acceptance criteria

- [ ] `StageServer.start(..., 'refreshRate', 59.94)` opens the server and `getMonitorRefreshRate` returns exactly 59.94, no empirical measurement runs.
- [ ] Passing `0`, negative, or non-finite rates raises an input-validation error before any window is created.
- [ ] Absence of the parameter preserves current behavior (measure at start).
- [ ] New wire event `setMonitorRefreshRate` in [specs/WIRE_PROTOCOL.md](specs/WIRE_PROTOCOL.md) — takes a double, returns `'ok'` or a validation error. Allowed outside of a play, rejected mid-play (same model as `stop`).
- [ ] `StageClient.setMonitorRefreshRate` wraps the event and returns when ack'd.
- [ ] `StageServerApp` UI (TASK-004) gains an optional "Override refresh rate (Hz)" text field; empty = measure, numeric = override. Persists via preferences.
- [ ] `specs/MONITOR_TIMING.md` updated to document the override path and the order of precedence (argument > wire event > empirical measurement > GLFW integer fallback).

### Out of scope

- Automatic drift correction during a long session (e.g., re-measuring periodically). If a display's rate changes at runtime, the override stays in effect until explicitly changed.
- Symphony-side calibration itself — that's Symphony's problem; TASK-007 just receives the number.

---

## TASK-008 — `glfwInit` crashes MATLAB on macOS 15+ (main-thread assertion)

**Spec:** [decisions/0002-cross-platform-direction.md](decisions/0002-cross-platform-direction.md)
**Status:** Code complete — 2026-04-23; awaiting end-to-end on-rig validation
**Priority:** P1 (upgraded from P2 on 2026-04-23 after a Mac-using collaborator needed Stage now)

### Problem

MATLAB runs user code on a worker thread (`MCR 0 interpreter thread`), not the process's main thread. GLFW's macOS backend (`_glfwInitCocoa`) calls Apple's TSM (Text Services Manager) during `glfwInit` to enumerate keyboard input sources. macOS 15 (Sequoia, 2024) enforces a hard `dispatch_assert_queue` assertion on TSM calls. The assertion fires on the MCR thread → MATLAB dies with a Trace trap.

First observed 2026-04-23 on:
- macOS 15.7.4 (24G517)
- Apple Silicon (M4)
- MATLAB R2024b (maca64)
- GLFW 3.4 from Homebrew (/opt/homebrew)

Crash stack: `mexFunction` → `glfwInit` → `_glfwInitCocoa` → `updateUnicodeData` → `TSMGetInputSourceProperty` → `islGetInputSourceListWithAdditions` → `dispatch_assert_queue_fail`.

### Chosen approach: Option 1 — Main-thread dispatch via GCD

Picked 2026-04-23 after a Mac researcher needed Stage. Options 2-4 below kept as fallbacks.

Implementation:

- **New header** `lib/matlab-glfw3/glfw_mac_dispatch.h` defines two macros:
  - `GLFW_ON_MAIN({ ...stmt... })` — runs the braced statement on the macOS main thread via `dispatch_sync(dispatch_get_main_queue(), ...)`. Short-circuits to inline if `pthread_main_np()` reports we're already on the main thread (avoids self-deadlock). On non-Apple platforms the macro is a no-op wrapper.
  - `GLFW_BLOCK` — expands to `__block` on clang and nothing on GCC/MSVC. Used to qualify variables that receive a value assigned inside `GLFW_ON_MAIN`.

- **Every MEX wrapper** in `lib/matlab-glfw3/*.c` (30 files) was updated to `#include "glfw_mac_dispatch.h"` and wrap every direct `glfw*()` call in `GLFW_ON_MAIN({ ... })`. Non-GLFW code (input parsing, output building, error reporting, callback bookkeeping) was left alone.

- **Tested 2026-04-23** on macOS 15.7.4 / Apple Silicon M4 / R2024b: `glfwInit()`, `glfwGetMonitors()`, `glfwTerminate()` called from the MCR interpreter thread no longer crash. The earlier `dispatch_assert_queue_fail` trace trap is gone because the Cocoa/TSM calls now run on the main thread via GCD.

Caveat: the approach requires MATLAB's main thread to be actively draining its dispatch queue (i.e. a Cocoa `NSRunLoop` pumping the main queue). Regular MATLAB desktop mode satisfies this because the main thread hosts the MATLAB desktop UI. `matlab -batch` and possibly `matlab -nodesktop` may not — needs verification before ruling them in for Stage on macOS.

### Fallback options (not pursued today)

**2. Replace GLFW on macOS with Psychtoolbox's `Screen`**.

Psychtoolbox-3 is a widely-used MATLAB toolbox in the vision-science community that wraps all the platform-specific OpenGL context creation, including the macOS threading quirks. Replacing `lib/matlab-glfw3` with `Screen()` calls on macOS would solve the problem definitively but introduces a significant dependency and requires partial rewrites of `stage.core.Window`, `stage.core.Canvas`, and related.

**3. Native-code Stage server on macOS** (ADR-0002 Option B).

A C++ executable creates its own main thread and initializes GLFW on it. MATLAB becomes a thin client that talks to it over TCP. This is the original ADR-0002 Option B proposal — months of work but the real long-term fix.

**4. Document as a permanent limitation on macOS, support only Linux cross-platform**.

Now not applicable since we actually have a Mac user.

### Acceptance criteria

- [x] `glfwInit()` from MATLAB's MCR thread on macOS 15+ no longer crashes — 2026-04-23 ✅
- [x] `glfwGetMonitors()` returns successfully — 2026-04-23 ✅
- [x] `glfwTerminate()` returns successfully — 2026-04-23 ✅
- [x] All 30 `matlab-glfw3/*.c` files updated to wrap GLFW calls via GLFW_ON_MAIN — 2026-04-23 ✅
- [x] `VerifyStage` passes all checks on macOS 15 / Apple Silicon — 2026-04-23 ✅
- [x] Fixed the GL-context thread-affinity sub-issue — 2026-04-24. See sub-issue below for the design (first attempt was wrong and had to be revised).
- [x] `StartStage` opens a real GLFW window on macOS — 2026-04-24 ✅
- [x] A second MATLAB can connect as a StageClient and poll `getMonitorRefreshRate` — 2026-04-24 ✅
- [ ] A basic stage demo (`stage.demos.expandingSpot` or similar) runs end-to-end — next to verify
- [ ] Verified behavior under `matlab -batch` mode — likely will NOT work; if it doesn't, document the limitation

### Sub-issue: OpenGL context thread affinity on macOS

Discovered 2026-04-23 while testing the GLFW dispatch fix. macOS's OpenGL / Cocoa is strict about context-to-thread binding: `glfwMakeContextCurrent` marks a thread as the owner of the GL context, and subsequent GL calls are only valid on that thread. Under our main-thread-dispatch scheme, the GL context is pinned to the main thread, which means every GL call must also hop to the main thread.

First attempt (rejected): dispatch `moglcore.mexFunction` to the main thread via the same `dispatch_sync` pattern. Crashed with an assertion deeper inside MATLAB's MEX runtime:

```
Assertion in findOrFail at management.cpp line 802:
findOrFail: no active context for type 'CurrentMexInfoPerMVM'
```

MATLAB's MEX runtime relies on thread-local state (`CurrentMexInfoPerMVM`) that is only set up on the MCR interpreter thread. Running mexFunction on the main thread tripped this assertion when the function called `mexAtExit` (which registers a cleanup callback).

**Working design (2026-04-24):**

- GLFW calls that touch NSWindow / TSM / Cocoa event loop (`glfwCreateWindow`, `glfwPollEvents`, `glfwSetGamma`, etc.) stay dispatched to the main thread via GLFW_ON_MAIN.
- GLFW calls that bind or operate on the OpenGL context (`glfwMakeContextCurrent`, `glfwSwapBuffers`, `glfwSwapInterval`) run on the **caller's thread** — they have no GLFW_ON_MAIN wrapper. `[NSOpenGLContext makeCurrentContext]` and `[flushBuffer]` are thread-agnostic Cocoa calls, safe to run from any thread.
- `stage.core.Window` on macOS explicitly calls `glfwMakeContextCurrent(obj.handle)` right after `glfwCreateWindow` returns. Since `glfwCreateWindow` ran on the main thread under GLFW_ON_MAIN and left the context current there, this pulls the context to the MCR interpreter thread, where subsequent MATLAB-side GL calls (via moglcore) will happen.
- `moglcore.mexFunction` runs on the MCR thread as MATLAB expects. No dispatch hop there. GL calls inside it find the current context on the same thread and succeed.

Options considered and rejected:
- "Dispatch moglcore.mexFunction to main thread" — breaks MATLAB's MEX-runtime thread-local state (see above).
- "Use a dedicated GL worker thread with a command queue" — significant architecture change, no clear win over pinning to MCR thread.
- "Keep context on main thread, make all GL calls from main" — essentially the first attempt; rejected.

### Temporary workaround (obsolete)

No longer needed. Main-thread dispatch resolves the crash in the MATLAB desktop scenario.

---

## Task lifecycle

- New tasks are appended with sequential numbering.
- When a task is complete, commit the spec/code changes with the acceptance criteria checked off in the message, then delete the task from this file.
- If a task is abandoned, replace its body with `**Status:** Dropped — YYYY-MM-DD — <reason>` and leave the shell.
