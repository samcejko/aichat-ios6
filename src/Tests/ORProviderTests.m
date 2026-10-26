#import "ORProviderTests.h"
#import "ORProvider.h"
#import "OROpenRouterClient.h"
#import "ORSettings.h"
#import "ORUtils.h"
#import "ORModelInfo.h"
#import "ORConversation.h"
#import "ORChatEngine.h"
#import "ORCommon.h"
@interface ORChatEngine (ProviderRegression)
- (BOOL)providerMatches;
@end
@interface ORProviderTestRun : NSObject
@property(nonatomic,strong) NSMutableDictionary *checks;
@property(nonatomic,strong) NSArray *cases;
@property(nonatomic,copy) NSString *server;
@property(nonatomic) NSUInteger index;
- (void)next;
@end
@implementation ORProviderTestRun
- (void)next {
 if(self.index>=self.cases.count){BOOL passed=YES;for(NSString *key in self.checks)if(![self.checks[key] boolValue])passed=NO;NSDictionary *report=@{@"allPassed":@(passed),@"checks":self.checks,@"version":[ORUtils appVersion]};[[ORUtils JSONDataFromObject:report] writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"provider-tests.json"] atomically:YES];return;}
 NSDictionary *c=self.cases[self.index++];NSString *protocol=c[@"protocol"],*model=c[@"model"];
 NSDictionary *profile=@{@"id":@"transport-test",@"baseURL":[self.server stringByAppendingFormat:@"/%@",protocol],@"protocol":protocol};
 __block NSMutableString *text=[NSMutableString string];__block BOOL finishLength=NO;
 [[OROpenRouterClient shared] chatCompletionWithBody:@{@"model":model,@"messages":@[@{@"role":@"user",@"content":@"fixture"}],@"max_tokens":@64} stream:[c[@"stream"] boolValue] profile:profile key:@"fixture-key" onDelta:^(NSDictionary *chunk){NSArray *choices=chunk[@"choices"];if(choices.count){NSDictionary *choice=choices[0];NSString *delta=[choice[@"delta"] objectForKey:@"content"];if([delta isKindOfClass:[NSString class]])[text appendString:delta];if([choice[@"finish_reason"] isEqual:@"length"])finishLength=YES;}} completion:^(NSDictionary *json,NSError *error){
  if(![c[@"stream"] boolValue]){NSArray *choices=json[@"choices"];if(choices.count){id content=[choices[0][@"message"] objectForKey:@"content"];if([content isKindOfClass:[NSString class]])[text appendString:content];}}
  BOOL expectedError=[c[@"error"] boolValue];BOOL ok=expectedError?(error!=nil):(!error&&[text isEqual:@"Čau 🌍"]);if([c[@"length"] boolValue])ok=ok&&finishLength;
  self.checks[c[@"name"]]=@(ok);[self next];
 }];
}
@end
@implementation ORProviderTests
+ (void)runWithServer:(NSString *)server {
 static ORProviderTestRun *run;run=[ORProviderTestRun new];run.server=server;run.checks=[NSMutableDictionary dictionary];
 NSError *error=nil;run.checks[@"normalizeFullEndpoint"]=@([[ORProvider normalizeBaseURL:@" HTTPS://EXAMPLE.COM:443/v1/chat/completions/ " error:&error] isEqual:@"https://example.com/v1"]);
 run.checks[@"rejectQueryCredentials"]=@(![ORProvider normalizeBaseURL:@"https://example.com/v1?key=secret" error:&error]);run.checks[@"rejectURLUserInfo"]=@(![ORProvider normalizeBaseURL:@"https://user:pass@example.com/v1" error:&error]);
 NSString *a=[ORProvider identityForID:@"custom" baseURL:@"https://a.example/v1" protocol:@"openai"],*b=[ORProvider identityForID:@"custom" baseURL:@"https://b.example/v1" protocol:@"openai"],*c=[ORProvider identityForID:@"custom" baseURL:@"https://a.example/v1" protocol:@"anthropic"];
 run.checks[@"credentialOriginsSeparated"]=@(![a isEqual:b]&&![a isEqual:c]);
 NSDictionary *base=@{@"id":@"custom",@"baseURL":@"http://127.0.0.1:11434/v1",@"protocol":@"openai"};ORHTTPRequest *request=[ORProvider request:@"POST" suffix:@"/chat/completions" profile:base key:nil];
 run.checks[@"localHTTPPortAndNoAuth"]=@(!request.secure&&request.port==11434&&[request.path isEqual:@"/v1/chat/completions"]&&!request.headers[@"Authorization"]&&!request.headers[@"HTTP-Referer"]);
 NSDictionary *anthropic=@{@"id":@"anthropic",@"baseURL":@"https://api.anthropic.com/v1",@"protocol":@"anthropic"};request=[ORProvider request:@"POST" suffix:@"/messages" profile:anthropic key:@"fixture-key"];
 run.checks[@"anthropicAuth"]=@([request.headers[@"x-api-key"] isEqual:@"fixture-key"]&&request.headers[@"anthropic-version"]&&!request.headers[@"Authorization"]);
 NSDictionary *body=@{@"model":@"fixture",@"plugins":@[@{@"id":@"web"}],@"messages":@[@{@"role":@"system",@"content":@"system fixture"},@{@"role":@"user",@"content":@[@{@"type":@"text",@"text":@"question"},@{@"type":@"image_url",@"image_url":@{@"url":@"data:image/png;base64,AQID"}}]}]};
 NSDictionary *adapted=[ORProvider adaptBody:body profile:anthropic];NSArray *messages=adapted[@"messages"],*parts=[messages[0] objectForKey:@"content"];
 run.checks[@"anthropicSystemAndImage"]=@([adapted[@"system"] isEqual:@"system fixture"]&&adapted[@"max_tokens"]&&[[parts[1] objectForKey:@"type"] isEqual:@"image"]&&!adapted[@"plugins"]);
 run.checks[@"stripRouterExtras"]=@(![[ORProvider adaptBody:body profile:base] objectForKey:@"plugins"]);
 ORModelInfo *unknown=[ORModelInfo modelWithJSON:@{@"id":@"custom/model"}];run.checks[@"unknownModelNotAdvertisedAsFree"]=@(!unknown.isFree&&unknown.supportsTextOutput);
 ORConversation *conversation=[ORConversation newConversation];NSString *current=conversation.providerIdentity;ORConversation *roundtrip=[ORConversation conversationFromJSON:[conversation toJSON]];run.checks[@"historyProviderRoundtrip"]=@([roundtrip.providerIdentity isEqual:current]);conversation.providerIdentity=@"different-provider";ORChatEngine *engine=[ORChatEngine new];engine.conversation=conversation;run.checks[@"crossProviderHistoryBlocked"]=@(![engine providerMatches]);
 run.cases=@[
 @{@"name":@"openaiStreamUTF8",@"protocol":@"openai",@"model":@"stream",@"stream":@YES},
 @{@"name":@"openaiJSON",@"protocol":@"openai",@"model":@"json",@"stream":@NO},
 @{@"name":@"providerIgnoresStream",@"protocol":@"openai",@"model":@"jsonstream",@"stream":@YES},
 @{@"name":@"httpError",@"protocol":@"openai",@"model":@"error",@"stream":@YES,@"error":@YES},
 @{@"name":@"anthropicStream",@"protocol":@"anthropic",@"model":@"stream",@"stream":@YES},
 @{@"name":@"anthropicJSON",@"protocol":@"anthropic",@"model":@"json",@"stream":@NO},
 @{@"name":@"anthropicStreamError",@"protocol":@"anthropic",@"model":@"sse-error",@"stream":@YES,@"error":@YES},
 @{@"name":@"responsesStream",@"protocol":@"responses",@"model":@"stream",@"stream":@YES},
 @{@"name":@"responsesJSON",@"protocol":@"responses",@"model":@"json",@"stream":@NO},
 @{@"name":@"responsesLength",@"protocol":@"responses",@"model":@"length",@"stream":@YES,@"length":@YES}];[run next];
}
@end
