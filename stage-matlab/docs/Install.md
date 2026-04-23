# Installing Stage

This guide walks you through installing the Stage testbed on Windows, macOS, and Linux. It covers prerequisites, building the MEX binaries, verifying the install, and running the server.

## Contents

- [Prerequisites (all OSs)](#prerequisites-all-oss)
- [Windows](#windows)
- [macOS](#macos)
- [Linux (Ubuntu / Debian)](#linux-ubuntu--debian)
- [Building the MEX binaries](#building-the-mex-binaries)
- [Verifying the install](#verifying-the-install)
- [Running Stage](#running-stage)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites (all OSs)

- **MATLAB R2019b or newer** (R2024b is the main development target). The `-sd` flag used by the launcher scripts was added in R2019b.
- A **C compiler** that MATLAB recognizes. Run `mex -setup c` from the MATLAB command window to pick one. On Windows this is usually MinGW-w64 (installed via the Add-On Manager); on macOS it's Apple's Command Line Tools; on Linux it's `gcc` from your distro.
- Enough disk space for the source tree (~200 MB with dependencies).

### What Stage needs at runtime

1. **GLFW 3.x** — window management, OpenGL context, vsync. Native library.
2. **OpenGL 3.3+** — for rendering. Provided by the OS/GPU driver.
3. **FFmpeg + FFprobe** — for `stage.builtin.stimuli.Movie`. Invoked as subprocesses; no linking, just `PATH`.
4. **X11 display** (Linux) or an active window server (macOS / Windows). Headless server environments without a display require a virtual X server (Xvfb, etc.) and are not officially supported.

Everything else — the MEX bindings, MOGL, netbox — is in the source tree.

---

## Windows

### 1. Install MATLAB

Standard install. MinGW-w64 compiler add-on recommended — install via HOME → Add-Ons → Get Add-Ons → search "MinGW".

### 2. Install FFmpeg

From an elevated PowerShell or Command Prompt:

```
winget install Gyan.FFmpeg
```

Close and reopen your terminal so `PATH` picks up ffmpeg. Verify:

```
ffmpeg -version
ffprobe -version
```

### 3. Get the source

Clone or copy the `stage_testbed` folder anywhere. The launcher scripts resolve their own directory, so no path editing is required.

### 4. Build MEX binaries

Most Windows users will find pre-built `.mexw64` files already in the lib directories. If they're present, you can skip this step.

To rebuild from source:

```
cd lib\matlab-glfw3    && matlab -batch "make(true)"
cd ..\matlab-priority  && matlab -batch "make(true)"
cd ..\MOGL             && matlab -batch "make()"
cd ..\..
```

MOGL's Windows build expects the bundled freeglut in `lib/MOGL/freeglut/`, which ships with the repo.

### 5. Run

Double-click `StartStage.bat` in the repo root, or from a terminal:

```
StartStage.bat              REM default uifigure UI
StartStage.bat headless     REM no UI, server starts immediately
StartStage.bat legacy       REM old Swing UI (for comparison; will be removed)
```

---

## macOS

### 1. Install MATLAB

Standard install from MathWorks. Note the install path — typically `/Applications/MATLAB_R2024b.app`. The launcher script auto-detects this pattern, but you can override with the `MATLAB_EXE` environment variable.

Install Apple Command Line Tools if you haven't already:

```
xcode-select --install
```

Then in MATLAB: `mex -setup c` to confirm the compiler is wired up.

### 2. Install GLFW and FFmpeg

[Homebrew](https://brew.sh/) is the easiest source:

```
brew install glfw ffmpeg
```

Verify:

```
ffmpeg -version
ffprobe -version
pkg-config --modversion glfw3
```

### 3. Get the source

Clone or copy the `stage_testbed` folder anywhere.

### 4. Build MEX binaries

```
cd lib/matlab-glfw3    && matlab -batch "make(true)"
cd ../matlab-priority  && matlab -batch "make(true)"
cd ../MOGL             && matlab -batch "make()"
cd ../..
```

This produces `.mexmaci64` (Intel Macs) or `.mexmaca64` (Apple Silicon) files in each directory.

### 5. Make the launcher executable (once)

```
chmod +x StartStage.command
```

### 6. Run

Double-click `StartStage.command` in Finder, or from a terminal:

```
./StartStage.command            # default uifigure UI
./StartStage.command headless   # no UI, server starts immediately
./StartStage.command legacy     # old Swing UI
```

To override the MATLAB location:

```
MATLAB_EXE=/Applications/MATLAB_R2024b.app/bin/matlab ./StartStage.command
```

### macOS notes

- OpenGL on macOS is frozen at version 4.1 and has been deprecated by Apple. Stage's rendering (vertex + fragment shaders only, no compute) works fine at 4.1. If a future macOS release removes OpenGL entirely we'll need Metal; not an issue today.
- Fullscreen on macOS uses the WindowServer; there's no equivalent of Windows' DWM-disable hack. For tear-free output, make sure the monitor is set to "Separate Displays" rather than mirrored.

---

## Linux (Ubuntu / Debian)

Tested on Ubuntu 22.04 LTS. Other distros work with equivalent package names.

### 1. Install MATLAB

Standard install. MATLAB should be on `PATH`; if not, `MATLAB_EXE` can override. Typical install paths:

- `/usr/local/MATLAB/R2024b/bin/matlab`
- `/opt/MATLAB/R2024b/bin/matlab`

Confirm the compiler: `mex -setup c` — on Ubuntu this is usually `gcc` from `build-essential`.

```
sudo apt install build-essential
```

### 2. Install runtime dependencies

```
sudo apt install libglfw3-dev \
                 libglew-dev libglu1-mesa-dev freeglut3-dev mesa-common-dev \
                 libx11-dev libxext-dev libxrandr-dev libxi-dev libxxf86vm-dev \
                 ffmpeg
```

Breakdown:

| Package | What it provides |
|---|---|
| `libglfw3-dev` | GLFW library + headers — for `lib/matlab-glfw3` |
| `libglew-dev` | GLEW — OpenGL extension loader, for `lib/MOGL` |
| `libglu1-mesa-dev` | `GL/glu.h` + `-lGLU` |
| `freeglut3-dev` | `GL/glut.h` + `-lglut` |
| `mesa-common-dev` | `GL/gl.h` + core OpenGL |
| `libx11-dev` | X11 core |
| `libxext-dev`, `libxrandr-dev`, `libxi-dev`, `libxxf86vm-dev` | X11 extensions required by GLEW / GLFW / GLUT |
| `ffmpeg` | `ffmpeg` and `ffprobe` binaries for the Movie stimulus |

Verify:

```
ffmpeg -version
ffprobe -version
dpkg -l | grep -E 'libglfw3-dev|libglew-dev' | head
```

### 3. Get the source

Clone or copy the `stage_testbed` folder anywhere.

### 4. Build MEX binaries

```
cd lib/matlab-glfw3    && matlab -batch "make(true)"
cd ../matlab-priority  && matlab -batch "make(true)"
cd ../MOGL             && matlab -batch "make()"
cd ../..
```

Produces `.mexa64` files.

### 5. Make the launcher executable (once)

```
chmod +x StartStage.sh
```

### 6. Run

```
./StartStage.sh             # default uifigure UI
./StartStage.sh headless    # no UI, server starts immediately
./StartStage.sh legacy      # old Swing UI
```

Override MATLAB location:

```
MATLAB_EXE=/usr/local/MATLAB/R2024b/bin/matlab ./StartStage.sh
```

### Linux notes

- **SCHED_FIFO needs CAP_SYS_NICE** or running as root for `setMaxPriority()` to take effect. Most research rigs run as root. On a laptop without privileges, `setMaxPriority()` falls back to `nice(-20)`; if even that fails, the MEX returns an error and the player catches it and continues without RT boost. Timing may jitter slightly under load but acquisition continues.
- **Wayland compositors may cap swap rate** to the compositor's refresh rate (often 60 Hz) even on faster panels. If your panel is >60 Hz and Stage reports 60 Hz, log out and log in under an Xorg session (available from the login screen's gear icon on Ubuntu Gnome).

---

## Building the MEX binaries

Summary table — exact commands per OS already covered above.

| Directory | Signature | Argument |
|---|---|---|
| `lib/matlab-glfw3`    | `make(rebuild)` | `true` forces rebuild; `false` (default) rebuilds only stale files |
| `lib/matlab-priority` | `make(rebuild)` | same |
| `lib/MOGL`            | `make()`        | no argument; always rebuilds the single target |

**Do not build** `lib/matlab-avbin/make.m`. That's the old AVbin MEX, which requires the abandoned AVbin library and is no longer used. The Movie stimulus now uses `VideoSource_FFmpeg` which is pure MATLAB + an ffmpeg subprocess.

---

## Verifying the install

A `VerifyStage.m` script at the repo root runs seven self-checks in increasing scope: path setup → MEX loading → GLFW init → Monitor enumeration → priority MEXes → FFmpeg on PATH → Java subprocess I/O sanity.

```matlab
StartStage           % or addpath the lib/ and src/main/matlab/ dirs manually
% Close the UI if it appears — you just wanted the paths set up.
VerifyStage
```

Output looks like:

```
================================================
 VerifyStage — cross-platform bring-up self-test
================================================

  [PASS] Path setup (stage.core available)
  [PASS] MEX: glfwInit available
  [PASS] MEX: setMaxPriority available
  [PASS] MEX: InitializeMatlabOpenGL available (MOGL)
  [PASS] GLFW init
  [PASS] GLFW enumerate monitors
         → (found 2 monitor(s))
  [PASS] Monitor.refreshRate (default/integer)
         → (got 60 Hz)
  [PASS] setMaxPriority() succeeded
  [PASS] setNormalPriority() succeeded
  [PASS] ffmpeg on PATH
  [PASS] ffprobe on PATH
  [PASS] ffmpeg subprocess I/O sanity

------------------------------------------------
 ALL 12 CHECKS PASSED.
------------------------------------------------
```

If anything `FAIL`s, the script prints an actionable next step right beneath the failure.

---

## Running Stage

### UI mode (default)

```
./StartStage.sh                  # Linux
./StartStage.command             # macOS
StartStage.bat                   # Windows
```

Opens a small config window. Set width/height/monitor/fullscreen/port, click **Start**. The Stage window appears; once it's active, shift+escape (with focus on the Stage window) exits.

### Headless mode

```
./StartStage.sh headless
./StartStage.command headless
StartStage.bat headless
```

Skips the UI entirely. Server starts on port 5678 with defaults (640x480, fullscreen, monitor 1). You can override from the MATLAB side if needed:

```matlab
StartStage('headless', 'port', 9999, 'size', [1280 720], 'fullscreen', false, 'monitor', 2)
```

### Legacy Swing UI

```
./StartStage.sh legacy
```

Runs the old pre-uifigure UI for comparison during the TASK-004 migration period. Emits MATLAB Java deprecation warnings; will be removed entirely after the new UI is validated on all OSs.

---

## Troubleshooting

### "MATLAB not found as 'matlab'"

The launcher couldn't find MATLAB on `PATH`. Set `MATLAB_EXE` to the full path:

```
MATLAB_EXE=/opt/MATLAB/R2024b/bin/matlab ./StartStage.sh
```

Or on Windows, edit `StartStage.bat` and set `MATLAB_EXE` to a full path like `"C:\Program Files\MATLAB\R2024b\bin\matlab.exe"`.

### "Error using make / Too many input arguments"

You're calling `make.m` with an argument that one specific `make` doesn't accept. The rule:

- `lib/matlab-glfw3` and `lib/matlab-priority`: `make(true)`
- `lib/MOGL`: `make()` (no argument)

### "fatal error: GL/*.h: No such file or directory"

A missing OpenGL / X11 dev header on Linux. See the step 2 Linux install command for the full list. The most common missing packages:

- `GL/glu.h` → `sudo apt install libglu1-mesa-dev`
- `GL/glew.h` → `sudo apt install libglew-dev`
- `GL/glut.h` → `sudo apt install freeglut3-dev`
- `GL/gl.h` → `sudo apt install mesa-common-dev`

### "'TRUE' undeclared" on Linux (MOGL build)

Historically `moglcore.c` assigned `glewExperimental = TRUE;`, where `TRUE` is defined by `<windows.h>` on Windows and by Cocoa headers on macOS but isn't defined anywhere on Linux. Fixed in-tree on 2026-04-23 by changing to `GL_TRUE` (provided by `<GL/gl.h>` on every platform). If you see this error with a fresh checkout, pull the latest source; if for some reason you're on an old copy, edit `lib/MOGL/source/moglcore.c` line ~191 to read `glewExperimental = GL_TRUE;`.

### "Error building 'glfwXXX.c'" on macOS (matlab-glfw3)

The build script silently told you the target failed but not *why* — fixed on 2026-04-23 by surfacing `ex.message`. Common real causes (which the updated script now prints):

- **`fatal error: 'GLFW/glfw3.h' file not found`** → GLFW isn't installed. `brew install glfw`.
- **`ld: library 'glfw' not found`** → GLFW installed but MEX couldn't locate it. Most common on Apple Silicon Macs (M1–M4), where Homebrew's prefix is `/opt/homebrew`, not `/usr/local`. The updated `make.m` auto-detects ARM vs Intel. If yours doesn't, set the override:

  ```matlab
  setenv('GLFW_PREFIX', '/opt/homebrew');   % or wherever `brew --prefix` reports
  cd lib/matlab-glfw3
  make(true)
  ```

### "mexopts.sh is not a valid XML file" (MOGL build)

Old MOGL `make.m` passed `-f ../mexopts.sh`, a pre-R2014 MEX options file. Modern MATLAB rejects it as "not valid XML". Fixed on 2026-04-23 by removing the `-f` flag entirely — MATLAB's default mex options plus the explicit `-DMACOSX -DGLEW_STATIC` etc. are sufficient. If you see this error, pull the latest `lib/MOGL/make.m`.

### MOGL macOS build fails on Apple Silicon

Until 2026-04-23 the MOGL macOS branch passed `-I/usr/include` (the Intel-era Homebrew include path). On Apple Silicon Macs the Homebrew include path is `/opt/homebrew/include`. The updated `make.m` auto-detects which directory exists.

### `VideoSource_FFmpeg` hangs on Movie open

Almost certainly ffmpeg not on `PATH` in the Stage MATLAB session — even if it's on `PATH` in your shell. On macOS, launching MATLAB from the Dock gives it a minimal environment without Homebrew's PATH. Two fixes:

1. Launch MATLAB from a terminal that has `ffmpeg` on `PATH`: `open -a MATLAB_R2024b` after `brew install ffmpeg`.
2. Symlink ffmpeg into a globally-visible location: `sudo ln -s /opt/homebrew/bin/ffmpeg /usr/local/bin/ffmpeg` (Apple Silicon paths may differ).

Check by running `system('ffmpeg -version')` in the Stage MATLAB command window.

### Movie stimulus shows a black frame

The Movie was loaded but decoded bytes didn't arrive. This was a real issue during development that is now resolved; if you see it again, check:

1. Does `VerifyStage` report all checks pass? If ffmpeg subprocess I/O fails there, it'll fail for Movie too.
2. Does `TestVideoSource_FFmpeg('<your-movie.mp4>')` (in `lib/matlab-avbin/`) produce a non-black first frame?

If (1) passes and (2) produces a correct PNG at `%TEMP%/TestVideoSource_FFmpeg/frame1_ffmpeg.png`, the Movie path should work. If not, paste the `TestVideoSource_FFmpeg` output and I'll debug.

### `setMaxPriority()` errors on Linux

Normal on systems without `CAP_SYS_NICE`. The error is caught by the player, acquisition continues without the real-time boost. To eliminate the warning, run as root (research rigs) or set the capability:

```
sudo setcap cap_sys_nice=eip /opt/MATLAB/R2024b/bin/glnxa64/MATLAB
```

### No window appears on Linux

If you're ssh'd into a remote machine or running without a display, Stage can't create a fullscreen window. Options:

1. Run locally with an actual display.
2. Set up X-forwarding (`ssh -X`) — slow but works for testing.
3. Run under a virtual framebuffer: `xvfb-run matlab -batch "StartStage('headless')"`. Not recommended for real acquisition because vsync timing is unreliable on a virtual framebuffer.

---

## Related

- [spec/decisions/0002-cross-platform-direction.md](../spec/decisions/0002-cross-platform-direction.md) — why the cross-platform approach is what it is
- [spec/TASKS.md § TASK-005](../spec/TASKS.md) — cross-platform task status
- [spec/TASKS.md § TASK-006](../spec/TASKS.md) — video backend migration from AVbin to ffmpeg
- [spec/specs/MONITOR_TIMING.md](../spec/specs/MONITOR_TIMING.md) — how the empirical refresh-rate measurement works
- [lib/matlab-avbin/README.md](../lib/matlab-avbin/README.md) — Movie / video backend details
