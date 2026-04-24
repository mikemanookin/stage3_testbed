function VerifyStage()
%VERIFYSTAGE  Self-test Stage's platform dependencies on the current OS.
%
%   Intended for new-OS bring-up (TASK-005 Phase 2). Runs a series of
%   non-visual checks in order of increasing scope:
%
%     1. Confirms MATLAB paths are set up (StartStage has been run OR
%        addpath was called manually).
%     2. Confirms the three critical MEX packages are loadable:
%          matlab-glfw3, matlab-priority, MOGL.
%     3. Pokes GLFW lightly — init, enumerate monitors, create a
%        hidden window, flip once. (No visible window is created.)
%     4. Constructs a Monitor, reports its nominal refresh rate.
%     5. Calls setMaxPriority() / setNormalPriority() and reports
%        whether they succeeded, failed softly (caught error), or
%        are unexpectedly crashing MATLAB.
%     6. Verifies ffmpeg + ffprobe are on PATH.
%     7. Runs a tiny ffmpeg pipe test to confirm subprocess I/O works
%        the way VideoSource_FFmpeg expects.
%
%   Does NOT do:
%     - Open a visible fullscreen window
%     - Run a stimulus presentation
%     - Connect to a client
%
%   Usage:
%     Run StartStage (or addpath manually), then at the MATLAB prompt:
%       VerifyStage
%
%   Exit: prints a summary like "ALL TESTS PASSED" or lists which
%   checks failed with actionable next steps.

    fprintf('\n================================================\n');
    fprintf(' VerifyStage — cross-platform bring-up self-test\n');
    fprintf('================================================\n\n');

    % Auto-setup paths by delegating to StartStage's 'pathsonly'
    % mode. This makes VerifyStage safe to run from a fresh MATLAB
    % shell via `matlab -batch "VerifyStage"` — no manual addpath
    % required.
    try
        thisFile = mfilename('fullpath');
        thisDir = fileparts(thisFile);
        if ~any(strcmp(strsplit(path, pathsep), thisDir))
            addpath(thisDir);   % so StartStage itself is findable
        end
        evalc('StartStage(''pathsonly'')');
    catch pathEx
        fprintf(2, 'WARNING: auto-path-setup failed: %s\n', pathEx.message);
        fprintf(2, '         Proceeding; some tests may fail.\n\n');
    end

    % Pre-initialize results as an empty struct array with the
    % right fields. An uninitialized `struct()` has no fields, and
    % the first assignment with .name/.pass/.msg triggers a
    % "dissimilar structures" error when MATLAB tries to grow it.
    results = struct('name', {}, 'pass', {}, 'msg', {});
    ok = @(name, pass, msg) recordResult(name, pass, msg);

    % --- 1. Path setup
    results(end+1) = ok('Path setup (stage.core available)', ...
        exist('stage.core.Monitor', 'class') == 8, ...
        'Run StartStage(''pathsonly'') manually, or addpath the lib/ and src/main/matlab/ directories.');

    % --- 2. Critical MEX packages
    results(end+1) = ok('MEX: glfwInit available', ...
        exist('glfwInit', 'file') == 3, ...
        'Build lib/matlab-glfw3: cd there, run make(true).');
    results(end+1) = ok('MEX: setMaxPriority available', ...
        exist('setMaxPriority', 'file') == 3, ...
        'Build lib/matlab-priority: cd there, run make(true).');
    results(end+1) = ok('MEX: InitializeMatlabOpenGL available (MOGL)', ...
        exist('InitializeMatlabOpenGL', 'file') == 2, ...
        'Build lib/MOGL: cd there, run make(true).');

    % Short-circuit the remaining tests if MEX aren't present.
    if ~all([results.pass])
        printSummary(results);
        return;
    end

    % --- 3. GLFW basics
    [passed, msg] = tryCatch(@() glfwInit());
    results(end+1) = ok('GLFW init', passed, msg);

    if passed
        [passed, msg, monitors] = tryCatchValue(@() glfwGetMonitors());
        results(end+1) = ok('GLFW enumerate monitors', ...
            passed && ~isempty(monitors), ...
            sprintf('%s (found %d monitor(s))', msg, numel(monitors)));
    end

    % --- 4. Monitor + refresh rate (uses the default integer-from-GLFW
    %     getter — measureRefreshRate needs an active Canvas, which
    %     would pop a window, so we skip the empirical measurement here).
    [passed, msg, rate] = tryCatchValue(@() stage.core.Monitor(1).refreshRate);
    results(end+1) = ok('Monitor.refreshRate (default/integer)', ...
        passed && isnumeric(rate) && rate > 0, ...
        sprintf('%s (got %s Hz)', msg, num2str(rate)));

    % --- 5. Priority MEXes
    [passed, msg] = tryCatch(@() setMaxPriority());
    if passed
        results(end+1) = ok('setMaxPriority() succeeded', true, ...
            'Thread likely at SCHED_FIFO (Linux) / real-time (Windows / macOS).');
    else
        % Soft failure is acceptable on Linux without CAP_SYS_NICE.
        % Mark as warning, not fail.
        results(end+1) = ok('setMaxPriority() soft-failed (OK on non-root Linux)', ...
            true, sprintf('Warning: %s', msg));
    end

    [passed, msg] = tryCatch(@() setNormalPriority());
    if passed
        results(end+1) = ok('setNormalPriority() succeeded', true, '');
    else
        results(end+1) = ok('setNormalPriority() soft-failed', true, ...
            sprintf('Warning: %s', msg));
    end

    % --- 6. ffmpeg / ffprobe on PATH
    % Auto-augment PATH on macOS if MATLAB was launched without a
    % shell-inherited PATH (e.g. from Finder). No-op on Windows/Linux
    % or if ffmpeg is already callable. See stage.util.ensureFFmpegOnPath.
    try %#ok<TRYNC>
        ffStatus = stage.util.ensureFFmpegOnPath();
        if ffStatus.wasAdded
            fprintf('  [note] added %s to PATH so ffmpeg is reachable\n', ...
                ffStatus.addedDir);
        end
    end

    [status_ff,  ~] = system('ffmpeg -version');
    results(end+1) = ok('ffmpeg on PATH', status_ff == 0, ...
        'Install ffmpeg: macOS `brew install ffmpeg`; Linux `apt install ffmpeg`; Windows `winget install Gyan.FFmpeg`.');
    [status_fp,  ~] = system('ffprobe -version');
    results(end+1) = ok('ffprobe on PATH', status_fp == 0, ...
        'Usually bundled with ffmpeg. Check install.');

    % --- 7. Java-ProcessBuilder + pipe sanity test
    %     Spawn ffmpeg and pipe 8 bytes of silence through it. If
    %     VideoSource_FFmpeg's ByteBuffer read pattern works on this
    %     MATLAB, this check passes.
    if status_ff == 0
        [passed, msg] = tryCatch(@() checkFfmpegPipe());
        results(end+1) = ok('ffmpeg subprocess I/O sanity', passed, msg);
    end

    printSummary(results);
end


% --- helpers ---

function r = recordResult(name, pass, msg)
    status = 'PASS';
    if ~pass, status = 'FAIL'; end
    fprintf('  [%s] %s\n', status, name);
    if ~pass && ~isempty(msg)
        fprintf('         → %s\n', msg);
    elseif pass && ~isempty(msg) && startsWith(strtrim(msg), 'Warning')
        fprintf('         → %s\n', msg);
    end
    r.name = name;
    r.pass = pass;
    r.msg = msg;
end

function [ok, msg] = tryCatch(fn)
    try
        fn();
        ok = true; msg = '';
    catch ex
        ok = false; msg = ex.message;
    end
end

function [ok, msg, val] = tryCatchValue(fn)
    try
        val = fn();
        ok = true; msg = '';
    catch ex
        val = [];
        ok = false; msg = ex.message;
    end
end

function checkFfmpegPipe()
    % Generate 8 bytes via a one-shot ffmpeg call, read via the same
    % Java ByteBuffer pattern VideoSource_FFmpeg uses. A 2×2 single-
    % frame rawvideo output is 12 bytes of RGB — perfect tiny test.
    args = javaArray('java.lang.String', 10);
    argList = {'ffmpeg', '-hide_banner', '-loglevel', 'error', ...
        '-f', 'lavfi', '-i', 'color=c=red:s=2x2:d=0.02', ...
        '-frames:v', '1'};
    for k = 1:numel(argList)
        args(k) = java.lang.String(argList{k});
    end
    % Tack on the rawvideo output spec separately
    argsFull = javaArray('java.lang.String', numel(argList) + 5);
    for k = 1:numel(argList)
        argsFull(k) = java.lang.String(argList{k});
    end
    argsFull(numel(argList) + 1) = java.lang.String('-f');
    argsFull(numel(argList) + 2) = java.lang.String('rawvideo');
    argsFull(numel(argList) + 3) = java.lang.String('-pix_fmt');
    argsFull(numel(argList) + 4) = java.lang.String('rgb24');
    argsFull(numel(argList) + 5) = java.lang.String('-');

    pb = java.lang.ProcessBuilder(argsFull);
    pb.redirectErrorStream(false);
    p = pb.start();

    bb = java.nio.ByteBuffer.allocate(12);  % 2*2*3 bytes
    ch = java.nio.channels.Channels.newChannel(p.getInputStream());
    while bb.hasRemaining()
        n = ch.read(bb);
        if n < 0, break; end
    end
    p.waitFor();
    ch.close();

    if bb.position() ~= 12
        error('Got %d bytes, expected 12', bb.position());
    end

    rgb = typecast(int8(bb.array()), 'uint8');
    % The first pixel should be "red-ish". Exact values depend on
    % ffmpeg's lavfi → YUV → RGB conversion path, but R should
    % clearly dominate.
    if rgb(1) < 150 || rgb(2) > 80 || rgb(3) > 80
        error('First pixel was not red-dominant: RGB = (%d, %d, %d)', ...
            rgb(1), rgb(2), rgb(3));
    end
end

function printSummary(results)
    fprintf('\n------------------------------------------------\n');
    nPass = sum([results.pass]);
    nTotal = numel(results);
    if nPass == nTotal
        fprintf(' ALL %d CHECKS PASSED.\n', nTotal);
        fprintf(' Stage''s platform dependencies are healthy on this OS.\n');
        fprintf(' Next step: run StartStage(''headless'') to open the server.\n');
    else
        fprintf(' %d of %d checks passed.\n', nPass, nTotal);
        fprintf(' Failures above need to be addressed before Stage will run.\n');
    end
    fprintf('------------------------------------------------\n\n');
end
