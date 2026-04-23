# ADR-0001: In-Frame Polling for Mid-Presentation Stop

## Status
Accepted — 2026-04-22

## Context

When Symphony ends an epoch early (e.g., user presses Stop mid-streaming), the Stage visual stimulus should terminate promptly instead of continuing to run for the full presentation duration. This requires a way to deliver a `stop` message to the Stage server while it's inside `player.play()`, which blocks the server's main serve loop.

Stage's netbox-based server is single-threaded: only one connection is accepted and served at a time, and each `EventReceived` dispatch blocks the serve loop until the handler returns. There is no background thread that could receive a control message in parallel with a running presentation.

Three architectures were considered:

### (A) Thread the server

Rewrite `netbox.Server.serve()` to dispatch each `EventReceived` onto a worker thread, letting the main serve loop accept further messages in parallel. A separate thread would receive `stop` and set a flag the player observes.

- Pros: Textbook concurrent-server design; extends naturally to other async operations.
- Cons: MATLAB's cooperative threading doesn't map cleanly to worker threads — each thread needs its own safe entry into the shared OpenGL context, and netbox's Java-level reader isn't thread-safe. High engineering cost for a single feature.

### (B) Second TCP connection for control

Client opens a second connection dedicated to control (`stop`, future `pause`). Server runs a secondary listener that dispatches on this connection.

- Pros: No changes to the data connection's behavior.
- Cons: netbox's `listen.accept()` runs in the main MATLAB thread; adding a second listener requires threading. Same fundamental cost as (A).

### (C) In-frame polling (chosen)

The player's frame loop calls a stop-check callback between frames. The callback does a non-blocking receive on the existing connection and dispatches any pending control events (today: `stop`; future: `pause`, `setParameter`, etc.). On `stop`, the callback sends `'ok'` back to the client immediately and sets `player.stopRequested = true`. The frame loop exits at the next iteration.

- Pros: No threading. Cost is a single non-blocking read per frame (≈ one microsecond when no message is pending). Uses existing netbox primitives.
- Cons: Stop latency is one frame (~16 ms at 60 Hz), which is well within the user-perceptible threshold for this use case. In-frame polling couples the frame loop to the network layer — a concern for separation of concerns, mitigated by keeping the polling entirely inside a server-supplied callback.

## Decision

Adopt in-frame polling. The flow:

1. `StageServer.onEventPlay` sets a stop-checker callback on the player before calling `player.play(canvas)`.
2. The callback (a closure over the connection and a shared `stopRequested` handle) does `connection.receiveMessage()` with a 0-second timeout.
3. If a `stop` event is received, the callback sends `'ok'` on the connection, sets the shared flag, and returns.
4. If any other event arrives during a play, the callback sends `'error'` with an explanatory message — we don't support overlapping events during a play other than `stop`.
5. The player's frame loop invokes the callback after each `pollEvents()` and breaks on the flag being set.

`PlayInfo` gains a `stopped` boolean so Symphony can distinguish natural completion from early stop.

## Consequences

**Positive:**

- Minimal implementation (~50 lines across server + player base class).
- No threading; no new failure modes.
- Stop latency bounded by one frame (~16 ms at 60 Hz).
- Callback is parameterized — future control events (`pause`, `resume`, `setParameter`) can reuse the same polling slot.

**Negative:**

- Each frame pays a small fixed cost for the non-blocking read. At 60 Hz and ~1 µs per poll this is negligible, but it's not zero.
- The player base class acquires a dependency on a network-level callback, mildly violating separation of concerns. Mitigated by treating the callback as opaque (the player doesn't know what it does, only that it may set `stopRequested`).
- Prerendering (in `PrerenderedPlayer`) is not interruptible with this approach — prerender runs *before* the frame loop starts, so no polling opportunities exist. Addressing this requires a separate polling hook during prerender or a different architecture; explicitly deferred.

## Related

- Spec: [WIRE_PROTOCOL.md](../specs/WIRE_PROTOCOL.md) — the `stop` event definition
- Spec: [PLAYER_LIFECYCLE.md](../specs/PLAYER_LIFECYCLE.md) — how players observe `stopRequested`
- Spec: [SERVER_MODEL.md](../specs/SERVER_MODEL.md) — the threading context this decision lives in
- Task: [TASKS.md § TASK-001](../TASKS.md#task-001)
