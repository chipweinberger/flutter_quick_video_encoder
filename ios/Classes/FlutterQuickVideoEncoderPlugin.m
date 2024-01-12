#import "FlutterQuickVideoEncoderPlugin.h"
#import <Foundation/Foundation.h>

#import <AVFoundation/AVAssetWriter.h>
#import <AVFoundation/AVAssetWriterInput.h>
#import <AVFoundation/AVMediaFormat.h>
#import <AVFoundation/AVVideoSettings.h>
#import <AVFoundation/AVAudioSettings.h>

#import <CoreMedia/CMFormatDescription.h>
#import <CoreMedia/CMSampleBuffer.h>

#define kOutputBus 0
#define NAMESPACE @"flutter_quick_video_encoder" 

// forward define
CMSampleBufferRef createAudioSampleBuffer(NSData *audioSampleData, int sampleRate);
CMSampleBufferRef createVideoSampleBuffer(int width, int height, CMTime frameTime, NSData *videoFrameData);

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
@property(nonatomic) NSNumber *width;
@property(nonatomic) NSNumber *height;
@property(nonatomic) NSNumber *fps;
@property(nonatomic) NSNumber *sampleRate;
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
        if ([@"setLogLevel" isEqualToString:call.method])
        {
            NSDictionary *args = (NSDictionary*)call.arguments;
            NSNumber *logLevelNumber  = args[@"log_level"];

            self.mLogLevel = (LogLevel)[logLevelNumber integerValue];

            result(@(true));
        }
        else if ([@"setup" isEqualToString:call.method])
        {
            NSDictionary *args = (NSDictionary*)call.arguments;

            // Extract parameters from 'args'
            NSNumber *width = args[@"width"];
            NSNumber *height = args[@"height"];
            NSNumber *fps = args[@"fps"];
            NSNumber *bitrate = args[@"bitrate"];
            NSNumber *sampleRate = args[@"sampleRate"];
            NSString *filepath = args[@"filepath"];

            // remember these
            self.width = width;
            self.height = height;
            self.fps = fps;
            self.sampleRate = sampleRate;

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

            // Video settings
            NSDictionary *compressionProperties = @{AVVideoAverageBitRateKey : bitrate};
            NSDictionary *videoSettings = @{AVVideoCodecKey : AVVideoCodecTypeH264,
                                            AVVideoWidthKey : width,
                                            AVVideoHeightKey : height,
                                            AVVideoCompressionPropertiesKey : compressionProperties};

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

            // Audio settings
            // Adjust audio settings as needed
            NSDictionary* audioSettings = @{AVFormatIDKey : @(kAudioFormatMPEG4AAC),
                                            AVSampleRateKey : sampleRate,
                                            AVNumberOfChannelsKey: @1};

            // Initialize audio input
            self.mAudioInput = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeAudio
                                                            outputSettings:audioSettings];
            self.mAudioInput.expectsMediaDataInRealTime = NO;

            // Add audio input to asset writer
            if (![self.mAssetWriter canAddInput:self.mAudioInput]) {
                result([FlutterError errorWithCode:@"AudioInputAdditionError" 
                                           message:@"Unable to add audio input to AVAssetWriter" 
                                           details:nil]);
                return;
            }
            [self.mAssetWriter addInput:self.mAudioInput];

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

            // Ensure that we have started the session
            if (!self.mAssetWriter.status == AVAssetWriterStatusWriting) {
                [self.mAssetWriter startWriting];
                [self.mAssetWriter startSessionAtSourceTime:kCMTimeZero];
            }

            // Create video sample buffer from the provided data
            CMSampleBufferRef sampleBuffer = NULL;
            sampleBuffer = [self createVideoSampleBufferWithWidth:[self.width intValue] 
                                                        height:[self.height intValue] 
                                                            data:videoFrameData];

            if (!sampleBuffer) {
                result([FlutterError errorWithCode:@"SampleBufferCreationFailed"
                                        message:@"Failed to create video sample buffer"
                                        details:nil]);
                return;
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

            result(@(true));
        }
        else if ([@"appendAudioSamples" isEqualToString:call.method])
        {
            NSDictionary *args = (NSDictionary*)call.arguments;
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

            // Ensure that we have started the session
            if (!self.mAssetWriter.status == AVAssetWriterStatusWriting) {
                [self.mAssetWriter startWriting];
                [self.mAssetWriter startSessionAtSourceTime:kCMTimeZero];
            }

            // Create audio sample buffer from the provided data
            CMSampleBufferRef sampleBuffer = NULL;
            sampleBuffer = [self createAudioSampleBufferWithData:audioSampleData sampleRate:[self.sampleRate intValue]];

            if (!sampleBuffer) {
                result([FlutterError errorWithCode:@"SampleBufferCreationFailed"
                                        message:@"Failed to create audio sample buffer"
                                        details:nil]);
                return;
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

            // Mark the inputs as finished
            [self.mAudioInput markAsFinished];
            [self.mVideoInput markAsFinished];

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
@end


CMSampleBufferRef createVideoSampleBuffer(int width, int height, CMTime frameTime, NSData *videoFrameData)
{
    CVPixelBufferRef pixelBuffer = NULL;
    CVReturn cvReturn = CVPixelBufferCreate(
                            kCFAllocatorDefault,
                            width,
                            height,
                            kCVPixelFormatType_32BGRA,
                            NULL, // cvPixelBufferAtttributes
                            &pixelBuffer);
    
    if (cvReturn != kCVReturnSuccess) {
        NSLog(@"Failed to create pixel buffer: %d", cvReturn);
        return NULL;
    }
    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    
    void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
    memcpy(baseAddress, [videoFrameData bytes], [videoFrameData length]);
    
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
    timingInfo.duration = CMTimeMake(1, 600); // Sample duration
    timingInfo.decodeTimeStamp = kCMTimeInvalid;
    timingInfo.presentationTimeStamp = frameTime;
    
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
        CMFormatDescriptionRelease(formatDescription);
        return NULL;
    }

    CVPixelBufferRelease(pixelBuffer);
    CMFormatDescriptionRelease(formatDescription);
    
    return sampleBuffer;
}


CMSampleBufferRef createAudioSampleBuffer(NSData *audioSampleData, int sampleRate)
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
        .mBytesPerPacket = 2,
        .mFramesPerPacket = 1,
        .mBytesPerFrame = 2,
        .mChannelsPerFrame = 1,
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
        .duration = CMTimeMake(1, sampleRate),
        .decodeTimeStamp = kCMTimeInvalid,
        .presentationTimeStamp = CMTimeMake(0, sampleRate)
    };

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
        CMFormatDescriptionRelease(formatDescription);
        return NULL;
    }

    CFRelease(blockBuffer);
    CMFormatDescriptionRelease(formatDescription);
    return sampleBuffer;
}

