# Stage — Plan

Strategic direction and roadmap. Tactical work items live in [TASKS.md](TASKS.md); format contracts live in [specs/](specs/); permanent decisions are in [decisions/](decisions/).

---

## Current state

- netbox TCP server (default port 5678) exposes a fixed set of events: canvas/projection/renderer configuration, monitor queries, and the main `play` / `replay` / `getPlayInfo` lifecycle.
- Single-connection server (`netbox.Server` accepts one connection at a time; its `serve` loop blocks in an event handler until the handler returns).
- Players (`RealtimePlayer`, `PrerenderedPlayer`, `RegenPlayer`) run a frame loop that terminates only when `presentation.duration` elapses.
- No mid-presentation stop mechanism exists. Stop can only be triggered by terminating the server process (shift + escape in the Stage window).

## Roadmap

### Now
- **Mid-presentation stop** — client can request early termination of an in-progress play; server reports stopped state in `PlayInfo`. See [TASK-001](TASKS.md#task-001). *Code complete; awaiting end-to-end hardware test.*

### Next
- **Accurate frame rate detection** — today Stage polls the OS (`GLFW.getMonitorRefreshRate`), which floors the result (e.g. returns 59 for a 59.94 Hz monitor). Stimulus durations computed as `nFrames / frameRate` inherit the rounding error, accumulating to seconds over long epochs. Measure the true refresh rate empirically and use it everywhere. See [TASK-002](TASKS.md#task-002).
- **System-clock-based `time` property** — today `state.time = frame / frameRate` inherits the frame-rate error *and* assumes perfectly-paced frames, which breaks under dropped frames. Use a wall-clock timestamp (`stage.core.Clock` equivalent) started at the first flip. See [TASK-003](TASKS.md#task-003).
- **UI modernization off deprecated Java Swing** — the stage-server UI (`stageui.*` + `appbox`) calls `javacomponent`, `JavaFrame`, and `findjobj`, all slated for removal in a future MATLAB release. Today the UI emits ~15 deprecation warnings on launch. Port required before a future MATLAB release drops these APIs. Gated on [ADR-0002](decisions/0002-cross-platform-direction.md) — if we move off MATLAB entirely (Options B/C), the UI gets rewritten in the target language and this port is unnecessary. A headless path (`StartStage('headless')`) is already available as an interim workaround. See [TASK-004](TASKS.md#task-004).
- **Structured error telemetry** — standardize the shape of `'error'` responses across all event handlers, include error codes the client can reason about programmatically.
- **Multi-client tolerance** — at minimum detect and reject a second concurrent connection with a clear error; ideally queue or round-robin.

### Later — architectural bets under consideration

Each of these requires an accepted ADR before any implementation begins.

#### Cross-platform support (Windows, macOS, Linux)

Stage currently runs only on Windows — the MATLAB + GLFW combination has rough edges on macOS (OpenGL is deprecated in favor of Metal) and is untested on Linux. Users want to develop protocols and preview stimuli without booting a Windows rig.

Three architectural options, each with different trade-offs around cross-platform reach, performance, and required rewrite scope:

| Option | Description | Reach | Effort |
|--------|-------------|-------|--------|
| **A. Keep MATLAB + GLFW, port carefully** | Fix GLFW build for macOS/Linux; accept OpenGL deprecation on macOS. | Windows + Linux first-class; macOS "works but unsupported by Apple." | Small–medium |
| **B. C++ core with MATLAB client** | Move rendering + netbox server into a native binary; MATLAB stays as a thin client for test tooling. | All three. Near-optimal performance. Direct access to platform-native vsync APIs (`CVDisplayLink`, DXGI VBlank, Linux DRM). | Large |
| **C. C# core** | Same as B but in .NET. Can share the Symphony C# acquisition pipeline's plumbing (log4net, packaging, etc.). | All three via .NET 10. Slightly slower than C++ but still well below frame-time. | Medium–large |

See [decisions/0002-cross-platform-direction.md](decisions/0002-cross-platform-direction.md) — currently Proposed, awaiting a prototype + decision.

#### CUDA acceleration for stimulus generation

Frame-perfect noise, drifting gratings, and large texture operations are the most expensive CPU work in current protocols. Offloading to CUDA would cut per-frame stimulus-generation time substantially.

Gated on the cross-platform decision (CUDA is NVIDIA-only; macOS hasn't supported CUDA since 2019; Apple Silicon never will). Any cross-platform design needs a non-CUDA fallback path (compute shaders or CPU) for Mac, and likely for future AMD-only Linux rigs.

See [decisions/0003-cuda-acceleration.md](decisions/0003-cuda-acceleration.md) — currently Proposed.

#### Other long-horizon items

- **Replace netbox with a modern IPC** — netbox is a custom netty-style wrapper over Java TCP with bespoke serialization. An alternative like gRPC or WebSockets would give us typed schemas, streaming responses, and multi-language clients. Independent of the cross-platform decision but likely to be revisited as part of it.
- **Typed PlayInfo schema** — today `PlayInfo` is a loose MATLAB struct that varies by player. A formal schema (matching the DJ JSON approach on the Symphony side) would help downstream analysis.

## Principles

1. **Symphony compatibility over elegance.** Wire-protocol changes must be backward compatible with existing Symphony releases unless an ADR explicitly accepts the break.
2. **Frame-loop priority.** The rendering frame loop runs at 60+ Hz and must not be blocked by control messages for more than a few microseconds.
3. **Fail visibly.** Any error during a presentation is recorded in `PlayInfo` and surfaced to Symphony; Stage never silently swallows a rendering error.
4. **Timing correctness over implementation simplicity.** If the OS-reported refresh rate disagrees with the measured rate, the measured rate wins. If a controller asks for time and the frame count disagrees with the wall clock, the wall clock wins. The visual science done with this system cannot tolerate silent accumulation of timing error.
5. **Platform choices are reversible until they land.** Any move toward a non-MATLAB core must keep the MATLAB client API usable during the transition (dual-stack period) so user protocols don't all break at once.
