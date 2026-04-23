classdef VideoPlayer < handle
    
    properties
        playbackSpeed = PlaybackSpeed.NORMAL
    end
    
    properties (SetAccess = private)
        isPlaying
    end
    
    properties (Access = private)
        source
        start
        playPosition
        previousImage
    end
    
    methods
        
        function obj = VideoPlayer(source)
            obj.source = source;
            obj.isPlaying = false;
            obj.previousImage = {[], []};
        end
        
        function play(obj)
            % Begins playing the current source.
            
            if obj.isPlaying
                error('Player is already playing');
            end
            
            obj.start = tic;
            obj.isPlaying = true;
        end
        
        function p = get.playPosition(obj)
            if ~obj.isPlaying
                p = 0;
                return;
            end
            
            if obj.playbackSpeed == PlaybackSpeed.FRAME_BY_FRAME
                p = obj.source.nextTimestamp();
            else
                p = toc(obj.start) * 1e6 * obj.playbackSpeed;
            end
        end
        
        function img = getImage(obj)
            % Gets an image of the video frame at the current play position.
            
            position = obj.playPosition;
            if ~isempty(position) && ~isempty(obj.previousImage{2}) && position <= obj.previousImage{2}
                img = obj.previousImage{1};
                return;
            end
                        
            [img, timestamp] = obj.source.getImage(position);
            obj.previousImage = {img, timestamp};
        end
        
    end
    
end

