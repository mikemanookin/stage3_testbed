classdef RegenPlayer < stage.core.Player
    % A player that draws all frames to memory prior to playback.
    
    properties (Access = public)
        renderedFrames
    end

    methods

        function obj = RegenPlayer(presentation)
            obj = obj@stage.core.Player(presentation);
        end

        function info = play(obj, canvas)
            if isempty(obj.renderedFrames)
                obj.prerender(canvas);
            end
            info = obj.replay(canvas);
        end

        function prerender(obj, canvas, epoch_params)
            frameRate = epoch_params.frameRate;
            
            if isfield(epoch_params, 'startTime')
                if isfield(epoch_params, 'stopTime')
                    nFrames = floor(((epoch_params.stopTime*1e-3)-(epoch_params.startTime*1e-3))*frameRate);
                    fprintf('\nStart and stop time provided, regenerating ~%d frames\n', nFrames);
                    frame = floor(epoch_params.startTime * 1e-3 * frameRate);
                    fprintf('Starting at frame %d\n\n', frame);
                    stopTime = epoch_params.stopTime * 1e-3;
                else
                    nFrames = floor((obj.presentation.duration-epoch_params.startTime*1e-3)*frameRate);
                    fprintf('\nOnly start time provided, regenerating ~%d frames\n', nFrames);
                    frame = floor(epoch_params.startTime * 1e-3 * frameRate);
                    fprintf('Starting at frame %d\n\n', frame);
                    stopTime = obj.presentation.duration;
                end
            elseif isfield(epoch_params, 'stopTime')
                nFrames = floor(epoch_params.stopTime * 1e-3 * frameRate);
                frame = 0;
                fprintf('\nOnly stop time provided, regenerating ~%d frames\n\n', nFrames);
                stopTime = epoch_params.stopTime * 1e-3;
            else
                nFrames = floor(obj.presentation.duration * frameRate);
                frame = 0;
                fprintf('\nNo start or stop time provided, regenerating all %d frames\n\n', nFrames);
                stopTime = obj.presentation.duration;
            end

            obj.renderedFrames = cell(1, nFrames);

            obj.compositor.init(canvas);
            
            canvas.setClearColor(obj.presentation.backgroundColor);

            stimuli = obj.presentation.stimuli;
            controllers = obj.presentation.controllers;

            for i = 1:length(stimuli)
                stimuli{i}.init(canvas);
            end
            
            % Prerender is deterministic: frames are rendered to RAM
            % before any flip, so state.time stays frame-indexed (no
            % wall-clock available). state.frameTime mirrors state.time
            % here for API symmetry with RealtimePlayer. See
            % spec/specs/PLAYER_LIFECYCLE.md § state.
            time = frame/frameRate;
            frameOffset = frame;

            while time < stopTime
                canvas.clear();

                state.canvas = canvas;
                state.frame = frame;
                state.frameRate = frameRate;
                state.time = time;
                state.frameTime = time;
                obj.compositor.drawFrame(stimuli, controllers, state);

                obj.renderedFrames{frame - frameOffset + 1} = canvas.getPixelData(0, 0, canvas.size(1), canvas.size(2), false);
                obj.renderedFrames{frame - frameOffset + 1} = permute(obj.renderedFrames{frame - frameOffset + 1}, [3,2,1]);

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

            % Reset the stop flag at the playback boundary. Prerender itself
            % is not interruptible — see PLAYER_LIFECYCLE.md.
            obj.resetStopState();

            nFrames = length(obj.renderedFrames);
            for frame = 1:nFrames
                canvas.clear();

                texture.setSubImage(obj.renderedFrames{frame}, 0, [0, 0], false);

                renderer.drawArray(vao, GL.TRIANGLE_STRIP, 0, 4, [1, 1, 1, 1], [], texture, []);

                canvas.window.flip();
                flipTimer.tick();

                canvas.window.pollEvents();

                % Poll for stop — PLAYER_LIFECYCLE.md § Early termination.
                obj.checkForStop();
                if obj.stopRequested
                    % Render the canonical "stop" frame: original
                    % background color + FrameTrackers forced black,
                    % all user stimuli suppressed. See
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
