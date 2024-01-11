package com.lib.flutter_quick_video_encoder;



public class FlutterQuickVideoEncoderPlugin implements
    FlutterPlugin,
    MethodChannel.MethodCallHandler
{
    private static final String TAG = "[FQVE-Android]";
    private static final String CHANNEL_NAME = "flutter_quick_video_encoder/methods";
    private MethodChannel mMethodChannel;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        BinaryMessenger messenger = binding.getBinaryMessenger();
        mMethodChannel = new MethodChannel(messenger, CHANNEL_NAME);
        mMethodChannel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        mMethodChannel.setMethodCallHandler(null);
        cleanup();
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "setLogLevel":
            case "setup":
            case "appendVideoFrame":
            case "appendAudioSamples":
            case "finish":
        }
    }
}
