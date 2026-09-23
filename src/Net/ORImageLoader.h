#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

extern NSString * const ORImageDidLoadNotification;   // userInfo[@"url"]

// Downloads remote images referenced in replies through the app's own HTTP stack
// (modern TLS works even though iOS 6 Safari cannot open the same sites). Disk cache in Caches/images.
@interface ORImageLoader : NSObject

+ (instancetype)shared;

// Cached image for a URL, or nil (and a download starts if none is running).
- (UIImage *)imageForURL:(NSString *)url;
- (BOOL)hasFailed:(NSString *)url;
- (NSString *)cachedFilePathForURL:(NSString *)url;   // nil until downloaded
- (void)clearCache;

@end
