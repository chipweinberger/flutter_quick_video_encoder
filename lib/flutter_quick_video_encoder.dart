import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

enum LogLevel {
  none,
  error,
  standard,
  verbose,
}

// H264 profile level
enum ProfileLevel {
  any,
  high40,
  high41,
  main30,
  main31,
  main32,
  main41,
  baseline30,
  baseline31,
  baseline41,
  highAutoLevel,
  mainAutoLevel,
  baselineAutoLevel,
}

class FlutterQuickVideoEncoder {
  static const MethodChannel _channel = const MethodChannel('flutter_quick_video_encoder/methods');

  // setup values
  static int width = 0;
  static int height = 0;
  static int fps = 0;
  static int audioChannels = 0;
  static int sampleRate = 0;

  // log level
  static LogLevel logLevel = LogLevel.standard;

  /// set log level
  static Future<void> setLogLevel(LogLevel level) async {
    logLevel = level;
    return await _invokeMethod('setLogLevel', {'log_level': level.index});
  }

  /// setup encoder
  static Future<void> setup(
      {required int width,
      required int height,
      required int fps,
      required int videoBitrate,
      required ProfileLevel profileLevel,
      required int audioChannels,
      required int audioBitrate,
      required int sampleRate,
      required String filepath}) async {
    _createIntermediateDirectories(filepath);
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
      'profileLevel': profileLevel.toString().split('.')[1],
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
    try {
      await _invokeMethod('finish');
    } finally {
      width = 0;
      height = 0;
      fps = 0;
      audioChannels = 0;
      sampleRate = 0;
    }
  }

  // create output directory
  static void _createIntermediateDirectories(String filepath) {
    File file = File(filepath);
    Directory dir = file.parent;
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  }

  static Future<T?> _invokeMethod<T>(String method, [dynamic arguments]) async {
    // log args
    if (logLevel.index >= LogLevel.standard.index) {
      if (method == "appendVideoFrame") {
        print("[FQVE] '<$method>' rawRgba: ${arguments['rawRgba'].length} bytes");
      } else if (method == "appendAudioFrame") {
        print("[FQVE] '<$method>' rawPcm: ${arguments['rawPcm'].length} bytes");
      } else {
        print("[FQVE] '<$method>' args: $arguments");
      }
    }

    // invoke
    var result = await _channel.invokeMethod(method, arguments);

    // log result
    if (logLevel.index >= LogLevel.standard.index) {
      print("[FQVE] <$method> result: $result");
    }

    return result;
  }
}
