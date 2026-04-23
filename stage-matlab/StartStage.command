#!/usr/bin/env bash
# StartStage.command — launch the Stage testbed source tree in MATLAB (macOS).
#
# The `.command` extension makes this file double-clickable in Finder.
# Double-clicking opens a Terminal window, runs this script in it, and
# leaves the window open when MATLAB exits so error messages remain
# visible. To run from a terminal instead: `./StartStage.command`.
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
#     Typical macOS install:
#       /Applications/MATLAB_R2024b.app/bin/matlab
#   - glfw3 installed: `brew install glfw`.
#   - ffmpeg + ffprobe installed for Movie stimuli: `brew install ffmpeg`.
#   - The MEX binaries for macOS must be built locally before first use:
#       cd lib/matlab-glfw3    && matlab -batch "make(true)"
#       cd lib/matlab-priority && matlab -batch "make(true)"
#       cd lib/MOGL            && matlab -batch "make()"
#         (MOGL's make takes no arguments; the other two accept a 'rebuild' flag.)
#     See spec/TASKS.md § TASK-005 Phase 2.
#
# Make this script executable (once, after checkout):
#   chmod +x StartStage.command
#
# Usage (from terminal):
#   ./StartStage.command             — UI mode (Java deprecation warnings;
#                                      see TASK-004).
#   ./StartStage.command headless    — headless mode (no MATLAB UI).
#
# From Finder: double-click the file. (Passes no args — equivalent to
# UI mode. For headless, run from a terminal.)
#
# Override MATLAB location:
#   MATLAB_EXE=/Applications/MATLAB_R2024b.app/bin/matlab ./StartStage.command

set -e

# Resolve the directory containing this script (absolute path).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default MATLAB_EXE. Try PATH, then common macOS install paths.
if [ -z "${MATLAB_EXE:-}" ]; then
    if command -v matlab >/dev/null 2>&1; then
        MATLAB_EXE="matlab"
    else
        # Look for the newest MATLAB_Rxxxx.app in /Applications.
        for candidate in /Applications/MATLAB_R2*.app/bin/matlab; do
            if [ -x "$candidate" ]; then
                MATLAB_EXE="$candidate"
            fi
        done
    fi
fi

if [ -z "${MATLAB_EXE:-}" ] || ! command -v "$MATLAB_EXE" >/dev/null 2>&1; then
    echo "Error: MATLAB not found." >&2
    echo "Set MATLAB_EXE to the full path, e.g.:" >&2
    echo "  MATLAB_EXE=/Applications/MATLAB_R2024b.app/bin/matlab $0" >&2
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
echo "MATLAB: $MATLAB_EXE"
echo

exec "$MATLAB_EXE" -sd "$ROOT" -nosplash -nodesktop -r "$LAUNCH_CMD"
