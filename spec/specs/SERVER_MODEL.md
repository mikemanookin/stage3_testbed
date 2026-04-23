# Stage Server Threading Model

**Status:** Draft
**Implementation:** `stage.core.network.StageServer`, built on `netbox.Server`

---

## Purpose

Document the concurrency model of the Stage server — what runs where, and what constraints this imposes on protocol design (especially for control events that need to interrupt in-progress work).

---

## Threading model (current)

Stage runs as a **single MATLAB process**. The server is cooperatively single-threaded:

```
MATLAB main thread
  └── netbox.Server.start(port)
        ├── listen loop: accept() with 10-second timeout
        │     └── emits Interrupt event on timeout (no client connected)
        │
        └── per-client serve loop: receiveMessage() with 10-second timeout
              ├── emits Interrupt event on timeout (no message)
              └── emits EventReceived event on message
                    └── StageServer.onEventReceived dispatches to onEvent<Name>
                          │
                          │   Fast handlers return within one loop iteration.
                          │
                          └── onEventPlay: calls player.play(canvas)  ← BLOCKS
                                └── frame loop runs until done or stopped
```

Only **one connection** is served at a time; netbox's serve loop blocks on each event handler until it returns, then reads the next message from the same connection. A second client's `accept()` doesn't return until the first client disconnects.

---

## Why in-frame polling is necessary

A stop request from the client must be honored while a `play` is in progress. But during a play, the server's serve loop is blocked inside `onEventPlay` → `player.play(canvas)` — no new messages can be dispatched via the normal `EventReceived → onEvent<Name>` path.

Two alternatives were considered and rejected:

| Alternative | Why not |
|-------------|---------|
| Multi-threaded netbox server (separate thread per connection, or a control thread) | Requires rewriting netbox's dispatch loop and introduces thread-safety concerns across MATLAB/Java/OpenGL. High scope; defers the simple feature. |
| Second TCP connection purely for control | netbox's `listen.accept()` is in the main loop; a second connection can't be accepted while serving the first. Requires the same threading rewrite. |

The chosen approach is **in-frame polling**: the player's frame loop calls a stop-check callback once per frame that does a non-blocking read on the connection and dispatches any control events that arrive. See [ADR-0001](../decisions/0001-in-frame-stop-polling.md).

---

## Invariants

1. **Exactly one active connection at a time.** If a second client connects while the first is serving, the second is queued in the OS TCP backlog — Stage won't accept it until the first disconnects. This is currently acceptable because Symphony is the only intended client.
2. **Event handlers run on the main MATLAB thread.** No locking is needed between handlers because they execute serially.
3. **OpenGL calls must happen on the main thread.** All canvas, window, and GLFW calls are made from within event handlers (and the player frame loop, which runs synchronously inside `onEventPlay`). Introducing worker threads would break the OpenGL context assumption.
4. **Frame-loop polling is the only way to deliver messages during a play.** Any event that needs to be handled while a play is in progress (today: `stop`; potentially future: `pause`, `setParameter`, etc.) must be checked via the in-frame polling callback.
5. **Polling must be truly non-blocking.** The poll uses `Connection.hasPendingMessage()` (which calls `InputStream.available()`) to test for waiting data, and only invokes `receiveMessage()` when the answer is yes. Do **not** attempt to simulate a non-blocking read via `setReceiveTimeout(0)` — netbox treats a zero or negative timeout as *infinite*, so that path would hang the frame loop indefinitely whenever no stop message is waiting. See `netbox.Connection.hasPendingMessage` and `netbox.tcp.TcpConnection.hasPendingData`.

---

## Related specs

- [WIRE_PROTOCOL.md](WIRE_PROTOCOL.md) — the events the server knows about
- [PLAYER_LIFECYCLE.md](PLAYER_LIFECYCLE.md) — the frame loop's stop-check responsibility
- [ADR-0001](../decisions/0001-in-frame-stop-polling.md) — the decision record for this design
