#import "ORChatEngine.h"
#import "OROpenRouterClient.h"
#import "ORModelCatalog.h"
#import "ORSettings.h"
#import "ORStore.h"
#import "ORUtils.h"
#import "ORCommon.h"

@interface ORChatEngine ()
@property (nonatomic) BOOL isBusy;
@property (nonatomic, strong) ORHTTPRequest *activeRequest;
@property (nonatomic, strong) ORMessage *pendingAssistant;
@property (nonatomic) BOOL updateScheduled;
@property (nonatomic) BOOL cancelled;
- (void)flushUpdate;
@end

@implementation ORChatEngine

- (void)setBusy:(BOOL)busy
{
    if (self.isBusy == busy) return;
    self.isBusy = busy;
    [self.delegate chatEngineDidChangeBusyState:self];
}

#pragma mark - Public

- (void)sendText:(NSString *)text attachments:(NSArray *)attachments model:(ORModelInfo *)model
{
    if (self.isBusy || !self.conversation) return;
    ORMessage *user = [ORMessage messageWithRole:ORMessageRoleUser text:text ?: @""];
    user.attachments = attachments ?: @[];
    [self.conversation.messages addObject:user];
    if (!self.conversation.modelId) self.conversation.modelId = model.modelId;
    [self.conversation updateTitleIfNeeded];
    [[ORStore shared] saveConversation:self.conversation];
    [self.delegate chatEngine:self didAddMessage:user];
    [self runAssistantTurnWithModel:model];
}

- (void)regenerateWithModel:(ORModelInfo *)model
{
    if (self.isBusy || !self.conversation) return;
    // Drop everything after the last user message.
    NSInteger lastUser = -1;
    for (NSInteger i = (NSInteger)self.conversation.messages.count - 1; i >= 0; i--) {
        if (((ORMessage *)self.conversation.messages[i]).role == ORMessageRoleUser) { lastUser = i; break; }
    }
    if (lastUser < 0) return;
    while ((NSInteger)self.conversation.messages.count > lastUser + 1) [self.conversation.messages removeLastObject];
    [self runAssistantTurnWithModel:model];
}

- (void)cancel
{
    if (!self.isBusy) return;
    self.cancelled = YES;
    [self.activeRequest cancel];
}

- (void)deleteMessage:(ORMessage *)message
{
    if (!message) return;
    [self.conversation.messages removeObject:message];
    for (ORAttachment *a in message.attachments) [a deleteFile];
    if (self.conversation.isEmpty) {
        [[ORStore shared] deleteConversation:self.conversation.conversationId];
    } else {
        [[ORStore shared] saveConversation:self.conversation];
    }
}

#pragma mark - Turn

- (void)runAssistantTurnWithModel:(ORModelInfo *)model
{
    if (!model) {
        [self appendError:L(@"No model selected. Tap the model name to choose one.")];
        return;
    }
    self.cancelled = NO;
    [self setBusy:YES];
    self.conversation.modelId = model.modelId;

    ORMessage *assistant = [ORMessage messageWithRole:ORMessageRoleAssistant text:@""];
    assistant.modelId = model.modelId;
    assistant.isStreaming = YES;
    assistant.statusText = L(@"Thinking…");
    self.pendingAssistant = assistant;
    [self.conversation.messages addObject:assistant];
    [self.delegate chatEngine:self didAddMessage:assistant];

    ORMessage *lastUser = [self.conversation lastUserMessage];
    BOOL needsVision = lastUser.hasImages && ![model supportsImages] && lastUser.visionNote.length == 0;
    if (needsVision) {
        ORModelInfo *vision = [[ORModelCatalog shared] modelWithId:[ORSettings shared].visionModelId];
        if (vision && [vision supportsImages]) {
            [self describeImagesOfMessage:lastUser withVisionModel:vision thenSendWithModel:model];
        } else {
            [self.delegate chatEngine:self needsVisionModelWithCompletion:^(ORModelInfo *picked) {
                if (self.cancelled) { [self finishCancelled]; return; }
                if (!picked) {
                    [self failPendingWithMessage:L(@"This model cannot see images. Choose a vision helper model in Settings, or pick a model with image input.")];
                    return;
                }
                [ORSettings shared].visionModelId = picked.modelId;
                [self describeImagesOfMessage:lastUser withVisionModel:picked thenSendWithModel:model];
            }];
        }
        return;
    }
    [self sendMainRequestWithModel:model];
}

#pragma mark - Vision relay

- (NSString *)visionPromptForMessage:(ORMessage *)message
{
    NSMutableString *p = [NSMutableString string];
    [p appendString:@"You are an image description assistant. Describe the attached image in detail for another AI model that cannot see it. "
                     "Include all visible text verbatim, the layout, objects, people, colors, and any charts or tables with their values. "
                     "Be thorough and factual, do not speculate, do not answer the user's question yourself."];
    NSString *text = [message.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length) {
        [p appendFormat:@"\nThe user's request about the image is: \"%@\". Pay special attention to details relevant to it.", [ORUtils truncate:text to:500]];
    }
    return p;
}

- (NSArray *)imagePartsForMessage:(ORMessage *)message
{
    NSMutableArray *parts = [NSMutableArray array];
    for (ORAttachment *a in [message imageAttachments]) {
        NSData *d = [a data];
        if (!d.length) continue;
        NSString *mime = a.mime ?: @"image/jpeg";
        [parts addObject:@{ @"type": @"image_url", @"image_url": @{ @"url": [ORUtils dataURLWithMime:mime data:d] } }];
    }
    return parts;
}

- (void)describeImagesOfMessage:(ORMessage *)user withVisionModel:(ORModelInfo *)vision thenSendWithModel:(ORModelInfo *)model
{
    self.pendingAssistant.statusText = [NSString stringWithFormat:L(@"Describing image with %@…"), [vision displayName]];
    [self.delegate chatEngine:self didUpdateMessage:self.pendingAssistant];

    NSMutableArray *content = [NSMutableArray array];
    [content addObject:@{ @"type": @"text", @"text": [self visionPromptForMessage:user] }];
    [content addObjectsFromArray:[self imagePartsForMessage:user]];
    NSDictionary *body = @{
        @"model": vision.modelId,
        @"messages": @[ @{ @"role": @"user", @"content": content } ],
        @"temperature": @0.2,
        @"max_tokens": @1500,
    };
    self.activeRequest = [[OROpenRouterClient shared] chatCompletionWithBody:body stream:NO onDelta:nil completion:^(NSDictionary *json, NSError *error) {
        self.activeRequest = nil;
        if (self.cancelled) { [self finishCancelled]; return; }
        if (error) {
            [self failPendingWithMessage:[NSString stringWithFormat:L(@"Image description failed: %@"), error.localizedDescription]];
            return;
        }
        NSString *desc = [self contentStringFromResponse:json];
        if (!desc.length) {
            [self failPendingWithMessage:L(@"The vision model returned an empty description.")];
            return;
        }
        user.visionNote = desc;
        user.visionModelId = vision.modelId;
        [[ORStore shared] saveConversation:self.conversation];
        [self.delegate chatEngine:self didUpdateMessage:user];
        self.pendingAssistant.statusText = L(@"Thinking…");
        [self.delegate chatEngine:self didUpdateMessage:self.pendingAssistant];
        [self sendMainRequestWithModel:model];
    }];
}

- (NSString *)contentStringFromResponse:(NSDictionary *)json
{
    NSArray *choices = json[@"choices"];
    if (![choices isKindOfClass:[NSArray class]] || !choices.count) return nil;
    NSDictionary *msg = choices[0][@"message"];
    if (![msg isKindOfClass:[NSDictionary class]]) return nil;
    id content = msg[@"content"];
    if ([content isKindOfClass:[NSString class]]) return content;
    if ([content isKindOfClass:[NSArray class]]) {
        NSMutableString *s = [NSMutableString string];
        for (id part in content) {
            if ([part isKindOfClass:[NSDictionary class]] && [part[@"text"] isKindOfClass:[NSString class]]) [s appendString:part[@"text"]];
        }
        return s;
    }
    return nil;
}

#pragma mark - Request building

- (NSString *)textForUserMessage:(ORMessage *)m includeVisionNote:(BOOL)includeNote rawImages:(BOOL)rawImages rawPDFs:(BOOL)rawPDFs
{
    NSMutableString *s = [NSMutableString stringWithString:m.text ?: @""];
    NSInteger limit = [ORSettings shared].maxTextAttachmentBytes;
    for (ORAttachment *a in m.attachments) {
        if ([a isTextLike]) {
            BOOL truncated = NO;
            NSString *content = [a textContentWithLimit:limit truncated:&truncated];
            if (content) {
                [s appendFormat:@"\n\n--- File: %@ ---\n%@\n%@--- End of %@ ---", a.displayName, content,
                 truncated ? L(@"[truncated]\n") : @"", a.displayName];
            } else {
                [s appendFormat:@"\n\n[Attached file %@ could not be read]", a.displayName];
            }
        } else if ([a isImage]) {
            if (!rawImages) {
                if (includeNote && m.visionNote.length) {
                    NSString *by = m.visionModelId ?: @"vision model";
                    [s appendFormat:@"\n\n[Attached image \"%@\", described by %@]:\n%@", a.displayName, by, m.visionNote];
                } else {
                    [s appendFormat:@"\n\n[Attached image: %@]", a.displayName];
                }
            }
        } else if ([a isPDF]) {
            if (!rawPDFs) [s appendFormat:@"\n\n[PDF attached earlier: %@]", a.displayName];
        } else {
            [s appendFormat:@"\n\n[Attached file: %@ (%@)]", a.displayName, a.mime];
        }
    }
    return s;
}

- (NSDictionary *)buildBodyWithModel:(ORModelInfo *)model
{
    ORSettings *settings = [ORSettings shared];
    NSMutableArray *messages = [NSMutableArray array];
    NSString *sys = [settings.systemPrompt stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (sys.length) [messages addObject:@{ @"role": @"system", @"content": sys }];

    // History without local error bubbles and without the streaming placeholder.
    NSMutableArray *history = [NSMutableArray array];
    for (ORMessage *m in self.conversation.messages) {
        if (m.role == ORMessageRoleError || m == self.pendingAssistant) continue;
        [history addObject:m];
    }

    NSInteger depth = settings.imageHistoryDepth;
    if (depth < 1) depth = 1;
    NSMutableSet *recentUserIds = [NSMutableSet set];
    NSInteger seen = 0;
    for (NSInteger i = (NSInteger)history.count - 1; i >= 0 && seen < depth; i--) {
        ORMessage *m = history[i];
        if (m.role == ORMessageRoleUser) { [recentUserIds addObject:m.messageId]; seen++; }
    }

    BOOL anyPDF = NO;
    NSMutableArray *built = [NSMutableArray array];    // parallel to history: dictionaries + size estimate
    NSMutableArray *sizes = [NSMutableArray array];
    for (ORMessage *m in history) {
        if (m.role == ORMessageRoleAssistant) {
            if (!m.text.length) continue;
            [built addObject:@{ @"role": @"assistant", @"content": m.text }];
            [sizes addObject:@(m.text.length)];
            continue;
        }
        BOOL recent = [recentUserIds containsObject:m.messageId];
        BOOL rawImages = recent && [model supportsImages] && m.hasImages;
        BOOL rawPDFs = recent && [m pdfAttachments].count > 0;
        NSString *text = [self textForUserMessage:m includeVisionNote:YES rawImages:rawImages rawPDFs:rawPDFs];
        NSInteger size = text.length;
        NSMutableArray *parts = [NSMutableArray array];
        if (text.length) [parts addObject:@{ @"type": @"text", @"text": text }];
        if (rawImages) {
            NSArray *imgs = [self imagePartsForMessage:m];
            [parts addObjectsFromArray:imgs];
            size += 1500 * imgs.count;
        }
        if (rawPDFs) {
            for (ORAttachment *a in [m pdfAttachments]) {
                NSData *d = [a data];
                if (!d.length) continue;
                [parts addObject:@{ @"type": @"file", @"file": @{ @"filename": a.displayName ?: @"document.pdf",
                                                                  @"file_data": [ORUtils dataURLWithMime:@"application/pdf" data:d] } }];
                size += d.length / 2;
                anyPDF = YES;
            }
        }
        if (parts.count == 0) continue;
        id content = (parts.count == 1 && [parts[0][@"type"] isEqualToString:@"text"]) ? text : parts;
        [built addObject:@{ @"role": @"user", @"content": content }];
        [sizes addObject:@(size)];
    }

    // Rough context trimming: ~3.5 characters per token, keep room for the answer.
    NSInteger ctx = model.contextLength > 0 ? model.contextLength : 8192;
    NSInteger reserve = settings.maxTokens > 0 ? settings.maxTokens : 4096;
    long long budget = (long long)(ctx - reserve) * 35 / 10;
    if (budget < 4000) budget = 4000;
    long long total = sys.length;
    for (NSNumber *n in sizes) total += [n longLongValue];
    NSUInteger dropFrom = 0;
    while (total > budget && dropFrom < built.count - 1) {
        total -= [sizes[dropFrom] longLongValue];
        dropFrom++;
    }
    for (NSUInteger i = dropFrom; i < built.count; i++) [messages addObject:built[i]];

    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    body[@"model"] = model.modelId;
    body[@"messages"] = messages;
    if (settings.temperature >= 0 && [model supportsParameter:@"temperature"]) body[@"temperature"] = @(settings.temperature);
    if (settings.maxTokens > 0) body[@"max_tokens"] = @(settings.maxTokens);
    NSMutableArray *plugins = [NSMutableArray array];
    if (anyPDF) [plugins addObject:@{ @"id": @"file-parser", @"pdf": @{ @"engine": settings.pdfEngine ?: @"cloudflare-ai" } }];
    if (settings.middleOut) [plugins addObject:@{ @"id": @"context-compression", @"engine": @"middle-out" }];
    if (plugins.count) body[@"plugins"] = plugins;
    return body;
}

#pragma mark - Main request

- (void)scheduleUpdate
{
    if (self.updateScheduled) return;
    self.updateScheduled = YES;
    [self performSelector:@selector(flushUpdate) withObject:nil afterDelay:0.1];
}

- (void)flushUpdate
{
    self.updateScheduled = NO;
    if (self.pendingAssistant) [self.delegate chatEngine:self didUpdateMessage:self.pendingAssistant];
}

- (void)sendMainRequestWithModel:(ORModelInfo *)model
{
    ORMessage *assistant = self.pendingAssistant;
    NSDictionary *body = [self buildBodyWithModel:model];
    BOOL stream = [ORSettings shared].streaming;
    self.activeRequest = [[OROpenRouterClient shared] chatCompletionWithBody:body stream:stream onDelta:^(NSDictionary *chunk) {
        NSArray *choices = chunk[@"choices"];
        if (![choices isKindOfClass:[NSArray class]] || !choices.count) return;
        NSDictionary *delta = choices[0][@"delta"];
        if (![delta isKindOfClass:[NSDictionary class]]) return;
        id content = delta[@"content"];
        id reasoning = delta[@"reasoning"];
        BOOL changed = NO;
        if ([content isKindOfClass:[NSString class]] && [content length]) {
            assistant.text = [assistant.text stringByAppendingString:content];
            changed = YES;
        }
        if ([reasoning isKindOfClass:[NSString class]] && [reasoning length]) {
            assistant.reasoning = [(assistant.reasoning ?: @"") stringByAppendingString:reasoning];
            if (!assistant.text.length) assistant.statusText = L(@"Reasoning…");
            changed = YES;
        }
        if (changed) {
            if (assistant.text.length) assistant.statusText = nil;
            [self scheduleUpdate];
        }
    } completion:^(NSDictionary *finalJSON, NSError *error) {
        self.activeRequest = nil;
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(flushUpdate) object:nil];
        self.updateScheduled = NO;
        if (!stream && finalJSON) {
            NSString *text = [self contentStringFromResponse:finalJSON];
            assistant.text = text ?: @"";
            NSArray *choices = finalJSON[@"choices"];
            if ([choices isKindOfClass:[NSArray class]] && choices.count) {
                id r = choices[0][@"message"][@"reasoning"];
                if ([r isKindOfClass:[NSString class]]) assistant.reasoning = r;
            }
        }
        NSDictionary *usage = finalJSON[@"usage"];
        if ([usage isKindOfClass:[NSDictionary class]]) {
            assistant.promptTokens = [usage[@"prompt_tokens"] integerValue];
            assistant.completionTokens = [usage[@"completion_tokens"] integerValue];
            assistant.cost = [usage[@"cost"] doubleValue];
            assistant.hasUsage = YES;
        }
        [self finishWithError:error];
    }];
    if (!self.activeRequest && self.pendingAssistant) {
        // Immediate failure (no key etc.) already reported through the completion block.
    }
}

#pragma mark - Finishing

- (void)finishCancelled
{
    [self finishWithError:ORMakeError(ORErrorCancelled, L(@"Cancelled"))];
}

- (void)finishWithError:(NSError *)error
{
    ORMessage *assistant = self.pendingAssistant;
    self.pendingAssistant = nil;
    assistant.isStreaming = NO;
    assistant.statusText = nil;
    BOOL cancelled = error && error.code == ORErrorCancelled && [error.domain isEqualToString:ORErrorDomain];

    if (assistant.text.length == 0) {
        [self.conversation.messages removeObject:assistant];
        if (error && !cancelled) {
            [self appendErrorMessage:error.localizedDescription];
        } else if (!error) {
            [self appendErrorMessage:L(@"The model returned an empty reply.")];
        }
    } else if (error && !cancelled) {
        [self appendErrorMessage:error.localizedDescription];
    }
    [[ORStore shared] saveConversation:self.conversation];
    [self setBusy:NO];
    [self.delegate chatEngine:self didFinishMessage:assistant];
}

- (void)appendErrorMessage:(NSString *)text
{
    ORMessage *err = [ORMessage messageWithRole:ORMessageRoleError text:text ?: L(@"Unknown error")];
    [self.conversation.messages addObject:err];
}

- (void)appendError:(NSString *)text
{
    [self appendErrorMessage:text];
    [self.delegate chatEngine:self didAddMessage:self.conversation.messages.lastObject];
}

- (void)failPendingWithMessage:(NSString *)text
{
    [self finishWithError:ORMakeError(ORErrorBadResponse, text)];
}

@end
