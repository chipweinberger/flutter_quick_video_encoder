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

  /// set log level
  static Future<void> setLogLevel(LogLevel level) async {
    return await _invokeMethod('setLogLevel', {'log_level': level.index});
  }

  /// setup encoder
  static Future<void> setup(
      {required int width,
      required int height,
      required int fps,
      required int bitrate,
      required int sampleRate,
      required String filepath}) async {
    return await _invokeMethod('setup', {
      'width': width,
      'height': height,
      'fps': fps,
      'bitrate': bitrate,
      'sampleRate': sampleRate,
      'filepath': filepath,
    });
  }

  /// append raw rgba video frame, 8 bits per channel
  static Future<void> appendVideoFrame(Uint8List rawRgba) async {
    return await _invokeMethod('appendVideoFrame', {
      'rawRgba': rawRgba,
    });
  }

  /// append raw pcm audio samples
  static Future<void> appendAudioSamples(Uint8List rawPcm) async {
    return await _invokeMethod('appendAudioSamples', {
      'rawPcm': rawPcm,
    });
  }

  /// finish writing the video file
  static Future<void> finish() async {
    return await _invokeMethod('finish');
  }

  static Future<T?> _invokeMethod<T>(String method, [dynamic arguments]) async {
    return await _channel.invokeMethod(method, arguments);
  }
}

