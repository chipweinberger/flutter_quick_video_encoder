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
    filepath: "/documents/video.mp4",
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



