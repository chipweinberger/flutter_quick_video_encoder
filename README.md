[![pub package](https://img.shields.io/pub/v/flutter_quick_video_encoder.svg)](https://pub.dartlang.org/packages/flutter_quick_video_encoder)

<p align="center">
    <img alt="Logo" src="https://github.com/chipweinberger/flutter_quick_video_encoder/blob/master/site/logo.png?raw=true" style="height: 300px;" />
</p>

Encode rgb images & pcm audio to a mp4 video, using system video encoders.

## No Dependencies

FlutterQuickVideoEncoder has zero dependencies besides Flutter, Android, iOS, and MacOS themselves.

## Usage

```dart
await FlutterQuickVideoEncoder.setup(sampleRate: 44100, channelCount: 1);
await FlutterQuickVideoEncoder.setFeedThreshold(8000); // feed when below 8000 queued frames
await FlutterQuickVideoEncoder.setFeedCallback(onFeed);
await FlutterQuickVideoEncoder.play();
```

## Other Functions

```dart
// suspend playback but does *not* clear queued samples
await FlutterQuickVideoEncoder.pause();

// clears all queued samples
await FlutterQuickVideoEncoder.clear();

// suspend playback & clear queued samples
await FlutterQuickVideoEncoder.stop();

// get the current number of queued frames
int samples = await FlutterQuickVideoEncoder.remainingFrames();
```

## ⭐ Stars ⭐

Please star this repo & on [pub.dev](https://pub.dev/packages/flutter_quick_video_encoder). We all benefit from having a larger community.

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



