// Shared macros and constants. Everything here must be iOS 5.0 safe.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Any API newer than the iOS 5.0 deployment target is a hard error in files that include this header.
#pragma clang diagnostic error "-Wunguarded-availability"

#define L(key) NSLocalizedString((key), nil)
#define ORIsPad() (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
#define ORLog(fmt, ...) NSLog((@"[AIChat] " fmt), ##__VA_ARGS__)

// Runs a block on the main thread (immediately if already there).
static inline void ORMain(dispatch_block_t block)
{
    if ([NSThread isMainThread]) block();
    else dispatch_async(dispatch_get_main_queue(), block);
}

extern NSString * const ORThemeDidChangeNotification;
extern NSString * const ORIncomingFileNotification;     // userInfo[@"path"] = file copied into Attachments
extern NSString * const ORModelsDidUpdateNotification;
extern NSString * const ORAPIKeyDidChangeNotification;
extern NSString * const ORSettingsDidChangeNotification;
extern NSString * const ORErrorDomain;

// NSError codes in ORErrorDomain (HTTP errors use the HTTP status as code)
enum {
    ORErrorNetwork      = -1,
    ORErrorTLS          = -2,
    ORErrorCertificate  = -3,
    ORErrorTimeout      = -4,
    ORErrorCancelled    = -5,
    ORErrorBadResponse  = -6,
    ORErrorNoAPIKey     = -7,
    ORErrorNoModel      = -8,
};

NSError *ORMakeError(NSInteger code, NSString *message);
