# ADR-0002: Cross-Platform Architecture Direction

## Status
**Accepted — 2026-04-23. Option A (keep MATLAB, fix the platform gaps).**

The survey documented below ([Option A — scope reality check](#option-a--scope-reality-check)) showed that the Windows-specific surface area is much smaller than the original "hypothetical port" framing assumed. Most of the low-level MEX sources already branch on `ispc`/`ismac`/`isunix`; the gap is that only Windows binaries have ever been compiled and shipped. The residual hard part is `matlab-avbin` (abandoned library, no Mac/Linux binaries) — addressed by replacing its backend with MATLAB's built-in `VideoReader`.

Options B and C (C++ / C# rewrite) remain recorded below but are not being pursued in this cycle. They would be re-opened if empirical validation on macOS/Linux reveals issues the Option A approach cannot fix within Stage's timing tolerances.

## Context

Stage runs only on Windows today. The core stack is:

- MATLAB R2024b for the server, wire handlers, and rendering loop
- GLFW for window/input/vsync
- OpenGL 3.3 for rendering
- netbox (Java TCP wrapper) for the wire protocol
- Symphony as the only known client, via `VideoDevice` → `StageClient`

Multiple constraints motivate considering a cross-platform rewrite:

1. **Researchers want to develop protocols on macOS and Linux** — stimulus authoring shouldn't require a Windows rig.
2. **OS-reported refresh rate is integer-floored** (see [TASK-002](../TASKS.md#task-002)). Accurate timing needs OS-native vsync APIs that GLFW abstracts away.
3. **The `time` property needs a true wall-clock source** (see [TASK-003](../TASKS.md#task-003)). Each OS has a different best-available monotonic clock.
4. **Future CUDA/compute-shader acceleration** (see [ADR-0003](0003-cuda-acceleration.md)) has different best practices on each OS.
5. **macOS has deprecated OpenGL** in favor of Metal; Apple Silicon support requires Metal or MoltenVK.
6. Current MATLAB + GLFW + OpenGL + Java (via netbox) has a very large deployed-runtime footprint that isn't typical for a visual stimulus presenter.
7. **MATLAB is deprecating the Java Swing UI components** that `appbox` and the `stageui` package depend on (`javacomponent`, `JavaFrame`, `findjobj`). The server-management UI emits deprecation warnings today and will stop loading on some future MATLAB release. See [TASK-004](../TASKS.md#task-004). Options B and C remove the dependency by rewriting the UI in the target language; Option A requires a MATLAB-side UIFigure port (which Symphony already did — see its `spec/decisions/0005-uifigure-over-swing.md`).

The user has explicitly said a substantial rewrite into C++ or C# is acceptable. Doing nothing locks us to Windows.

## Options

### Option A — Keep MATLAB, fix the platform gaps

Ship MATLAB + GLFW on all three OSs. Rebuild GLFW binaries for macOS (universal2) and Linux. Accept OpenGL deprecation on macOS (stays functional in 14.x+ but with no vendor support). Fix timing issues inside MATLAB using `tic`/`toc` or Java `System.nanoTime`.

| ✅ Pros | ❌ Cons |
|---------|---------|
| Smallest scope; ships in weeks, not months | No native Metal/Vulkan access — stuck with OpenGL on macOS |
| MATLAB runs on all three — no client/server language change | Integer-floored OS refresh rate still a problem (solvable via empirical measurement) |
| Existing user protocols unchanged | No path to CUDA on the rendering side |
| | Doesn't future-proof against macOS dropping OpenGL entirely |

### Option B — C++ core with MATLAB-callable client

Rewrite the server, rendering loop, compositor, and stimulus engine in C++. MATLAB becomes a thin client that sends a serialized presentation over TCP. Native access to `CVDisplayLink` (macOS), `DXGI_OUTPUT.WaitForVBlank` (Windows), and DRM page-flip events (Linux) for frame-accurate vsync. GL (or Metal/Vulkan) renderer chosen per-platform.

| ✅ Pros | ❌ Cons |
|---------|---------|
| Best possible timing accuracy; native vsync APIs | Largest rewrite — months, not weeks |
| Direct CUDA integration on Windows/Linux | Build system across three OSs is work |
| No MATLAB runtime dependency on rig machines (lighter deploy) | Team needs ongoing C++ maintenance |
| Stimulus engine becomes embeddable (e.g. from Python) | Serialization of user-authored MATLAB stimulus classes to C++ is the hard part |

### Option C — C# / .NET 10 core with MATLAB-callable client

Same shape as B but in .NET. Could share plumbing with Symphony's C# acquisition pipeline (log4net, packaging, CI). OpenTK for GL on all three platforms; Silk.NET for Vulkan if we want it. Modern async / pipe / task story for netbox-style dispatch.

| ✅ Pros | ❌ Cons |
|---------|---------|
| Shares tooling with Symphony — unified .NET story | Still a large rewrite |
| Cross-platform already solved by .NET 10 | Slightly slower than C++ (usually not a problem for visual stimulus) |
| Typed serialization (protobuf, MessagePack) well-supported | CUDA access less ergonomic than C++; usually via ManagedCuda or calling a C++ shim |
| OpenTK + GLFW# work on all three OSs | MATLAB's .NET interop is solid on Windows, rougher on macOS/Linux (relevant only to the **client** side if MATLAB is the authoring environment) |

### Option D — Hybrid (Option A short-term, Option B/C long-term)

Ship Option A immediately to unblock macOS/Linux users at all, then invest in B or C in parallel. The first generation's MATLAB + GLFW codebase becomes the reference for what the C++/C# rewrite must preserve.

## Option A — scope reality check

The 2026-04-23 survey of the codebase revealed the Windows-specific surface is limited and mostly already gated:

| File / path | Windows-specific? | Current state | Action required |
|---|---|---|---|
| `lib/matlab-glfw3/*.c`, `make.m` | No | make.m branches on OS; only `.mexw64` binaries shipped | Build `.mexmaci64` / `.mexmaca64` / `.mexa64` |
| `lib/matlab-priority/setMaxPriority.c`, `setNormalPriority.c` | Partial | Windows + macOS impls exist; Linux branch is stub | Implement Linux (`pthread_setschedparam(SCHED_FIFO)` + `setpriority` fallback) |
| `lib/MOGL/*` | No | Cross-platform sources, make.m handles all three | Build per-OS binaries |
| `lib/matlab-avbin/*` | Effectively yes | AVbin is abandoned; no non-Windows binaries exist | Replace `VideoSource.m` backend with MATLAB's built-in `VideoReader` |
| `lib/matlab-dwm/*` | Yes | `make.m` exits on non-Windows; `Canvas.m:41` wraps call in `if ispc` | None — already no-op on Mac/Linux |
| `Canvas.m:41-44` DWM disable | Yes, gated | Correctly wrapped in `ispc` | None |
| `StartStage.bat` | Yes | Windows launcher | Add `StartStage.sh` (Linux) and `StartStage.command` (macOS) |
| All other MATLAB source | No | — | None |

Net: a few hundred lines of new code and a CI matrix, not a rewrite.

## Decision

Implement Option A via the phased plan captured in [TASK-005 Cross-platform support](../TASKS.md#task-005). B and C stay on the shelf as escape hatches if Option A runs into a wall during validation.

## Consequences

- [TASK-004](../TASKS.md#task-004) (UI port off deprecated Java Swing) is **no longer gated** — with Option A accepted, the UI layer stays in MATLAB and needs the `uifigure` migration. Upgrades from P2 to P1.
- [ADR-0003](0003-cuda-acceleration.md) (CUDA acceleration) stays blocked. CUDA from MATLAB is possible (Parallel Computing Toolbox's `gpuArray`, or a MEX shim) but each path has tradeoffs that need their own decision.
- AVbin MEX files (`lib/matlab-avbin/*.mexw64` + `.c` sources) become unused after the `VideoReader` switch lands. Retained in git history / directory during the transition for rollback; deletion happens in a followup cleanup after end-to-end validation on all three OSs.
- macOS users inherit a frozen OpenGL 4.1. Fine for current Stage rendering (vertex + fragment shaders only, no compute). If future work needs compute shaders, Metal bridging would re-open the B/C question for the rendering layer only.

## Related

- [ADR-0003 CUDA acceleration](0003-cuda-acceleration.md) — gated on this decision
- [TASK-002 Accurate frame rate detection](../TASKS.md#task-002) — work that will port
- [TASK-003 Wall-clock time](../TASKS.md#task-003) — work that will port
- [PLAN.md](../PLAN.md) § "Later — architectural bets under consideration"
