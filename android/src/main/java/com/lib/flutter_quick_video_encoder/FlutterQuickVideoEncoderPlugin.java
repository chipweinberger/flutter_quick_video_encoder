package com.lib.flutter_quick_video_encoder;

import android.media.MediaCodec;
import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.media.MediaFormat;
import android.media.MediaMuxer;

import java.nio.ByteBuffer;
import java.io.PrintWriter;
import java.io.StringWriter;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;


public class FlutterQuickVideoEncoderPlugin implements
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
    private int mVideoTrackIndex;
    private int mAudioTrackIndex;

    @Override
    public void onAttachedToEngine(FlutterPluginBinding binding) {
        BinaryMessenger messenger = binding.getBinaryMessenger();
        mMethodChannel = new MethodChannel(messenger, CHANNEL_NAME);
        mMethodChannel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(FlutterPluginBinding binding) {
        mMethodChannel.setMethodCallHandler(null);
    }

    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        try{
            switch (call.method) {
                case "setLogLevel":
                {
                    result.success(null);
                    break;
                }
                case "setup":
                {
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

                    // check video support
                    int colorFormat = MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface;
                    if (isColorFormatSupported("video/avc", colorFormat) == false) {
                        result.error("UnsupportedColorFormat", "RGBA color format is not supported", null);
                        return;
                    }

                    // check audio support
                    int audioProfile = MediaCodecInfo.CodecProfileLevel.AACObjectLC;
                    if (!isAudioFormatSupported(MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, audioProfile)) {
                        result.error("UnsupportedAudioFormat", "AAC audio format is not supported", null);
                        return;
                    }

                    // Video format
                    MediaFormat videoFormat = MediaFormat.createVideoFormat("video/avc", width, height);
                    videoFormat.setInteger(MediaFormat.KEY_BIT_RATE, bitrate);
                    videoFormat.setInteger(MediaFormat.KEY_FRAME_RATE, fps);
                    videoFormat.setInteger(MediaFormat.KEY_COLOR_FORMAT, colorFormat);
                    videoFormat.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1);
                    
                    // Video encoder
                    mVideoEncoder = MediaCodec.createEncoderByType("video/avc");
                    mVideoEncoder.configure(videoFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);

                    // Audio format
                    MediaFormat audioFormat = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, 1); // Mono channel
                    audioFormat.setInteger(MediaFormat.KEY_BIT_RATE, 64000);
                    audioFormat.setInteger(MediaFormat.KEY_AAC_PROFILE, audioProfile);

                    // Audio encoder
                    mAudioEncoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC);
                    mAudioEncoder.configure(audioFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
                    
                    // Initialize the MediaMuxer
                    mMediaMuxer = new MediaMuxer(filepath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
                    mVideoTrackIndex = mMediaMuxer.addTrack(mVideoEncoder.getOutputFormat());
                    mAudioTrackIndex = mMediaMuxer.addTrack(mAudioEncoder.getOutputFormat());

                    try {
                        mVideoEncoder.start();
                    } catch (Exception e) {
                        result.error("Hardware", "Could not start video encoder. Check logs.", null);
                        return;
                    }

                    try {
                        mAudioEncoder.start();
                    } catch (Exception e) {
                        result.error("Hardware", "Could not start audio encoder. Check logs.", null);
                        return;
                    }

                    try {
                        mMediaMuxer.start();
                    } catch (Exception e) {
                        result.error("Hardware", "Could not start media muxer. Check logs.", null);
                        return;
                    }

                    // success
                    result.success(null);

                    break;
                }
                case "addVideoFrame":
                {
                    ByteBuffer rawRgba = ((ByteBuffer) call.argument("rawRgba"));

                    // time
                    long presentationTime = mVideoFrameIdx * 1000000000L / mFps;

                    // feed encoder
                    int inIdx = mVideoEncoder.dequeueInputBuffer(-1);
                    if (inIdx >= 0) {
                        ByteBuffer buf = mVideoEncoder.getInputBuffer(inIdx);
                        buf.clear();
                        buf.put(rawRgba);
                        mVideoEncoder.queueInputBuffer(inIdx, 0, rawRgba.capacity(), presentationTime, 0);
                    }

                    // retrieve encoded data & feed muxer
                    MediaCodec.BufferInfo bufferInfo = new MediaCodec.BufferInfo();
                    int outIdx = mVideoEncoder.dequeueOutputBuffer(bufferInfo, 0);
                    while (outIdx >= 0) {
                        ByteBuffer buf = mVideoEncoder.getOutputBuffer(outIdx);
                        if (bufferInfo.flags != MediaCodec.BUFFER_FLAG_CODEC_CONFIG) {
                            mMediaMuxer.writeSampleData(mVideoTrackIndex, buf, bufferInfo);
                        }
                        mVideoEncoder.releaseOutputBuffer(outIdx, false);
                        outIdx = mVideoEncoder.dequeueOutputBuffer(bufferInfo, 0);
                    }

                    // increment
                    mVideoFrameIdx++;

                    // success
                    result.success(null);

                    break;
                }
                case "appendAudioFrame":
                {
                    ByteBuffer rawPcm = ((ByteBuffer) call.argument("rawPcm"));

                    // time
                    long presentationTime = mAudioFrameIdx * 1000000000L / mFps;

                    // feed encoder
                    int inIdx = mAudioEncoder.dequeueInputBuffer(-1);
                    if (inIdx >= 0) {
                        ByteBuffer buf = mAudioEncoder.getInputBuffer(inIdx);
                        buf.clear();
                        buf.put(rawPcm);
                        mAudioEncoder.queueInputBuffer(inIdx, 0, rawPcm.capacity(), presentationTime, 0);
                    }

                    // retrieve encoded data & feed muxer
                    MediaCodec.BufferInfo bufferInfo = new MediaCodec.BufferInfo();
                    int outIdx = mAudioEncoder.dequeueOutputBuffer(bufferInfo, 0);
                    while (outIdx >= 0) {
                        ByteBuffer buf = mAudioEncoder.getOutputBuffer(outIdx);
                        if (bufferInfo.flags != MediaCodec.BUFFER_FLAG_CODEC_CONFIG) {
                            mMediaMuxer.writeSampleData(mAudioTrackIndex, buf, bufferInfo);
                        }
                        mAudioEncoder.releaseOutputBuffer(outIdx, false);
                        outIdx = mAudioEncoder.dequeueOutputBuffer(bufferInfo, 0);
                    }

                    result.success(null);
                    break;
                }
                case "finish":
                {
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
                }
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

    private boolean isColorFormatSupported(String mimeType, int desiredColorFormat) {
        MediaCodecInfo codecInfo = getCodecInfo(mimeType);
        if (codecInfo == null) {
            return false;
        }

        MediaCodecInfo.CodecCapabilities capabilities = codecInfo.getCapabilitiesForType(mimeType);
        for (int colorFormat : capabilities.colorFormats) {
            if (colorFormat == desiredColorFormat) {
                return true;
            }
        }

        return false;
    }

    private boolean isAudioFormatSupported(String mimeType, int sampleRate, int profile) {
        MediaCodecInfo codecInfo = getCodecInfo(mimeType);
        if (codecInfo == null) {
            return false;
        }

        MediaCodecInfo.CodecCapabilities capabilities = codecInfo.getCapabilitiesForType(mimeType);

        // Check if sample rate is supported
        boolean isSampleRateSupported = false;
        for (int rate : capabilities.getAudioCapabilities().getSupportedSampleRates()) {
            if (rate == sampleRate) {
                isSampleRateSupported = true;
                break;
            }
        }

        // Check if profile is supported
        boolean isProfileSupported = (capabilities.profileLevels != null);
        for (MediaCodecInfo.CodecProfileLevel level : capabilities.profileLevels) {
            if (level.profile == profile) {
                isProfileSupported = true;
                break;
            }
        }

        return isSampleRateSupported && isProfileSupported;
    }

    private MediaCodecInfo getCodecInfo(String mimeType) {
        MediaCodecList codecList = new MediaCodecList(MediaCodecList.ALL_CODECS);
        for (MediaCodecInfo codecInfo : codecList.getCodecInfos()) {
            if (!codecInfo.isEncoder()) {
                continue;
            }
            String[] types = codecInfo.getSupportedTypes();
            for (String type : types) {
                if (type.equalsIgnoreCase(mimeType)) {
                    return codecInfo;
                }
            }
        }
        return null;
    }
}
