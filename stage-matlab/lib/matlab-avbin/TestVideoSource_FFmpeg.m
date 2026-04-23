function TestVideoSource_FFmpeg(filename)
% Side-by-side comparison of VideoSource (AVbin-backed, current
% production) vs VideoSource_FFmpeg (subprocess-backed prototype).
%
% Prints:
%   - Metadata reported by each backend
%   - Cold-start latency (open + first frame)
%   - Pixel-level diff between first N frames of the two backends
%   - Steady-state per-frame latency over M frames
%   - Behavior of seek + nextImage
%
% Usage:
%   TestVideoSource_FFmpeg('C:\path\to\movie.mp4')
%
% Requires both backends on the MATLAB path (they both live in
% lib/matlab-avbin). AVbin MEX binaries must be present on Windows
% for the AVbin side; ffmpeg/ffprobe must be on PATH for the ffmpeg
% side.
%
% Run this from a fresh MATLAB session (outside Stage) to avoid
% interference with Stage's render loop. The test does not touch
% Movie.m or any Symphony protocol.

    if nargin < 1
        error('Usage: TestVideoSource_FFmpeg(''path\\to\\movie.mp4'')');
    end
    if ~exist(filename, 'file')
        error('File not found: %s', filename);
    end

    fprintf('================================================================\n');
    fprintf(' VideoSource A/B test\n');
    fprintf(' File: %s\n', filename);
    fprintf('================================================================\n\n');

    % ------------------------------------------------------------------
    % Cold-start: open + first frame, each backend
    % ------------------------------------------------------------------
    fprintf('--- Cold start (open + first frame) ---\n');

    fprintf('[AVbin]   open: ');
    tic;
    avbinSrc = VideoSource(filename);
    tOpen_avbin = toc;
    fprintf('%6.1f ms | size = %dx%d, dur = %.2f s\n', ...
        tOpen_avbin*1000, avbinSrc.size(1), avbinSrc.size(2), ...
        avbinSrc.duration/1e6);

    fprintf('[AVbin]   first frame: ');
    tic;
    [img1_avbin, ts1_avbin] = avbinSrc.nextImage();
    tFirst_avbin = toc;
    fprintf('%6.1f ms | ts = %.1f us\n', tFirst_avbin*1000, ts1_avbin);

    fprintf('[FFmpeg]  open: ');
    tic;
    ffmpegSrc = VideoSource_FFmpeg(filename);
    tOpen_ffmpeg = toc;
    fprintf('%6.1f ms | size = %dx%d, dur = %.2f s\n', ...
        tOpen_ffmpeg*1000, ffmpegSrc.size(1), ffmpegSrc.size(2), ...
        ffmpegSrc.duration/1e6);

    fprintf('[FFmpeg]  first frame: ');
    tic;
    [img1_ffmpeg, ts1_ffmpeg] = ffmpegSrc.nextImage();
    tFirst_ffmpeg = toc;
    fprintf('%6.1f ms | ts = %.1f us\n', tFirst_ffmpeg*1000, ts1_ffmpeg);

    % ------------------------------------------------------------------
    % Save first frames to disk for visual inspection
    % ------------------------------------------------------------------
    outDir = fullfile(tempdir, 'TestVideoSource_FFmpeg');
    if ~exist(outDir, 'dir')
        mkdir(outDir);
    end
    imwrite(img1_avbin,  fullfile(outDir, 'frame1_avbin.png'));
    imwrite(img1_ffmpeg, fullfile(outDir, 'frame1_ffmpeg.png'));
    % Diagnostic: vertically-flipped ffmpeg frame, to test the flip
    % hypothesis visually without code changes.
    imwrite(flip(img1_ffmpeg, 1), fullfile(outDir, 'frame1_ffmpeg_vflip.png'));

    % ------------------------------------------------------------------
    % Correctness: pixel-level diff across first N frames
    % ------------------------------------------------------------------
    N = 10;
    fprintf('\n--- Pixel fidelity (first %d frames) ---\n', N);
    fprintf('First frames saved to %s\n', outDir);
    fprintf('  frame1_avbin.png        (AVbin reference)\n');
    fprintf('  frame1_ffmpeg.png       (FFmpeg output as-is)\n');
    fprintf('  frame1_ffmpeg_vflip.png (FFmpeg vertically flipped — diagnostic)\n');
    fprintf('Open all three; if _vflip.png matches _avbin.png, the fix is a vertical flip in VideoSource_FFmpeg.\n\n');

    if ~isequal(size(img1_avbin), size(img1_ffmpeg))
        fprintf('!!! SIZE MISMATCH on frame 1: avbin=%s, ffmpeg=%s\n', ...
            mat2str(size(img1_avbin)), mat2str(size(img1_ffmpeg)));
    end

    meanDiffs = zeros(1, N);
    maxDiffs = zeros(1, N);

    diff = double(img1_ffmpeg) - double(img1_avbin);
    meanDiffs(1) = mean(abs(diff(:)));
    maxDiffs(1)  = max(abs(diff(:)));

    % Quantitative check of the flip hypothesis.
    img1_ffmpeg_vflip = flip(img1_ffmpeg, 1);
    diffFlip = double(img1_ffmpeg_vflip) - double(img1_avbin);
    meanDiffFlip = mean(abs(diffFlip(:)));
    maxDiffFlip  = max(abs(diffFlip(:)));

    if meanDiffFlip < meanDiffs(1) / 5
        flipVerdict = '← flip hypothesis SUPPORTED';
    else
        flipVerdict = '  (flip not the answer)';
    end
    fprintf('frame  1: mean |d| = %6.3f LSB, max |d| = %3d LSB\n', ...
        meanDiffs(1), maxDiffs(1));
    fprintf('  with ffmpeg vertically flipped: mean = %.3f, max = %d  %s\n', ...
        meanDiffFlip, maxDiffFlip, flipVerdict);

    % Try all 1D transforms to narrow down the mismatch.
    fprintf('\n--- Transform sweep (frame 1 only) ---\n');
    fprintf('Identity (as-is)         : mean %6.3f, max %3d\n', meanDiffs(1), maxDiffs(1));
    reportTransform(img1_ffmpeg, img1_avbin, 'Vertical flip (rows)     ', flip(img1_ffmpeg, 1));
    reportTransform(img1_ffmpeg, img1_avbin, 'Horizontal flip (cols)   ', flip(img1_ffmpeg, 2));
    reportTransform(img1_ffmpeg, img1_avbin, 'Channel swap (RGB->BGR)  ', flip(img1_ffmpeg, 3));
    reportTransform(img1_ffmpeg, img1_avbin, 'Transpose (swap rows/cols)', permute(img1_ffmpeg, [2, 1, 3]));
    reportTransform(img1_ffmpeg, img1_avbin, 'V + H flip (180 rotate)  ', flip(flip(img1_ffmpeg, 1), 2));
    reportTransform(img1_ffmpeg, img1_avbin, 'V flip + channel swap    ', flip(flip(img1_ffmpeg, 1), 3));

    % Pixel statistics — per-channel mean, min, max for each backend.
    fprintf('\n--- Pixel statistics (frame 1) ---\n');
    for c = 1:3
        chLabel = {'R', 'G', 'B'};
        av = img1_avbin(:,:,c);
        ff = img1_ffmpeg(:,:,c);
        fprintf('Channel %s: AVbin mean=%6.2f min=%3d max=%3d | FFmpeg mean=%6.2f min=%3d max=%3d\n', ...
            chLabel{c}, mean(av(:)), min(av(:)), max(av(:)), ...
            mean(ff(:)), min(ff(:)), max(ff(:)));
    end

    % A couple of corner pixels, for byte-level inspection.
    fprintf('\n--- Corner pixel values (frame 1) ---\n');
    fprintf('Pixel (  1,  1) AVbin = (%3d,%3d,%3d)  FFmpeg = (%3d,%3d,%3d)\n', ...
        img1_avbin(1,1,1), img1_avbin(1,1,2), img1_avbin(1,1,3), ...
        img1_ffmpeg(1,1,1), img1_ffmpeg(1,1,2), img1_ffmpeg(1,1,3));
    fprintf('Pixel (  1,end) AVbin = (%3d,%3d,%3d)  FFmpeg = (%3d,%3d,%3d)\n', ...
        img1_avbin(1,end,1), img1_avbin(1,end,2), img1_avbin(1,end,3), ...
        img1_ffmpeg(1,end,1), img1_ffmpeg(1,end,2), img1_ffmpeg(1,end,3));
    fprintf('Pixel (end,  1) AVbin = (%3d,%3d,%3d)  FFmpeg = (%3d,%3d,%3d)\n', ...
        img1_avbin(end,1,1), img1_avbin(end,1,2), img1_avbin(end,1,3), ...
        img1_ffmpeg(end,1,1), img1_ffmpeg(end,1,2), img1_ffmpeg(end,1,3));
    fprintf('Pixel (ctr,ctr) AVbin = (%3d,%3d,%3d)  FFmpeg = (%3d,%3d,%3d)\n', ...
        img1_avbin(305,305,1), img1_avbin(305,305,2), img1_avbin(305,305,3), ...
        img1_ffmpeg(305,305,1), img1_ffmpeg(305,305,2), img1_ffmpeg(305,305,3));

    % Keep the prior frame from each backend so we can quantify
    % how much THAT backend advanced frame-to-frame.
    prev_avbin  = img1_avbin;
    prev_ffmpeg = img1_ffmpeg;

    for k = 2:N
        [ia, tsA] = avbinSrc.nextImage();
        [ib, tsB] = ffmpegSrc.nextImage();
        if isempty(ia) || isempty(ib)
            fprintf('frame %2d: end of stream reached early (avbin empty=%d, ffmpeg empty=%d)\n', ...
                k, isempty(ia), isempty(ib));
            meanDiffs = meanDiffs(1:k-1);
            maxDiffs  = maxDiffs(1:k-1);
            break;
        end
        d = double(ib) - double(ia);
        meanDiffs(k) = mean(abs(d(:)));
        maxDiffs(k)  = max(abs(d(:)));
        % Frame-to-frame intra-backend change, so we can tell
        % directly if one backend is stuck on the same frame.
        dA = mean(abs(double(ia) - double(prev_avbin)),  'all');
        dB = mean(abs(double(ib) - double(prev_ffmpeg)), 'all');
        fprintf(['frame %2d: |FF-AV|=%6.3f | AVbin mean=%5.2f ts=%7.3fms d_vs_prev=%5.2f ' ...
                 '| FFmpeg mean=%5.2f ts=%7.3fms d_vs_prev=%5.2f\n'], ...
            k, meanDiffs(k), ...
            mean(ia(:)), tsA/1e3, dA, ...
            mean(ib(:)), tsB/1e3, dB);
        prev_avbin  = ia;
        prev_ffmpeg = ib;
    end

    fprintf('\noverall mean |d| across %d frames: %.3f LSB\n', ...
        length(meanDiffs), mean(meanDiffs));
    fprintf('overall max  |d| across %d frames: %d LSB\n', ...
        length(maxDiffs), max(maxDiffs));
    fprintf('(A diff of 0-1 LSB/channel = equivalent; 2-3 = colorspace quirk; >5 = something is wrong)\n');

    % ------------------------------------------------------------------
    % Steady-state throughput: decode M frames from a fresh open
    % ------------------------------------------------------------------
    M = 100;
    fprintf('\n--- Steady-state throughput (%d frames from fresh open) ---\n', M);

    clear avbinSrc ffmpegSrc;  % ensure old processes/handles closed

    avbinSrc2 = VideoSource(filename);
    tic;
    for k = 1:M
        [im, ~] = avbinSrc2.nextImage();
        if isempty(im), break; end
    end
    tTotal_avbin = toc;
    fprintf('[AVbin]   %d frames in %6.1f ms → %5.2f ms/frame\n', ...
        k, tTotal_avbin*1000, tTotal_avbin/k*1000);

    ffmpegSrc2 = VideoSource_FFmpeg(filename);
    tic;
    for k = 1:M
        [im, ~] = ffmpegSrc2.nextImage();
        if isempty(im), break; end
    end
    tTotal_ffmpeg = toc;
    fprintf('[FFmpeg]  %d frames in %6.1f ms → %5.2f ms/frame\n', ...
        k, tTotal_ffmpeg*1000, tTotal_ffmpeg/k*1000);

    fprintf('\n(Target for 60 Hz playback: < 16.7 ms/frame)\n');

    % ------------------------------------------------------------------
    % Seek: jump to 50% of the duration, read one frame
    % ------------------------------------------------------------------
    fprintf('\n--- Seek (50%% through) ---\n');
    halfway_us = avbinSrc2.duration / 2;

    fprintf('[AVbin]   seek to %.2f s: ', halfway_us/1e6);
    tic;
    avbinSrc2.seek(halfway_us);
    [~, tsA] = avbinSrc2.nextImage();
    t = toc;
    fprintf('%5.1f ms, first frame ts = %.2f s\n', t*1000, tsA/1e6);

    fprintf('[FFmpeg]  seek to %.2f s: ', halfway_us/1e6);
    tic;
    ffmpegSrc2.seek(halfway_us);
    [~, tsF] = ffmpegSrc2.nextImage();
    t = toc;
    fprintf('%5.1f ms, first frame ts = %.2f s\n', t*1000, tsF/1e6);

    clear avbinSrc2 ffmpegSrc2;

    fprintf('\n================================================================\n');
    fprintf(' Test complete.\n');
    fprintf('================================================================\n');

end

function reportTransform(ffmpegFrame, avbinFrame, label, transformed)
    if ~isequal(size(transformed), size(avbinFrame))
        fprintf('%s: size mismatch %s vs %s\n', label, ...
            mat2str(size(transformed)), mat2str(size(avbinFrame)));
        return;
    end
    d = double(transformed) - double(avbinFrame);
    m = mean(abs(d(:)));
    mx = max(abs(d(:)));
    fprintf('%s: mean %6.3f, max %3d\n', label, m, mx);
end
