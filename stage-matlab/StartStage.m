function StartStage(varargin)
%STARTSTAGE  Set up MATLAB paths for the Stage testbed source tree and
%            launch the Stage server.
%
%   Usage:
%     StartStage()                     — Launch the classic stage-server UI
%                                        (currently emits Java deprecation
%                                        warnings; see PLAN.md → UI modernization).
%     StartStage('headless')           — Skip the UI entirely. Starts the
%                                        StageServer directly with default
%                                        parameters (port 5678, 640x480
%                                        window, fullscreen, monitor 1).
%                                        Recommended while working on the
%                                        core server / player / wire-protocol
%                                        code — no Java UI noise.
%     StartStage('headless', 'port', P, ...
%                'size', [W H], 'fullscreen', TF, 'monitor', N)
%                                      — Headless with explicit overrides.
%
%   Running from a terminal: double-click StartStage.bat, or open a terminal
%   and invoke it. All paths are resolved relative to this file's location,
%   so the testbed folder can be moved without editing anything.
%
%   IMPORTANT: If you have the "Stage Server" app installed as a MATLAB
%   toolbox (via the Add-On Manager), you should UNINSTALL it before using
%   this script. Otherwise the installed toolbox's paths will take
%   precedence over the testbed source tree and you'll be editing files
%   that MATLAB isn't actually loading.
%
%   To uninstall:
%     HOME tab -> Add-Ons -> Manage Add-Ons -> find "Stage Server" -> Uninstall
%   (or run `matlab.addons.uninstall('Stage Server')` at the prompt).
%
%   See also: spec/README.md for the development workflow.

    root = fileparts(mfilename('fullpath'));

    % Directories to add, in load order. All paths are relative to `root`.
    % Core Stage library first, then bundled platform libraries, then the
    % stage-server UI app that main.m lives in.
    pathSpecs = {
        {fullfile(root, 'src', 'main', 'matlab'),                                     false}, ...  % +stage.*
        {fullfile(root, 'lib', 'matlab-glfw3'),                                       true},  ...  % GLFW wrapper + GLFW package
        {fullfile(root, 'lib', 'matlab-avbin'),                                       true},  ...
        {fullfile(root, 'lib', 'matlab-dwm'),                                         true},  ...
        {fullfile(root, 'lib', 'matlab-priority'),                                    true},  ...
        {fullfile(root, 'lib', 'MOGL'),                                               true},  ...  % OpenGL bindings
        {fullfile(root, 'lib', 'netbox', 'src', 'main', 'matlab'),                    false}, ...  % +netbox + +netbox.+tcp
        {fullfile(root, 'lib', 'netbox', 'src', 'main', 'matlab', '+netbox', '+tcp'), false}, ...
        {fullfile(root, 'apps', 'stage-server', 'src', 'main', 'matlab'),             false}, ...  % +stageui + main.m
        {fullfile(root, 'apps', 'stage-server', 'lib', 'appbox'),                     true}   ...  % BusyPresenter etc.
    };

    added = {};
    missing = {};
    for i = 1:numel(pathSpecs)
        p = pathSpecs{i}{1};
        recurse = pathSpecs{i}{2};
        if ~exist(p, 'dir')
            missing{end + 1} = p; %#ok<AGROW>
            continue;
        end
        if recurse
            addpath(genpath(p));
        else
            addpath(p);
        end
        added{end + 1} = p; %#ok<AGROW>
    end

    fprintf('[StartStage] testbed root: %s\n', root);
    fprintf('[StartStage] added %d directories to path\n', numel(added));
    if ~isempty(missing)
        fprintf(2, '[StartStage] WARNING: %d expected directories were not found:\n', ...
            numel(missing));
        for i = 1:numel(missing)
            fprintf(2, '  - %s\n', missing{i});
        end
        fprintf(2, 'The source tree may be incomplete. Stage may fail to start.\n');
    end

    % If the installed "Stage Server" toolbox is present, warn — its paths
    % will shadow the source tree and the user probably doesn't want that.
    try
        installed = matlab.addons.installedAddons();
        if ~isempty(installed) && any(strcmp(installed.Name, 'Stage Server'))
            fprintf(2, [ ...
                '[StartStage] NOTE: the "Stage Server" toolbox is installed as an Add-On.\n', ...
                '            Its paths may shadow the testbed source tree. Consider\n', ...
                '            uninstalling it:  HOME -> Add-Ons -> Manage Add-Ons.\n']);
        end
    catch
        % matlab.addons.installedAddons is R2017b+; silently skip on older
        % MATLAB releases.
    end

    % ---- Dispatch to headless, modern UI, or legacy Swing UI ----
    mode = '';
    if ~isempty(varargin) && ischar(varargin{1})
        mode = lower(varargin{1});
    end

    switch mode
        case 'headless'
            % Strip the 'headless' flag and forward the rest as name-value pairs
            startHeadless(varargin(2:end));
        case 'legacy'
            % Old Swing / appbox UI. Still runnable for comparison during the
            % UI port (TASK-004); will be removed after validation.
            fprintf('[StartStage] LEGACY: launching old Swing-based main.m\n');
            fprintf('[StartStage] (Java deprecation warnings are expected.)\n');
            main();
        case 'pathsonly'
            % Set up paths and return without launching anything.
            % Used by VerifyStage and other scripts that need the
            % Stage source tree on the MATLAB path but do not want
            % to open a UI or start the server.
            return;
        case ''
            % Default: the new uifigure-based app (TASK-004).
            fprintf('[StartStage] launching StageServerApp (uifigure)\n');
            fprintf('[StartStage] (tip: StartStage(''headless'') runs without a UI;\n');
            fprintf('             StartStage(''legacy'') runs the old Swing UI.)\n');
            StageServerApp();
        otherwise
            error('StartStage:unknownMode', ...
                ['Unknown mode ''%s''. Valid modes: ''headless'', ''legacy'', ' ...
                 '''pathsonly'', or no argument (default uifigure UI).'], mode);
    end
end


function startHeadless(args)
    % Parse optional overrides for StageServer defaults.
    ip = inputParser();
    ip.addParameter('port', 5678, @(x) isnumeric(x) && isscalar(x));
    ip.addParameter('size', [640 480], @(x) isnumeric(x) && numel(x) == 2);
    ip.addParameter('fullscreen', true, @(x) islogical(x) || ismember(x, [0, 1]));
    ip.addParameter('monitor', 1, @(x) isnumeric(x) && isscalar(x));
    ip.parse(args{:});

    port       = ip.Results.port;
    canvasSize = ip.Results.size;
    fullscreen = logical(ip.Results.fullscreen);
    monitorIdx = ip.Results.monitor;

    fprintf('[StartStage] headless mode:\n');
    fprintf('             port       = %d\n', port);
    fprintf('             size       = [%d %d]\n', canvasSize(1), canvasSize(2));
    fprintf('             fullscreen = %s\n', mat2str(fullscreen));
    fprintf('             monitor    = %d\n', monitorIdx);
    fprintf('[StartStage] shift + escape in the Stage window will stop the server.\n');

    monitor = stage.core.Monitor(monitorIdx);
    server  = stage.core.network.StageServer(port);
    server.start(canvasSize, fullscreen, monitor);
end
