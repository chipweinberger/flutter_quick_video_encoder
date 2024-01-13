package com.lib.flutter_quick_video_encoder;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public class FlutterQuickmVideoEncoderPlugin implements
    FlutterPlugin,
    MethodChannel.MethodCallHandler
{
    private static final String TAG = "[FQVE-Android]";
    private static final String CHANNEL_NAME = "flutter_quick_video_encoder/methods";

    private MethodChannel mMethodChannel;
    private int mFps;
    private MediaCodec mVideoEncoder;
    private MediaCodec mAudioEncoder;
    private MediaMuxer mMediaMuxer;
    private int mVideoFrameIdx;
    private int mAudioFrameIdx;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        BinaryMessenger messenger = binding.getBinaryMessenger();
        mMethodChannel = new MethodChannel(messenger, CHANNEL_NAME);
        mMethodChannel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        mMethodChannel.setMethodCallHandler(null);
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        try{
            switch (call.method) {
                case "setup":

                    // Extract parameters
                    int width = call.argument("width");
                    int height = call.argument("height");
                    int fps = call.argument("fps");
                    int bitrate = call.argument("bitrate");
                    int sampleRate = call.argument("sampleRate");
                    String filepath = call.argument("filepath");

                    // save
                    mFps = fps;

                    // reset
                    mVideoFrameIdx = 0;
                    mAudioFrameIdx = 0;

                    // Video format
                    MediaFormat videoFormat = MediaFormat.createVideoFormat("video/avc", width, height);
                    videoFormat.setInteger(MediaFormat.KEY_BIT_RATE, bitrate);
                    videoFormat.setInteger(MediaFormat.KEY_FRAME_RATE, fps);
                    videoFormat.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface);
                    videoFormat.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, I_FRAME_INTERVAL);
                    
                    // Video encoder
                    mVideoEncoder = MediaCodec.createEncoderByType("video/avc");
                    mVideoEncoder.configure(videoFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);

                    // Audio format
                    MediaFormat audioFormat = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, 1); // Mono channel
                    audioFormat.setInteger(MediaFormat.KEY_BIT_RATE, 64000); // Example bitrate
                    audioFormat.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC);

                    // Audio encoder
                    MediaCodec mAudioEncoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC);
                    mAudioEncoder.configure(audioFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
                    
                    // Initialize the mMediaMuxer
                    mMediaMuxer mMediaMuxer = new mMediaMuxer(filepath, mMediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);

                    // success
                    result.success(null);

                    break;

                case "addVideoFrame":

                    ByteBuffer frameData = ((ByteBuffer) call.argument("rawRgba"));

                    // time
                    long presentationTime = mVideoFrameIdx * 1000000000L / fps;

                    // feed encoder
                    int inIdx = mVideoEncoder.dequeueInputBuffer(-1);
                    if (inIdx >= 0) {
                        ByteBuffer buf = mVideoEncoder.getInputBuffer(inIdx);
                        buf.clear();
                        buf.put(frameData);
                        mVideoEncoder.queueInputBuffer(inIdx, 0, frameData.capacity(), presentationTime, 0);
                    }

                    // retrieve encoded data & feed muxer
                    MediaCodec.BufferInfo bufferInfo = new MediaCodec.BufferInfo();
                    int outIdx = mVideoEncoder.dequeueOutputBuffer(bufferInfo, 0);
                    while (outIdx >= 0) {
                        ByteBuffer buf = mVideoEncoder.getOutputBuffer(outIdx);
                        if (bufferInfo.flags != MediaCodec.BUFFER_FLAG_CODEC_CONFIG) {
                            mMediaMuxer.writeSampleData(videoTrackIndex, buf, bufferInfo);
                        }
                        mVideoEncoder.releaseOutputBuffer(outIdx, false);
                        outIdx = mVideoEncoder.dequeueOutputBuffer(bufferInfo, 0);
                    }

                    // increment
                    mVideoFrameIdx++;

                    // success
                    result.success(null);

                    break;

                case "appendAudioFrame":

                    ByteBuffer frameData = ((ByteBuffer) call.argument("rawRgba"));

                    // time
                    long presentationTime = mAudioFrameIdx * 1000000000L / fps;

                    // feed encoder
                    int inIdx = mVideoEncoder.dequeueInputBuffer(-1);
                    if (inIdx >= 0) {
                        ByteBuffer buf = mVideoEncoder.getInputBuffer(inIdx);
                        buf.clear();
                        buf.put(frameData);
                        mVideoEncoder.queueInputBuffer(inIdx, 0, frameData.capacity(), presentationTime, 0);
                    }

                    // retrieve encoded data & feed muxer
                    MediaCodec.BufferInfo bufferInfo = new MediaCodec.BufferInfo();
                    int outIdx = mVideoEncoder.dequeueOutputBuffer(bufferInfo, 0);
                    while (outIdx >= 0) {
                        ByteBuffer buf = mVideoEncoder.getOutputBuffer(outIdx);
                        if (bufferInfo.flags != MediaCodec.BUFFER_FLAG_CODEC_CONFIG) {
                            mMediaMuxer.writeSampleData(videoTrackIndex, buf, bufferInfo);
                        }
                        mVideoEncoder.releaseOutputBuffer(outIdx, false);
                        outIdx = mVideoEncoder.dequeueOutputBuffer(bufferInfo, 0);
                    }

                    result.success(null);
                    break;

                case "finish":

                    // flush video encoder
                    mVideoEncoder.stop();
                    mVideoEncoder.release();

                    // flush audio encoder
                    mAudioEncoder.stop();
                    mAudioEncoder.release();

                    // close muxer
                    mMediaMuxer.stop();
                    mMediaMuxer.release();

                    result.success(null);

                    break;
                default:
                    result.notImplemented();
                    break;
            }
        } catch (Exception e) {
            StringWriter sw = new StringWriter();
            PrintWriter pw = new PrintWriter(sw);
            e.printStackTrace(pw);
            String stackTrace = sw.toString();
            result.error("androidException", e.toString(), stackTrace);
            return;
        }
    }
}
