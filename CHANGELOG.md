## 1.6.0
* **[Perf]** Android: speed up android perf about 2x

## 1.5.1
* **[Fix]** iOS: only call `markAsFinished` when needed

## 1.5.0
* **[Fix]** Android: Switch to `YUV420Flexible` to fix `YUV420Planar is not supported` error

## 1.4.1
* **[Fix]** android must increment mAudioFrameIdx

## 1.4.0
* **[Fix]** android was not working

## 1.3.1
* **[Pub]** update package description

## 1.3.0
* **[Feature]** add android support

## 1.2.1
* **[Fix]** iOS: mostly fixes clicking noises by using `audioWriterInput.expectsMediaDataInRealTime`

## 1.2.0
* **[Feature]** add support for audio-only

## 1.1.1
* **[Improve]** clear encoding params after `finish` is called, not before

## 1.1.0
* **[Fix]** iOS: needed to set `kCVPixelBufferIOSurfacePropertiesKey`

## 1.0.4
* **[Fix]** iOS: must convert RGBA to BGRA

## 1.0.3
* **[Feature]** add support for profileLevel on ios

## 1.0.2
* **[Fix]** must ensure output directory exists

## 1.0.1
* **[Feature]** add support for audio bitrate and stereo audio

## 1.0.0
* **[Feature]** Initial Release.
