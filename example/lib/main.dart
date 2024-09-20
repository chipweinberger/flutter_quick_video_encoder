import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_quick_video_encoder/flutter_quick_video_encoder.dart';

void main() {
  runApp(MyApp());
}

enum ExportMode {
  videoAndAudio,
  videoOnly,
  audioOnly,
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FqveApp();
  }
}

class FqveApp extends StatefulWidget {
  @override
  _FqveAppState createState() => _FqveAppState();
}

class _FqveAppState extends State<FqveApp> {
  static const int width = 480;
  static const int height = 854;
  static const int fps = 30;
  static const int audioChannels = 1;
  static const int sampleRate = 44100;

  BuildContext? _context;

  double _progress = 1;
  bool _shouldCancel = false;

  @override
  void initState() {
    super.initState();
    FlutterQuickVideoEncoder.setLogLevel(LogLevel.verbose);
  }

  Future<Uint8List> _generateVideoFrame(int frameIndex) async {
    const int boxSize = 50; // Size of the moving box

    // Calculate the box position
    int boxX = (frameIndex * 5) % width;
    int boxY = (frameIndex * 5) % height;

    // Paint the moving box
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint();

    // Draw a white background
    paint.color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), paint);

    // Draw the blue box
    paint.color = Colors.blue;
    canvas.drawRect(Rect.fromLTWH(boxX.toDouble(), boxY.toDouble(), boxSize.toDouble(), boxSize.toDouble()), paint);

    // Convert canvas to image
    final picture = recorder.endRecording();
    final img = await picture.toImage(width, height);

    // Convert the image to a byte array
    final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    return byteData!.buffer.asUint8List();
  }

  // generate 1 frame worth of audio samples
  Uint8List _generateAudioFrame(int frameIndex) {
    const int bytesPerSample = 2;
    const double htz = 220.0; // sine wave htz
    const int sampleCount = sampleRate ~/ fps;

    // Calculate the phase shift for this frame to maintain continuity
    double phaseShift = 2 * pi * htz * frameIndex / fps;

    // Create a ByteData buffer for the audio data
    ByteData byteData = ByteData(sampleCount * bytesPerSample * audioChannels);

    // Fill in the buffer
    for (int i = 0; i < sampleCount; i++) {
      double t = i / sampleRate;
      double sampleValue = sin(2 * pi * htz * t + phaseShift);

      // Convert the sample value to 16-bit PCM format
      int sampleInt = (sampleValue * 32767).toInt();

      // Store the sample in the buffer as little-endian
      for (int n = 0; n < audioChannels; n++) {
        int bufferIndex = (i * audioChannels + n) * bytesPerSample;
        byteData.setInt16(bufferIndex, sampleInt, Endian.little);
      }
    }

    // Convert the buffer to Uint8List
    return byteData.buffer.asUint8List();
  }

  Future<void> export({required ExportMode mode}) async {
    try {
      _shouldCancel = false;

      setState(() {
        _progress = 0;
      });

      Directory appDir = await getApplicationDocumentsDirectory();

      // setup
      if (mode == ExportMode.audioOnly) {
        await FlutterQuickVideoEncoder.setup(
          width: 0,
          height: 0,
          fps: fps,
          videoBitrate: 0,
          profileLevel: ProfileLevel.any,
          audioBitrate: 64000,
          audioChannels: audioChannels,
          sampleRate: sampleRate,
          filepath: '${appDir.path}/exportAudioOnly.m4a',
        );
      } else if (mode == ExportMode.videoOnly) {
        await FlutterQuickVideoEncoder.setup(
          width: width,
          height: height,
          fps: fps,
          videoBitrate: 1000000,
          profileLevel: ProfileLevel.any,
          audioBitrate: 0,
          audioChannels: 0,
          sampleRate: 0,
          filepath: '${appDir.path}/exportVideoOnly.mp4',
        );
      } else {
        await FlutterQuickVideoEncoder.setup(
          width: width,
          height: height,
          fps: fps,
          videoBitrate: 1000000,
          profileLevel: ProfileLevel.any,
          audioBitrate: 64000,
          audioChannels: audioChannels,
          sampleRate: sampleRate,
          filepath: '${appDir.path}/exportVideoAndAudio.mp4',
        );
      }

      DateTime startTime = DateTime.now();

      Completer<void> readyForMore = Completer<void>();
      readyForMore.complete();

      int totalFrames = 24 * 60;
      for (int i = 0; i < totalFrames; i++) {
        Uint8List? videoFrame;
        Uint8List? audioFrame;
        if (mode == ExportMode.videoOnly || mode == ExportMode.videoAndAudio) {
          videoFrame = await _generateVideoFrame(i);
        }
        if (mode == ExportMode.audioOnly || mode == ExportMode.videoAndAudio) {
          audioFrame = _generateAudioFrame(i);
        }

        // ensure previous _appendFrames call
        // has completed, so we don't queue too much
        await readyForMore.future;
        readyForMore = Completer<void>();

        // perf: append frames *without* awaiting.
        //  this lets us start work generating the next frames
        //  while these frames are still encoding
        _appendFrames(videoFrame, audioFrame)
            .then((value) => readyForMore.complete())
            .catchError((e) => readyForMore.completeError(e));

        setState(() {
          _progress = (i + 1) / totalFrames;
        });

        if (_shouldCancel) {
          setState(() {
            _progress = 1;
          });
          return;
        }
      }

      // ensure previous _appendFrames call has completed
      await readyForMore.future;

      await FlutterQuickVideoEncoder.finish();

      DateTime endTime = DateTime.now();
      Duration duration = endTime.difference(startTime);

      showSnackBar('Export Success: (${duration.inMilliseconds / 1000} seconds) ${FlutterQuickVideoEncoder.filepath}');

      await Share.shareXFiles([XFile(FlutterQuickVideoEncoder.filepath)]);
    } catch (e) {
      showSnackBar('Error: $e');
    }
  }

  // helper function
  Future<void> _appendFrames(Uint8List? videoFrame, Uint8List? audioFrame) async {
    if (videoFrame != null) await FlutterQuickVideoEncoder.appendVideoFrame(videoFrame);
    if (audioFrame != null) await FlutterQuickVideoEncoder.appendAudioFrame(audioFrame);
    if (audioFrame != null && (Platform.isIOS || Platform.isMacOS)) {
      // hack: going too fast causes clicking noises for some reason
      await Future.delayed(Duration(milliseconds: 1));
    }
  }

  void showSnackBar(String message) {
    print(message);
    final snackBar = SnackBar(content: Text(message));
    if (_context != null && _context!.mounted) {
      ScaffoldMessenger.of(_context!).showSnackBar(snackBar);
    }
  }

  Widget _buildButtons(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          ElevatedButton(
            onPressed: () {
              export(mode: ExportMode.videoAndAudio);
            },
            child: Text('Export Video & Audio'),
          ),
          ElevatedButton(
            onPressed: () {
              export(mode: ExportMode.videoOnly);
            },
            child: Text('Export Video Only'),
          ),
          ElevatedButton(
            onPressed: () {
              export(mode: ExportMode.audioOnly);
            },
            child: Text('Export Audio Only'),
          ),
        ],
      ),
    );
  }

  Widget _buildProgress(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Padding(
            padding: const EdgeInsets.all(32.0),
            child: LinearProgressIndicator(
              value: _progress,
            ),
          ),
          ElevatedButton(
            onPressed: () {
              _shouldCancel = true;
            },
            child: Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        theme: ThemeData(
          primarySwatch: Colors.blue,
        ),
        home: ScaffoldMessenger(
          child: Builder(builder: (context) {
            _context = context;
            return Scaffold(
              appBar: AppBar(
                centerTitle: true,
                title: Text('Flutter Quick Video Encoder'),
              ),
              body: _progress < 1 ? 
                _buildProgress(context) : 
                _buildButtons(context)
            );
          }),
        ));
  }
}
