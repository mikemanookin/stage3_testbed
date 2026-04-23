# ADR-0003: CUDA Acceleration for Stimulus Generation

## Status
**Proposed** — 2026-04-22. **Not yet accepted.** Blocked on [ADR-0002](0002-cross-platform-direction.md): the cross-platform decision shapes what CUDA integration even looks like.

## Context

The heaviest per-frame work in real protocols is stimulus generation on the CPU:

- **White-noise checkerboards** at high spatial resolution — regenerating the pattern each frame
- **Drifting gratings** with arbitrary pixel-level phase modulation
- **Large textures** being updated per-frame (e.g. natural-image movies with dynamic contrast adjustment)

On a good day the CPU-bound generation plus OpenGL upload stays under the 16.67 ms frame budget at 60 Hz. On a less good day (multi-electrode array running in parallel, other MATLAB work, a few frame drops) it goes over, causing dropped frames that today don't even surface in `PlayInfo` (fixed by [TASK-003](../TASKS.md#task-003)'s timestamp tracking).

NVIDIA CUDA on supported video cards would let us:

1. Generate stimuli on the GPU directly (no CPU → GPU upload)
2. Use CUDA-OpenGL interop to write stimuli directly into OpenGL textures
3. Offload per-frame parametric computations (gamma correction curves, per-pixel phase maps, etc.) to thousands of threads

## The blocker: platform reach

CUDA is NVIDIA-only. Specifically:

- **Windows + NVIDIA:** full CUDA support, latest toolkit
- **Linux + NVIDIA:** full CUDA support, latest toolkit
- **macOS:** CUDA deprecated in 2019; not supported on Apple Silicon at all
- **Windows + AMD / Intel Arc:** no CUDA
- **Linux + AMD:** no CUDA (ROCm is a different, incompatible stack)

So any cross-platform Stage must have a non-CUDA fallback path. Options:

- **OpenCL** — cross-vendor, cross-platform, but Apple has deprecated it on macOS too
- **Compute shaders** (GLSL / SPIR-V / Metal / HLSL) — runs on every modern GPU, but less ergonomic than CUDA for general-purpose compute
- **Vulkan compute** — similar story to compute shaders; universal but lower-level

A realistic architecture: CUDA where available, compute-shader fallback elsewhere. The stimulus API must hide which backend is active from protocol authors.

## Options considered

### Option A — CUDA-only, Windows+Linux rigs only (status quo extended)

If cross-platform (ADR-0002 Option A — stay MATLAB) doesn't happen, CUDA becomes attractive on rigs that already run Windows/Linux NVIDIA boxes. Integration via MATLAB's Parallel Computing Toolbox (`gpuArray`) or a MEX wrapper around custom CUDA kernels.

Viable today. Small investment. Doesn't help anyone on Apple Silicon.

### Option B — CUDA + compute-shader fallback, cross-platform

Target two backends: CUDA for NVIDIA on Windows/Linux, compute shaders (GL 4.3+ or SPIR-V) everywhere else. The stimulus-generation API is shared; each backend implements the primitives.

Larger engineering investment; right answer if Stage is genuinely cross-platform.

### Option C — Defer until profiling shows it's the bottleneck

Run TASK-002 (accurate frame rate) and TASK-003 (wall-clock time) first. Once `PlayInfo.flipTimestamps` exists we'll have real data on dropped frames per rig / per protocol. If frame drops are rare in practice, CUDA is a premature optimization.

## Decision

**Not yet made.** Specifically: **CUDA should not be pursued until ADR-0002 is accepted.** The cross-platform commitment determines whether we're targeting one backend (A) or two (B), and whether we're writing CUDA code in MATLAB, C++, or C#.

The right near-term work is Option C: **defer.** After TASK-003 lands we'll have actual frame-drop statistics from real protocols. If those statistics show measurable drops on rigs where protocols matter, revisit this ADR with the data.

## What to collect between now and the revisit

- `PlayInfo.flipTimestamps` data from real running protocols on each lab's rig
- Rough CPU profile of the worst-case stimuli (SpatialNoise, large natural-image protocols): how much time is spent in per-frame stimulus generation vs. OpenGL draw calls vs. GPU wait?
- Anecdotal reports of dropped frames in current operations

## Consequences of deferring

- CPU-bound stimulus generation stays as-is. Rigs that are currently fine stay fine; rigs that are marginal stay marginal.
- If ADR-0002 picks Option A (keep MATLAB), CUDA via `gpuArray` becomes a straightforward low-scope addition whenever we revisit.
- If ADR-0002 picks Option B or C (C++ or C# core), CUDA is one line item in the larger architectural change and gets designed in from the start.

## Related

- [ADR-0002 Cross-platform direction](0002-cross-platform-direction.md) — this ADR is gated on that one
- [TASK-003 Wall-clock time](../TASKS.md#task-003) — provides the data needed to re-evaluate
- [PLAN.md](../PLAN.md) § "Later — architectural bets under consideration"
