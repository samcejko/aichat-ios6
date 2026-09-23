#import "ORCommon.h"

NSString * const ORThemeDidChangeNotification    = @"ORThemeDidChangeNotification";
NSString * const ORIncomingFileNotification      = @"ORIncomingFileNotification";
NSString * const ORModelsDidUpdateNotification   = @"ORModelsDidUpdateNotification";
NSString * const ORAPIKeyDidChangeNotification   = @"ORAPIKeyDidChangeNotification";
NSString * const ORSettingsDidChangeNotification = @"ORSettingsDidChangeNotification";
NSString * const ORErrorDomain                   = @"com.samcejko.aichat";

NSError *ORMakeError(NSInteger code, NSString *message)
{
    if (!message) message = @"Unknown error";
    return [NSError errorWithDomain:ORErrorDomain code:code userInfo:@{ NSLocalizedDescriptionKey: message }];
}
