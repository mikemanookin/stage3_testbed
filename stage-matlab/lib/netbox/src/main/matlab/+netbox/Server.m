classdef Server < handle
    
    events
        ClientConnected
        ClientDisconnected
        EventReceived
        Interrupt
    end
    
    properties (Access = private)
        stopRequested
    end
    
    methods
        
        function start(obj, port)
            if nargin < 2
                port = 5678;
            end
            
            obj.stopRequested = false;
            
            listen = netbox.tcp.TcpListen(port);
            close = onCleanup(@()delete(listen));
            
            listen.setAcceptTimeout(10);
            
            while ~obj.stopRequested
                try
                    connection = netbox.Connection(listen.accept());
                catch x
                    if strcmp(x.identifier, 'TcpListen:AcceptTimeout')
                        notify(obj, 'Interrupt');
                        continue;
                    else
                        rethrow(x);
                    end
                end
                obj.serve(connection);
            end
        end
        
        function requestStop(obj)
            obj.stopRequested = true;
        end
        
    end
    
    methods (Access = protected)
        
        function serve(obj, connection)
            notify(obj, 'ClientConnected', netbox.NetEventData(connection));
            
            connection.setReceiveTimeout(10);
                        
            while ~obj.stopRequested
                try
                    message = connection.receiveMessage();
                catch x
                    if strcmp(x.identifier, 'Connection:ReceiveTimeout')
                        notify(obj, 'Interrupt');
                        continue;
                    else
                        rethrow(x);
                    end
                end
                
                if strcmp(message.type, 'disconnect')
                    break;
                end
                
                notify(obj, 'EventReceived', netbox.NetEventData(connection, message.event));
            end
            
            notify(obj, 'ClientDisconnected', netbox.NetEventData(connection));
        end
        
    end
    
end

