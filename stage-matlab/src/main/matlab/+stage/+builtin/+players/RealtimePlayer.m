classdef RealtimePlayer < stage.core.Player
    % A player that draws each frame during the inter-frame interval.
    
    methods

        function obj = RealtimePlayer(presentation)
            obj = obj@stage.core.Player(presentation);
        end

        function info = play(obj, canvas)
            frameRate = canvas.window.monitor.refreshRate;
            flipTimer = stage.core.FlipTimer();

            obj.compositor.init(canvas);

            canvas.setClearColor(obj.presentation.backgroundColor);

            stimuli = obj.presentation.stimuli;
            controllers = obj.presentation.controllers;

            for i = 1:length(stimuli)
                stimuli{i}.init(canvas);

                % HACK: This appears to preload stimulus array data onto the graphics card, making subsequent calls to
                % draw() faster.
                v = stimuli{i}.visible;
                stimuli{i}.visible = true;
                stimuli{i}.draw();
                stimuli{i}.visible = v;
            end

            try %#ok<TRYNC>
                setMaxPriority();
            end
            cleanup = onCleanup(@resetPriority);
            function resetPriority()
                try %#ok<TRYNC>
                    setNormalPriority();
                end
            end

            % Reset the stop flag so that a previous stop request doesn't
            % immediately terminate this play. See
            % spec/specs/PLAYER_LIFECYCLE.md § Early termination.
            obj.resetStopState();

            % Wall-clock time drives state.time (TASK-003). t0 is
            % captured immediately before the render loop starts, so
            % the first frame sees state.time = 0 and each subsequent
            % iteration sees the true elapsed seconds since t0 —
            % independent of frame-count/refresh-rate arithmetic. If a
            % frame is dropped the next iteration's state.time
            % advances by ~2 * (1/frameRate), and controllers computing
            % cos(2πft) stay phase-correct. See
            % spec/specs/PLAYER_LIFECYCLE.md § state.
            frame = 0;
            t0 = glfwGetTime();
            time = 0;
            while time < obj.presentation.duration
                canvas.clear();

                state.canvas = canvas;
                state.frame = frame;
                state.frameRate = frameRate;
                state.time = time;                      % wall-clock (s)
                state.frameTime = frame / frameRate;    % frame-indexed (s)
                obj.compositor.drawFrame(stimuli, controllers, state);

                canvas.window.flip();
                flipTimer.tick();

                canvas.window.pollEvents();

                % Poll for a 'stop' (or other control) event. The callback
                % may set stopRequested; we observe it before computing the
                % next frame's time so no further rendering happens.
                obj.checkForStop();
                if obj.stopRequested
                    % Render the canonical "stop" frame: original
                    % background color + FrameTrackers forced black,
                    % with all user stimuli suppressed. See
                    % stage.core.Player.renderStopFrame.
                    obj.renderStopFrame(canvas);
                    flipTimer.tick();
                    break;
                end

                frame = frame + 1;
                time = glfwGetTime() - t0;
            end

            info.flipDurations = flipTimer.flipDurations;
            info.flipTimestamps = flipTimer.flipTimestamps;
            info.stopped = obj.stopRequested;
        end

    end

end
