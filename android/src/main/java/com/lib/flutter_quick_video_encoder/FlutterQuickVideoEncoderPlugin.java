package com.lib.flutter_quick_video_encoder;

import android.media.MediaCodec;
import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.media.MediaFormat;
import android.media.MediaMuxer;
import android.util.Log;

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
    private int mWidth;
    private int mHeight;
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
                    int width =         call.argument("width");
                    int height =        call.argument("height");
                    int fps =           call.argument("fps");
                    int videoBitrate =  call.argument("videoBitrate");
                    int audioChannels = call.argument("audioChannels");
                    int audioBitrate =  call.argument("audioBitrate");
                    int sampleRate =    call.argument("sampleRate");
                    String filepath =   call.argument("filepath");

                    // save
                    mFps = fps;
                    mHeight = height;
                    mWidth = width;

                    // reset
                    mVideoFrameIdx = 0;
                    mAudioFrameIdx = 0;

                    // Initialize the MediaMuxer
                    mMediaMuxer = new MediaMuxer(filepath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);

                    // setup video?
                    if (width != 0 && height != 0) {

                        // color format
                        int colorFormat = getColorFormat();
                        if (isColorFormatSupported("video/avc", colorFormat) == false) {
                            result.error("UnsupportedColorFormat", "YUV420Planar is not supported", null);
                            return;
                        }

                        // Video format
                        MediaFormat videoFormat = MediaFormat.createVideoFormat("video/avc", width, height);
                        videoFormat.setInteger(MediaFormat.KEY_BIT_RATE, videoBitrate);
                        videoFormat.setInteger(MediaFormat.KEY_FRAME_RATE, fps);
                        videoFormat.setInteger(MediaFormat.KEY_COLOR_FORMAT, colorFormat);
                        videoFormat.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1);
                        
                        // Video encoder
                        mVideoEncoder = MediaCodec.createEncoderByType("video/avc");
                        mVideoEncoder.configure(videoFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);

                        // add track
                        mVideoTrackIndex = mMediaMuxer.addTrack(mVideoEncoder.getOutputFormat());
                    }

                    // setup audio?
                    if (audioChannels != 0 && sampleRate != 0) {

                        // check audio support
                        int audioProfile = MediaCodecInfo.CodecProfileLevel.AACObjectLC;
                        if (!isAudioFormatSupported(MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, audioProfile)) {
                            result.error("UnsupportedAudioFormat", "AAC audio is not supported", null);
                            return;
                        }

                        // Audio format
                        MediaFormat audioFormat = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, audioChannels);
                        audioFormat.setInteger(MediaFormat.KEY_BIT_RATE, audioBitrate);
                        audioFormat.setInteger(MediaFormat.KEY_AAC_PROFILE, audioProfile);

                        // Audio encoder
                        mAudioEncoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC);
                        mAudioEncoder.configure(audioFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);

                        // add track
                        mAudioTrackIndex = mMediaMuxer.addTrack(mAudioEncoder.getOutputFormat());
                    }

                    // has video?
                    if (width != 0 && height != 0) {
                        try {
                            mVideoEncoder.start();
                        } catch (Exception e) {
                            result.error("Hardware", "Could not start video encoder. Check logs.", null);
                            return;
                        }
                    }

                    // has audio?
                    if (audioChannels != 0 && sampleRate != 0) {
                        try {
                            mAudioEncoder.start();
                        } catch (Exception e) {
                            result.error("Hardware", "Could not start audio encoder. Check logs.", null);
                            return;
                        }
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
                case "appendVideoFrame":
                {
                    byte[] rawRgba = ((byte[]) call.argument("rawRgba"));

                    // convert to yuv420
                    byte[] yuv420 = rgbaToYuv420Planar(rawRgba, mWidth, mHeight);

                    // time
                    long presentationTime = mVideoFrameIdx * 1000000000L / mFps;

                    // feed encoder
                    int inIdx = mVideoEncoder.dequeueInputBuffer(-1);
                    if (inIdx >= 0) {
                        ByteBuffer buf = mVideoEncoder.getInputBuffer(inIdx);
                        buf.clear();
                        buf.put(yuv420);
                        mVideoEncoder.queueInputBuffer(inIdx, 0, yuv420.length, presentationTime, 0);
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
                    byte[] rawPcmArray = ((byte[]) call.argument("rawPcm"));
                    ByteBuffer rawPcm  = ByteBuffer.wrap(rawPcmArray);

                    // push data to encoder
                    int offset = 0;
                    while (offset < rawPcmArray.length) {
                        int inIdx = mAudioEncoder.dequeueInputBuffer(-1);
                        if (inIdx >= 0) {
                            ByteBuffer buf = mAudioEncoder.getInputBuffer(inIdx);
                            buf.clear();

                            // push as many bytes as the encoder allows
                            int remaining = buf.remaining();
                            int toWrite = Math.min(rawPcmArray.length - offset, remaining);
                            buf.put(rawPcmArray, offset, toWrite);

                            // time
                            long beginTime = mAudioFrameIdx * 1000000000L / mFps;
                            long duration = 1000000000L / mFps;
                            long presentationTime = beginTime + (duration * offset) / rawPcmArray.length;

                            // queue
                            mAudioEncoder.queueInputBuffer(inIdx, 0, toWrite, presentationTime, 0);

                            offset += toWrite; 
                        }
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
                    if (mVideoEncoder != null) {
                        mVideoEncoder.stop();
                        mVideoEncoder.release();
                        mVideoEncoder = null;
                    }

                    // flush audio encoder
                    if (mAudioEncoder != null) {
                        mAudioEncoder.stop();
                        mAudioEncoder.release();
                        mAudioEncoder = null;
                    }

                    // close muxer
                    if (mMediaMuxer != null) {
                        //mMediaMuxer.stop();
                        //mMediaMuxer.release();
                        mMediaMuxer = null; 
                    }

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

    private byte[] rgbaToYuv420Planar(byte[] rgba, int width, int height) {
        final int frameSize = width * height;

        int yIndex = 0;
        int uIndex = frameSize;
        int vIndex = frameSize + frameSize / 4;

        byte[] yuv420 = new byte[width * height * 3 / 2];

        int r, g, b, y, u, v;
        for (int j = 0; j < height; j++) {
            for (int i = 0; i < width; i++) {
                r = rgba[j * width * 4 + i * 4] & 0xFF;
                g = rgba[j * width * 4 + i * 4 + 1] & 0xFF;
                b = rgba[j * width * 4 + i * 4 + 2] & 0xFF;

                // RGB to YUV formula
                y = ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16;
                u = ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128;
                v = ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128;

                yuv420[yIndex++] = (byte) Math.max(0, Math.min(255, y));
                if (j % 2 == 0 && i % 2 == 0) {
                    yuv420[uIndex++] = (byte) Math.max(0, Math.min(255, u));
                    yuv420[vIndex++] = (byte) Math.max(0, Math.min(255, v));
                }
            }
        }

        return yuv420;
    }

    @SuppressWarnings({"deprecation"})
    private int getColorFormat() {
        if (android.os.Build.VERSION.SDK_INT >= 23) {
            return MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible;
        } else {
            return MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Planar;
        }
    }
}
