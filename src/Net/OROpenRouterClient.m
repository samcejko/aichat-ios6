#import "OROpenRouterClient.h"
#import "ORSSEParser.h"
#import "ORSettings.h"
#import "ORUtils.h"
#import "ORCommon.h"

static NSString * const kHost = @"openrouter.ai";
static NSString * const kAppReferer = @"https://github.com/samcejko/aichat-ios6";
static NSString * const kAppTitle = @"AI Chat for iOS 6";

@implementation OROpenRouterClient

+ (instancetype)shared
{
    static OROpenRouterClient *c = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ c = [[OROpenRouterClient alloc] init]; });
    return c;
}

- (NSDictionary *)headersWithKey:(NSString *)key accept:(NSString *)accept
{
    NSMutableDictionary *h = [NSMutableDictionary dictionary];
    if (key.length) h[@"Authorization"] = [@"Bearer " stringByAppendingString:key];
    h[@"Accept"] = accept ?: @"application/json";
    h[@"HTTP-Referer"] = kAppReferer;
    h[@"X-Title"] = kAppTitle;
    return h;
}

+ (NSString *)hintForHTTPStatus:(NSInteger)status
{
    switch (status) {
        case 401: return L(@"The API key was rejected. Check it in Settings.");
        case 402: return L(@"Not enough credits on your OpenRouter account.");
        case 403: return L(@"The request was blocked by moderation or permissions.");
        case 404: return L(@"Model not found. Refresh the model list.");
        case 408: return L(@"The request timed out. Try again.");
        case 413: return L(@"The request is too large. Use a smaller image or file.");
        case 429: return L(@"Rate limited. Free models allow 20 requests per minute and a daily quota.");
        case 502: return L(@"The model is down or returned an invalid response. Try another model.");
        case 503: return L(@"No provider is available for this model right now.");
        default: return nil;
    }
}

+ (NSError *)errorFromResponseJSON:(id)json status:(NSInteger)status
{
    NSString *message = nil;
    NSInteger code = status;
    if ([json isKindOfClass:[NSDictionary class]]) {
        id err = json[@"error"];
        if ([err isKindOfClass:[NSDictionary class]]) {
            id msg = err[@"message"];
            if ([msg isKindOfClass:[NSString class]]) message = msg;
            id c = err[@"code"];
            if ([c isKindOfClass:[NSNumber class]]) code = [c integerValue];
            else if ([c isKindOfClass:[NSString class]] && [c integerValue] > 0) code = [c integerValue];
            id meta = err[@"metadata"];
            if ([meta isKindOfClass:[NSDictionary class]]) {
                id raw = meta[@"raw"];
                if ([raw isKindOfClass:[NSString class]] && [raw length] && [raw length] < 300 && ![message isEqualToString:raw]) {
                    message = message ? [NSString stringWithFormat:@"%@ (%@)", message, raw] : raw;
                }
            }
        } else if ([err isKindOfClass:[NSString class]]) {
            message = err;
        }
    }
    if (!message) message = [NSString stringWithFormat:L(@"Request failed (HTTP %ld)."), (long)status];
    NSString *hint = [self hintForHTTPStatus:code];
    if (hint) message = [NSString stringWithFormat:@"%@\n%@", message, hint];
    return ORMakeError(code > 0 ? code : ORErrorBadResponse, message);
}

#pragma mark - Models

- (ORHTTPRequest *)fetchModels:(void (^)(NSArray *, NSError *))completion
{
    ORHTTPRequest *req = [ORHTTPRequest requestWithMethod:@"GET" host:kHost path:@"/api/v1/models"];
    req.headers = [self headersWithKey:[ORSettings shared].apiKey accept:@"application/json"];
    req.readTimeout = 60;
    req.onComplete = ^(NSInteger status, NSData *body, NSError *error) {
        if (error) { completion(nil, error); return; }
        id json = [ORUtils JSONObjectFromData:body];
        if (status != 200) { completion(nil, [OROpenRouterClient errorFromResponseJSON:json status:status]); return; }
        NSArray *data = [json isKindOfClass:[NSDictionary class]] ? json[@"data"] : nil;
        if (![data isKindOfClass:[NSArray class]]) {
            completion(nil, ORMakeError(ORErrorBadResponse, L(@"Unexpected model list format.")));
            return;
        }
        completion(data, nil);
    };
    [req start];
    return req;
}

#pragma mark - Key info

- (ORHTTPRequest *)fetchKeyInfoWithKey:(NSString *)apiKey completion:(ORJSONCompletion)completion
{
    ORHTTPRequest *req = [ORHTTPRequest requestWithMethod:@"GET" host:kHost path:@"/api/v1/key"];
    req.headers = [self headersWithKey:apiKey accept:@"application/json"];
    req.readTimeout = 30;
    req.onComplete = ^(NSInteger status, NSData *body, NSError *error) {
        if (error) { completion(nil, error); return; }
        id json = [ORUtils JSONObjectFromData:body];
        if (status != 200) { completion(nil, [OROpenRouterClient errorFromResponseJSON:json status:status]); return; }
        NSDictionary *data = [json isKindOfClass:[NSDictionary class]] ? json[@"data"] : nil;
        if (![data isKindOfClass:[NSDictionary class]]) {
            completion(nil, ORMakeError(ORErrorBadResponse, L(@"Unexpected response format.")));
            return;
        }
        completion(data, nil);
    };
    [req start];
    return req;
}

#pragma mark - Chat

- (ORHTTPRequest *)chatCompletionWithBody:(NSDictionary *)body
                                   stream:(BOOL)stream
                                  onDelta:(void (^)(NSDictionary *))onDelta
                               completion:(void (^)(NSDictionary *, NSError *))completion
{
    NSString *key = [ORSettings shared].apiKey;
    if (!key.length) {
        completion(nil, ORMakeError(ORErrorNoAPIKey, L(@"No API key set.")));
        return nil;
    }
    NSMutableDictionary *payload = [body mutableCopy];
    payload[@"stream"] = @(stream);
    NSData *json = [ORUtils JSONDataFromObject:payload];
    if (!json) {
        completion(nil, ORMakeError(ORErrorBadResponse, L(@"Could not encode the request.")));
        return nil;
    }

    ORHTTPRequest *req = [ORHTTPRequest requestWithMethod:@"POST" host:kHost path:@"/api/v1/chat/completions"];
    req.headers = [self headersWithKey:key accept:stream ? @"text/event-stream" : @"application/json"];
    req.body = json;
    req.readTimeout = 180;
    req.streamBody = stream;

    if (!stream) {
        req.onComplete = ^(NSInteger status, NSData *data, NSError *error) {
            if (error) { completion(nil, error); return; }
            id resp = [ORUtils JSONObjectFromData:data];
            if (status != 200 || ![resp isKindOfClass:[NSDictionary class]] || resp[@"error"]) {
                completion(nil, [OROpenRouterClient errorFromResponseJSON:resp status:status]);
                return;
            }
            completion(resp, nil);
        };
        [req start];
        return req;
    }

    ORSSEParser *sse = [[ORSSEParser alloc] init];
    NSMutableData *errorBody = [NSMutableData data];
    __block NSInteger httpStatus = 0;
    __block NSDictionary *lastChunkWithUsage = nil;
    __block NSError *streamError = nil;
    __block BOOL done = NO;

    sse.onEvent = ^(NSString *data) {
        if (done) return;
        NSString *trimmed = [data stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([trimmed isEqualToString:@"[DONE]"]) { done = YES; return; }
        id chunk = [ORUtils JSONObjectFromData:[trimmed dataUsingEncoding:NSUTF8StringEncoding]];
        if (![chunk isKindOfClass:[NSDictionary class]]) return;
        if (chunk[@"error"]) {
            streamError = [OROpenRouterClient errorFromResponseJSON:chunk status:200];
            done = YES;
            return;
        }
        if ([chunk[@"usage"] isKindOfClass:[NSDictionary class]]) lastChunkWithUsage = chunk;
        if (onDelta) onDelta(chunk);
    };
    req.onHeaders = ^(NSInteger status, NSDictionary *headers) {
        httpStatus = status;
    };
    req.onData = ^(NSData *chunk) {
        if (httpStatus == 200) [sse feedData:chunk];
        else [errorBody appendData:chunk];
    };
    req.onComplete = ^(NSInteger status, NSData *unused, NSError *error) {
        if (error && !streamError) { completion(nil, error); return; }
        if (status != 200 && status != 0) {
            id resp = [ORUtils JSONObjectFromData:errorBody];
            completion(nil, [OROpenRouterClient errorFromResponseJSON:resp status:status]);
            return;
        }
        [sse finish];
        if (streamError) { completion(nil, streamError); return; }
        completion(lastChunkWithUsage, nil);
    };
    [req start];
    return req;
}

@end
