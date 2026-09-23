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
    m.messageId = json[@"id"] ?: [ORUtils uuid];
    m.role = (ORMessageRole)[json[@"role"] integerValue];
    m.text = [json[@"text"] isKindOfClass:[NSString class]] ? json[@"text"] : @"";
    m.reasoning = [json[@"reasoning"] isKindOfClass:[NSString class]] ? json[@"reasoning"] : nil;
    m.modelId = [json[@"model"] isKindOfClass:[NSString class]] ? json[@"model"] : nil;
    m.createdAt = [NSDate dateWithTimeIntervalSince1970:[json[@"created"] doubleValue]];
    m.visionNote = [json[@"visionNote"] isKindOfClass:[NSString class]] ? json[@"visionNote"] : nil;
    m.visionModelId = [json[@"visionModel"] isKindOfClass:[NSString class]] ? json[@"visionModel"] : nil;
    m.promptTokens = [json[@"promptTokens"] integerValue];
    m.completionTokens = [json[@"completionTokens"] integerValue];
    m.cost = [json[@"cost"] doubleValue];
    m.hasUsage = [json[@"hasUsage"] boolValue];
    NSMutableArray *atts = [NSMutableArray array];
    for (id a in (json[@"attachments"] ?: @[])) {
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
