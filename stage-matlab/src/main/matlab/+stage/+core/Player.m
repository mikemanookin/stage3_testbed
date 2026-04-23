classdef Player < handle
    % Abstract class for all presentation players.

    properties (SetAccess = private)
        presentation
        compositor
    end

    properties (Access = protected)
        % Set to true to request an early exit from the frame loop. See
        % spec/specs/PLAYER_LIFECYCLE.md for the full lifecycle.
        stopRequested = false

        % Optional function handle installed by the server to let the frame
        % loop poll for control messages (e.g. 'stop') between frames. The
        % callback should accept no arguments and have side effects only —
        % it is expected to set obj.stopRequested as needed. See
        % spec/decisions/0001-in-frame-stop-polling.md.
        stopChecker = []
    end

    methods

        function obj = Player(presentation)
            % Constructs a player with a given presentation.
            obj.presentation = presentation;
            obj.setCompositor(stage.core.Compositor());
        end

        function setCompositor(obj, compositor)
            % Sets the compositor used to composite the presentation stimuli into frame images during playback.
            obj.compositor = compositor;
        end

        function setStopChecker(obj, fn)
            % Installs a between-frames callback. The callback is invoked
            % once per frame from the play() loop (after the frame flip) and
            % may set obj.stopRequested to true to terminate the play early.
            % Pass [] to clear the callback.
            if ~isempty(fn) && ~isa(fn, 'function_handle')
                error('stage:Player:invalidStopChecker', ...
                    'stopChecker must be a function handle or empty');
            end
            obj.stopChecker = fn;
        end

        function requestStop(obj)
            % Directly marks this player for early termination on the next
            % frame-loop iteration. The server installs stopChecker to call
            % this in response to a wire-protocol 'stop' event.
            obj.stopRequested = true;
        end

        function tf = isStopRequested(obj)
            tf = obj.stopRequested;
        end

        function exportMovie(obj, canvas, filename, frameRate, profile)
            % Exports the presentation to a movie file. The VideoWriter frame rate and profile may optionally be
            % provided. If the given profile specifies only one color channel, the red, green, and blue color channels
            % of the presentation are averaged to produce the output video data.

            if nargin < 4
                frameRate = canvas.window.monitor.refreshRate;
            end

            if nargin < 5
                profile = 'Uncompressed AVI';
            end

            writer = VideoWriter(filename, profile);
            writer.FrameRate = frameRate;
            writer.open();

            obj.compositor.init(canvas);

            canvas.setClearColor(obj.presentation.backgroundColor);

            stimuli = obj.presentation.stimuli;
            controllers = obj.presentation.controllers;

            for i = 1:length(stimuli)
                stimuli{i}.init(canvas);
            end

            frame = 0;
            time = frame / frameRate;
            while time < obj.presentation.duration
                canvas.clear();

                state.canvas = canvas;
                state.frame = frame;
                state.frameRate = frameRate;
                state.time = time;
                obj.compositor.drawFrame(stimuli, controllers, state);

                pixelData = canvas.getPixelData();
                if writer.ColorChannels == 1
                    pixelData = uint8(mean(pixelData, 3));
                end

                writer.writeVideo(pixelData);

                canvas.window.pollEvents();

                frame = frame + 1;
                time = frame / frameRate;
            end

            writer.close();
        end

    end

    methods (Access = protected)

        function checkForStop(obj)
            % Frame-loop hook. Subclasses call this once per frame (after
            % canvas.window.pollEvents()) and break when stopRequested
            % becomes true.
            if ~isempty(obj.stopChecker)
                try
                    obj.stopChecker();
                catch x
                    % A failure in the poll should never kill the frame loop —
                    % log via stderr and continue. The most common legitimate
                    % cause is a transient TCP read error that will resolve on
                    % the next frame's poll.
                    fprintf(2, '[stage.core.Player] stop-checker error: %s\n', x.message);
                end
            end
        end

        function resetStopState(obj)
            % Called at the start of play() so that a stopRequested flag
            % left over from a prior play doesn't immediately terminate the
            % new one. Subclasses must invoke this before entering their
            % frame loop.
            obj.stopRequested = false;
        end

        function renderStopFrame(obj, canvas)
            % Renders the canonical end-of-sweep frame on an early stop.
            % Subclasses call this once after the frame loop breaks.
            %
            % The goal is to leave the display in the same visual state
            % it would be in if the presentation had completed naturally:
            %
            %   - every user stimulus (gratings, noise, images, etc.) is
            %     removed so the canvas shows only the original background
            %     color that was in effect at the start of createPresentation
            %   - every FrameTracker is driven to color = 0 (black) so the
            %     photodiode-based trigger hardware sees a clean end-of-sweep
            %     edge
            %
            % Symphony device convention (see VideoDevice.play,
            % LightCrafterDevice, MicrodisplayDevice):
            %
            %   1. The first stimulus in the presentation is a Rectangle
            %      that was inserted by VideoDevice.play to preserve the
            %      original backgroundColor. Drawing it restores the
            %      "before any stimulus ran" display state.
            %   2. The last stimulus is a FrameTracker whose controller
            %      normally toggles black/white per frame. On stop we
            %      force its color to 0 and draw it; the controller is
            %      not run (since we're not invoking the compositor).
            %
            % All other stimuli are skipped. If a rig uses a different
            % convention (no leading Rectangle, no trailing FrameTracker),
            % the canvas stays at its clear color and no tracker is
            % emitted — the hardware tracker just sees whatever background
            % is configured. This is a best-effort helper, not a guarantee.
            %
            % See spec/specs/PLAYER_LIFECYCLE.md § Early termination.

            canvas.clear();

            stimuli = obj.presentation.stimuli;

            % 1. Restore the original background by drawing the leading
            %    Rectangle if present.
            if ~isempty(stimuli) && isa(stimuli{1}, 'stage.builtin.stimuli.Rectangle')
                stimuli{1}.draw();
            end

            % 2. Draw any FrameTracker stimuli with color forced to 0.
            for i = 1:numel(stimuli)
                s = stimuli{i};
                if isa(s, 'stage.builtin.stimuli.FrameTracker')
                    originalColor = s.color;
                    try
                        s.color = 0;
                        s.draw();
                    catch %#ok<CTCH>
                        % If color is immutable or draw fails, skip
                        % rather than taking down the whole stop path.
                    end
                    s.color = originalColor;
                end
            end

            canvas.window.flip();
        end

    end

    methods (Abstract)
        % Plays the presentation for its set duration.
        info = play(obj, canvas);
    end

end
