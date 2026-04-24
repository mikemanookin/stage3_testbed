function status = ensureFFmpegOnPath()
%ENSUREFFMPEGONPATH  If ffmpeg isn't callable from MATLAB, try to fix PATH.
%
%   On macOS, MATLAB launched from Finder, the Dock, or as a .command
%   file inherits a minimal PATH that does not include Homebrew's bin
%   directories (/opt/homebrew/bin on Apple Silicon, /usr/local/bin on
%   Intel, or /opt/local/bin for MacPorts). This means ffmpeg installed
%   via `brew install ffmpeg` can't be called from MATLAB via system(),
%   even though it works fine in a Terminal.
%
%   This function:
%     1. Probes whether `ffmpeg -version` can be run.
%     2. If not and we're on macOS, looks for ffmpeg in common
%        Homebrew / MacPorts bin dirs.
%     3. Prepends the first dir that contains ffmpeg onto PATH via
%        setenv, so subsequent system() calls succeed.
%
%   On Windows and Linux, where MATLAB started from a shell or icon
%   inherits the shell's PATH normally, this function only checks and
%   does not modify PATH.
%
%   Returns a struct with fields:
%     ok       (logical) true if ffmpeg is callable after the function
%                        returns
%     wasAdded (logical) true if we modified PATH to make ffmpeg work
%     addedDir (char)    the dir added to PATH (empty if nothing added)
%
%   Example:
%     s = stage.util.ensureFFmpegOnPath();
%     if ~s.ok
%         error('ffmpeg not found — install it (brew install ffmpeg).');
%     end

    status.ok = false;
    status.wasAdded = false;
    status.addedDir = '';

    if localIsFFmpegCallable()
        status.ok = true;
        return;
    end

    if ~ismac
        % On Windows / Linux we don't try to augment PATH — if ffmpeg
        % wasn't found, the install or shell environment is the real
        % problem and should be fixed there, not papered over here.
        return;
    end

    % Probe the three most common places Mac users install ffmpeg.
    candidates = { ...
        '/opt/homebrew/bin', ...   % Apple Silicon Homebrew
        '/usr/local/bin', ...      % Intel Homebrew
        '/opt/local/bin' ...       % MacPorts
        };

    currentPath = getenv('PATH');
    for k = 1:numel(candidates)
        c = candidates{k};
        ff = fullfile(c, 'ffmpeg');
        if exist(ff, 'file')
            setenv('PATH', [c ':' currentPath]);
            if localIsFFmpegCallable()
                status.ok = true;
                status.wasAdded = true;
                status.addedDir = c;
                return;
            end
            % Didn't help — shouldn't happen, but restore PATH and
            % keep probing.
            setenv('PATH', currentPath);
        end
    end

    % Nothing worked; status.ok stays false.
end


function tf = localIsFFmpegCallable()
    % Run `ffmpeg -version` and check exit status. Capture output so
    % it doesn't flood the MATLAB command window. On macOS we suppress
    % stderr too because ffmpeg writes its version banner to stdout,
    % stderr stays quiet on success.
    [rc, ~] = system('ffmpeg -version');
    tf = (rc == 0);
end
