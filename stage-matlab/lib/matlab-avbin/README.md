# matlab-avbin

Video decoding for `stage.builtin.stimuli.Movie`.

## Files

- **`VideoSource.m`** — AVbin-backed. Still present but **no longer the active backend**. Kept for rollback during the cross-platform migration.
- **`VideoSource_FFmpeg.m`** — **Active backend as of 2026-04-23.** ffmpeg-subprocess-based, cross-platform, no MEX dependencies. Used by `Movie.m` via the one-line swap `source = VideoSource_FFmpeg(obj.filename)`.
- **`VideoPlayer.m`** — Wraps a source with a playback-speed clock. Unchanged.
- **`VideoBuffer.m`** — FIFO frame buffer used for preload + peek. Added a `clear()` method for seek support on 2026-04-23.
- **`PlaybackSpeed.m`** — Enum (NORMAL, FRAME_BY_FRAME, numeric multiplier). Unchanged.
- **`TestVideoSource_FFmpeg.m`** — A/B test harness comparing the two backends.
- **`VideoSource_VideoReader.m.disabled`** — Early, ruled-out attempt at a MATLAB `VideoReader`-based backend (fails on MPEG-4 ASP, and Media Foundation H.264 wasn't registered on the test rig). Header documents the investigation.

## Backend status

| Backend | Status | Platforms |
|---|---|---|
| AVbin | retired 2026-04-23 (file kept for rollback) | Windows only |
| **ffmpeg subprocess** | **active** | Windows, macOS, Linux (ffmpeg install required) |
| MATLAB `VideoReader` | ruled out 2026-04-23 | Fails on this rig's codec setup |

## ffmpeg install

Required for the active backend. Once per rig:

- Windows: `winget install Gyan.FFmpeg` (or download from gyan.dev)
- macOS: `brew install ffmpeg`
- Linux: `apt install ffmpeg`

## Reverting to AVbin (Windows only, troubleshooting)

Edit `src/main/matlab/+stage/+builtin/+stimuli/Movie.m`, change:

```matlab
source = VideoSource_FFmpeg(obj.filename);
```

to:

```matlab
source = VideoSource(obj.filename);
```

Restart Stage. AVbin MEX files and the original `VideoSource.m` are still in this directory.

## Known AVbin bug (pre-existing, not introduced by migration)

Direct calls to `VideoSource.nextImage()` in a loop return the same pixel content on every call after the first. Timestamp advances correctly, pixels don't. `VideoPlayer`-driven access (via `nextTimestamp` + buffered `getImage`) happens to dodge this bug, which is why Movie worked in production despite the bug being present. Tracked in `spec/TASKS.md` § TASK-006 as a side finding; becomes irrelevant once AVbin is deleted entirely in TASK-005 Phase 5.

## Testing the ffmpeg backend in isolation

From a **fresh MATLAB session** (not Stage, not Symphony):

```matlab
addpath('C:\Users\dev\Documents\Symphony3\stage_testbed\lib\matlab-avbin')
TestVideoSource_FFmpeg('C:\path\to\any\movie.mp4')
```

Reports cold-start latency, pixel fidelity vs AVbin, steady-state throughput, and seek latency.

## License

MIT.
