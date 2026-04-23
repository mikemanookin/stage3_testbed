classdef Monitor < handle
    % Represents a physical display attached to the computer.
    
    properties (SetAccess = private)
        refreshRate     % Refresh rate (Hz)
        resolution      % Resolution [width, height] (pixels)
        physicalSize    % Physical size of display area [width, height] (mm)
        name            % Human-readable monitor name
        handle          % GLFW monitor handle
    end
    
    properties
        getRefreshRateFcn   % Allows users to specify a non-default refresh rate function
    end
    
    methods (Static)
        
        function m = availableMonitors()
            glfwInit();
            
            handles = glfwGetMonitors();
            m = cell(1, numel(handles));
            for i = 1:numel(handles)
                m{i} = stage.core.Monitor(i);
            end
        end
        
    end
    
    methods
        
        function obj = Monitor(number)
            % Constructs a monitor for the display with the given display number. The primary display is number 1. 
            % Further displays increment from there (2, 3, 4, etc).
            
            if nargin < 1
                number = 1;
            end
            
            glfwInit();
            
            monitors = glfwGetMonitors();
            obj.handle = monitors(number);
            
            obj.getRefreshRateFcn = @defaultGetRefreshRateFcn;
        end
        
        function r = get.refreshRate(obj)
            r = obj.getRefreshRateFcn(obj);
        end

        function r = defaultGetRefreshRateFcn(obj)
            % GLFW reports the mode's `refreshRate` as an integer, so a
            % 59.94 Hz display reads as 59. This is the fallback — call
            % measureRefreshRate() against an active window to get the
            % true rate. See spec/specs/MONITOR_TIMING.md.
            mode = glfwGetVideoMode(obj.handle);
            r = mode.refreshRate;
        end

        function r = measureRefreshRate(obj, window, nFrames)
            % Empirically measures the true refresh rate by driving
            % `nFrames` buffer swaps against vsync and computing the
            % median inter-flip interval. Caches the result on this
            % Monitor — subsequent reads of obj.refreshRate return the
            % measured value.
            %
            % Call this once on a visible window after Canvas
            % construction (which sets glfwSwapInterval(1)). GLFW's
            % integer mode rate is a biased undercount on NTSC-era
            % displays (59.94 → 59); downstream code computes state
            % times and frame counts from this rate, so the ~1.6%
            % error accumulates visibly over long epochs. See
            % spec/specs/MONITOR_TIMING.md.
            %
            % Requirements:
            %   - window is an active stage.core.Window, visible
            %   - glfwSwapInterval(1) in effect (Canvas does this)
            %
            % Tuning:
            %   - nFrames defaults to 120 (~2 s at 60 Hz)
            %   - 5 warm-up flips discard compositor transients
            %   - median across frames rejects occasional 2×-interval
            %     outliers from OS scheduling jitter

            if nargin < 3
                nFrames = 120;
            end
            warmupFrames = 5;

            for i = 1:warmupFrames %#ok<FXSET>
                window.flip();
            end

            timestamps = zeros(1, nFrames + 1);
            timestamps(1) = glfwGetTime();
            for i = 1:nFrames
                window.flip();
                timestamps(i + 1) = glfwGetTime();
            end

            intervals = diff(timestamps);
            medianPeriod = median(intervals);

            if medianPeriod <= 0 || ~isfinite(medianPeriod)
                error('stage:monitor:badMeasurement', ...
                    ['Measured median flip period is %g s — cannot ' ...
                    'invert to a refresh rate.'], medianPeriod);
            end

            r = 1 / medianPeriod;

            % Swap the getter so subsequent obj.refreshRate reads return
            % the cached value. Capturing `r` in the closure keeps the
            % cache local to this Monitor instance.
            obj.getRefreshRateFcn = @(~) r;
        end
        
        function r = get.resolution(obj)
            mode = glfwGetVideoMode(obj.handle);
            r = [mode.width, mode.height];
        end
        
        function s = get.physicalSize(obj)
            [w, h] = glfwGetMonitorPhysicalSize(obj.handle);
            s = [w, h];
        end
        
        function n = get.name(obj)
            n = glfwGetMonitorName(obj.handle);
        end
        
        function setGamma(obj, gamma)
            % Sets a gamma ramp from the given gamma exponent.
            glfwSetGamma(obj.handle, gamma);
        end
        
        function [red, green, blue] = getGammaRamp(obj)
            ramp = glfwGetGammaRamp(obj.handle);
            
            red = ramp.red;
            green = ramp.green;
            blue = ramp.blue;
        end
        
        function setGammaRamp(obj, red, green, blue)
            % Sets a gamma ramp from the given red, green, and blue lookup tables. The tables should have length of 256 
            % and values that range from 0 to 65535.
            
            % To row vector.
            red = red(:)';
            green = green(:)';
            blue = blue(:)';
            
            ramp.red = red;
            ramp.green = green;
            ramp.blue = blue;
            glfwSetGammaRamp(obj.handle, ramp);
        end
        
    end
    
end