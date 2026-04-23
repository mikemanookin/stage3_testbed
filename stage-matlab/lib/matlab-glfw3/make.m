function make(rebuild)
%MAKE  Build the matlab-glfw3 MEX bindings for the current OS.
%
%   make()         — build only out-of-date or missing MEX files
%   make(true)     — force a rebuild of every MEX file in this directory
%
%   Requires GLFW 3.x headers and library:
%     Linux:   sudo apt install libglfw3-dev
%     macOS:   brew install glfw
%     Windows: a prebuilt glfw3.lib is bundled in this directory
%
%   On macOS the script auto-detects the Homebrew prefix:
%     Apple Silicon → /opt/homebrew
%     Intel Mac     → /usr/local
%   Override by setting the `GLFW_PREFIX` environment variable before
%   calling make, e.g.:
%     setenv('GLFW_PREFIX', '/some/other/location'); make(true)

    if nargin < 1
        rebuild = false;
    end

    filePath = mfilename('fullpath');
    projectDir = fileparts(filePath);

    currentDir = pwd;
    returnToDir = onCleanup(@()cd(currentDir));
    cd(projectDir);

    % --- Compose per-OS options ---------------------------------------
    if ispc
        % Windows: expect a bundled glfw3.lib in this directory.
        options = [' -L"' projectDir '" -lglfw3'];
    elseif ismac
        brewPrefix = resolveMacPrefix();
        options = sprintf(' -I"%s/include" -L"%s/lib" -lglfw LDFLAGS="\\$LDFLAGS -framework Cocoa -framework OpenGL -framework IOKit -framework CoreVideo"', ...
            brewPrefix, brewPrefix);
    else
        % Linux: libglfw3-dev installs headers to /usr/include and the
        % library to a standard linker path; no explicit -I/-L needed.
        options = ' -lglfw';
    end

    % --- Build each .c in this directory ------------------------------
    sourceFiles = dir(fullfile(projectDir, '*.c'));
    anyFailed = false;
    for i = 1:length(sourceFiles)
        source = sourceFiles(i);

        [~, name] = fileparts(source.name);
        mexname = [name '.' mexext];
        mexfile = dir(mexname);

        if rebuild || isempty(mexfile) || datenum(source.date) > datenum(mexfile.date)
            command = sprintf('mex %s %s', options, source.name);
            disp(command);

            try
                eval(command);
            catch ex
                % Previously the catch swallowed ex.message; that made
                % "Error building 'foo.c'" the only clue. Print the real
                % error so docs/Install.md troubleshooting can match.
                fprintf(2, 'Error building ''%s'':\n  %s\n', ...
                    source.name, ex.message);
                anyFailed = true;
            end
        else
            disp([source.name ' is up to date']);
        end
    end

    if anyFailed
        fprintf(2, ['\nOne or more MEX files failed to build. Common causes:\n' ...
            '  - GLFW dev package not installed. See docs/Install.md.\n' ...
            '  - Wrong Homebrew prefix detected on macOS. If ''brew --prefix''\n' ...
            '    reports somewhere other than /opt/homebrew or /usr/local,\n' ...
            '    set GLFW_PREFIX=$(brew --prefix) in MATLAB via setenv and retry.\n']);
    end

end


function brewPrefix = resolveMacPrefix()
%RESOLVEMACPREFIX  Pick the right Homebrew root for this Mac.
%
%   Priority: env var GLFW_PREFIX > Apple Silicon default > Intel default.
%   Falls back to /usr/local with a warning if nothing works.

    envOverride = getenv('GLFW_PREFIX');
    if ~isempty(envOverride)
        if exist(fullfile(envOverride, 'include', 'GLFW', 'glfw3.h'), 'file')
            brewPrefix = envOverride;
            return;
        end
        warning('matlabGlfw3:make:badPrefix', ...
            'GLFW_PREFIX=%s does not contain include/GLFW/glfw3.h; falling back to auto-detection.', ...
            envOverride);
    end

    % Apple Silicon: /opt/homebrew
    if exist('/opt/homebrew/include/GLFW/glfw3.h', 'file')
        brewPrefix = '/opt/homebrew';
        return;
    end

    % Intel: /usr/local
    if exist('/usr/local/include/GLFW/glfw3.h', 'file')
        brewPrefix = '/usr/local';
        return;
    end

    warning('matlabGlfw3:make:noPrefix', ...
        'Could not find GLFW 3 headers. Did you run "brew install glfw"?');
    brewPrefix = '/usr/local';  % best guess; mex will fail verbosely
end
