import 'dart:async';

import 'package:flutter/services.dart';

enum LogLevel {
  none,
  error,
  standard,
  verbose,
}

class FlutterQuickVideoEncoder {
  static const MethodChannel _channel = const MethodChannel('flutter_quick_video_encoder/methods');

  // setup values
  static int width = 0;
  static int height = 0;
  static int fps = 0;
  static int audioChannels = 0;
  static int sampleRate = 0;

  /// set log level
  static Future<void> setLogLevel(LogLevel level) async {
    return await _invokeMethod('setLogLevel', {'log_level': level.index});
  }

  /// setup encoder
  static Future<void> setup(
      {required int width,
      required int height,
      required int fps,
      required int videoBitrate,
      required int audioChannels,
      required int audioBitrate,
      required int sampleRate,
      required String filepath}) async {
    FlutterQuickVideoEncoder.width = width;
    FlutterQuickVideoEncoder.height = height;
    FlutterQuickVideoEncoder.fps = fps;
    FlutterQuickVideoEncoder.audioChannels = audioChannels;
    FlutterQuickVideoEncoder.sampleRate = sampleRate;
    return await _invokeMethod('setup', {
      'width': width,
      'height': height,
      'fps': fps,
      'videoBitrate': videoBitrate,
      'audioChannels': audioChannels,
      'audioBitrate': audioBitrate,
      'sampleRate': sampleRate,
      'filepath': filepath,
    });
  }

  /// append raw rgba video frame, 8 bits per channel
  static Future<void> appendVideoFrame(Uint8List rawRgba) async {
    assert(rawRgba.length == width * height * 4, "invalid data length");
    return await _invokeMethod('appendVideoFrame', {
      'rawRgba': rawRgba,
    });
  }

  /// append raw pcm audio samples
  ///  - 16 bit, little-endiant
  ///  - when using stereo audio, samples should be interleaved left channel first
  static Future<void> appendAudioFrame(Uint8List rawPcm) async {
    assert(rawPcm.length == (sampleRate * audioChannels * 2) / fps, "invalid data length");
    return await _invokeMethod('appendAudioFrame', {
      'rawPcm': rawPcm,
    });
  }

  /// finish writing the video file
  static Future<void> finish() async {
    width = 0;
    height = 0;
    fps = 0;
    audioChannels = 0;
    sampleRate = 0;
    return await _invokeMethod('finish');
  }

  static Future<T?> _invokeMethod<T>(String method, [dynamic arguments]) async {
    return await _channel.invokeMethod(method, arguments);
  }
}
