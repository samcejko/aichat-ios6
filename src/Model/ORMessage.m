#import "ORMessage.h"
#import "ORUtils.h"

@implementation ORMessage

+ (instancetype)messageWithRole:(ORMessageRole)role text:(NSString *)text
{
    ORMessage *m = [[ORMessage alloc] init];
    m.messageId = [ORUtils uuid];
    m.role = role;
    m.text = text ?: @"";
    m.createdAt = [NSDate date];
    m.attachments = @[];
    return m;
}

+ (instancetype)messageFromJSON:(NSDictionary *)json
{
    if (![json isKindOfClass:[NSDictionary class]]) return nil;
    ORMessage *m = [[ORMessage alloc] init];
    m.messageId = [json objectForKey:@"id"] ?: [ORUtils uuid];
    m.role = (ORMessageRole)[[json objectForKey:@"role"] integerValue];
    m.text = [[json objectForKey:@"text"] isKindOfClass:[NSString class]] ? [json objectForKey:@"text"] : @"";
    m.reasoning = [[json objectForKey:@"reasoning"] isKindOfClass:[NSString class]] ? [json objectForKey:@"reasoning"] : nil;
    m.modelId = [[json objectForKey:@"model"] isKindOfClass:[NSString class]] ? [json objectForKey:@"model"] : nil;
    m.createdAt = [NSDate dateWithTimeIntervalSince1970:[[json objectForKey:@"created"] doubleValue]];
    m.visionNote = [[json objectForKey:@"visionNote"] isKindOfClass:[NSString class]] ? [json objectForKey:@"visionNote"] : nil;
    m.visionModelId = [[json objectForKey:@"visionModel"] isKindOfClass:[NSString class]] ? [json objectForKey:@"visionModel"] : nil;
    m.promptTokens = [[json objectForKey:@"promptTokens"] integerValue];
    m.completionTokens = [[json objectForKey:@"completionTokens"] integerValue];
    m.cost = [[json objectForKey:@"cost"] doubleValue];
    m.hasUsage = [[json objectForKey:@"hasUsage"] boolValue];
    m.finishReason = [[json objectForKey:@"finishReason"] isKindOfClass:[NSString class]] ? [json objectForKey:@"finishReason"] : nil;
    m.usedWebSearch = [[json objectForKey:@"web"] boolValue];
    NSMutableArray *atts = [NSMutableArray array];
    for (id a in ([json objectForKey:@"attachments"] ?: @[])) {
        ORAttachment *att = [ORAttachment attachmentFromJSON:a];
        if (att) [atts addObject:att];
    }
    m.attachments = atts;
    return m;
}

- (NSDictionary *)toJSON
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"id"] = self.messageId ?: @"";
    d[@"role"] = @(self.role);
    d[@"text"] = self.text ?: @"";
    if (self.reasoning.length) d[@"reasoning"] = self.reasoning;
    if (self.modelId) d[@"model"] = self.modelId;
    d[@"created"] = @([self.createdAt timeIntervalSince1970]);
    if (self.visionNote) d[@"visionNote"] = self.visionNote;
    if (self.visionModelId) d[@"visionModel"] = self.visionModelId;
    d[@"promptTokens"] = @(self.promptTokens);
    d[@"completionTokens"] = @(self.completionTokens);
    d[@"cost"] = @(self.cost);
    d[@"hasUsage"] = @(self.hasUsage);
    if (self.finishReason) d[@"finishReason"] = self.finishReason;
    d[@"web"] = @(self.usedWebSearch);
    NSMutableArray *atts = [NSMutableArray array];
    for (ORAttachment *a in self.attachments) [atts addObject:[a toJSON]];
    d[@"attachments"] = atts;
    return d;
}

- (NSArray *)attachmentsOfKind:(ORAttachmentKind)kind
{
    NSMutableArray *out = [NSMutableArray array];
    for (ORAttachment *a in self.attachments) if (a.kind == kind) [out addObject:a];
    return out;
}

- (NSArray *)imageAttachments { return [self attachmentsOfKind:ORAttachmentKindImage]; }
- (NSArray *)pdfAttachments { return [self attachmentsOfKind:ORAttachmentKindPDF]; }

- (NSArray *)textAttachments
{
    NSMutableArray *out = [NSMutableArray array];
    for (ORAttachment *a in self.attachments) if ([a isTextLike]) [out addObject:a];
    return out;
}

- (BOOL)hasImages
{
    return [self imageAttachments].count > 0;
}

@end
