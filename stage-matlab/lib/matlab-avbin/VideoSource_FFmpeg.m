classdef VideoSource_FFmpeg < handle
    % A cross-platform VideoSource backed by ffmpeg as a subprocess.
    %
    % Mirrors the public API of the AVbin-backed VideoSource in this
    % directory so it can be A/B tested against it without touching
    % Movie.m, VideoPlayer.m, or any Symphony protocol.
    %
    % Requires the `ffmpeg` and `ffprobe` CLI binaries to be on PATH.
    % Install on Windows: `winget install Gyan.FFmpeg`; macOS:
    % `brew install ffmpeg`; Linux: `apt install ffmpeg`.
    %
    % Design notes
    % ------------
    % - Metadata (width, height, duration, frame rate) comes from
    %   `ffprobe` as JSON, parsed with jsondecode.
    % - Frame data comes from a single long-lived `ffmpeg` subprocess
    %   writing raw RGB24 bytes to stdout. Each frame is exactly
    %   width*height*3 bytes; we read them in sequence.
    % - Timestamps are computed as frame_index / frame_rate * 1e6
    %   (microseconds), matching AVbin's units. The raw-video output
    %   from ffmpeg carries no per-frame timestamps of its own.
    % - Seek restarts the subprocess with `-ss <seconds>` before
    %   `-i <file>`. This is fast-seek (nearest keyframe); sufficient
    %   for our seek-to-start use cases. Accurate seek would put -ss
    %   after -i but is ~10x slower to initialize.
    % - Process lifetime is tied to the VideoSource handle. delete()
    %   forcibly terminates ffmpeg and waits for it to exit to avoid
    %   zombies.
    %
    % See spec/TASKS.md § TASK-006 and
    % spec/decisions/0002-cross-platform-direction.md § AVbin cleanup.

    properties (SetAccess = private)
        size        % [width, height] in pixels
        duration    % Total duration in microseconds
    end

    properties (Access = private)
        filename
        frameRate       % frames per second, double
        frameBytes      % width * height * 3
        process         % java.lang.Process, the live ffmpeg subprocess
        channel         % java.nio.channels.ReadableByteChannel over stdout
        stderrBuffer    % Accumulated stderr for error diagnostics
        frameIndex      % 0-based index of the next frame to read
        buffer          % VideoBuffer — used by nextTimestamp peek + preload
    end

    methods

        function obj = VideoSource_FFmpeg(filename)
            if ~exist(filename, 'file')
                error('stage:VideoSource:fileNotFound', ...
                    'Video file not found: %s', filename);
            end

            obj.filename = filename;
            obj.buffer = VideoBuffer();
            obj.frameIndex = 0;

            obj.probeMetadata();
            obj.startProcess(0);
        end

        function delete(obj)
            obj.tearDownProcess();
        end

        function seek(obj, timestamp)
            % Jump to approximately `timestamp` microseconds. Restarts
            % the ffmpeg subprocess because raw-video streams aren't
            % seekable in-stream. Fast-seek to nearest keyframe; for
            % long-GOP content actual first frame read may be slightly
            % earlier than requested.
            seekSeconds = timestamp / 1e6;
            obj.buffer.clear();
            obj.startProcess(seekSeconds);
        end

        function preload(obj)
            % Decode all remaining frames into RAM via VideoBuffer.
            [img, ts] = obj.readAndDecodeNextImage();
            while ~isempty(img)
                obj.buffer.add(img, ts);
                [img, ts] = obj.readAndDecodeNextImage();
            end
        end

        function [img, timestamp] = getImage(obj, time)
            [img, timestamp] = obj.nextImage();
            while ~isempty(img) && timestamp < time
                [img, timestamp] = obj.nextImage();
            end
        end

        function [img, timestamp] = nextImage(obj)
            if obj.buffer.count > 0
                [img, timestamp] = obj.buffer.remove();
                return;
            end
            [img, timestamp] = obj.readAndDecodeNextImage();
        end

        function timestamp = nextTimestamp(obj)
            if obj.buffer.count > 0
                [~, timestamp] = obj.buffer.peek();
                return;
            end
            [img, timestamp] = obj.readAndDecodeNextImage();
            if ~isempty(img)
                obj.buffer.add(img, timestamp);
            end
        end

    end

    methods (Access = private)

        function probeMetadata(obj)
            % Runs `ffprobe -of json` to get width/height/fps/duration.
            % Uses Java ProcessBuilder so argument quoting works
            % identically on Windows/macOS/Linux.

            args = obj.toJavaStringArray({ ...
                'ffprobe', ...
                '-v', 'error', ...
                '-select_streams', 'v:0', ...
                '-show_entries', 'stream=width,height,r_frame_rate,duration', ...
                '-of', 'json', ...
                obj.filename});

            pb = java.lang.ProcessBuilder(args);
            pb.redirectErrorStream(true);
            try
                p = pb.start();
            catch ex
                error('stage:VideoSource:ffprobeLaunchFailed', ...
                    ['Failed to launch ffprobe. Is it on PATH? ' ...
                    'Install with `winget install Gyan.FFmpeg` (Windows), ' ...
                    '`brew install ffmpeg` (macOS), or ' ...
                    '`apt install ffmpeg` (Linux). Java error: %s'], ...
                    ex.message);
            end

            reader = java.io.BufferedReader( ...
                java.io.InputStreamReader(p.getInputStream()));
            sb = java.lang.StringBuilder();
            line = reader.readLine();
            while ~isempty(line)
                sb.append(line);
                sb.append(char(10));
                line = reader.readLine();
            end
            exitCode = p.waitFor();
            output = char(sb.toString());

            if exitCode ~= 0
                error('stage:VideoSource:ffprobeFailed', ...
                    'ffprobe exited with code %d. Output:\n%s', ...
                    exitCode, output);
            end

            info = jsondecode(output);
            if ~isfield(info, 'streams') || isempty(info.streams)
                error('stage:VideoSource:noVideoStream', ...
                    'No video stream found in %s', obj.filename);
            end

            stream = info.streams(1);
            obj.size = [stream.width, stream.height];
            obj.frameBytes = stream.width * stream.height * 3;

            % r_frame_rate is a rational fraction as string: "60/1",
            % "30000/1001" (NTSC), etc.
            parts = sscanf(stream.r_frame_rate, '%d/%d');
            if numel(parts) ~= 2 || parts(2) == 0
                error('stage:VideoSource:badFrameRate', ...
                    'Unparseable r_frame_rate: %s', stream.r_frame_rate);
            end
            obj.frameRate = parts(1) / parts(2);

            % duration is a decimal string in seconds. May be missing
            % for some containers; default to 0 in that case.
            if isfield(stream, 'duration') && ~isempty(stream.duration)
                durSec = str2double(stream.duration);
                if isnan(durSec)
                    durSec = 0;
                end
            else
                durSec = 0;
            end
            obj.duration = durSec * 1e6;
        end

        function startProcess(obj, seekSeconds)
            obj.tearDownProcess();

            argCells = {'ffmpeg', '-hide_banner', '-loglevel', 'error'};
            if seekSeconds > 0
                argCells = [argCells, {'-ss', sprintf('%.6f', seekSeconds)}];
            end
            argCells = [argCells, { ...
                '-i', obj.filename, ...
                '-f', 'rawvideo', ...
                '-pix_fmt', 'rgb24', ...
                '-'}];

            args = obj.toJavaStringArray(argCells);
            pb = java.lang.ProcessBuilder(args);
            pb.redirectErrorStream(false);  % keep stderr separate — we want the frame bytes clean

            try
                obj.process = pb.start();
            catch ex
                error('stage:VideoSource:ffmpegLaunchFailed', ...
                    'Failed to launch ffmpeg: %s', ex.message);
            end

            % Wrap stdout in a NIO channel so we can read into a
            % ByteBuffer. The ByteBuffer is the only Java construct
            % MATLAB will hold as a real Java Object reference
            % (primitive byte[] returns get auto-converted to int8);
            % channel.read(bb) writes inside the Java-managed
            % storage of bb, and bb.array() at the end returns a
            % byte[] whose MATLAB-side auto-convert actually has
            % the data. See the long comment in
            % readAndDecodeNextImage.
            rawStdout = obj.process.getInputStream();
            obj.channel = java.nio.channels.Channels.newChannel(rawStdout);

            obj.stderrBuffer = java.io.BufferedReader( ...
                java.io.InputStreamReader(obj.process.getErrorStream()));
            obj.frameIndex = floor(seekSeconds * obj.frameRate);
        end

        function tearDownProcess(obj)
            if ~isempty(obj.channel)
                try %#ok<TRYNC>
                    obj.channel.close();
                end
                obj.channel = [];
            end
            if ~isempty(obj.stderrBuffer)
                try %#ok<TRYNC>
                    obj.stderrBuffer.close();
                end
                obj.stderrBuffer = [];
            end
            if ~isempty(obj.process)
                try %#ok<TRYNC>
                    obj.process.destroyForcibly();
                    obj.process.waitFor();
                end
                obj.process = [];
            end
        end

        function [img, timestamp] = readAndDecodeNextImage(obj)
            img = [];
            timestamp = [];

            if isempty(obj.channel)
                return;
            end

            % Getting bytes from a Java InputStream into a MATLAB
            % int8/uint8 array via MATLAB is surprisingly tricky.
            % Failed attempts and their symptoms, for the record:
            %
            % (a) readFully(matlabInt8Array)
            %     → MATLAB converts the int8 arg to a Java byte[]
            %       COPY at call boundary. Java fills the copy,
            %       it gets GC'd, MATLAB array stays zero. Silent
            %       all-black frames.
            %
            % (b) readNBytes(N) -> byte[]
            %     → Hung on 1 MB+ returns on this MATLAB build;
            %       may be a bug in auto-conversion of large
            %       returned arrays. Never diagnosed fully.
            %
            % (c) ByteBuffer.allocate(N).array() + read(ba,off,len)
            %     → .array() ALREADY auto-converts to MATLAB int8
            %       at that line. Passing back to read() goes
            %       through another copy. Same silent all-black
            %       as (a).
            %
            % (d) [THIS ONE] keep the ByteBuffer as a Java Object
            %     (MATLAB does NOT auto-unwrap Objects), fill it
            %     via channel.read(ByteBuffer), then call
            %     .array() at the VERY END and let the MATLAB-
            %     side auto-conversion run once with real data.
            %     Works because channel.read acts on Java-managed
            %     storage that MATLAB never touched.
            %
            % The unchanging signature underneath is: MATLAB cannot
            % hold a raw Java byte[] reference, so mutation-through-
            % argument never works. Objects (ByteBuffer, channels,
            % streams) are fine.

            % Allocate a FRESH ByteBuffer per frame. Reusing a single
            % buffer via .clear() and re-reading produced a subtle
            % issue where frames 2+ returned stale data (frame 1
            % matched AVbin, frames 2-10 had mean |d| ≈ 25 — same
            % signature as the all-zeros bug). Suspected cause:
            % MATLAB's auto-conversion of the byte[] returned by
            % .array() may cache / alias in a way that breaks on
            % repeated calls to the same Java object. Allocating a
            % fresh buffer gives MATLAB a fresh Java object to
            % convert each frame and sidesteps the issue entirely.
            % Cost is minor — Java heap allocation + GC of a ~1 MB
            % buffer per frame is <1 ms on any modern JVM.
            bb = java.nio.ByteBuffer.allocate(obj.frameBytes);
            while bb.hasRemaining()
                try
                    n = obj.channel.read(bb);
                catch ex
                    obj.logStderr();
                    rethrow(ex);
                end
                if n < 0
                    % EOF before frame complete — treat as
                    % end-of-stream, return empty.
                    return;
                end
            end

            % bb.array() returns the backing byte[], now filled.
            % MATLAB auto-converts this byte[] to int8 on return —
            % with the actual data, because Java already wrote it.
            matBytes = bb.array();
            rgb = typecast(matBytes, 'uint8');
            % ffmpeg rgb24 rawvideo byte order: row-major, for each
            % pixel R,G,B. Reshape to [3, W, H] (channel-major per
            % pixel), permute to H×W×3 MATLAB image format.
            img = permute(reshape(rgb, 3, obj.size(1), obj.size(2)), [3, 2, 1]);
            timestamp = obj.frameIndex / obj.frameRate * 1e6;
            obj.frameIndex = obj.frameIndex + 1;
        end

        function logStderr(obj)
            % Drains any pending stderr and prints it to the command
            % window. Called only on errors — ffmpeg's stderr buffer
            % fills slowly at -loglevel error, so we never pre-drain.
            if isempty(obj.stderrBuffer)
                return;
            end
            try %#ok<TRYNC>
                line = obj.stderrBuffer.readLine();
                while ~isempty(line)
                    fprintf(2, '[ffmpeg stderr] %s\n', char(line));
                    line = obj.stderrBuffer.readLine();
                end
            end
        end

    end

    methods (Static, Access = private)

        function arr = toJavaStringArray(cellArray)
            % Convert a MATLAB cell array of char vectors into a
            % java.lang.String[]. Needed because MATLAB's Java auto-
            % conversion adds char vectors to an ArrayList as Java
            % char[] objects, not java.lang.String. ProcessBuilder's
            % internal `toArray(new String[...])` then throws
            % ArrayStoreException. Explicit String wrapping fixes it.
            n = numel(cellArray);
            arr = javaArray('java.lang.String', n);
            for k = 1:n
                arr(k) = java.lang.String(cellArray{k});
            end
        end

    end

end
