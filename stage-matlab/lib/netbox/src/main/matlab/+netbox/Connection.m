classdef Connection < handle

    properties (Access = private)
        connection
        attachedData
        % One-slot push-back buffer for messages read out of order. See
        % putBackMessage. Used by the Stage server's in-frame control-event
        % poller to peek at a message, act on it if it's a stop, or put it
        % back for the main serve loop to handle later.
        pendingMessage
    end

    methods

        function obj = Connection(host, port)
            if nargin < 2
                obj.connection = host;
            else
                obj.connection = netbox.tcp.TcpConnection();
                obj.connection.connect(host, port);
            end
            obj.attachedData = containers.Map();
            obj.pendingMessage = [];
        end
        
        function n = getHostName(obj)
            n = obj.connection.getHostName();
        end
        
        function disconnect(obj)
            message.type = 'disconnect';
            try %#ok<TRYNC>
                obj.connection.write(message);
            end
            obj.connection.close();
        end
        
        function sendEvent(obj, event)
            message.type = 'message';
            message.event = event;
            obj.connection.write(message);
        end
        
        function setReceiveTimeout(obj, t)
            obj.connection.setReadTimeout(t);
        end
        
        function m = receiveMessage(obj)
            % If a prior caller used putBackMessage to queue a message,
            % return it first — the wire hasn't actually produced a new
            % one, but the semantics are the same from the caller's side.
            if ~isempty(obj.pendingMessage)
                m = obj.pendingMessage;
                obj.pendingMessage = [];
                return;
            end
            try
                m = obj.connection.read();
            catch x
                if strcmp(x.identifier, 'TcpConnection:ReadTimeout')
                    error('Connection:ReceiveTimeout', 'Receive timeout');
                else
                    rethrow(x);
                end
            end
        end

        function putBackMessage(obj, m)
            % Push a message back onto the front of the receive queue so
            % that the NEXT call to receiveMessage returns it instead of
            % reading from the socket. Used by the Stage server's control
            % poller when it reads a non-stop message during a play and
            % needs to leave it for the main serve loop to process after
            % play completes.
            %
            % Errors if a previous put-back hasn't been consumed yet (only
            % one slot). Callers should ensure they don't double-put-back.
            if ~isempty(obj.pendingMessage)
                error('Connection:PutBackFull', ...
                    'A previously put-back message is still pending; cannot queue another');
            end
            obj.pendingMessage = m;
        end

        function tf = hasPendingMessage(obj)
            % True if a message is ready to receive without blocking.
            % Use this before receiveMessage() from inside latency-sensitive
            % paths (e.g. the player frame loop's stop-check). The netbox
            % receive timeout can't be used for "return now" because a
            % timeout of zero is treated as infinite.
            tf = ~isempty(obj.pendingMessage) || obj.connection.hasPendingData();
        end
        
        function setData(obj, key, value)
            obj.attachedData(key) = value;
        end
        
        function d = getData(obj, key)
            d = obj.attachedData(key);
        end
        
        function removeData(obj, key)
            if ~obj.isData(key)
                return;
            end
            obj.attachedData.remove(key);
        end
        
        function tf = isData(obj, key)
            tf = obj.attachedData.isKey(key);
        end
        
        function clearData(obj)
            obj.attachedData = containers.Map();
        end
        
    end
    
end

