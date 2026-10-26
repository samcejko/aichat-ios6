#import <Foundation/Foundation.h>
@class ORHTTPRequest;
extern NSString * const ORProviderDidChangeNotification;
@interface ORProvider : NSObject
+ (NSArray *)presets;
+ (NSDictionary *)preset:(NSString *)identifier;
+ (NSString *)normalizeBaseURL:(NSString *)value error:(NSError **)error;
+ (NSString *)identityForID:(NSString *)identifier baseURL:(NSString *)base protocol:(NSString *)protocol;
+ (NSDictionary *)current;
+ (BOOL)isOpenRouter;
+ (ORHTTPRequest *)request:(NSString *)method suffix:(NSString *)suffix profile:(NSDictionary *)profile key:(NSString *)key;
+ (NSDictionary *)adaptBody:(NSDictionary *)body profile:(NSDictionary *)profile;
+ (NSDictionary *)adaptResponse:(NSDictionary *)json profile:(NSDictionary *)profile;
+ (NSDictionary *)adaptEvent:(NSDictionary *)json profile:(NSDictionary *)profile;
@end
