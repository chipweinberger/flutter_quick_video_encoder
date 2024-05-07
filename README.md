[![pub package](https://img.shields.io/pub/v/flutter_quick_video_encoder.svg)](https://pub.dartlang.org/packages/flutter_quick_video_encoder)

<p align="center">
    <img alt="Logo" src="https://github.com/chipweinberger/flutter_quick_video_encoder/blob/master/site/logo.png?raw=true" style="height: 300px;" />
</p>

Quickly encode raw RGB images & PCM audio to MP4 video using the system h264 encoder

## No Dependencies

FlutterQuickVideoEncoder has zero dependencies besides Flutter, Android, iOS, and MacOS themselves.

## ⭐ Stars ⭐

Please star this repo & on [pub.dev](https://pub.dev/packages/flutter_quick_video_encoder). We all benefit from having a larger community.

## Usage

```dart
await FlutterQuickVideoEncoder.setup(
    width: 1920,
    height: 1080,
    fps: 60,
    videoBitrate: 2500000,
    audioChannels: 1,
    audioBitrate: 64000,
    sampleRate: 44100,
    filepath: "/documents/video.mp4", // output file
);
for(int i = 0; i < frameCount; i++) {
    Uint8List rgba = _renderVideoFrame(i);  // your video function
    Uint8List pcm = _renderAudioFrame(i); // your audio function
    await FlutterQuickVideoEncoder.appendVideoFrame(rgba); 
    await FlutterQuickVideoEncoder.appendAudioFrame(pcm);
}
await FlutterQuickVideoEncoder.finish();
```

## Example App

Enable the platforms you need.

```
cd ./example                      
flutter config --enable-macos-desktop                                                      
flutter config --enable-android 
flutter config --enable-ios 
flutter create .
flutter run
```

## Create video frames using ui.Image

The easiest way to render a video frame is to use Flutter!

For example, you can render an RGBA frame using [ui.Image](https://api.flutter.dev/flutter/dart-ui/Image-class.html)

```
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
```

## Create video frames from Widgets

You can also create video frames from widgets, using `RenderRepaintBoundary`

```
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'dart:typed_data';

class MyWidget extends StatefulWidget {
  @override
  _MyWidgetState createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  GlobalKey repaintBoundaryKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: repaintBoundaryKey,
      child: YourWidget(), // Replace with your actual widget
    );
  }

  // you would then call appendVideoFrame with this data
  Future<Uint8List?> captureWidgetAsRGBA() async {
    try {
      RenderRepaintBoundary boundary = repaintBoundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 1.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      print(e);
      return null;
    }
  }
}
```



