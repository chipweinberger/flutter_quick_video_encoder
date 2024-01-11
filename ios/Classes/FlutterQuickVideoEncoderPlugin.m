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
            NSNumber *sampleRate  = args[@"sample_rate"];

            //
            // output file
            // 

            NSError *error = nil;
    
            // AVAssetWriter will not write over an existing file.
            [[NSFileManager defaultManager] removeItemAtURL:self.URL error:NULL];

            //
            // writer
            //
            
            mAssetWriter = [[AVAssetWriter alloc] initWithURL:self.URL
                                                    fileType:AVFileTypeQuickTimeMovie
                                                        error:&error];
            
            // Create and add inputs
            if (error) {
                return NULL;
            }
            
            //
            // video
            // 
            
            NSDictionary *compressionProperties = @{AVVideoAverageBitRateKey : @(1.05)};

            NSDictionary *videoSettings = @{AVVideoCodecKey : AVVideoCodecTypeH264,
                                            AVVideoWidthKey : @(width),
                                            AVVideoHeightKey : @(height),
                                            AVVideoCompressionPropertiesKey : compressionProperties};
            
            if (false == [mAssetWriter canApplyOutputSettings:videoSettings
                                                forMediaType:AVMediaTypeVideo]) {
                return NULL;
            }
            
            mVideoInput = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo
                                                        outputSettings:videoSettings
                                                    sourceFormatHint:NULL];
            
            mVideoInput.expectsMediaDataInRealTime = YES;
            
            if (false == [mAssetWriter canAddInput:mVideoInput]) {
                return NULL;
            }
            
            [mAssetWriter addInput:mVideoInput];
            
            //
            // audio
            // 

            AudioChannelLayout monoLayout = {
                .mChannelLayoutTag = kAudioChannelLayoutTag_Mono,
                .mChannelBitmap = 0,
                .mNumberChannelDescriptions = 0,
            };
            
            NSData *monoLayoutData = [NSData dataWithBytes:&monoLayout
                                                length:offsetof(AudioChannelLayout, mChannelDescriptions)];

            NSDictionary* audioSettings = @{AVFormatIDKey : @(kAudioFormatMPEG4AAC),
                                            AVSampleRateKey:@44100,
                                            AVChannelLayoutKey:monoLayoutData,
                                            AVNumberOfChannelsKey: @1};

            if ( false == [mAssetWriter canApplyOutputSettings:audioSettings
                                                forMediaType:AVMediaTypeAudio] ) {
                return NULL;
            }
            
            mAudioInput = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeAudio
                                                        outputSettings:audioSettings
                                                    sourceFormatHint:NULL];
            
            
            mAudioInput.expectsMediaDataInRealTime = NO;
            
            if (false == [mAssetWriter canAddInput:mAudioInput])
            {
                return NULL;
            }
            
            [mAssetWriter addInput:mAudioInput];

            
            BOOL success = [mAssetWriter startWriting];
            
            if (!success) {
                //error = mAssetWriter.error;
                return NULL;
            }
            
            return self;

            result(@(true));
        }
        else if ([@"appendVideoFrame" isEqualToString:call.method])
        {
            NSDictionary *args = (NSDictionary*)call.arguments;
            NSNumber *sampleRate  = args[@"sample_rate"];

            if (NO == _haveStartedSession) {
                CMTime tStart = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
                [mAssetWriter startSessionAtSourceTime:tStart];
                _haveStartedSession = YES;
                NSLog(@"_haveStartedSession = YES");
            }
            
            // todo: instead of sleeping, use: requestMediaDataWhenReadyOnQueue:mediaInputQueue
            while (mVideoInput.readyForMoreMediaData == FALSE) {
                [NSThread sleepForTimeInterval:0.1];
            }
            
            if (NO == [mVideoInput appendSampleBuffer:sampleBuffer]) {
                *error = mAssetWriter.error;
            }

            result(@(true));
        }
        else if ([@"appendAudioSamples" isEqualToString:call.method])
        {

            if (NO == _haveStartedSession) {
                CMTime tStart = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
                [mAssetWriter startSessionAtSourceTime:tStart];
                _haveStartedSession = YES;
            }
            
            while (mAudioInput.readyForMoreMediaData == FALSE) {
                NSLog(@"audio sleep");
                [NSThread sleepForTimeInterval:0.1];
            }

            if (NO == [mAudioInput appendSampleBuffer:sampleBuffer]) {
                *error = mAssetWriter.error;
            }

            result(@(true));
        }
        else if ([@"finish" isEqualToString:call.method])
        {
            [mAudioInput markAsFinished];
            [mVideoInput markAsFinished];
            [mAssetWriter finishWritingWithCompletionHandler:^{
                ... need to wait until this finishes before we return ....
            }];

            while (...not done?....) {
                [NSThread sleepForTimeInterval:0.1];
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



CMSampleBufferRef createVideoSampleBuffer(int width, int height, int frame, int fps, ...data...) {
    
    CVPixelBufferRef pixelBuffer = NULL;
    
    CVReturn cvReturn = CVPixelBufferCreate(
                            CFAllocatorGetDefault(),
                            width,
                            height,
                            kCVPixelFormatType_32RGBA,
                            NULL, // cvPixelBufferAtttributes
                            &pixelBuffer);
    
    XCTAssertTrue(cvReturn == noErr);
    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    
    uint8_t* baseAddr = (uint8_t*) CVPixelBufferGetBaseAddress(pixelBuffer);
    
    // copy data 
    for (int j = 0; j < width * height * 3; j++) {
        baseAddr[j] = ......
    }
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

    
    CMVideoFormatDescriptionRef formatDesc;
    
    OSStatus status = CMVideoFormatDescriptionCreateForImageBuffer(
                            kCFAllocatorDefault,
                            pixelBuffer,
                            &formatDesc);
    
    XCTAssertTrue(status == noErr);
    
    CMSampleTimingInfo timingInfo = {0};
    timingInfo.duration = kCMTimeInvalid;//CMTimeMake(1, fps);//kCMTimeInvalid;
    timingInfo.decodeTimeStamp = kCMTimeInvalid;
    timingInfo.presentationTimeStamp = CMTimeMake(frame, fps);
    
    CMSampleBufferRef sampleBuffer;
    
    status = CMSampleBufferCreateForImageBuffer(
                          kCFAllocatorDefault, // allocator
                          pixelBuffer, // cvImage
                          true, // dataReady
                          NULL, // makeDataReadyCallback
                          NULL, // makeDataReadyRefContext
                          formatDesc, // formatDescription
                          &timingInfo, // sampleTiming
                          &sampleBuffer ); // out
    
    XCTAssertTrue(status == noErr);
    
    return sampleBuffer;
}

CMSampleBufferRef createAudioSampleBuffer(int iFrame, int sampleRate, int fps, ...data...) {
    
    int numSamples = 44100 / fps;
    int dataLen = numSamples * sizeof(int16_t);
    int16_t* samples = malloc(dataLen);
    
    XCTAssertTrue(samples != NULL);
    
    // copy data
    for(int i = 0; i < numSamples; i++) {
        samples[i] = ....
    }
    
    CMBlockBufferRef tmpBlock = NULL;
    OSStatus status = CMBlockBufferCreateWithMemoryBlock(
                         kCFAllocatorDefault, // allocator
                         samples, // memoryBlock
                         dataLen, // blockLength
                         kCFAllocatorNull, // fallback allocator (if data is NULL)
                         NULL, // customBlockSource
                         0, // offsetToData
                         dataLen, // dataLength
                         0, // flags
                         &tmpBlock);

    XCTAssertTrue(status == noErr);
    
    CMBlockBufferRef block = tmpBlock;
    
    AudioStreamBasicDescription basicDesc = {
        .mSampleRate = 44100,
        .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger,
        .mBytesPerFrame = 2,
        .mFramesPerPacket = 1,
        .mBytesPerPacket = 2,
        .mChannelsPerFrame = 1,
        .mBitsPerChannel = 16,
        .mReserved = 0,
    };
    
    CMAudioFormatDescriptionRef audioFormatDesc;
    
    status = CMAudioFormatDescriptionCreate(
                kCFAllocatorDefault,
                &basicDesc,
                0, // layout num
                NULL, // speaker location layout
                0, // format's magic cookie size
                NULL, // format's magic cookie
                NULL, // extensions
                &audioFormatDesc);
    
    
    XCTAssertTrue(status == noErr);
    
    CMSampleBufferRef sampleBuffer;
    
    CMSampleTimingInfo* timingInfo = calloc(sizeof(CMSampleTimingInfo), 1);
    timingInfo[0].duration = kCMTimeInvalid;//CMTimeMake(1, fps);
    timingInfo[0].decodeTimeStamp = kCMTimeInvalid;
    timingInfo[0].presentationTimeStamp = CMTimeMake(iFrame, fps);
    
    size_t* sampleSizeArray = calloc(sizeof(size_t), 1);
    sampleSizeArray[0] = dataLen;
    
    status = CMSampleBufferCreate(kCFAllocatorDefault,// allocator
                         block, // dataBuffer
                         TRUE, // dataReady
                         NULL, // dataReadyCallback
                         NULL, // makeDataReadyRefContext
                         audioFormatDesc,
                         numSamples,
                         1, // numSampleTimingEntries
                         timingInfo, // timing info
                         1, // number of samples (frames)
                         sampleSizeArray, // sizes of each sample (frame)
                         &sampleBuffer);

    XCTAssertTrue(status == noErr);
    
    return sampleBuffer;
}
