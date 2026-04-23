function make()
%MAKE  Build the MOGL moglcore MEX binary for the current OS.
%
%   MOGL (MATLAB OpenGL) is a single-target MEX built from a fixed set
%   of C files. Unlike lib/matlab-glfw3 and lib/matlab-priority, this
%   make script doesn't take a `rebuild` flag — it always compiles the
%   one target (moglcore.mexXXX).
%
%   Historical notes:
%     - The old script passed `-f ../mexopts.sh`, which is a pre-R2014
%       mex options file. Modern MATLAB (R2019b+) uses XML-based
%       mexopts and rejects the shell-style file as "not a valid XML
%       file". The `-f` flag has been removed; MATLAB's default options
%       + the explicit flags below are sufficient.
%     - The old macOS branch used `-I/usr/include`, which is wrong on
%       Apple Silicon where Homebrew installs headers to
%       `/opt/homebrew/include`. Now auto-detected.
%
%   Requires (Linux): libglew-dev, libglu1-mesa-dev, freeglut3-dev,
%                     mesa-common-dev, libx11-dev, libxext-dev,
%                     libxrandr-dev, libxi-dev, libxxf86vm-dev.
%   Requires (macOS): nothing beyond Xcode Command Line Tools and
%                     the system OpenGL / GLUT frameworks.
%                     (GLEW is statically compiled in via glew.c.)
%   Requires (Windows): the bundled freeglut in ./freeglut/.

    filePath = mfilename('fullpath');
    moglDir = fileparts(filePath);

    currentDir = pwd;
    returnToDir = onCleanup(@()cd(currentDir));
    cd(fullfile(moglDir, 'source'));

    sources = {'moglcore.c', 'gl_auto.c', 'gl_manual.c', 'glew.c', ...
               'mogl_rebinder.c', 'ftglesGlue.c'};

    try
        if ismac
            % Detect Homebrew prefix so any future dep-via-brew (e.g.
            % if glut headers move) Just Works on both Intel and
            % Apple Silicon. Today we only need it for the -I path.
            if exist('/opt/homebrew/include', 'dir')
                brewInclude = '/opt/homebrew/include';
            else
                brewInclude = '/usr/local/include';
            end

            args = [{'-v', '-outdir', './', '-output', 'moglcore', ...
                     '-DMACOSX', '-DGLEW_STATIC', '-largeArrayDims', ...
                     'LDFLAGS=$LDFLAGS -framework OpenGL -framework GLUT', ...
                     ['-I' brewInclude]}, sources];
            mex(args{:});

        elseif ispc
            args = [{'-v', '-outdir', './', '-output', 'moglcore', ...
                     '-DWINDOWS', '-DGLEW_STATIC', '-largeArrayDims', ...
                     '-L../freeglut/lib/x64', '-lfreeglut', ...
                     '-I../freeglut/include', 'windowhacks.c'}, sources, ...
                    {'user32.lib', 'gdi32.lib', 'advapi32.lib', ...
                     'glu32.lib', 'opengl32.lib'}];
            mex(args{:});

        elseif isunix
            args = [{'-v', '-outdir', './', '-output', 'moglcore', ...
                     '-DLINUX', '-DGLEW_STATIC', '-largeArrayDims', ...
                     '-I/usr/include', '-I/usr/include/GL'}, sources, ...
                    {'-lGLEW', '-lGL', '-lGLU', '-lglut', ...
                     '-lX11', '-lXext', '-lXrandr', '-lXi', '-lXxf86vm', ...
                     '-lpthread', '-lm', '-ldl'}];
            mex(args{:});

        else
            error('mogl:make:unknownOs', 'Unsupported operating system.');
        end

    catch ex
        fprintf(2, ['MOGL build failed:\n  %s\n\n' ...
            'Common fixes:\n' ...
            '  Linux:   apt install libglew-dev libglu1-mesa-dev freeglut3-dev\n' ...
            '           libx11-dev libxext-dev libxrandr-dev libxi-dev libxxf86vm-dev\n' ...
            '  macOS:   xcode-select --install   (if compiler missing)\n' ...
            '  macOS:   ensure /opt/homebrew/include or /usr/local/include exists\n' ...
            '  Windows: re-extract the bundled freeglut under ./freeglut/\n'], ...
            ex.message);
        rethrow(ex);
    end

end
