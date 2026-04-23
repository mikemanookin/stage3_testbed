# Stage Wire Protocol

**Status:** Draft
**Transport:** TCP, default port 5678
**Framing:** Java `ObjectOutputStream`/`ObjectInputStream` via netbox
**Message type:** `netbox.NetEvent(name, arguments)` — `name` is a string, `arguments` is a cell array (or a single value)

---

## Request / response pattern

Every client request produces exactly one server response, either:

- `NetEvent('ok', <result>)` — success; `result` is a single value or cell array
- `NetEvent('error', MException)` — failure; the exception is rethrown on the client side

---

## Control events (fast, synchronous)

These complete within one serve-loop iteration. The client's `sendReceive` blocks until the response arrives.

| Event name | Arguments | Response on success |
|------------|-----------|---------------------|
| `getCanvasSize` | — | `ok, [w h]` |
| `setCanvasProjectionIdentity` | — | `ok` |
| `setCanvasProjectionTranslate` | `{x, y, z}` | `ok` |
| `setCanvasProjectionOrthographic` | `{left, right, bottom, top}` | `ok` |
| `resetCanvasProjection` | — | `ok` |
| `setCanvasRenderer` | `{renderer}` | `ok` |
| `resetCanvasRenderer` | — | `ok` |
| `getMonitorRefreshRate` | — | `ok, refreshRate` |
| `getMonitorResolution` | — | `ok, [w h]` |
| `setMonitorGamma` | `{gamma}` | `ok` |
| `getMonitorGammaRamp` | — | `ok, {red, green, blue}` |
| `setMonitorGammaRamp` | `{red, green, blue}` | `ok` |
| `clearMemory` | — | `ok` |

---

## Play lifecycle events

The play lifecycle is intentionally asynchronous. `play` acknowledges immediately and starts rendering; `getPlayInfo` retrieves the result after rendering ends.

### `play`
- **Arguments:** `{player}` — a serialized `stage.core.Player` subclass
- **Response:** `ok` — sent **before** the frame loop begins
- **Side effect:** server stores the player on the connection and begins `player.play(canvas)`; the server's main serve loop is blocked until `play()` returns. Incoming events are polled from *inside* the frame loop — see [SERVER_MODEL.md](SERVER_MODEL.md#in-frame-polling).

### `replay`
- **Arguments:** — (none)
- **Response:** `ok` — sent before the frame loop begins
- **Side effect:** re-runs the player most recently sent via `play`; errors if no player has been stored yet.

### `getPlayInfo`
- **Arguments:** — (none)
- **Response:** `ok, info` — `info` is the struct returned by the most recent `play()`/`replay()` call (or an exception if the play threw). Always has `flipDurations` and `stopped` fields — see [PLAYER_LIFECYCLE.md](PLAYER_LIFECYCLE.md#playinfo-schema).
- **Timing:** if the play is still in progress, the server blocks the response until the play completes.

### `stop`
- **Arguments:** — (none)
- **Response:** `ok` — sent **from within the frame loop** as soon as the stop event is polled
- **Side effect:** sets `stopRequested = true` on the currently-running player. The frame loop breaks on its next iteration. `PlayInfo.stopped` will be `true` for that play.
- **Error cases:**
  - No play is currently running → `error, MException('stage:stop:noActivePlay', ...)`
  - The player doesn't support stop (all current players do, but future ones may not) → `error, MException('stage:stop:unsupported', ...)`

---

## Invariants

1. **Every request gets exactly one response.** Requests and responses are serialized per connection; the client's `sendReceive` is built on this 1:1 pairing.
2. **`play` and `replay` respond before they render.** This is required for the client's async / polling pattern; existing clients depend on it.
3. **`stop` responds before the frame loop exits.** The response is emitted the instant the stop event is polled from inside the loop; the actual frame-loop termination happens on the next iteration after response.
4. **`getPlayInfo` always waits for a complete `PlayInfo`.** Never returns a half-built struct. The server stores info only after `play()` returns control.
5. **Unknown events yield `error`, not a crash.** The top-level `onEventReceived` switch-statement's `otherwise` branch throws a clear error back to the client.
