classdef NetEventData < event.EventData
    
    properties (SetAccess = private)
        connection
        event
    end
    
    methods
        
        function obj = NetEventData(connection, event)
            if nargin < 2
                event = [];
            end
            obj.connection = connection;
            obj.event = event;
        end
        
    end
    
end

