classdef FlipTimer < handle
    % Records per-flip timing for a presentation. A player calls tick()
    % immediately after each canvas.window.flip(); the timer captures
    % both the inter-flip interval (flipDurations) and the absolute
    % wall-clock offset since the first flip (flipTimestamps).
    %
    % - flipDurations(k) = seconds between flip k and flip k+1.
    %   length(flipDurations) == nFlips - 1
    % - flipTimestamps(k) = seconds from first flip to flip k. First
    %   entry is always 0.
    %   length(flipTimestamps) == nFlips
    %
    % Downstream analysis uses flipDurations for drop detection
    % (values noticeably >1/frameRate) and flipTimestamps for
    % aligning the stimulus trace with response data. See
    % spec/specs/PLAYER_LIFECYCLE.md § PlayInfo.

    properties (SetAccess = private)
        flipDurations
        flipTimestamps
    end

    properties (Access = private)
        t0          % Absolute glfwGetTime() at first tick
        prevTime    % Absolute glfwGetTime() at most recent tick
    end

    methods

        function tick(obj)
            currentTime = glfwGetTime();

            if isempty(obj.t0)
                obj.t0 = currentTime;
                obj.prevTime = currentTime;
                obj.flipTimestamps(end + 1) = 0;
            else
                obj.flipDurations(end + 1) = currentTime - obj.prevTime;
                obj.flipTimestamps(end + 1) = currentTime - obj.t0;
                obj.prevTime = currentTime;
            end
        end

    end

end
