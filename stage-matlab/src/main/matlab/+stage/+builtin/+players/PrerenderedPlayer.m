classdef PrerenderedPlayer < stage.core.Player
    % A player that draws all frames to memory prior to playback.
    
    properties (Access = private)
        renderedFrames
    end

    methods

        function obj = PrerenderedPlayer(presentation)
            obj = obj@stage.core.Player(presentation);
        end

        function info = play(obj, canvas)
            if isempty(obj.renderedFrames)
                obj.prerender(canvas);
            end
            info = obj.replay(canvas);
        end

        function prerender(obj, canvas)
            frameRate = canvas.window.monitor.refreshRate;
            nFrames = floor(obj.presentation.duration * frameRate);

            obj.renderedFrames = cell(1, nFrames);

            obj.compositor.init(canvas);
            
            canvas.setClearColor(obj.presentation.backgroundColor);

            stimuli = obj.presentation.stimuli;
            controllers = obj.presentation.controllers;

            for i = 1:length(stimuli)
                stimuli{i}.init(canvas);
            end

            % Prerender runs before any frames are displayed, so
            % wall-clock time is meaningless here — state.time stays
            % frame-indexed to keep prerender deterministic.
            % state.frameTime mirrors it for API symmetry with
            % RealtimePlayer (which differs between the two under
            % dropped-frame conditions). See
            % spec/specs/PLAYER_LIFECYCLE.md § state.
            frame = 0;
            time = frame / frameRate;
            while time < obj.presentation.duration
                canvas.clear();

                state.canvas = canvas;
                state.frame = frame;
                state.frameRate = frameRate;
                state.time = time;
                state.frameTime = time;
                obj.compositor.drawFrame(stimuli, controllers, state);

                obj.renderedFrames{frame + 1} = canvas.getPixelData(0, 0, canvas.size(1), canvas.size(2), false);

                canvas.window.pollEvents();

                frame = frame + 1;
                time = frame / frameRate;
            end
        end

        function info = replay(obj, canvas)
            flipTimer = stage.core.FlipTimer();

            % Each vertex position is followed by a texture coordinate and a mask coordinate.
            vertexData = [ 0  1  0  1,  0  1,  0  1 ...
                           0  0  0  1,  0  0,  0  0 ...
                           1  1  0  1,  1  1,  1  1 ...
                           1  0  0  1,  1  0,  1  0];

            vbo = stage.core.gl.VertexBufferObject(canvas, GL.ARRAY_BUFFER, single(vertexData), GL.STATIC_DRAW);

            vao = stage.core.gl.VertexArrayObject(canvas);
            vao.setAttribute(vbo, 0, 4, GL.FLOAT, GL.FALSE, 8*4, 0);
            vao.setAttribute(vbo, 1, 2, GL.FLOAT, GL.FALSE, 8*4, 4*4);
            vao.setAttribute(vbo, 2, 2, GL.FLOAT, GL.FALSE, 8*4, 6*4);

            texture = stage.core.gl.TextureObject(canvas, 2);
            texture.setImage(obj.renderedFrames{1}, 0, false);

            renderer = stage.core.Renderer(canvas);
            renderer.projection.orthographic(0, 1, 0, 1);

            try %#ok<TRYNC>
                setMaxPriority();
            end
            cleanup = onCleanup(@resetPriority);
            function resetPriority()
                try %#ok<TRYNC>
                    setNormalPriority();
                end
            end

            % Reset the stop flag at the playback boundary. Note: prerender
            % itself is not interruptible in this player — see
            % spec/decisions/0001-in-frame-stop-polling.md (Consequences).
            obj.resetStopState();

            nFrames = length(obj.renderedFrames);
            for frame = 1:nFrames
                canvas.clear();

                texture.setSubImage(obj.renderedFrames{frame}, 0, [0, 0], false);

                renderer.drawArray(vao, GL.TRIANGLE_STRIP, 0, 4, [1, 1, 1, 1], [], texture, []);

                canvas.window.flip();
                flipTimer.tick();

                canvas.window.pollEvents();

                % Poll the connection for a stop event. See PLAYER_LIFECYCLE.md.
                obj.checkForStop();
                if obj.stopRequested
                    % Render the canonical "stop" frame: original
                    % background color + FrameTrackers forced black,
                    % all user stimuli suppressed. Uses the live stimulus
                    % instances from obj.presentation (they were init'd on
                    % this canvas during prerender). See
                    % stage.core.Player.renderStopFrame.
                    obj.renderStopFrame(canvas);
                    flipTimer.tick();
                    break;
                end
            end

            info.flipDurations = flipTimer.flipDurations;
            info.flipTimestamps = flipTimer.flipTimestamps;
            info.stopped = obj.stopRequested;
        end

    end

end
