classdef StageServerApp < handle
%STAGESERVERAPP  UI for configuring and launching the Stage server.
%
%   Replaces the older Swing-based stageui.ui.presenters.MainPresenter
%   (which depended on deprecated `javacomponent`, `findjobj`, and
%   GUI Layout Toolbox 2.2.2 internals). Entirely built on
%   `uifigure` + `uigridlayout` + native uicontrols, so it runs on
%   Windows / macOS / Linux with zero deprecation warnings.
%
%   Same user-visible functionality as the old Swing UI:
%     - Width / Height / Monitor / Fullscreen inputs
%     - Advanced section with Port and Disable DWM
%     - Start / Cancel buttons
%     - Settings persist across MATLAB sessions via setpref/getpref
%
%   Usage:
%     app = StageServerApp();
%     % user clicks Start → StageServer takes over the MATLAB thread
%
%   Spec: see spec/TASKS.md § TASK-004, spec/decisions/0002-cross-platform-direction.md.

    properties (Access = private)
        fig             matlab.ui.Figure
        widthField      matlab.ui.control.NumericEditField
        heightField     matlab.ui.control.NumericEditField
        monitorDropdown matlab.ui.control.DropDown
        fullscreenBox   matlab.ui.control.CheckBox
        portField       matlab.ui.control.NumericEditField
        disableDwmBox   matlab.ui.control.CheckBox

        availableMonitors   % cell array of stage.core.Monitor
    end

    properties (Constant, Access = private)
        PREFS_GROUP = 'StageServerApp'
    end

    methods

        function obj = StageServerApp()
            obj.buildUi();
            obj.populateMonitorList();
            obj.loadSettings();
        end

        function delete(obj)
            if isvalid(obj) && ~isempty(obj.fig) && isvalid(obj.fig)
                delete(obj.fig);
            end
        end

    end

    methods (Access = private)

        % --- UI construction ---------------------------------------

        function buildUi(obj)
            figWidth = 360;
            figHeight = 300;

            obj.fig = uifigure( ...
                'Name', 'Stage Server', ...
                'Position', obj.screenCenter(figWidth, figHeight), ...
                'Resize', 'off');

            % Root layout: two sections stacked over a button row.
            root = uigridlayout(obj.fig, [3 1], ...
                'RowHeight', {'fit', 'fit', 'fit'}, ...
                'Padding', [12 12 12 12], ...
                'RowSpacing', 10);

            obj.buildStandardPanel(root);
            obj.buildAdvancedPanel(root);
            obj.buildButtonRow(root);
        end

        function buildStandardPanel(obj, parent)
            p = uipanel(parent, 'Title', 'Standard');
            g = uigridlayout(p, [4 2], ...
                'ColumnWidth', {90, '1x'}, ...
                'RowHeight', repmat({'fit'}, 1, 4), ...
                'Padding', [10 10 10 10], ...
                'RowSpacing', 6, ...
                'ColumnSpacing', 8);

            uilabel(g, 'Text', 'Width:');
            obj.widthField = uieditfield(g, 'numeric', ...
                'Limits', [1 16384], ...
                'RoundFractionalValues', 'on', ...
                'ValueDisplayFormat', '%d', ...
                'Value', 640);

            uilabel(g, 'Text', 'Height:');
            obj.heightField = uieditfield(g, 'numeric', ...
                'Limits', [1 16384], ...
                'RoundFractionalValues', 'on', ...
                'ValueDisplayFormat', '%d', ...
                'Value', 480);

            uilabel(g, 'Text', 'Monitor:');
            obj.monitorDropdown = uidropdown(g, 'Items', {' '});

            uilabel(g, 'Text', 'Fullscreen:');
            obj.fullscreenBox = uicheckbox(g, 'Text', '', ...
                'Value', true, ...
                'ValueChangedFcn', @(~, ~) obj.onFullscreenChanged());
        end

        function buildAdvancedPanel(obj, parent)
            p = uipanel(parent, 'Title', 'Advanced');
            g = uigridlayout(p, [2 2], ...
                'ColumnWidth', {90, '1x'}, ...
                'RowHeight', repmat({'fit'}, 1, 2), ...
                'Padding', [10 10 10 10], ...
                'RowSpacing', 6, ...
                'ColumnSpacing', 8);

            uilabel(g, 'Text', 'Port:');
            obj.portField = uieditfield(g, 'numeric', ...
                'Limits', [1 65535], ...
                'RoundFractionalValues', 'on', ...
                'ValueDisplayFormat', '%d', ...
                'Value', 5678);

            uilabel(g, 'Text', 'Disable DWM:');
            obj.disableDwmBox = uicheckbox(g, 'Text', '', ...
                'Value', true);
        end

        function buildButtonRow(obj, parent)
            row = uigridlayout(parent, [1 3], ...
                'ColumnWidth', {'1x', 80, 80}, ...
                'RowHeight', {32}, ...
                'Padding', [0 0 0 0], ...
                'ColumnSpacing', 6);
            uilabel(row, 'Text', '');  % spacer
            uibutton(row, 'push', ...
                'Text', 'Start', ...
                'ButtonPushedFcn', @(~, ~) obj.onStart());
            uibutton(row, 'push', ...
                'Text', 'Cancel', ...
                'ButtonPushedFcn', @(~, ~) obj.onCancel());
        end

        % --- populate / sync helpers -------------------------------

        function populateMonitorList(obj)
            try
                mons = stage.core.Monitor.availableMonitors();
            catch ex
                uialert(obj.fig, ...
                    sprintf(['Could not enumerate monitors: %s\n\n' ...
                             'GLFW may not be initialized; the "Stage Server" app requires ' ...
                             'lib/matlab-glfw3 MEX binaries on the MATLAB path.'], ex.message), ...
                    'Monitor detection failed');
                obj.availableMonitors = {};
                return;
            end

            names = cell(1, numel(mons));
            for k = 1:numel(mons)
                res = mons{k}.resolution;
                names{k} = sprintf('%s  (%d x %d)', mons{k}.name, res(1), res(2));
            end

            obj.availableMonitors = mons;
            if isempty(names)
                obj.monitorDropdown.Items = {'(no monitors detected)'};
            else
                obj.monitorDropdown.Items = names;
            end
        end

        function onFullscreenChanged(obj)
            if obj.fullscreenBox.Value
                obj.monitorDropdown.Enable = 'on';
            else
                obj.monitorDropdown.Enable = 'off';
            end
        end

        % --- settings persistence ----------------------------------

        function loadSettings(obj)
            try
                if ispref(obj.PREFS_GROUP, 'width')
                    obj.widthField.Value = getpref(obj.PREFS_GROUP, 'width');
                end
                if ispref(obj.PREFS_GROUP, 'height')
                    obj.heightField.Value = getpref(obj.PREFS_GROUP, 'height');
                end
                if ispref(obj.PREFS_GROUP, 'monitorName')
                    name = getpref(obj.PREFS_GROUP, 'monitorName');
                    idx = find(strcmp(obj.monitorDropdown.Items, name), 1);
                    if ~isempty(idx)
                        obj.monitorDropdown.Value = obj.monitorDropdown.Items{idx};
                    end
                end
                if ispref(obj.PREFS_GROUP, 'fullscreen')
                    obj.fullscreenBox.Value = getpref(obj.PREFS_GROUP, 'fullscreen');
                end
                if ispref(obj.PREFS_GROUP, 'port')
                    obj.portField.Value = getpref(obj.PREFS_GROUP, 'port');
                end
                if ispref(obj.PREFS_GROUP, 'disableDwm')
                    obj.disableDwmBox.Value = getpref(obj.PREFS_GROUP, 'disableDwm');
                end
            catch ex
                warning('StageServerApp:loadSettings', ...
                    'Failed to load saved settings: %s', ex.message);
            end
            obj.onFullscreenChanged();
        end

        function saveSettings(obj)
            try
                setpref(obj.PREFS_GROUP, 'width', obj.widthField.Value);
                setpref(obj.PREFS_GROUP, 'height', obj.heightField.Value);
                setpref(obj.PREFS_GROUP, 'monitorName', obj.monitorDropdown.Value);
                setpref(obj.PREFS_GROUP, 'fullscreen', obj.fullscreenBox.Value);
                setpref(obj.PREFS_GROUP, 'port', obj.portField.Value);
                setpref(obj.PREFS_GROUP, 'disableDwm', obj.disableDwmBox.Value);
            catch ex
                warning('StageServerApp:saveSettings', ...
                    'Failed to save settings: %s', ex.message);
            end
        end

        % --- button callbacks --------------------------------------

        function onStart(obj)
            if isempty(obj.availableMonitors)
                uialert(obj.fig, 'No monitors detected; cannot start the server.', ...
                    'Start failed');
                return;
            end

            width     = obj.widthField.Value;
            height    = obj.heightField.Value;
            idx       = find(strcmp(obj.monitorDropdown.Items, obj.monitorDropdown.Value), 1);
            if isempty(idx)
                idx = 1;
            end
            monitor   = obj.availableMonitors{idx};
            fullscreen = logical(obj.fullscreenBox.Value);
            port      = obj.portField.Value;
            disableDwm = logical(obj.disableDwmBox.Value);

            obj.saveSettings();

            % Hide the window but keep it alive so any error dialog can
            % anchor to it. StageServer.start blocks until shift+escape
            % in the Stage window; after that we tear down the figure.
            obj.fig.Visible = 'off';
            drawnow;

            try
                server = stage.core.network.StageServer(port);
                server.start([width, height], fullscreen, monitor, ...
                    'disableDwm', disableDwm);
            catch ex
                obj.fig.Visible = 'on';
                uialert(obj.fig, ex.message, 'Server error');
                return;
            end

            % Server exited cleanly (user hit shift+escape in-window).
            delete(obj);
        end

        function onCancel(obj)
            delete(obj);
        end

    end

    methods (Static, Access = private)
        function pos = screenCenter(w, h)
            screen = get(0, 'ScreenSize');
            x = round((screen(3) - w) / 2);
            y = round((screen(4) - h) / 2);
            pos = [x y w h];
        end
    end

end
