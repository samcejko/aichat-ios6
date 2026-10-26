#import "ORProvider.h"
#import "ORSettings.h"
#import "ORHTTPRequest.h"
#import "ORUtils.h"
#import "ORCommon.h"
#import <CommonCrypto/CommonDigest.h>
NSString * const ORProviderDidChangeNotification = @"ORProviderDidChangeNotification";
static NSDictionary *ORPDict(id v){return [v isKindOfClass:[NSDictionary class]]?v:@{};}
static NSArray *ORPArray(id v){return [v isKindOfClass:[NSArray class]]?v:@[];}
@implementation ORProvider
+ (NSArray *)presets { static NSArray *rows;static dispatch_once_t once;dispatch_once(&once,^{id value=[ORUtils JSONObjectFromData:[NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"Providers" ofType:@"json"]]];rows=[value isKindOfClass:[NSArray class]]?value:@[];});return rows; }
+ (NSDictionary *)preset:(NSString *)identifier {for(NSDictionary *p in [self presets])if([[p objectForKey:@"id"] isEqual:identifier])return p;return [self presets].count?[self presets][0]:@{};}
+ (NSString *)normalizeBaseURL:(NSString *)value error:(NSError **)error {
    NSString *s=[value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSURL *u=[NSURL URLWithString:s];NSString *scheme=[u.scheme lowercaseString];
    BOOL valid=([scheme isEqual:@"https"]||[scheme isEqual:@"http"])&&u.host.length&&!u.user.length&&!u.password.length&&!u.query.length&&!u.fragment.length&&[s rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location==NSNotFound;
    if(!valid){if(error)*error=ORMakeError(ORErrorBadResponse,L(@"Enter an HTTP or HTTPS API base URL without a query, password or fragment."));return nil;}
    while([s hasSuffix:@"/"])s=[s substringToIndex:s.length-1];
    for(NSString *ending in @[@"/chat/completions",@"/messages",@"/models",@"/responses"])if([s hasSuffix:ending]){s=[s substringToIndex:s.length-ending.length];break;}
    // Canonicalize the authority so harmless case changes do not select another credential slot.
    NSURL *canonical=[NSURL URLWithString:s];NSString *host=[canonical.host lowercaseString];if([host rangeOfString:@":"].location!=NSNotFound)host=[NSString stringWithFormat:@"[%@]",host];
    NSInteger port=canonical.port.integerValue;NSString *authority=port&&port!=([scheme isEqual:@"https"]?443:80)?[NSString stringWithFormat:@"%@:%ld",host,(long)port]:host;
    NSString *path=CFBridgingRelease(CFURLCopyPath((__bridge CFURLRef)canonical)) ?: @"";while([path hasSuffix:@"/"])path=[path substringToIndex:path.length-1];
    return [NSString stringWithFormat:@"%@://%@%@",scheme,authority,path];
}
+ (NSString *)identityForID:(NSString *)identifier baseURL:(NSString *)base protocol:(NSString *)protocol {
    NSData *d=[[NSString stringWithFormat:@"%@|%@|%@",identifier ?: @"openrouter",protocol ?: @"openai",base ?: @""] dataUsingEncoding:NSUTF8StringEncoding];unsigned char hash[CC_SHA256_DIGEST_LENGTH];CC_SHA256(d.bytes,(CC_LONG)d.length,hash);NSMutableString *s=[NSMutableString string];for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[s appendFormat:@"%02x",hash[i]];return s;
}
+ (NSDictionary *)current {ORSettings *s=[ORSettings shared];return @{@"id":s.providerID,@"baseURL":s.apiBaseURL,@"protocol":s.apiProtocol};}
+ (BOOL)isOpenRouter {ORSettings *s=[ORSettings shared];return [s.providerID isEqual:@"openrouter"]&&[s.apiBaseURL isEqual:@"https://openrouter.ai/api/v1"]&&[s.apiProtocol isEqual:@"openai"];}
+ (ORHTTPRequest *)request:(NSString *)method suffix:(NSString *)suffix profile:(NSDictionary *)profile key:(NSString *)key {
    NSURL *u=[NSURL URLWithString:[[profile objectForKey:@"baseURL"] stringByAppendingString:suffix]];ORHTTPRequest *r=[ORHTTPRequest requestWithMethod:method host:u.host path:CFBridgingRelease(CFURLCopyPath((__bridge CFURLRef)u)) ?: @"/"];r.secure=[[u.scheme lowercaseString] isEqual:@"https"];r.port=u.port?u.port.integerValue:(r.secure?443:80);
    NSMutableDictionary *h=[NSMutableDictionary dictionaryWithObject:@"application/json" forKey:@"Accept"];
    NSString *protocol=[profile objectForKey:@"protocol"];
    if([protocol isEqual:@"anthropic"]){h[@"anthropic-version"]=@"2023-06-01";if(key.length)h[@"x-api-key"]=key;}
    else if(key.length)h[[protocol isEqual:@"azure"]?@"api-key":@"Authorization"]=[protocol isEqual:@"azure"]?key:[@"Bearer " stringByAppendingString:key];
    if([[profile objectForKey:@"id"] isEqual:@"openrouter"]&&[[profile objectForKey:@"baseURL"] isEqual:@"https://openrouter.ai/api/v1"]){h[@"HTTP-Referer"]=@"https://github.com/samcejko/aichat-ios6";h[@"X-Title"]=@"AI Chat";}
    r.headers=h;return r;
}
+ (NSDictionary *)adaptBody:(NSDictionary *)body profile:(NSDictionary *)profile {
    NSMutableDictionary *b=[body mutableCopy];BOOL router=[[profile objectForKey:@"id"] isEqual:@"openrouter"]&&[[profile objectForKey:@"baseURL"] isEqual:@"https://openrouter.ai/api/v1"];
    if(router)return b;
    [b removeObjectForKey:@"plugins"];[b removeObjectForKey:@"transforms"];[b removeObjectForKey:@"route"];[b removeObjectForKey:@"provider"];[b removeObjectForKey:@"reasoning"];[b removeObjectForKey:@"modalities"];
    if([[profile objectForKey:@"protocol"] isEqual:@"responses"]){
        NSMutableArray *input=[NSMutableArray array],*systems=[NSMutableArray array];
        for(NSDictionary *m in [body objectForKey:@"messages"]){id content=[m objectForKey:@"content"];NSString *role=[m objectForKey:@"role"];if([role isEqual:@"system"]){if([content isKindOfClass:[NSString class]])[systems addObject:content];continue;}
            if([content isKindOfClass:[NSString class]])[input addObject:@{@"role":role,@"content":content}];
            else {NSMutableArray *parts=[NSMutableArray array];for(NSDictionary *p in content){if([[p objectForKey:@"type"] isEqual:@"text"])[parts addObject:@{@"type":[role isEqual:@"assistant"]?@"output_text":@"input_text",@"text":[p objectForKey:@"text"] ?: @""}];else if([[p objectForKey:@"type"] isEqual:@"image_url"])[parts addObject:@{@"type":@"input_image",@"image_url":[[p objectForKey:@"image_url"] objectForKey:@"url"] ?: @""}];}if(parts.count)[input addObject:@{@"role":role,@"content":parts}];}
        }
        NSMutableDictionary *r=[NSMutableDictionary dictionaryWithDictionary:@{@"model":[body objectForKey:@"model"] ?: @"",@"input":input,@"store":@NO}];if(systems.count)r[@"instructions"]=[systems componentsJoinedByString:@"\n\n"];if([body objectForKey:@"max_tokens"])r[@"max_output_tokens"]=[body objectForKey:@"max_tokens"];return r;
    }
    if([[profile objectForKey:@"protocol"] isEqual:@"anthropic"]){
        NSMutableArray *messages=[NSMutableArray array],*systems=[NSMutableArray array];
        for(NSDictionary *m in [body objectForKey:@"messages"]){id content=[m objectForKey:@"content"];if([[m objectForKey:@"role"] isEqual:@"system"]){if([content isKindOfClass:[NSString class]])[systems addObject:content];continue;}
            NSMutableArray *parts=[NSMutableArray array];if([content isKindOfClass:[NSString class]]){if([content length])[parts addObject:@{@"type":@"text",@"text":content}];}
            else for(NSDictionary *part in content){NSString *type=[part objectForKey:@"type"];if([type isEqual:@"text"])[parts addObject:part];else if([type isEqual:@"image_url"]){NSString *url=[[part objectForKey:@"image_url"] objectForKey:@"url"];if([url hasPrefix:@"data:"]){NSRange comma=[url rangeOfString:@","];NSRange semi=[url rangeOfString:@";"];if(comma.location!=NSNotFound&&semi.location!=NSNotFound&&semi.location<comma.location)[parts addObject:@{@"type":@"image",@"source":@{@"type":@"base64",@"media_type":[url substringWithRange:NSMakeRange(5,semi.location-5)],@"data":[url substringFromIndex:comma.location+1]}}];}else if(url.length)[parts addObject:@{@"type":@"image",@"source":@{@"type":@"url",@"url":url}}];}}
            if(parts.count)[messages addObject:@{@"role":[[m objectForKey:@"role"] isEqual:@"assistant"]?@"assistant":@"user",@"content":parts}];
        }
        NSMutableDictionary *a=[NSMutableDictionary dictionaryWithDictionary:@{@"model":[body objectForKey:@"model"] ?: @"",@"messages":messages,@"max_tokens":[body objectForKey:@"max_tokens"] ?: @4096}];if(systems.count)a[@"system"]=[systems componentsJoinedByString:@"\n\n"];if([body objectForKey:@"temperature"])a[@"temperature"]=[body objectForKey:@"temperature"];return a;
    }
    if([[profile objectForKey:@"id"] isEqual:@"openai"]||[[profile objectForKey:@"protocol"] isEqual:@"azure"]){if([b objectForKey:@"max_tokens"]){b[@"max_completion_tokens"]=[b objectForKey:@"max_tokens"];[b removeObjectForKey:@"max_tokens"];}NSString *model=[b objectForKey:@"model"];if([model hasPrefix:@"o1"]||[model hasPrefix:@"o3"]||[model hasPrefix:@"o4"]||[model hasPrefix:@"gpt-5"]||[model hasPrefix:@"gpt-6"])[b removeObjectForKey:@"temperature"];}
    return b;
}
+ (NSDictionary *)adaptResponse:(NSDictionary *)json profile:(NSDictionary *)profile {
    if([[profile objectForKey:@"protocol"] isEqual:@"responses"]){
        NSMutableString *text=[NSMutableString string];for(NSDictionary *item in ORPArray([json objectForKey:@"output"]))if([[item objectForKey:@"type"] isEqual:@"message"])for(NSDictionary *part in ORPArray([item objectForKey:@"content"])){if([[part objectForKey:@"type"] isEqual:@"output_text"])[text appendString:[part objectForKey:@"text"] ?: @""];else if([[part objectForKey:@"type"] isEqual:@"refusal"])[text appendString:[part objectForKey:@"refusal"] ?: @""];}
        NSDictionary *usage=ORPDict([json objectForKey:@"usage"]);return @{@"choices":@[@{@"message":@{@"content":text},@"finish_reason":[[json objectForKey:@"status"] isEqual:@"incomplete"]?@"length":@"stop"}],@"usage":@{@"prompt_tokens":[usage objectForKey:@"input_tokens"] ?: @0,@"completion_tokens":[usage objectForKey:@"output_tokens"] ?: @0}};
    }
    if(![[profile objectForKey:@"protocol"] isEqual:@"anthropic"])return json;NSMutableString *text=[NSMutableString string],*thinking=[NSMutableString string];for(NSDictionary *p in ORPArray([json objectForKey:@"content"])){if([[p objectForKey:@"type"] isEqual:@"text"])[text appendString:[p objectForKey:@"text"] ?: @""];if([[p objectForKey:@"type"] isEqual:@"thinking"])[thinking appendString:[p objectForKey:@"thinking"] ?: @""];}
    NSDictionary *usage=ORPDict([json objectForKey:@"usage"]);return @{@"choices":@[@{@"message":@{@"content":text,@"reasoning":thinking},@"finish_reason":[[json objectForKey:@"stop_reason"] isEqual:@"max_tokens"]?@"length":@"stop"}],@"usage":@{@"prompt_tokens":[usage objectForKey:@"input_tokens"] ?: @0,@"completion_tokens":[usage objectForKey:@"output_tokens"] ?: @0}};
}
+ (NSDictionary *)adaptEvent:(NSDictionary *)json profile:(NSDictionary *)profile {
    if([[profile objectForKey:@"protocol"] isEqual:@"responses"]){NSString *type=[json objectForKey:@"type"];
        if([type isEqual:@"response.output_text.delta"]||[type isEqual:@"response.refusal.delta"]||[type isEqual:@"response.reasoning_summary_text.delta"])return @{@"choices":@[@{@"delta":@{([type isEqual:@"response.reasoning_summary_text.delta"]?@"reasoning":@"content"):[json objectForKey:@"delta"] ?: @""}}]};
        if([type isEqual:@"error"]||[type isEqual:@"response.failed"])return @{@"error":[ORPDict([json objectForKey:@"response"]) objectForKey:@"error"] ?: [json objectForKey:@"error"] ?: @{@"message":[json objectForKey:@"message"] ?: L(@"Unknown error")}};
        if([type isEqual:@"response.completed"]||[type isEqual:@"response.incomplete"]){NSDictionary *r=[self adaptResponse:ORPDict([json objectForKey:@"response"]) profile:profile];return @{@"choices":@[@{@"delta":@{},@"finish_reason":[type isEqual:@"response.incomplete"]?@"length":@"stop"}],@"usage":[r objectForKey:@"usage"] ?: @{}};}
        return @{@"choices":@[]};
    }
    if(![[profile objectForKey:@"protocol"] isEqual:@"anthropic"])return json;
    NSString *type=[json objectForKey:@"type"];NSDictionary *d=ORPDict([json objectForKey:@"delta"]);
    if([type isEqual:@"error"])return @{@"error":[json objectForKey:@"error"] ?: @{}};
    if([type isEqual:@"content_block_delta"])return @{@"choices":@[@{@"delta":@{@"content":[[d objectForKey:@"type"] isEqual:@"text_delta"]?([d objectForKey:@"text"] ?: @""):@"",@"reasoning":[[d objectForKey:@"type"] isEqual:@"thinking_delta"]?([d objectForKey:@"thinking"] ?: @""):@""}}]};
    if([type isEqual:@"message_delta"])return @{@"choices":@[@{@"delta":@{},@"finish_reason":[[d objectForKey:@"stop_reason"] isEqual:@"max_tokens"]?@"length":@"stop"}],@"usage":@{@"completion_tokens":[ORPDict([json objectForKey:@"usage"]) objectForKey:@"output_tokens"] ?: @0}};
    if([type isEqual:@"message_start"])return @{@"choices":@[],@"usage":@{@"prompt_tokens":[ORPDict([ORPDict([json objectForKey:@"message"]) objectForKey:@"usage"]) objectForKey:@"input_tokens"] ?: @0}};
    return @{@"choices":@[]};
}
@end
