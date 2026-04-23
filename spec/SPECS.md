# Stage — Specifications Manifest

Normative specifications for the Stage visual stimulus presenter.

## Wire protocol & runtime contracts

| Spec | Scope | Status |
|------|-------|--------|
| [WIRE_PROTOCOL.md](specs/WIRE_PROTOCOL.md) | netbox event names, request/response formats, stop semantics | Draft |
| [PLAYER_LIFECYCLE.md](specs/PLAYER_LIFECYCLE.md) | Player construction, frame loop, stop-request handling, PlayInfo | Draft |
| [SERVER_MODEL.md](specs/SERVER_MODEL.md) | Single-connection threading model, in-frame message polling | Draft |
| `MONITOR_TIMING.md` *(not yet written — part of TASK-002)* | Refresh-rate measurement procedure; `Monitor.refreshRate` accuracy invariant | Planned |

## Status key

| Status | Meaning |
|--------|---------|
| **Stable** | Frozen contract; breaking changes require an ADR + version bump |
| **Draft** | Documented but may change without notice |
| **Proposed** | Under discussion; not authoritative |

## Cross-cutting invariants

1. **Symphony is the sole client.** Stage supports exactly one active client connection at a time; netbox serves connections sequentially.
2. **Play is asynchronous.** The server responds `'ok'` to `play` immediately (before rendering starts); the client retrieves the result later via `getPlayInfo`.
3. **The frame loop owns real-time control of the connection.** While `player.play()` is running, the main server message loop is blocked. Any control message the server needs to respond to during a play must be polled from within the frame loop.
4. **PlayInfo always returns a struct.** Even on early termination (stop, error), `getPlayInfo` returns a struct with at minimum `flipDurations` and `stopped`. Callers should not assume absence of fields.
