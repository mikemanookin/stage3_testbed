# Player Lifecycle

**Status:** Draft
**Base class:** `stage.core.Player`
**Subclasses:** `stage.builtin.players.RealtimePlayer`, `stage.builtin.players.PrerenderedPlayer`, `stage.builtin.players.RegenPlayer`

---

## Purpose

A `Player` drives a `Presentation` to completion on the OpenGL canvas: initializes stimuli, iterates a frame loop, updates controllers, flips the canvas buffer, and collects timing metrics. The abstract `play(canvas)` method is the single entry point; subclasses implement it differently (realtime rendering, pre-rendered video, etc.).

---

## Lifecycle

```
stageServer.onEventPlay(connection, event)
  │
  │  1. extract player from event.arguments{1}
  │  2. store player on connection
  │  3. ACK 'ok' to client                               ← client's `play` call returns here
  │  4. install stop-check callback on player
  │  5. player.play(canvas)  ─ blocks until done ─┐
  │                                                │
  │        ┌─ frame loop ─────────────────────────┘
  │        │  per-frame:
  │        │    a. canvas.clear()
  │        │    b. compositor.drawFrame(stimuli, controllers, state)
  │        │    c. canvas.window.flip()
  │        │    d. canvas.window.pollEvents()
  │        │    e. player.checkForStop(connection)        ← NEW: reads one pending event per frame
  │        │    f. if stopRequested, break
  │        │  loop exits when time >= presentation.duration OR stopRequested
  │        │
  │        └─ returns info { flipDurations, stopped }
  │
  │  6. store info on connection (overwriting any prior play's info)
```

---

## Early termination

A client can terminate a presentation before `presentation.duration` elapses by sending a `stop` event (see [WIRE_PROTOCOL.md](WIRE_PROTOCOL.md#stop)).

Mechanics:

1. The server installs a per-frame stop-check callback on the player via `player.setStopChecker(fn)` in `onEventPlay`.
2. Each frame, the player invokes the callback. The callback:
   - Does a **non-blocking** read of the connection (short receive timeout).
   - If a `stop` event arrived, sends `'ok'` immediately and sets `player.stopRequested = true`.
   - If any other event arrived, forwards it to the normal event dispatcher (or errors if the player doesn't support it).
   - If no event arrived (timeout), returns and the frame loop proceeds normally.
3. After the callback sets `stopRequested`, the frame loop breaks on its next iteration.
4. `play()` returns `info` with `stopped = true`.

---

## Frame state

The `state` struct passed to `compositor.drawFrame(stimuli, controllers, state)` — and from there into every user-supplied `PropertyController`, `StimulusController`, and compositor — carries per-frame timing and identity information. Controllers compute their output from these fields; the values must be predictable across players.

| Field | Type | Description |
|-------|------|-------------|
| `canvas` | `stage.core.Canvas` | The canvas being drawn into. Used by controllers that need `canvas.size`, `canvas.width`, etc. |
| `frame` | `double` (integer-valued) | Zero-based frame index since the start of the presentation. Increments by 1 per iteration of the render loop. |
| `frameRate` | `double` | Monitor refresh rate in Hz. Measured empirically; see [MONITOR_TIMING.md](MONITOR_TIMING.md). |
| `time` | `double` | Elapsed time in seconds. **Wall-clock** in `RealtimePlayer` (`glfwGetTime() - t0`); **frame-indexed** (`frame / frameRate`) during prerender in `PrerenderedPlayer` and `RegenPlayer`. See "time vs frameTime" below. |
| `frameTime` | `double` | Frame-indexed time in seconds: always equals `frame / frameRate`. Use this when a controller needs a deterministic tick that matches frame count exactly (noise-seed indexing, frame-locked sub-period offsets in `PatternCompositor`, etc.). |
| `pattern` | `double` (integer-valued) | Present only when iterated inside `PatternCompositor`; identifies the sub-pattern within a frame. |
| `patternRate` | `double` | Present only inside `PatternCompositor`: `frameRate × numPatterns`. |

### time vs frameTime

The two fields differ **only in `RealtimePlayer` under frame-drop conditions**. On the happy path (every flip lands within one vsync period) `state.time ≈ state.frameTime` to within a fraction of a millisecond.

| Scenario | `state.time` | `state.frameTime` |
|---|---|---|
| `RealtimePlayer`, all frames on schedule | wall-clock since first flip (≈ `frame / frameRate`) | `frame / frameRate` |
| `RealtimePlayer`, one frame dropped at N | at frame N+1: `(N+2) / frameRate` (catches up) | at frame N+1: `(N+1) / frameRate` (keeps counting) |
| `PrerenderedPlayer.prerender` | `frame / frameRate` (no flips happening) | `frame / frameRate` |
| `RegenPlayer.prerender` | `frame / frameRate` (no flips happening) | `frame / frameRate` |
| `PrerenderedPlayer.replay` / `RegenPlayer.replay` | no `state` passed — stimuli already rendered | n/a |

**Guidance for controller authors:**

- A controller producing a time-domain waveform (`cos(2πft)`, ramps, linear drifts) should use `state.time`. Under frame drops in a real-time play, the waveform stays phase-correct because `state.time` reflects the actual elapsed wall time.
- A controller keying off integer frame count (discrete-step noise, pattern offsets, anything that must advance exactly once per frame) should use `state.frame` directly, or `state.frameTime` if it needs the frame count expressed in seconds.
- Existing controllers written against `state.time` keep working. Before this change `state.time` was `frame / frameRate`; it is now either that (prerender paths) or wall-clock (realtime path). Both are continuous, monotonically increasing, and equal on the happy path.

---

## PlayInfo schema

Every call to `play()` or `replay()` returns an `info` struct with at least these fields. Subclasses may add additional fields.

| Field | Type | Description |
|-------|------|-------------|
| `flipDurations` | `double[]` | Time (s) between each `canvas.window.flip()` call and the next. Length = (number of frames actually rendered) − 1. Empty if stopped before the second flip. |
| `flipTimestamps` | `double[]` | Time (s) of each flip relative to the first flip; first entry is always 0. Length = number of frames actually rendered. Use for aligning the stimulus sequence with recorded response data. |
| `stopped` | `logical` | `true` if play ended because a `stop` event was received, `false` if play ran to `presentation.duration`. |

Existing subclasses that return additional fields (e.g., `PrerenderedPlayer` may add prerender timings) retain those fields and add the three required ones alongside.

---

## Invariants

1. **`play(canvas)` is synchronous on the server thread.** It blocks until the presentation completes or is stopped. The server's main serve loop cannot process other messages during `play()` — in-frame polling is the only mechanism for control messages during a play.
2. **`stopRequested` is one-shot.** Once set, the frame loop exits at the next iteration and the flag stays set until the next `play()` call resets it (or the player instance is replaced).
3. **No frame is partially rendered after stop.** The stop check happens after `canvas.window.flip()`, so the flip that was about to produce the next frame has not yet happened when the loop breaks.
4. **`flipDurations` never includes a duration for a frame that wasn't flipped.** The last entry in `flipDurations` is the final flip that successfully completed — including the terminal black frame emitted by invariant 7.
5. **`stopped` defaults to `false`.** A player that never received a stop request returns `stopped = false` in its info struct.
6. **Prerender cannot be interrupted (current limitation).** For `PrerenderedPlayer`, the frame loop is preceded by a potentially long prerender phase. Stop requests during prerender are observed only after prerender completes. Improving this is a follow-up task (see [PLAN.md](../PLAN.md)).
7. **Stop ends on a canonical "terminal" frame** that mimics natural completion for trigger purposes while also restoring the original display background. When the frame loop breaks due to `stopRequested`, the player invokes `renderStopFrame(canvas)` (inherited from `stage.core.Player`), which emits exactly one flip showing:

   - **The original presentation background color**, by drawing the first stimulus if it's a `stage.builtin.stimuli.Rectangle`. This relies on the Symphony device convention of inserting a background Rectangle at index 1 (see `VideoDevice.play`, `LightCrafterDevice`, `MicrodisplayDevice` in both Symphony 2 and Symphony 3). All *other* user stimuli (gratings, noise, images, etc.) are suppressed — the display reverts to the same flat background the user saw before any stimulus ran.
   - **FrameTrackers forced to `color = 0` (black)**, by iterating stimuli and drawing every `stage.builtin.stimuli.FrameTracker` with its color temporarily overridden. Photodiode-based trigger hardware bound to a tracker reads this as the end-of-sweep edge, matching the behavior of the tracker controller on the natural last frame.

   Presentations that don't follow the Symphony convention (no leading Rectangle or no FrameTracker) get the canvas clear color in those regions instead — a best-effort fallback rather than a guarantee. Compositor-driven controllers are NOT re-run during the stop frame, so stimulus state doesn't advance.

---

## Subclass implementation checklist

A new `Player` subclass must:

1. Call `super@stage.core.Player(presentation)` in its constructor.
2. Initialize `obj.stopRequested = false` (inherited default).
3. Accept a `stop-check` callback via `setStopChecker(fn)` (inherited method).
4. In its frame loop, call `obj.checkForStop()` after `pollEvents()` and before incrementing `frame`/`time`.
5. When `obj.stopRequested` is true, invoke `obj.renderStopFrame(canvas)` (inherited) to emit the canonical terminal frame (original background + FrameTrackers forced black), then break. See invariant 7.
6. Populate `info.flipDurations`, `info.flipTimestamps`, and `info.stopped` before returning.
7. Set `state.time` and `state.frameTime` on the frame-state struct before dispatching to the compositor. For realtime play loops, `state.time = glfwGetTime() - t0`; for prerender loops that have no displayed flips, both fields equal `frame / frameRate`. See [MONITOR_TIMING.md](MONITOR_TIMING.md) for the frame-rate measurement contract.

---

## Related specs

- [WIRE_PROTOCOL.md](WIRE_PROTOCOL.md) — the `play` / `stop` / `getPlayInfo` event contracts
- [SERVER_MODEL.md](SERVER_MODEL.md) — why in-frame polling is necessary given netbox's threading model
