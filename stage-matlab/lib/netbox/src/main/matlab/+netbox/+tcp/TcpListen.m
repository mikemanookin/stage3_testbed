classdef TcpListen < handle
    
    properties (Access = private)
        socket
    end
    
    methods
        
        function obj = TcpListen(port)
            if nargin < 1
                port = 5678;
            end
            
            obj.socket = java.net.ServerSocket(port);
        end
        
        function delete(obj)
            obj.close();
        end
        
        function setAcceptTimeout(obj, t)
            obj.socket.setSoTimeout(t);
        end
        
        function connection = accept(obj)
            try
                s = obj.socket.accept();
            catch x
                if isa(x.ExceptionObject, 'java.net.SocketTimeoutException')
                    error('TcpListen:AcceptTimeout', 'Accept timeout');
                else
                    error(char(x.ExceptionObject.getMessage()));
                end
            end 
            connection = netbox.tcp.TcpConnection(s);
        end
        
        function close(obj)
            obj.socket.close();
        end
        
    end
    
end

