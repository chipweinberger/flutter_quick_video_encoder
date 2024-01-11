#import "FlutterQuickVideoEncoderPlugin.h"
#import <AVFoundation/AVFoundation.h>

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
        else if ([@"appendVideoFrame" isEqualToString:call.method])
        {
            NSDictionary *args = (NSDictionary*)call.arguments;
            NSNumber *sampleRate  = args[@"sample_rate"];

            
            result(@(true));
        }
        else if ([@"appendAudioSamples" isEqualToString:call.method])
        {
            result(@(true));
        }
        else if ([@"finish" isEqualToString:call.method])
        {

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
