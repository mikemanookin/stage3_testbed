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
%   Priority:
%     1. env var GLFW_PREFIX if it points somewhere with glfw3.h
%     2. The architecture-matched default for this MATLAB:
%          ARM MATLAB   (MACA64) → /opt/homebrew (ARM-native Homebrew)
%          Intel MATLAB (MACI64) → /usr/local    (Intel Homebrew)
%     3. The other prefix if only it has glfw3.h, with a LOUD warning
%        (links will fail with "found architecture X, required Y").
%
%   MATLAB is ARM-native on Apple Silicon from R2023b onward. Earlier
%   MATLAB ran under Rosetta and needed Intel libs. `computer()` is
%   the authoritative check — 'MACA64' is ARM, 'MACI64' is Intel.

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

    isArmMatlab = strcmp(computer, 'MACA64');
    if isArmMatlab
        primary        = '/opt/homebrew';
        primaryLabel   = 'ARM (Apple Silicon)';
        secondary      = '/usr/local';
        secondaryLabel = 'Intel';
    else
        primary        = '/usr/local';
        primaryLabel   = 'Intel';
        secondary      = '/opt/homebrew';
        secondaryLabel = 'ARM (Apple Silicon)';
    end

    if exist(fullfile(primary, 'include', 'GLFW', 'glfw3.h'), 'file')
        brewPrefix = primary;
        return;
    end

    if exist(fullfile(secondary, 'include', 'GLFW', 'glfw3.h'), 'file')
        % Only the mismatched arch is available. mex will fail with
        % "found architecture X, required architecture Y" — warn
        % up-front so the user knows exactly what to fix.
        warning('matlabGlfw3:make:archMismatch', ...
            ['GLFW was found at %s (%s Homebrew) but this MATLAB is ' ...
             '%s (computer()=''%s''). Linking will fail with an ' ...
             'architecture-mismatch error. Install %s-native Homebrew ' ...
             'and run "brew install glfw" from it. See ' ...
             'docs/Install.md troubleshooting.'], ...
            secondary, secondaryLabel, primaryLabel, computer, primaryLabel);
        brewPrefix = secondary;
        return;
    end

    warning('matlabGlfw3:make:noPrefix', ...
        ['Could not find GLFW 3 headers at /opt/homebrew/include or ' ...
         '/usr/local/include. Did you run "brew install glfw"?']);
    brewPrefix = primary;  % best guess; mex will fail verbosely
end
