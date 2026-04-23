classdef StageServer < handle
    
    properties (Access = protected)
        canvas
    end
    
    properties (Access = private)
        server
        port
    end
    
    methods
        
        function obj = StageServer(port)
            if nargin < 1
                port = 5678;
            end
            
            obj.server = netbox.Server();
            obj.port = port;
            
            addlistener(obj.server, 'ClientConnected', @obj.onClientConnected);
            addlistener(obj.server, 'ClientDisconnected', @obj.onClientDisconnected);
            addlistener(obj.server, 'EventReceived', @obj.onEventReceived);
            addlistener(obj.server, 'Interrupt', @obj.onInterrupt);
        end
        
        function start(obj, size, fullscreen, monitor, varargin)
            % Creates a window/canvas and starts serving clients. This method will block the current Matlab session 
            % until the shift and escape key are held while the window has focus.
            
            if nargin < 2
                size = [640, 480];
            end
            if nargin < 3
                fullscreen = true;
            end
            if nargin < 4
                monitor = stage.core.Monitor(1);
            end
            ip = inputParser();
            ip.addParameter('disableDwm', true);
            ip.parse(varargin{:});
            
            stop = onCleanup(@()obj.stop());
            
            window = stage.core.Window(size, fullscreen, monitor);
            obj.canvas = stage.core.Canvas(window, 'disableDwm', ip.Results.disableDwm);
            obj.canvas.clear();
            obj.canvas.window.flip();

            % Empirically measure the monitor's true refresh rate. GLFW's
            % integer mode rate misses NTSC-era 59.94 / 119.88 Hz panels
            % by ~1 %, which accumulates to hundreds of milliseconds over
            % a long epoch. Done once here so the server publishes the
            % measured rate via getMonitorRefreshRate and all players use
            % it. See spec/specs/MONITOR_TIMING.md and TASK-002.
            try
                measured = window.monitor.measureRefreshRate(window);
                fprintf('Monitor refresh rate: %.4f Hz (measured)\n', measured);
            catch ex
                fprintf(2, ['[StageServer] refresh-rate measurement ' ...
                    'failed, falling back to GLFW integer (%d Hz): %s\n'], ...
                    window.monitor.refreshRate, ex.message);
            end

            disp(['Serving on port: ' num2str(obj.port)]);
            disp('To exit press shift + escape while the Stage window has focus');
            obj.server.start(obj.port);
        end
        
        function stop(obj)
            % Automatically called when start completes.
            
            obj.server.requestStop();
            % TODO: Wait until tcpServer stops.
            
            delete(obj.canvas);
        end
        
    end
    
    methods (Access = protected)
        
        function onClientConnected(obj, ~, eventData) %#ok<INUSL>
            disp(['Client connected from ' eventData.connection.getHostName()]);
        end
        
        function onClientDisconnected(obj, ~, eventData) %#ok<INUSD>
            disp('Client disconnected');
        end
        
        function onInterrupt(obj, ~, ~)
            window = obj.canvas.window;
            
            window.pollEvents();
            escState = window.getKeyState(GLFW.GLFW_KEY_ESCAPE);
            shiftState = window.getKeyState(GLFW.GLFW_KEY_LEFT_SHIFT);
            if escState == GLFW.GLFW_PRESS && shiftState == GLFW.GLFW_PRESS
                obj.server.requestStop();
            end
        end
        
        function onEventReceived(obj, ~, eventData)
            connection = eventData.connection;
            event = eventData.event;
            
            try
                switch event.name
                    case 'getCanvasSize'
                        obj.onEventGetCanvasSize(connection, event);
                    case 'setCanvasProjectionIdentity'
                        obj.onEventSetCanvasProjectionIdentity(connection, event);
                    case 'setCanvasProjectionTranslate'
                        obj.onEventSetCanvasProjectionTranslate(connection, event);                        
                    case 'setCanvasProjectionOrthographic'
                        obj.onEventSetCanvasProjectionOrthographic(connection, event);
                    case 'resetCanvasProjection'
                        obj.onEventResetCanvasProjection(connection, event);
                    case 'setCanvasRenderer'
                        obj.onEventSetCanvasRenderer(connection, event);
                    case 'resetCanvasRenderer'
                        obj.onEventResetCanvasRenderer(connection, event);
                    case 'getMonitorRefreshRate'
                        obj.onEventGetMonitorRefreshRate(connection, event);
                    case 'getMonitorResolution'
                        obj.onEventGetMonitorResolution(connection, event);
                    case 'setMonitorGamma'
                        obj.onEventSetMonitorGamma(connection, event);
                    case 'getMonitorGammaRamp'
                        obj.onEventGetMonitorGammaRamp(connection, event);
                    case 'setMonitorGammaRamp'
                        obj.onEventSetMonitorGammaRamp(connection, event);
                    case 'play'
                        obj.onEventPlay(connection, event);
                    case 'replay'
                        obj.onEventReplay(connection, event);
                    case 'getPlayInfo'
                        obj.onEventGetPlayInfo(connection, event);
                    case 'stop'
                        % 'stop' can only arrive via the main serve loop
                        % when NO play is in progress (during a play it's
                        % polled from inside onEventPlay's frame loop and
                        % never reaches this switch). Outside of a play,
                        % there's nothing to stop — respond with an error.
                        obj.onEventStopOutsidePlay(connection, event);
                    case 'clearMemory'
                        obj.onEventClearMemory(connection, event);
                    otherwise
                        error('Unknown event');
                end
            catch x
                connection.sendEvent(netbox.NetEvent('error', x));
            end
        end
        
        function onEventGetCanvasSize(obj, connection, event) %#ok<INUSD>
            size = obj.canvas.size;
            connection.sendEvent(netbox.NetEvent('ok', size));
        end
        
        function onEventSetCanvasProjectionIdentity(obj, connection, event) %#ok<INUSD>
            obj.canvas.projection.setIdentity();
            connection.sendEvent(netbox.NetEvent('ok'));
        end
        
        function onEventSetCanvasProjectionTranslate(obj, connection, event)
            x = event.arguments{1};
            y = event.arguments{2};
            z = event.arguments{3};
            
            obj.canvas.projection.translate(x, y, z);
            connection.sendEvent(netbox.NetEvent('ok'));
        end
        
        function onEventSetCanvasProjectionOrthographic(obj, connection, event)
            left = event.arguments{1};
            right = event.arguments{2};
            bottom = event.arguments{3};
            top = event.arguments{4};
            
            obj.canvas.projection.orthographic(left, right, bottom, top);
            connection.sendEvent(netbox.NetEvent('ok'));
        end
        
        function onEventResetCanvasProjection(obj, connection, event) %#ok<INUSD>
            obj.canvas.resetProjection();
            connection.sendEvent(netbox.NetEvent('ok'));
        end
        
        function onEventSetCanvasRenderer(obj, connection, event)
            renderer = event.arguments{1};
            
            obj.canvas.setRenderer(renderer);
            connection.sendEvent(netbox.NetEvent('ok'));
        end
        
        function onEventResetCanvasRenderer(obj, connection, event) %#ok<INUSD>
            obj.canvas.resetRenderer();
            connection.sendEvent(netbox.NetEvent('ok'));
        end
        
        function onEventGetMonitorRefreshRate(obj, connection, event) %#ok<INUSD>
            rate = obj.canvas.window.monitor.refreshRate;
            connection.sendEvent(netbox.NetEvent('ok', rate));
        end
        
        function onEventGetMonitorResolution(obj, connection, event) %#ok<INUSD>
            resolution = obj.canvas.window.monitor.resolution;
            connection.sendEvent(netbox.NetEvent('ok', resolution));
        end
        
        function onEventSetMonitorGamma(obj, connection, event)
            gamma = event.arguments{1};
            
            obj.canvas.window.monitor.setGamma(gamma);
            connection.sendEvent(netbox.NetEvent('ok'));
        end
        
        function onEventGetMonitorGammaRamp(obj, connection, event) %#ok<INUSD>
            [red, green, blue] = obj.canvas.window.monitor.getGammaRamp();
            connection.sendEvent(netbox.NetEvent('ok', {red, green, blue}));
        end
        
        function onEventSetMonitorGammaRamp(obj, connection, event)
            red = event.arguments{1};
            green = event.arguments{2};
            blue = event.arguments{3};
            
            obj.canvas.window.monitor.setGammaRamp(red, green, blue);
            connection.sendEvent(netbox.NetEvent('ok'));
        end
        
        function onEventPlay(obj, connection, event)
            player = event.arguments{1};

            connection.setData('player', player);

            % Install the in-frame control-event poller BEFORE responding to
            % the client. This ensures that by the time the client's 'play'
            % call returns and the client is free to send 'stop', the frame
            % loop (which hasn't started yet) will be able to observe it.
            % See spec/decisions/0001-in-frame-stop-polling.md.
            player.setStopChecker(obj.makeStopChecker(connection, player));

            % Unlock client to allow async operations during play.
            connection.sendEvent(netbox.NetEvent('ok'));

            try
                info = player.play(obj.canvas);
            catch x
                info = x;
            end
            connection.setData('playInfo', info);
        end

        function onEventReplay(obj, connection, event) %#ok<INUSD>
            if ~connection.isData('player');
                error('No player exists');
            end

            % Unlock client to allow async operations during play.
            connection.sendEvent(netbox.NetEvent('ok'));

            try
                player = connection.getData('player');
                player.setStopChecker(obj.makeStopChecker(connection, player));
                info = player.play(obj.canvas);
            catch x
                info = x;
            end
            connection.setData('playInfo', info);
        end

        function onEventStopOutsidePlay(obj, connection, event) %#ok<INUSL,INUSD>
            % 'stop' received when no play is running. The mid-play stop
            % path lives inside the in-frame poller; this branch exists so
            % that a stray stop doesn't crash the server with "Unknown event".
            connection.sendEvent(netbox.NetEvent('error', ...
                MException('stage:stop:noActivePlay', ...
                    'No presentation is currently playing — nothing to stop.')));
        end

        function fn = makeStopChecker(obj, connection, player) %#ok<INUSL>
            % Returns a closure the player calls once per frame. It does a
            % non-blocking receive on the connection; if a 'stop' event is
            % pending, responds 'ok' and flips the player's stopRequested
            % flag. Any other event mid-play is an error.
            fn = @() obj.pollForControlEvent(connection, player);
        end

        function pollForControlEvent(obj, connection, player) %#ok<INUSL>
            % Truly non-blocking check: only receive a message if one is
            % already waiting. Falling back to setReceiveTimeout doesn't
            % work here — netbox treats a zero timeout as *infinite*, so
            % calling receiveMessage with no pending data would hang the
            % frame loop forever. See connection.hasPendingMessage.
            if ~connection.hasPendingMessage()
                return;
            end

            try
                message = connection.receiveMessage();
            catch x
                % A read error with pending bytes means the framing is
                % broken — abort the play rather than leaving the socket
                % in an ambiguous state.
                player.requestStop();
                fprintf(2, '[StageServer] receive error during play: %s\n', x.message);
                return;
            end

            % We either have a real event or a disconnect message.
            if ~isfield(message, 'type') || ~strcmp(message.type, 'message')
                % Disconnect or malformed — flag the player to stop so the
                % frame loop exits; the outer serve loop will then notice
                % and tear down the connection naturally.
                player.requestStop();
                return;
            end

            switch message.event.name
                case 'stop'
                    % Consume the stop — acknowledge, flag player.
                    player.requestStop();
                    connection.sendEvent(netbox.NetEvent('ok'));

                otherwise
                    % This is a legitimate message intended for the main
                    % serve loop (e.g. getPlayInfo, which the Symphony
                    % client sends immediately after 'play' and expects to
                    % block until playback completes). Before our in-frame
                    % poll existed, those messages simply sat in the TCP
                    % buffer until the serve loop resumed.
                    %
                    % Put the message back on the connection's receive
                    % queue so the serve loop picks it up after this play
                    % finishes, and disable further polling for the rest
                    % of this play. If we kept polling, we'd re-read our
                    % own put-back message every frame in a loop.
                    try
                        connection.putBackMessage(message);
                    catch putBackEx
                        fprintf(2, '[StageServer] put-back failed: %s\n', ...
                            putBackEx.message);
                    end
                    player.setStopChecker([]);
            end
        end
        
        function onEventGetPlayInfo(obj, connection, event) %#ok<INUSD,INUSL>
            info = connection.getData('playInfo');
            connection.sendEvent(netbox.NetEvent('ok', info));
        end
        
        function onEventClearMemory(obj, connection, event) %#ok<INUSL,INUSD>
            connection.clearData();
            
            memory = inmem('-completenames');
            for i = 1:length(memory)
                % Don't bother clearing anything under the MATLAB root directory
                if strncmp(memory{i}, matlabroot, length(matlabroot))
                    continue;
                end
                [package, name] = appbox.packageName(memory{i});
                % Don't bother clearning anything under the stage package
                if strncmp(package, 'stage.', length('stage.'))
                    continue;
                end
                if ~isempty(package)
                    package = [package '.']; %#ok<AGROW>
                end
                if exist([package name], 'class')
                    clear(name);
                end
            end
            
            connection.sendEvent(netbox.NetEvent('ok'));
        end
        
    end
    
end

