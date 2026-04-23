classdef TcpConnection < handle
    
    properties (Access = private, Transient)
        socket
    end
    
    properties (Access = private)
        readTimeout
    end
    
    methods
        
        function obj = TcpConnection(socket)
            v = version('-java');
            if str2double(v(6:8)) < 1.7
                error('Java 7+ required');
            end
            
            if nargin < 1
                socket = java.net.Socket();
            end
            
            obj.socket = socket;
            obj.readTimeout = 0;
        end
        
        function delete(obj)
            obj.close();
        end
        
        function connect(obj, host, port)
            % Connects to the specified host ip on the specified port.
            
            addr = java.net.InetSocketAddress(host, port);
            timeout = 10000;
            
            try
                obj.socket.connect(addr, timeout);
            catch x
                error(char(x.ExceptionObject.getMessage()));
            end
        end
        
        function close(obj)
            obj.socket.close();
        end
        
        function n = getHostName(obj)
            n = char(obj.socket.getInetAddress().getHostName());
        end
        
        function setReadTimeout(obj, t)
            % Sets read timeout in milliseconds. A timeout less than or equal to zero is considered infinite.
            
            obj.readTimeout = t;
        end
        
        function write(obj, varargin)
            try
                stream = java.io.ObjectOutputStream(obj.socket.getOutputStream());
            catch x
                if isa(x, 'matlab.exception.JavaException')
                    error(char(x.ExceptionObject.getMessage()));
                end
                rethrow(x);
            end
            
            bytes = getByteStreamFromArray(varargin);
            
            try
                stream.writeObject(bytes);
            catch x
                if isa(x, 'matlab.exception.JavaException')
                    error(char(x.ExceptionObject.getMessage()));
                end
                rethrow(x);
            end
        end
        
        function varargout = read(obj)
            in = obj.socket.getInputStream();

            start = tic;
            while in.available() == 0
                if obj.readTimeout > 0 && toc(start) >= obj.readTimeout / 1e3
                    error('TcpConnection:ReadTimeout', 'Read timeout');
                end
            end

            stream = java.io.ObjectInputStream(in);

            result = stream.readObject();

            varargout = getArrayFromByteStream(typecast(result, 'uint8'));
        end

        function tf = hasPendingData(obj)
            % True if the socket has at least one byte ready to read (i.e.
            % a subsequent read() will not block). Used by callers that
            % need a genuinely non-blocking poll — setReadTimeout(0) treats
            % zero as infinite, so it can't be used to mean "return now".
            tf = obj.socket.getInputStream().available() > 0;
        end
        
    end
    
end