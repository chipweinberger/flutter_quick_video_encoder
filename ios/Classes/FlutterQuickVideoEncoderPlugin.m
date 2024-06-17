#import "FlutterQuickVideoEncoderPlugin.h"
#import <Foundation/Foundation.h>

#import <AVFoundation/AVFoundation.h>
#import <AVFoundation/AVAssetWriter.h>
#import <AVFoundation/AVAssetWriterInput.h>
#import <AVFoundation/AVMediaFormat.h>

#import <CoreMedia/CoreMedia.h> 
#import <CoreMedia/CMFormatDescription.h>
#import <CoreMedia/CMSampleBuffer.h>

#define kOutputBus 0
#define NAMESPACE @"flutter_quick_video_encoder" 

// forward define
CMSampleBufferRef createVideoSampleBuffer(int fps, int videoFrameIdx, int width, int height, NSData *videoFrameData);
CMSampleBufferRef createAudioSampleBuffer(int fps, int audioFrameIdx, int audioChannels, int sampleRate, NSData *audioSampleData);

typedef NS_ENUM(NSUInteger, LogLevel) {
    none = 0,
    error = 1,
    standard = 2,
    verbose = 3,
};

@interface FlutterQuickVideoEncoderPlugin ()
@property(nonatomic) NSObject<FlutterPluginRegistrar> *registrar;
@property(nonatomic) FlutterMethodChannel *mMethodChannel;
@property(nonatomic) LogLevel mLogLevel;
@property(nonatomic) AVAssetWriter *mAssetWriter;
@property(nonatomic) AVAssetWriterInput *mAudioInput;
@property(nonatomic) AVAssetWriterInput *mVideoInput;
@property(nonatomic) int videoFrameIdx;
@property(nonatomic) int audioFrameIdx;
@property(nonatomic) int width;
@property(nonatomic) int height;
@property(nonatomic) int fps;
@property(nonatomic) int audioChannels;
@property(nonatomic) int sampleRate;
@end

@implementation FlutterQuickVideoEncoderPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar
{
    // method channel
    FlutterMethodChannel *methodChannel =
        [FlutterMethodChannel methodChannelWithName:@"flutter_quick_video_encoder/methods"
                                    binaryMessenger:[registrar messenger]];

    // instance
    FlutterQuickVideoEncoderPlugin *instance = [[FlutterQuickVideoEncoderPlugin alloc] init];
    instance.mMethodChannel = methodChannel;
    instance.mLogLevel = verbose;

    [registrar addMethodCallDelegate:instance channel:methodChannel];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result
{
    @try
    {
        if (self.mLogLevel >= standard) {
            NSLog(@"handleMethodCall: %@", call.method);
        }

        if ([@"setLogLevel" isEqualToString:call.method])
        {
            NSDictionary *args = (NSDictionary*)call.arguments;
            NSNumber *nLogLevel  = args[@"log_level"];

            self.mLogLevel = (LogLevel) nLogLevel.integerValue;

            result(@(true));
        }
        else if ([@"setup" isEqualToString:call.method])
        {
            NSDictionary *args = (NSDictionary*)call.arguments;

            // Extract parameters from 'args'
            NSNumber *nWidth =         args[@"width"];
            NSNumber *nHeight =        args[@"height"];
            NSNumber *nFps =           args[@"fps"];
            NSNumber *nVideoBitrate =  args[@"videoBitrate"];
            NSNumber *nAudioChannels = args[@"audioChannels"];
            NSNumber *nAudioBitrate =  args[@"audioBitrate"];
            NSNumber *nSampleRate =    args[@"sampleRate"];
            NSString *nProfileLevel =  args[@"profileLevel"];
            NSString *filepath =       args[@"filepath"];

            // remember these
            self.width =         (int) nWidth.integerValue;
            self.height =        (int) nHeight.integerValue;
            self.fps =           (int) nFps.integerValue;
            self.audioChannels = (int) nAudioChannels.integerValue;
            self.sampleRate =    (int) nSampleRate.integerValue;

            // reset counters
            self.videoFrameIdx = 0;
            self.audioFrameIdx = 0;

            NSError *error = nil;
    
            // Output file URL
            NSURL *fileURL = [NSURL fileURLWithPath:filepath];

            // Check if file already exists at URL, we must delete it
            if ([[NSFileManager defaultManager] fileExistsAtPath:[fileURL path]]) {
                [[NSFileManager defaultManager] removeItemAtURL:fileURL error:&error];
                if (error) {
                    result([FlutterError errorWithCode:@"FileRemoveError" 
                                            message:@"Unable to remove existing file" 
                                            details:[error localizedDescription]]);
                    return;
                }
            }

            // Initialize AVAssetWriter with the file URL
            self.mAssetWriter = [[AVAssetWriter alloc] initWithURL:fileURL
                                                         fileType:AVFileTypeQuickTimeMovie
                                                            error:&error];
            
            if (error) {
                result([FlutterError errorWithCode:@"AVAssetWriterInitializationError" 
                                           message:[error localizedDescription] 
                                           details:nil]);
                return;
            }

            // setup video?
            if (self.width != 0 && self.height != 0) {

                // Video compression settings
                NSMutableDictionary *compressionProperties = [NSMutableDictionary dictionaryWithDictionary:@{
                    AVVideoAverageBitRateKey : @(nVideoBitrate.integerValue)
                }];

                // Add profile level only if it's not 'any'
                if (![nProfileLevel isEqualToString:@"any"]) {
                    NSString *profileLevelValue = [self parseProfileLevel:nProfileLevel];
                    [compressionProperties setObject:profileLevelValue forKey:AVVideoProfileLevelKey];
                }

                // Video settings
                NSDictionary *videoSettings = @{
                    AVVideoCodecKey : AVVideoCodecTypeH264,
                    AVVideoWidthKey : @(self.width),
                    AVVideoHeightKey : @(self.height),
                    AVVideoCompressionPropertiesKey : compressionProperties
                };

                // Initialize video input
                self.mVideoInput = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo
                                                                outputSettings:videoSettings];
                self.mVideoInput.expectsMediaDataInRealTime = YES;

                // Add video input to asset writer
                if (![self.mAssetWriter canAddInput:self.mVideoInput]) {
                    result([FlutterError errorWithCode:@"VideoInputAdditionError" 
                                            message:@"Unable to add video input to AVAssetWriter" 
                                            details:nil]);
                    return;
                }

                [self.mAssetWriter addInput:self.mVideoInput];
            }

            // setup audio?
            if (self.audioChannels != 0 && self.sampleRate != 0) {

                // Audio settings
                NSDictionary* audioSettings = @{
                    AVFormatIDKey : @(kAudioFormatMPEG4AAC),
                    AVSampleRateKey : @(self.sampleRate),
                    AVNumberOfChannelsKey: @(nAudioChannels.integerValue),
                    AVEncoderBitRateKey: @(nAudioBitrate.integerValue)
                };

                // Initialize audio input
                self.mAudioInput = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeAudio
                                                                outputSettings:audioSettings];
                self.mAudioInput.expectsMediaDataInRealTime = YES;

                // Add audio input to asset writer
                if (![self.mAssetWriter canAddInput:self.mAudioInput]) {
                    result([FlutterError errorWithCode:@"AudioInputAdditionError" 
                                            message:@"Unable to add audio input to AVAssetWriter" 
                                            details:nil]);
                    return;
                }
                [self.mAssetWriter addInput:self.mAudioInput];
            }

            // Check status
            if (self.mAssetWriter.status == AVAssetWriterStatusFailed) {
                NSError *error = self.mAssetWriter.error;
                result([FlutterError errorWithCode:@"AVAssetWriterStatus"
                                        message:@"Failed to initialize AVAssetWriter"
                                        details:[error localizedDescription]]);
                return;
            }

            result(@(true));
        }
        else if ([@"appendVideoFrame" isEqualToString:call.method])
        {
            NSDictionary *args = (NSDictionary*)call.arguments;
            FlutterStandardTypedData *rawRgbaData = args[@"rawRgba"];
            NSData *videoFrameData = rawRgbaData.data;

            // Check if the asset writer is initialized
            if (!self.mAssetWriter) {
                result([FlutterError errorWithCode:@"AssetWriterUnavailable"
                                        message:@"AVAssetWriter is not initialized"
                                        details:nil]);
                return;
            }

            // Check if video input is ready
            if (!self.mVideoInput) {
                result([FlutterError errorWithCode:@"AVAssetWriterInputUnavailable"
                                        message:@"AVAssetWriterInput is not initialized"
                                        details:nil]);
                return;
            }

            // Check status
            if (self.mAssetWriter.status == AVAssetWriterStatusFailed) {
                NSError *error = self.mAssetWriter.error;
                result([FlutterError errorWithCode:@"AVAssetWriterStatus"
                                        message:@"AVAssetWriter bad status"
                                        details:[error localizedDescription]]);
                return;
            }

            // Ensure that we have started the session
            if (self.mAssetWriter.status != AVAssetWriterStatusWriting) {
                [self.mAssetWriter startWriting];
                [self.mAssetWriter startSessionAtSourceTime:kCMTimeZero];
            }

            // Create video sample buffer from the provided data
            CMSampleBufferRef sampleBuffer = createVideoSampleBuffer(
                self.fps, self.videoFrameIdx, self.width, self.height, videoFrameData);

            if (!sampleBuffer) {
                result([FlutterError errorWithCode:@"SampleBufferCreationFailed"
                                        message:@"Failed to create video sample buffer"
                                        details:nil]);
                return;
            }

            // wait until ready
            while (self.mVideoInput.readyForMoreMediaData == FALSE) {
                NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:0.1];
                [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
            }

            // wait until ready
            while (CMSampleBufferDataIsReady(sampleBuffer) == FALSE) {
                NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:0.1];
                [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
            }

            // Append the sample buffer
            if (![self.mVideoInput appendSampleBuffer:sampleBuffer]) {
                NSError *error = self.mAssetWriter.error;
                NSString *errorDetails = error ? [error localizedDescription] : @"Unknown error";
                result([FlutterError errorWithCode:@"SampleBufferAppendFailed"
                                        message:@"Failed to append video sample buffer"
                                        details:errorDetails]);
                CFRelease(sampleBuffer);
                return;
            }

            // Release the sample buffer
            CFRelease(sampleBuffer);

            // increment counter
            self.videoFrameIdx += 1;

            result(@(true));
        }
        else if ([@"appendAudioFrame" isEqualToString:call.method])
        {
            NSDictionary *args = (NSDictionary*) call.arguments;
            FlutterStandardTypedData *rawPcmData = args[@"rawPcm"];
            NSData *audioSampleData = rawPcmData.data;

            // Check if the asset writer is initialized
            if (!self.mAssetWriter) {
                result([FlutterError errorWithCode:@"AssetWriterUnavailable"
                                        message:@"AVAssetWriter is not initialized"
                                        details:nil]);
                return;
            }

            // Check if the audio input is initialized
            if (!self.mAudioInput) {
                result([FlutterError errorWithCode:@"AVAssetWriterInputUnavailable"
                                        message:@"AVAssetWriterInput is not initialized"
                                        details:nil]);
                return;
            }

            // Check status
            if (self.mAssetWriter.status == AVAssetWriterStatusFailed) {
                NSError *error = self.mAssetWriter.error;
                result([FlutterError errorWithCode:@"AVAssetWriterStatus"
                                        message:@"AVAssetWriter bad status"
                                        details:[error localizedDescription]]);
                return;
            }

            // Ensure that we have started the session
            if (self.mAssetWriter.status != AVAssetWriterStatusWriting) {
                [self.mAssetWriter startWriting];
                [self.mAssetWriter startSessionAtSourceTime:kCMTimeZero];
            }

            // Create audio sample buffer from the provided data
            CMSampleBufferRef sampleBuffer = createAudioSampleBuffer(
                self.fps, self.audioFrameIdx, self.audioChannels, self.sampleRate, audioSampleData);
            if (!sampleBuffer) {
                result([FlutterError errorWithCode:@"SampleBufferCreationFailed"
                                        message:@"Failed to create audio sample buffer"
                                        details:nil]);
                return;
            }

            // wait until ready
            while (self.mAudioInput.readyForMoreMediaData == FALSE) {
                NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:0.1];
                [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
            }

            // wait until ready
            while (CMSampleBufferDataIsReady(sampleBuffer) == FALSE) {
                NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:0.1];
                [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
            }

            // Append the sample buffer
            if (![self.mAudioInput appendSampleBuffer:sampleBuffer]) {
                NSError *error = self.mAssetWriter.error;
                NSString *errorDetails = error ? [error localizedDescription] : @"Unknown error";
                result([FlutterError errorWithCode:@"SampleBufferAppendFailed"
                                        message:@"Failed to append audio sample buffer"
                                        details:errorDetails]);
                CFRelease(sampleBuffer);
                return;
            }

            // Release the sample buffer
            CFRelease(sampleBuffer);

            // increment counter
            self.audioFrameIdx += 1;

            result(@(true));
        }
        else if ([@"finish" isEqualToString:call.method])
        {
            // Check if the asset writer is initialized
            if (!self.mAssetWriter) {
                result([FlutterError errorWithCode:@"AssetWriterUnavailable"
                                        message:@"AVAssetWriter is not initialized"
                                        details:nil]);
                return;
            }

            // Mark audio as finished
            if (self.audioChannels != 0 && self.sampleRate != 0) {
                [self.mAudioInput markAsFinished];
            }

            // Mark video as finished
            if (self.width != 0 && self.height != 0) {
                [self.mVideoInput markAsFinished];
            }
            

            // Setup a dispatch group to wait for the finishWriting completion
            dispatch_group_t dispatchGroup = dispatch_group_create();
            dispatch_group_enter(dispatchGroup);

            [self.mAssetWriter finishWritingWithCompletionHandler:^{
                // This block is executed when writing is finished
                dispatch_group_leave(dispatchGroup);
            }];

            // Wait for the completion handler to finish
            dispatch_group_wait(dispatchGroup, DISPATCH_TIME_FOREVER);

            // After writing is complete, check for any errors
            if (self.mAssetWriter.status == AVAssetWriterStatusFailed) {
                NSError *error = self.mAssetWriter.error;
                NSString *errorDetails = error ? [error localizedDescription] : @"Unknown error";
                result([FlutterError errorWithCode:@"AssetWriterFinishFailed"
                                        message:@"Failed to finish writing"
                                        details:errorDetails]);
                return;
            }

            result(@(true));
        }
        else
        {
            result([FlutterError errorWithCode:@"functionNotImplemented" message:call.method details:nil]);
        }
    }
    @catch (NSException *e)
    {
        NSString *stackTrace = [[e callStackSymbols] componentsJoinedByString:@"\n"];
        NSDictionary *details = @{@"stackTrace": stackTrace};
        result([FlutterError errorWithCode:@"iosException" message:[e reason] details:details]);
    }
}

- (NSString*)parseProfileLevel:(NSString*)str {
    if ([str isEqualToString:@"high40"])                 {return AVVideoProfileLevelH264High40;}
    else if ([str isEqualToString:@"high41"])            {return AVVideoProfileLevelH264High41;}
    else if ([str isEqualToString:@"main30"])            {return AVVideoProfileLevelH264Main30;}
    else if ([str isEqualToString:@"main31"])            {return AVVideoProfileLevelH264Main31;}
    else if ([str isEqualToString:@"main32"])            {return AVVideoProfileLevelH264Main32;}
    else if ([str isEqualToString:@"main41"])            {return AVVideoProfileLevelH264Main41;}
    else if ([str isEqualToString:@"baseline30"])        {return AVVideoProfileLevelH264Baseline30;}
    else if ([str isEqualToString:@"baseline31"])        {return AVVideoProfileLevelH264Baseline31;}
    else if ([str isEqualToString:@"baseline41"])        {return AVVideoProfileLevelH264Baseline41;}
    else if ([str isEqualToString:@"highAutoLevel"])     {return AVVideoProfileLevelH264HighAutoLevel;}
    else if ([str isEqualToString:@"mainAutoLevel"])     {return AVVideoProfileLevelH264MainAutoLevel;}
    else if ([str isEqualToString:@"baselineAutoLevel"]) {return AVVideoProfileLevelH264BaselineAutoLevel;}
    else                                                 {return AVVideoProfileLevelH264BaselineAutoLevel;}
}
@end


CMSampleBufferRef createVideoSampleBuffer(int fps, int frameIdx, int width, int height, NSData *videoFrameData)
{
#if TARGET_OS_IOS
    NSDictionary *attributes = @{(id)kCVPixelBufferIOSurfacePropertiesKey: @{}};
#else
    NSDictionary *attributes = NULL;
#endif

    CVPixelBufferRef pixelBuffer = NULL;
    CVReturn cvReturn = CVPixelBufferCreate(
                            kCFAllocatorDefault,
                            width,
                            height,
                            kCVPixelFormatType_32BGRA,
                            (__bridge CFDictionaryRef) attributes,
                            &pixelBuffer);
    
    if (cvReturn != kCVReturnSuccess) {
        NSLog(@"Failed to create pixel buffer: %d", cvReturn);
        return NULL;
    }
    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    
    void *bgraData = CVPixelBufferGetBaseAddress(pixelBuffer);
    uint8_t *rgbaData = (uint8_t *)[videoFrameData bytes];

    // convert RGBA to BGRA and copy to pixel buffer
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    for (int y = 0; y < height; y++) {
        uint8_t *rgbaRow = rgbaData + y * width * 4;
        uint8_t *bgraRow = bgraData + y * bytesPerRow;
        for (int x = 0; x < width; x++) {
            size_t pixelIndex = x * 4;
            bgraRow[pixelIndex]     = rgbaRow[pixelIndex + 2]; // Blue
            bgraRow[pixelIndex + 1] = rgbaRow[pixelIndex + 1]; // Green
            bgraRow[pixelIndex + 2] = rgbaRow[pixelIndex];     // Red
            bgraRow[pixelIndex + 3] = rgbaRow[pixelIndex + 3]; // Alpha
        }
    }
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

    CMVideoFormatDescriptionRef formatDescription;
    OSStatus status = CMVideoFormatDescriptionCreateForImageBuffer(
                            kCFAllocatorDefault,
                            pixelBuffer,
                            &formatDescription);
    
    if (status != noErr) {
        NSLog(@"Failed to create format description: %d", status);
        CVPixelBufferRelease(pixelBuffer);
        return NULL;
    }

    CMSampleTimingInfo timingInfo = {0};
    timingInfo.duration = CMTimeMake(1, fps);
    timingInfo.decodeTimeStamp = kCMTimeInvalid;
    timingInfo.presentationTimeStamp = CMTimeMake(frameIdx, fps);
    
    CMSampleBufferRef sampleBuffer = NULL;

    status = CMSampleBufferCreateForImageBuffer(
                          kCFAllocatorDefault, // allocator
                          pixelBuffer, // cvImage
                          true, // dataReady
                          NULL, // makeDataReadyCallback
                          NULL, // makeDataReadyRefContext
                          formatDescription, // formatDescription
                          &timingInfo, // sampleTiming
                          &sampleBuffer ); // out
    
    if (status != noErr) {
        NSLog(@"Failed to create sample buffer: %d", status);
        CVPixelBufferRelease(pixelBuffer);
        CFRelease(formatDescription);
        return NULL;
    }

    CVPixelBufferRelease(pixelBuffer);
    
    return sampleBuffer;
}


CMSampleBufferRef createAudioSampleBuffer(int fps, int frameIdx, int audioChannels, int sampleRate, NSData *audioSampleData)
{
    int numSamples = (int)[audioSampleData length] / sizeof(int16_t);

    CMBlockBufferRef blockBuffer = NULL;
    OSStatus status = CMBlockBufferCreateWithMemoryBlock(
                         kCFAllocatorDefault,
                         (void *)[audioSampleData bytes],
                         [audioSampleData length],
                         kCFAllocatorNull,
                         NULL,
                         0,
                         [audioSampleData length],
                         0,
                         &blockBuffer);

    if (status != kCMBlockBufferNoErr) {
        NSLog(@"Failed to create block buffer: %d", status);
        return NULL;
    }

    AudioStreamBasicDescription audioFormatDescription = {
        .mSampleRate = sampleRate,
        .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
        .mBytesPerPacket = 2 * audioChannels,
        .mFramesPerPacket = 1,
        .mBytesPerFrame = 2 * audioChannels,
        .mChannelsPerFrame = audioChannels,
        .mBitsPerChannel = 16,
        .mReserved = 0
    };

    CMAudioFormatDescriptionRef formatDescription = NULL;

    status = CMAudioFormatDescriptionCreate(
                kCFAllocatorDefault,
                &audioFormatDescription,
                0, // layout num
                NULL, // speaker location layout
                0, // format's magic cookie size
                NULL, // format's magic cookie
                NULL, // extensions
                &formatDescription);

    if (status != noErr) {
        NSLog(@"Failed to create audio format description: %d", status);
        CFRelease(blockBuffer);
        return NULL;
    }

    CMSampleTimingInfo timingInfo = {
        .duration = CMTimeMake(1, fps),
        .decodeTimeStamp = kCMTimeInvalid,
        .presentationTimeStamp = CMTimeMake(frameIdx, fps),
    };

    CMSampleBufferRef sampleBuffer = NULL;

    status = CMSampleBufferCreate(kCFAllocatorDefault,// allocator
                         blockBuffer, // dataBuffer
                         TRUE, // dataReady
                         NULL, // dataReadyCallback
                         NULL, // makeDataReadyRefContext
                         formatDescription,
                         numSamples,
                         1, // numSampleTimingEntries
                         &timingInfo, // timing info
                         0, // number of samples (frames)
                         NULL, // sizes of each sample (frame)
                         &sampleBuffer);

    if (status != noErr) {
        NSLog(@"Failed to create sample buffer: %d", status);
        CFRelease(blockBuffer);
        CFRelease(formatDescription);
        return NULL;
    }

    CFRelease(blockBuffer);
    return sampleBuffer;
}

