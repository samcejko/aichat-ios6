#import "ORConversation.h"
#import "ORUtils.h"
#import "ORCommon.h"

@implementation ORConversation

+ (instancetype)newConversation
{
    ORConversation *c = [[ORConversation alloc] init];
    c.conversationId = [ORUtils uuid];
    c.createdAt = [NSDate date];
    c.updatedAt = c.createdAt;
    c.messages = [NSMutableArray array];
    return c;
}

+ (instancetype)conversationFromJSON:(NSDictionary *)json
{
    if (![json isKindOfClass:[NSDictionary class]]) return nil;
    ORConversation *c = [[ORConversation alloc] init];
    c.conversationId = json[@"id"];
    if (!c.conversationId) return nil;
    c.title = [json[@"title"] isKindOfClass:[NSString class]] ? json[@"title"] : nil;
    c.modelId = [json[@"model"] isKindOfClass:[NSString class]] ? json[@"model"] : nil;
    c.createdAt = [NSDate dateWithTimeIntervalSince1970:[json[@"created"] doubleValue]];
    c.updatedAt = [NSDate dateWithTimeIntervalSince1970:[json[@"updated"] doubleValue]];
    c.messages = [NSMutableArray array];
    for (id m in (json[@"messages"] ?: @[])) {
        ORMessage *msg = [ORMessage messageFromJSON:m];
        if (!msg) continue;
        if (msg.role == ORMessageRoleAssistant && msg.text.length == 0) continue;
        [c.messages addObject:msg];
    }
    return c;
}

- (NSDictionary *)toJSON
{
    NSMutableArray *msgs = [NSMutableArray arrayWithCapacity:self.messages.count];
    for (ORMessage *m in self.messages) {
        // Never persist the streaming placeholder (empty assistant bubble).
        if (m.role == ORMessageRoleAssistant && m.text.length == 0) continue;
        [msgs addObject:[m toJSON]];
    }
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"id"] = self.conversationId ?: @"";
    if (self.title) d[@"title"] = self.title;
    if (self.modelId) d[@"model"] = self.modelId;
    d[@"created"] = @([self.createdAt timeIntervalSince1970]);
    d[@"updated"] = @([self.updatedAt timeIntervalSince1970]);
    d[@"messages"] = msgs;
    return d;
}

- (BOOL)isEmpty
{
    for (ORMessage *m in self.messages) {
        if (m.role != ORMessageRoleError) return NO;
    }
    return YES;
}

- (NSString *)preview
{
    for (NSInteger i = (NSInteger)self.messages.count - 1; i >= 0; i--) {
        ORMessage *m = self.messages[i];
        if (m.role == ORMessageRoleError) continue;
        if (m.text.length) return [ORUtils truncate:m.text to:80];
        if (m.attachments.count) return [NSString stringWithFormat:@"[%@]", ((ORAttachment *)m.attachments[0]).displayName];
    }
    return @"";
}

- (void)updateTitleIfNeeded
{
    if (self.title.length) return;
    for (ORMessage *m in self.messages) {
        if (m.role != ORMessageRoleUser) continue;
        if (m.text.length) {
            self.title = [ORUtils truncate:m.text to:48];
        } else if (m.attachments.count) {
            self.title = ((ORAttachment *)m.attachments[0]).displayName;
        }
        if (self.title.length) return;
    }
}

- (ORMessage *)lastMessage
{
    return self.messages.lastObject;
}

- (ORMessage *)lastUserMessage
{
    for (NSInteger i = (NSInteger)self.messages.count - 1; i >= 0; i--) {
        ORMessage *m = self.messages[i];
        if (m.role == ORMessageRoleUser) return m;
    }
    return nil;
}

@end
