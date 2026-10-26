#import <Foundation/Foundation.h>
#import "ORHTTPRequest.h"

typedef void (^ORJSONCompletion)(NSDictionary *json, NSError *error);

// Thin wrapper around the OpenRouter REST API. All completion blocks run on the main thread.
@interface OROpenRouterClient : NSObject

+ (instancetype)shared;

- (ORHTTPRequest *)fetchModels:(void (^)(NSArray *models, NSError *error))completion;
- (ORHTTPRequest *)fetchKeyInfoWithKey:(NSString *)apiKey completion:(ORJSONCompletion)completion;   // GET /api/v1/key -> "data"

// Streaming: onDelta receives every parsed chunk dictionary; completion receives the last chunk
// that carried "usage" (or nil) and any error. Non streaming: completion receives the response JSON.
- (ORHTTPRequest *)chatCompletionWithBody:(NSDictionary *)body
                                   stream:(BOOL)stream
                                  onDelta:(void (^)(NSDictionary *chunk))onDelta
                               completion:(void (^)(NSDictionary *finalJSON, NSError *error))completion;

// Explicit immutable profile, also used by the on-device transport regression tests.
- (ORHTTPRequest *)chatCompletionWithBody:(NSDictionary *)body stream:(BOOL)stream profile:(NSDictionary *)profile key:(NSString *)key onDelta:(void (^)(NSDictionary *chunk))onDelta completion:(ORJSONCompletion)completion;
+ (NSError *)errorFromResponseJSON:(id)json status:(NSInteger)status;
+ (NSString *)hintForHTTPStatus:(NSInteger)status;

@end
