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

### `ld: warning: ignoring file '…libglfw.dylib': found architecture 'x86_64', required architecture 'arm64'`

You have Intel Homebrew at `/usr/local/lib/` but MATLAB on Apple Silicon (M1/M2/M3/M4) from R2023b onward is ARM-native and requires ARM-built libraries. Install ARM-native Homebrew side-by-side:

```bash
# 1. Install ARM Homebrew (auto-installs to /opt/homebrew on Apple Silicon)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 2. Follow the installer's "Next steps" to add /opt/homebrew/bin to PATH
#    (it prints two eval lines to append to ~/.zprofile)

# 3. Install GLFW and ffmpeg from the ARM brew
brew install glfw ffmpeg

# 4. Verify the library is arm64
file /opt/homebrew/lib/libglfw.dylib
# expected: "Mach-O 64-bit dynamically linked shared library arm64"
```

Then retry the MEX build. The updated `lib/matlab-glfw3/make.m` uses `computer()` (which returns `'MACA64'` on ARM-native MATLAB) to match the library prefix to MATLAB's architecture — if it finds only a mismatched version it warns loudly up-front instead of letting you discover the issue via 30 identical "undefined symbols" errors.

Check your MATLAB architecture:

```matlab
computer   % 'MACA64' = ARM-native, 'MACI64' = Intel / Rosetta
```

### MATLAB crashes ("Trace trap") when `glfwInit()` is called on macOS 15+

**Fixed 2026-04-23 via TASK-008** — main-thread dispatch wrappers in every `lib/matlab-glfw3/*.c` file. Pull the latest source, rebuild, and run.

Background: MATLAB on macOS runs user code on a worker thread (`MCR 0 interpreter thread`), not the process's main Cocoa thread. GLFW's macOS backend calls Apple's TSM/HIToolbox/Cocoa APIs, and macOS 15 (Sequoia) enforces a hard main-thread-only assertion on those via `dispatch_assert_queue`. The crash showed up with a stack of `_glfwInitCocoa` → `updateUnicodeData` → `TSMGetInputSourceProperty` → `dispatch_assert_queue_fail`.

The fix routes every GLFW call in the MATLAB MEX layer through `dispatch_sync(dispatch_get_main_queue(), ...)` via two helper macros in `lib/matlab-glfw3/glfw_mac_dispatch.h`:

- `GLFW_ON_MAIN({ ...glfw calls... })` — runs the braced block on the main thread (or inline if already on main)
- `GLFW_BLOCK` — a storage-class qualifier (`__block` on clang, empty elsewhere) for locals that receive return values from inside the dispatch

**Requirement**: MATLAB's main thread must be actively draining its Cocoa event loop (a.k.a. the main dispatch queue). This is true in **regular MATLAB desktop mode** (the main thread hosts the MATLAB desktop UI, whose run loop pumps the main queue). It may NOT be true under `matlab -batch` or potentially `matlab -nodesktop` — if you hit a hang on `glfwInit` in those modes, fall back to desktop mode.

If you're on an older checkout and see this crash, `git pull` to get the fix (TASK-008 commits), then rebuild MEX files:

```
cd lib/matlab-glfw3
# In MATLAB:
make(true)
```

See [spec/TASKS.md § TASK-008](../spec/TASKS.md) for the full design rationale.

### MATLAB crashes with segfault in `glewContextInit` on macOS after window opens

**Fixed 2026-04-24 (final design).** OpenGL contexts on macOS are thread-affine. Our main-thread-dispatch fix for GLFW (TASK-008) initially made `glfwMakeContextCurrent` run on the main thread, which bound the GL context there — but `moglcore`'s `mexFunction` runs on MATLAB's MCR interpreter thread by default, where no context was current. First `glGetString(GL_VERSION)` inside `glewContextInit` returned NULL, segfault.

A brief attempt to fix this by dispatching `moglcore.mexFunction` to the main thread too was rejected: MATLAB's MEX runtime asserts that `mexAtExit` and related calls happen on the MCR thread (`findOrFail: no active context for type 'CurrentMexInfoPerMVM'`).

The working design:
- `glfwCreateWindow`, `glfwPollEvents`, `glfwSetGamma`, etc. — calls that touch NSWindow / TSM / Cocoa event loop — **stay dispatched to main thread**.
- `glfwMakeContextCurrent`, `glfwSwapBuffers`, `glfwSwapInterval` — calls that bind or operate on the OpenGL context — **run on the MCR thread** (no dispatch).
- `Window.m` constructor on macOS explicitly calls `glfwMakeContextCurrent(obj.handle)` right after `glfwCreateWindow` returns, to pull the context from the main thread (where `glfwCreateWindow` left it) to the MCR thread (where subsequent MEX-based GL calls will happen).

Net effect: the OpenGL context lives on the MCR thread from then on, matching where `moglcore.mexFunction` runs. No more null glGetString. The main thread handles window events and Cocoa lifecycle; the MCR thread handles rendering.

If you see this crash on an older copy, pull the latest source and rebuild the affected MEX files:

```matlab
cd lib/matlab-glfw3 && make(true)   % picks up the no-dispatch changes to makeCurrent/swap
cd ../MOGL           && make()       % picks up the moglcore revert
```

### `error: incompatible function pointer types passing 'void (GLboolean, void *)'` (MOGL build on macOS)

Clang 16+ (Xcode 15+) made `-Wincompatible-function-pointer-types` an error by default. MOGL's `gl_manual.c` passes typed callbacks to `gluTessCallback`, whose declared signature is the K&R-era `void (*)()`. Historically C accepted this; modern clang rejects it.

Fixed 2026-04-24 in `lib/MOGL/make.m` by demoting it back to a warning on macOS via `CFLAGS=$CFLAGS -Wno-error=incompatible-function-pointer-types`. Stage does not exercise the tessellation code path, so the technically-incompatible call is never made at runtime.

The same commit also silenced the 90+ OpenGL deprecation warnings (`-DGL_SILENCE_DEPRECATION`) and the "comparison of function equal to null pointer" warnings (`-Wno-tautological-pointer-compare`) that arise from MOGL's `if (NULL == glXxx)` null-checks on statically-linked symbols.

If you see this error on an older copy, pull the latest `lib/MOGL/make.m`.

### `fatal error: 'AGL/agl.h' file not found` (MOGL build on macOS)

AGL (Apple Graphics Library) was removed from the macOS SDK in macOS 10.14 (Mojave). MOGL's `mogltypes.h` unconditionally included it under `#ifdef MATLAB_MEX_FILE`, even though AGL is only used in `glm.c` — the optional Psychtoolbox-era GLUT-like module that Stage does not build. Fixed on 2026-04-23 by tightening the guard to `#if defined(MATLAB_MEX_FILE) && defined(BUILD_GLM)`. Stage's build does not set `BUILD_GLM`, so the include is skipped, and the MOGL build compiles on Mojave+.

If you see this error on an older copy of the source, edit `lib/MOGL/source/mogltypes.h` around line 49-51:

```c
/* Before: */
#ifdef MATLAB_MEX_FILE
#include <AGL/agl.h>
#endif

/* After: */
#if defined(MATLAB_MEX_FILE) && defined(BUILD_GLM)
#include <AGL/agl.h>
#endif
```

### `VideoSource_FFmpeg` hangs on Movie open / "ffmpeg on PATH" FAILs in VerifyStage

On macOS, MATLAB launched from Finder, the Dock, or a `.command` file inherits a minimal PATH that does not include `/opt/homebrew/bin` (Apple Silicon Homebrew) or `/usr/local/bin` (Intel Homebrew). So `ffmpeg` installed via `brew install ffmpeg` isn't callable from MATLAB's `system()`, even though it works fine in Terminal.

**Auto-fix (default).** `StartStage` and `VerifyStage` both call `stage.util.ensureFFmpegOnPath()` on the way up. On macOS, if `ffmpeg -version` fails, that helper probes `/opt/homebrew/bin`, `/usr/local/bin`, and `/opt/local/bin` (MacPorts) in order and prepends the first one that has `ffmpeg` to `getenv('PATH')`. You should see a line like:

```
[StartStage] ffmpeg: added /opt/homebrew/bin to PATH
```

After that, `system('ffmpeg -version')` works for the rest of the MATLAB session.

**Manual fixes**, if the auto-fix can't find your ffmpeg (installed somewhere unusual):

1. **Launch MATLAB from Terminal** — inherits your shell PATH.

   ```bash
   open -a MATLAB_R2024b
   ```

2. **Symlink** — create a link at `/usr/local/bin` which macOS's default PATH includes.

   ```bash
   sudo ln -s /opt/homebrew/bin/ffmpeg  /usr/local/bin/ffmpeg
   sudo ln -s /opt/homebrew/bin/ffprobe /usr/local/bin/ffprobe
   ```

3. **Set PATH manually** in MATLAB before calling `StartStage`:

   ```matlab
   setenv('PATH', ['/opt/homebrew/bin:' getenv('PATH')]);
   ```

Check which MATLAB sees by running `system('ffmpeg -version')` at the prompt.

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
