@echo off
REM StartStage.bat — launch the Stage testbed source tree in MATLAB.
REM
REM All paths are relative to the location of this .bat file, so you can
REM move the stage_testbed folder anywhere without editing this script.
REM
REM What it does:
REM   1. Sets MATLAB's starting directory to this testbed root.
REM   2. Runs `StartStage` (StartStage.m in this directory), which adds the
REM      source tree's subdirectories to the MATLAB path and calls
REM      apps/stage-server/src/main/matlab/main.m.
REM
REM Requirements:
REM   - MATLAB R2019b or newer (for the -sd flag).
REM   - If a specific MATLAB version isn't found on PATH, set MATLAB_EXE
REM     below to the full path, e.g. "C:\Program Files\MATLAB\R2024b\bin\matlab.exe".
REM
REM IMPORTANT: Uninstall the "Stage Server" Add-On from MATLAB first, otherwise
REM its bundled paths will shadow the testbed source. StartStage.m warns if it
REM detects the installed Add-On.
REM
REM Usage:
REM   StartStage.bat             — UI mode (classic stage-server UI;
REM                                emits Java deprecation warnings)
REM   StartStage.bat headless    — headless mode (no MATLAB UI; starts
REM                                the server directly with defaults)
REM
REM Headless mode is the recommended developer flow while we work on the
REM server / player / wire-protocol code. The UI is scheduled for porting
REM off Java Swing — see spec/PLAN.md → "UI modernization".

setlocal

set "ROOT=%~dp0"
REM Trim trailing backslash so MATLAB's -sd flag gets a clean path
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

REM Override MATLAB_EXE if matlab.exe isn't on PATH
set "MATLAB_EXE=matlab"

REM First CLI argument, if any, selects the mode — pass it through as a
REM MATLAB string literal. No args -> classic UI mode.
set "MODE=%~1"
if "%MODE%"=="" (
    set "LAUNCH_CMD=StartStage"
) else (
    set "LAUNCH_CMD=StartStage('%MODE%')"
)

echo Starting Stage testbed from: %ROOT%
echo Mode: %LAUNCH_CMD%
echo.

"%MATLAB_EXE%" -sd "%ROOT%" -nosplash -nodesktop -r "%LAUNCH_CMD%"

endlocal
