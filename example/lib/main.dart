import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_quick_video_encoder/flutter_quick_video_encoder.dart';

void main() {
  runApp(MyApp());
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
  double progress = 0.0;
  static const int width = 1280;
  static const int height = 720;
  static const int fps = 60;
  static const int sampleRate = 44100;

  BuildContext? _context;

  @override
  void initState() {
    super.initState();
    FlutterQuickVideoEncoder.setLogLevel(LogLevel.verbose);
  }

  // generate video data
  Uint8List _generateFrameData(int frameIndex) {
    const int boxSize = 50; // Size of the moving box

    // Initialize an RGBA buffer
    Uint32List buffer = Uint32List(width * height);

    // Calculate the box position
    int boxX = (frameIndex * 5) % width;
    int boxY = (frameIndex * 5) % height;

    // Draw the moving box
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        // Check if the pixel is inside the box
        if (x >= boxX && x < boxX + boxSize && y >= boxY && y < boxY + boxSize) {
          buffer[y * width + x] = 0xFF0000FF; // Blue in ARGB
        } else {
          buffer[y * width + x] = 0xFFFFFFFF; // White in ARGB
        }
      }
    }

    // Convert the buffer to Uint8List
    return Uint8List.view(buffer.buffer);
  }

  // generate audio data
  Uint8List _generateAudioData(int frameIndex) {
    const double htz = 220.0; // sine wave htz
    const int samplesPerFrame = sampleRate ~/ fps;

    // Calculate the phase shift for this frame to maintain continuity
    double phaseShift = 2 * pi * htz * frameIndex / 60;

    // Create a buffer for the audio data
    Int16List audioBuffer = Int16List(samplesPerFrame);

    // Fill in the buffer
    for (int i = 0; i < samplesPerFrame; i++) {
      double t = i / sampleRate;
      double sampleValue = sin(2 * pi * htz * t + phaseShift);

      // Convert the sample value to 16-bit PCM format
      audioBuffer[i] = (sampleValue * 32767).toInt();
    }

    // Convert the buffer to Uint8List
    return Uint8List.view(audioBuffer.buffer);
  }

  Future<void> exportVideo() async {
    try {
      Directory appDir = await getApplicationDocumentsDirectory();
      var filepath = "${appDir.path}/exportedVideo.mp4";

      await FlutterQuickVideoEncoder.setup(
        width: 1280,
        height: 720,
        fps: 60,
        bitrate: 1000000,
        sampleRate: 44100,
        filepath: filepath,
      );

      int totalFrames = 300;
      for (int i = 0; i < totalFrames; i++) {
        Uint8List frameData = _generateFrameData(i);
        await FlutterQuickVideoEncoder.appendVideoFrame(frameData);
        Uint8List audioData = _generateAudioData(i);
        await FlutterQuickVideoEncoder.appendAudioSamples(audioData);
        setState(() {
          progress = (i + 1) / totalFrames;
        });
      }

      await FlutterQuickVideoEncoder.finish();
      showSnackBar('Success: Video Exported: $filepath');
    } catch (e) {
      showSnackBar('Error: $e');
    }
  }

  void showSnackBar(String message) {
    print(message);
    final snackBar = SnackBar(content: Text(message));
    if (_context != null && _context!.mounted) {
      ScaffoldMessenger.of(_context!).showSnackBar(snackBar);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        theme: ThemeData(
          primarySwatch: Colors.blue,
        ),
        home: ScaffoldMessenger(
          child: Builder(
            builder: (context) {
              _context = context;
              return Scaffold(
                appBar: AppBar(
                  centerTitle: true,
                  title: Text('Flutter Quick Video Encoder'),
                ),
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: exportVideo,
                        child: Text('Export Test Video'),
                      ),
                      LinearProgressIndicator(
                        value: progress,
                      ),
                    ],
                  ),
                ),
              );
            }
          ),
        ));
  }
}
