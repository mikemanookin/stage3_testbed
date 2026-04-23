classdef NetEvent < handle
    
    properties (SetAccess = private)
        name
        arguments
    end
    
    methods
        
        function obj = NetEvent(name, arguments)
            if nargin < 2
                arguments = {};
            end
            if ~iscell(arguments)
                arguments = {arguments};
            end            
            obj.name = name;
            obj.arguments = arguments;
        end
        
    end
    
end

