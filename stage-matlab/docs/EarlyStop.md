# Early Stop — Mid-Presentation Termination from Symphony

**Status:** Code complete; awaiting extended hardware testing.
**Spec:** [`spec/specs/PLAYER_LIFECYCLE.md`](../spec/specs/PLAYER_LIFECYCLE.md), [`spec/specs/WIRE_PROTOCOL.md`](../spec/specs/WIRE_PROTOCOL.md), [`spec/specs/SERVER_MODEL.md`](../spec/specs/SERVER_MODEL.md)
**ADR:** [`spec/decisions/0001-in-frame-stop-polling.md`](../spec/decisions/0001-in-frame-stop-polling.md)
**Task:** [`spec/TASKS.md` § TASK-001](../spec/TASKS.md)

---

## Motivation

Before this change, once a Stage presentation started playing, the only way to end it was to let the frame loop run to `presentation.duration`. Symphony could not interrupt a presentation mid-epoch, which was a problem for:

- **Stop and Delete during streaming acquisition** — the user aborts the current epoch, but Stage keeps rendering visual stimuli for the remainder of the original duration.
- **Partial-save paths** — partial data is saved with `isPartial = true`, but the visual stimulus continues, which can affect the animal's response to subsequent epochs.
- **Runaway protocols** — a protocol with a very long stimulus could only be killed by closing MATLAB entirely.

The user-visible symptom: pressing Stop and Delete in SymphonyApp halted DAQ acquisition immediately but left Stage rendering for seconds more. Users on patch-clamp rigs saw the display continue to present a stimulus they were no longer recording.

## Overview

The change adds a new `stop` event to Stage's wire protocol and the plumbing on both sides to dispatch it correctly:

```
SymphonyApp                        Stage server                 OpenGL canvas
────────────                       ────────────                 ─────────────
press Stop and Delete              (blocked in player.play)
       │
       ├──► stopActiveVideoDevices()
       │         │
       │         └──► videoDevice.stop()
       │                   │
       │                   └──► stageClient.stop()
       │                              │
       │                              └──► sends NetEvent('stop') ──────► in-frame poll reads
       │                                    BLOCKS until 'ok'                    │
       │                                                                         ├─► player.requestStop()
       │                                                                         │        │
       │                              ◄──────── sends NetEvent('ok') ◄───────────┤        │
       │                              UNBLOCKS                                             │
       │                                                                                   │
       │                                                 frame loop checks stopRequested ◄┘
       │                                                 → true, emits renderStopFrame
       │                                                 → breaks, play() returns
       └──► controller.requestStop()                     server resumes main serve loop
            (or requestStopAndSavePartial, per dialog)
```

Stop latency from button press to display update: ≤ 1 frame period (~16 ms at 60 Hz).

## Architecture

### Why in-frame polling

Stage's netbox server is **single-threaded per connection**. While `onEventPlay` is running (which means `player.play(canvas)` is running), the server's main message loop is blocked. Normal event dispatch happens only when a handler returns, so a `stop` event sent during a play cannot be received by the ordinary `onEventReceived → onEvent<Name>` path.

Three alternatives were considered and rejected in favor of a fourth:

| Alternative | Why rejected |
|-------------|--------------|
| Multithread the netbox server (worker per connection) | MATLAB's threading model + Java netbox internals + single-threaded OpenGL context = high complexity, many new failure modes. |
| Second TCP connection for control | netbox's `accept()` is in the single-threaded main loop; can't accept a second connection until the first disconnects. Same threading rewrite. |
| File flag / shared memory | Polling overhead, cross-process fragility. |
| **In-frame polling (chosen)** | The player's frame loop calls a callback once per frame that checks for waiting messages and dispatches `stop` inline. No threading. Stop latency bounded by the frame period. |

Full rationale: [ADR-0001](../spec/decisions/0001-in-frame-stop-polling.md).

### The put-back buffer

Symphony's client pattern is: send `play` → (DAQ work) → send `getPlayInfo` (which blocks until play completes). Before this change, `getPlayInfo` sat in the TCP buffer while Stage's serve loop was busy in `onEventPlay`; the serve loop resumed after play and handled it.

A naive in-frame poller that consumes all waiting messages would read `getPlayInfo` during the frame loop and error because `getPlayInfo` doesn't make sense mid-play. To preserve the original pattern, the poller consumes **only `stop`** and **puts back** any other message onto the connection's receive queue for the main serve loop to handle after play completes.

The put-back mechanism is a single-slot buffer on `netbox.Connection` — simpler than a general queue because only one "in-flight" client request can be held at a time (the client is synchronous).

### The terminal-frame semantics

When the frame loop breaks due to stop, the player doesn't simply stop rendering — it emits **one final frame** that matches the "end-of-sweep" state the hardware expects:

- **The presentation's original background color** is restored by drawing the background Rectangle that Symphony's device files insert at stimulus index 1. All user stimuli (gratings, noise, images, etc.) are suppressed.
- **Every `FrameTracker` stimulus** is drawn with `color = 0` (black) so photodiode-based trigger hardware sees a clean end-of-sweep edge.

This matters because photodiode triggers bound to the FrameTracker are used to time-align downstream DAQ. On natural completion, the tracker controller's `mod(frame, 2) && (time + 1/frameRate < duration)` formula forces the tracker to black on the last natural frame; early stop breaks mid-toggle and could otherwise leave the tracker in an "on" (white) state, misleading the DAQ.

The helper that emits this frame lives on the `Player` base class as `renderStopFrame(canvas)` and is called by all three player subclasses uniformly.

## Wire protocol

One new event added. See [`spec/specs/WIRE_PROTOCOL.md`](../spec/specs/WIRE_PROTOCOL.md#stop) for the canonical reference.

### `stop`

- **Arguments:** none
- **Response (during play):** `ok` — sent from inside the player's frame loop as soon as the poller reads the event. The frame loop breaks on its next iteration.
- **Response (outside play):** `error` with `MException('stage:stop:noActivePlay', ...)` — nothing to stop.

No other wire-protocol events were changed. `play`, `replay`, and `getPlayInfo` keep their existing behavior.

### `PlayInfo` gains a `stopped` field

```matlab
info = struct(...
    'flipDurations', [...], ...  % existing — durations between flips
    'stopped',       false ...    % new — true if play ended via stop
)
```

Symphony can read `videoDevice.getPlayInfo().stopped` to distinguish "play ran to completion" from "play was cut short."

## File-by-file changes

### Stage side (`stage_testbed/`)

| File | Change |
|------|--------|
| `src/main/matlab/+stage/+core/Player.m` | Added `stopRequested` + `stopChecker` protected properties, `setStopChecker`, `requestStop`, `isStopRequested` public methods, protected `checkForStop`, `resetStopState`, and `renderStopFrame` helpers. |
| `src/main/matlab/+stage/+builtin/+players/RealtimePlayer.m` | Frame loop calls `checkForStop` after each `pollEvents`; breaks on `stopRequested`; emits the terminal frame via `renderStopFrame(canvas)`; populates `info.stopped`. |
| `src/main/matlab/+stage/+builtin/+players/PrerenderedPlayer.m` | Same pattern in the `replay` loop. |
| `src/main/matlab/+stage/+builtin/+players/RegenPlayer.m` | Same pattern in the `replay` loop. |
| `src/main/matlab/+stage/+core/+network/StageServer.m` | New `stop` dispatch in `onEventReceived` (errors when no play running). `onEventPlay` installs a stop-check closure on the player before calling `player.play`. New `makeStopChecker` and `pollForControlEvent`: the latter consumes `stop` inline (acks + flags player), puts non-stop messages back onto the connection's receive queue, and disables further polling for the remainder of this play. |
| `src/main/matlab/+stage/+core/+network/StageClient.m` | New `stop()` method that sends `NetEvent('stop')` and waits for `ok`. |
| `lib/netbox/src/main/matlab/+netbox/Connection.m` | Added `pendingMessage` single-slot put-back buffer, `putBackMessage(m)` method, updated `receiveMessage` to consume the buffer first, updated `hasPendingMessage` to report `(put-back set) || (socket has data)`. |
| `lib/netbox/src/main/matlab/+netbox/+tcp/TcpConnection.m` | New `hasPendingData()` method that checks the Java `InputStream.available()` — genuinely non-blocking. Added because netbox's `setReadTimeout(0)` is interpreted as *infinite* (documented in the netbox comment), so it couldn't be used to implement "read now or return." |

### Symphony side (`symphony3_testbed/`)

| File | Change |
|------|--------|
| `SymphonyApp/code/src/matlab/+symphonyui/+builtin/+devices/VideoDevice.m` | New `stop()` method that calls `stageClient.stop()`. Tolerant of "no active play" — catches `stage:stop:noActivePlay` and returns quietly, so callers can fire-and-forget. |
| `SymphonyApp/SymphonyApp.m` | New private helper `stopActiveVideoDevices()` iterates all devices on the current rig and calls `stop()` on any `VideoDevice`. Called from `stopAndDeleteButtonPushed` in the "Save Partial" and "Discard" branches (NOT in the "Cancel" branch; NOT on natural epoch completion). |

## When stop fires, and when it doesn't

### Triggers

- **Stop and Delete button → "Save Partial"** → `Controller.requestStopAndSavePartial()` → Stage stop fires.
- **Stop and Delete button → "Discard"** → `Controller.requestStop()` → Stage stop fires.
- **Stop and Delete button → short epoch / View Only / not recording** → `Controller.requestStop()` → Stage stop fires.

### Does NOT trigger

- **Protocol's `shouldContinueRun()` returns false** (natural completion) — Stage runs to completion.
- **Stop and Delete button → "Cancel"** — dialog cancelled; nothing happens.
- **Protocol error during acquisition** — `requestStop` path is taken but not via `stopAndDeleteButtonPushed`; Stage plays out.

Rule of thumb: Stage stop fires only on operator-driven abort paths that already destroy in-flight epoch data.

## Symphony ↔ Stage synchronization

The two concerns are independent:

- **DAQ side:** Symphony's `Controller.requestStop` / `requestStopAndSavePartial` handle the DAQ pipeline (drain buffers, finalize HDF5, etc.). This is unchanged.
- **Display side:** `stopActiveVideoDevices()` runs *before* the controller stop call, so the display starts halting while Symphony is still winding down the DAQ. The two happen in parallel; neither waits on the other.

This ordering is intentional: users care most about the display going dark quickly (it's visible feedback that the Stop button took effect). The DAQ side finalizes in the background over the next fraction of a second.

## Testing notes

### Manual end-to-end test

1. Start Stage via `StartStage.bat headless` (skips the Java UI, avoids deprecation-warning noise).
2. Launch SymphonyApp and initialize a rig with a `VideoDevice` (e.g. the `SimulatedStage` rig in the lab's common package).
3. Load a protocol with a Stage stimulus longer than a few seconds (a drifting grating, SpatialNoise, etc.).
4. Start recording (`Record` button) — partway through the first epoch, press **Stop and Delete**. Choose "Save Partial" or "Discard" in the dialog.
5. Verify:
   - The visual stimulus halts within ~1 frame.
   - The screen shows the protocol's original background color (not black, not the last-rendered frame's content).
   - The FrameTracker region goes black.
   - `VideoDevice.getPlayInfo()` at the MATLAB prompt returns a struct with `stopped == true`.
6. Start another recording and let it complete naturally (no Stop) — verify the presentation plays to its full duration and the tracker reaches its normal end-state.

### Regression tests to run

- **Normal epoch completion** — `stopped = false` in `PlayInfo`; natural tracker end-state.
- **Multi-epoch protocol with "Stop After Current Epoch"** — the current epoch finishes cleanly, next epoch is skipped; Stage plays that current epoch to completion (no premature stop).
- **Rig without a VideoDevice** — pressing Stop and Delete doesn't error even though there are no Stage devices to stop.
- **Stop pressed between epochs (Stage not playing)** — `stopActiveVideoDevices()` calls `stop()`, `VideoDevice.stop()` swallows `stage:stop:noActivePlay` without propagating an error.

### Known limitations

- **Prerender phase is not interruptible.** `PrerenderedPlayer.prerender()` runs the full duration before `replay()` starts the frame loop. Stop requests during prerender are observed only when prerender finishes and replay begins its first frame-loop iteration. This is deferred to a follow-up task — see [`spec/TASKS.md`](../spec/TASKS.md) for the notes.
- **The terminal frame depends on Symphony-device conventions.** The helper assumes the first stimulus is a background `Rectangle` and the tracker is a `FrameTracker` instance. Rigs using Stage through a non-Symphony client, or Symphony devices that don't follow these conventions, get a best-effort fallback: canvas clear color shows instead of the original background, and no tracker-off signal is emitted. See the `renderStopFrame` docstring and [PLAYER_LIFECYCLE.md invariant 7](../spec/specs/PLAYER_LIFECYCLE.md).

## Gotchas encountered during development

Documenting these so the next person working near this code doesn't re-hit them.

### `setReadTimeout(0)` means infinite, not zero

netbox's `TcpConnection.setReadTimeout` treats any value `<= 0` as infinite — the comment on line 53 of `TcpConnection.m` says so explicitly. An early version of the in-frame poller tried to use `setReceiveTimeout(0)` for a non-blocking read, which would have hung the frame loop forever any time no stop message was waiting. Fixed by adding `hasPendingData()` on `TcpConnection` (checks `InputStream.available()`) and using it in the poller.

### Consuming `getPlayInfo` mid-play breaks Symphony's async pattern

An earlier iteration of `pollForControlEvent` consumed every waiting message and responded with `error` to any non-`stop` event. That broke Symphony's pattern of sending `getPlayInfo` immediately after `play` (it relies on the TCP buffer holding the message until Stage's serve loop resumes). Symptom: `RETHROW can only throw a previously caught exception` on the client side when it tried to re-raise the serialized `MException` it got back.

Fixed by putting non-`stop` messages back onto the Connection's receive queue via the new `putBackMessage` slot and disabling the poller for the rest of the play.

### `canvas.clear()` clears the whole canvas

The first fix for the terminal frame did `canvas.setClearColor(0); canvas.clear(); canvas.window.flip()`, which blanked the entire display. That's trigger-safe for the FrameTracker but obliterates the rest of the scene — not what the user wants. The final version instead draws only the leading background Rectangle + the FrameTracker(s) forced to black, so the display reverts to the original background without going all-black.

### MATLAB `classdef` is strict about block structure

An early edit of `Player.m` closed the public `methods` block too early, stranding `exportMovie` outside any block. MATLAB R2024b reports this as `"Function definitions are not supported in this context"` at the stranded function's line — a confusingly-worded error for what is really a classdef structure issue. The fix was to put all public methods in one `methods` block and the protected helpers in a separate `methods (Access = protected)` block.

## Future work

- **Interrupt prerender.** `PrerenderedPlayer.prerender()` needs its own stop-check hook. Low priority because most Symphony protocols use `RealtimePlayer`, but worth addressing before any rig standardizes on prerendering.
- **Typed error codes.** All `error` wire responses today carry an `MException` whose identifier the client parses. Standardizing these as documented codes (e.g. `stage:stop:noActivePlay`, `stage:play:unsupportedEventDuringPlay`) would let the client reason programmatically rather than by string match. Tracked in [`spec/PLAN.md`](../spec/PLAN.md) as "Structured error telemetry."
- **Non-Symphony clients.** The terminal-frame helper depends on the Symphony device convention (leading background Rectangle + trailing FrameTracker). A more portable design would let the client register a "stop callback" on the presentation that specifies explicitly which stimuli to render in the terminal frame, rather than relying on the convention. Not critical while Symphony is the only client.
