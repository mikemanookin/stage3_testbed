#!/usr/bin/env bash
# StartStage.sh — launch the Stage testbed source tree in MATLAB (Linux).
#
# All paths are relative to the location of this script, so you can move
# the stage_testbed folder anywhere without editing this file.
#
# What it does:
#   1. Sets MATLAB's starting directory to this testbed root.
#   2. Runs `StartStage` (StartStage.m), which adds the source tree's
#      subdirectories to the MATLAB path and calls
#      apps/stage-server/src/main/matlab/main.m.
#
# Requirements:
#   - MATLAB R2019b or newer (for the -sd flag).
#   - `matlab` on PATH, OR export MATLAB_EXE=/absolute/path/to/matlab.
#     Common locations:
#       /usr/local/MATLAB/R2024b/bin/matlab
#       /opt/MATLAB/R2024b/bin/matlab
#   - X11 display (or Wayland with XWayland) — Stage renders OpenGL via
#     GLFW which needs a display server. For headless HPC / CI, see
#     spec/TASKS.md (no supported story yet).
#   - glfw3 installed: `sudo apt install libglfw3-dev` (or equivalent).
#   - ffmpeg + ffprobe installed for Movie stimuli:
#       `sudo apt install ffmpeg`.
#   - The MEX binaries for Linux must be built locally before first use:
#       cd lib/matlab-glfw3    && matlab -batch "make(true)"
#       cd lib/matlab-priority && matlab -batch "make(true)"
#       cd lib/MOGL            && matlab -batch "make()"
#         (MOGL's make takes no arguments; the other two accept a 'rebuild' flag.)
#     MOGL also needs, on Ubuntu: libglew-dev libglu1-mesa-dev freeglut3-dev
#                                 libx11-dev libxext-dev libxrandr-dev libxi-dev
#                                 libxxf86vm-dev
#     See spec/TASKS.md § TASK-005 Phase 2.
#
# Make this script executable (once, after checkout):
#   chmod +x StartStage.sh
#
# Usage:
#   ./StartStage.sh             — UI mode (Java deprecation warnings;
#                                 see TASK-004).
#   ./StartStage.sh headless    — headless mode (no MATLAB UI).
#
# Override MATLAB location:
#   MATLAB_EXE=/usr/local/MATLAB/R2024b/bin/matlab ./StartStage.sh

set -e

# Resolve the directory containing this script (absolute path).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MATLAB_EXE="${MATLAB_EXE:-matlab}"

if ! command -v "$MATLAB_EXE" >/dev/null 2>&1; then
    echo "Error: MATLAB not found as '$MATLAB_EXE'." >&2
    echo "Set MATLAB_EXE to the full path, e.g.:" >&2
    echo "  MATLAB_EXE=/usr/local/MATLAB/R2024b/bin/matlab $0" >&2
    exit 1
fi

# First CLI argument, if any, selects the mode. No arg -> classic UI mode.
MODE="${1:-}"
if [ -z "$MODE" ]; then
    LAUNCH_CMD="StartStage"
else
    LAUNCH_CMD="StartStage('$MODE')"
fi

echo "Starting Stage testbed from: $ROOT"
echo "Mode: $LAUNCH_CMD"
echo

exec "$MATLAB_EXE" -sd "$ROOT" -nosplash -nodesktop -r "$LAUNCH_CMD"
