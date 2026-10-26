#import "ORChatEngine.h"
#import "OROpenRouterClient.h"
#import "ORModelCatalog.h"
#import "ORSettings.h"
#import "ORProvider.h"
#import "ORStore.h"
#import "ORUtils.h"
#import "ORCommon.h"
#import <ImageIO/ImageIO.h>

NSString * const ORChatEngineDidStartNotification = @"ORChatEngineDidStartNotification";
NSString * const ORChatEngineDidFinishNotification = @"ORChatEngineDidFinishNotification";

@interface ORChatEngine ()
@property (nonatomic) BOOL isBusy;
@property (nonatomic, strong) ORHTTPRequest *activeRequest;
@property (nonatomic, strong) ORMessage *pendingAssistant;
@property (nonatomic) BOOL updateScheduled;
@property (nonatomic) BOOL cancelled;
@property (nonatomic) BOOL continuing;
@property (nonatomic, strong) NSMutableArray *pendingImageURLs;   // data URLs of generated images
- (void)flushUpdate;
@end

@implementation ORChatEngine
- (instancetype)init {if((self=[super init]))[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(providerChanged) name:ORProviderDidChangeNotification object:nil];return self;}
- (void)dealloc {[[NSNotificationCenter defaultCenter] removeObserver:self];[self.activeRequest cancel];}
- (void)providerChanged {[self cancel];}
- (BOOL)providerMatches {
 if(![self.conversation.providerIdentity isEqual:[ORSettings shared].providerIdentity]){[self appendError:L(@"This conversation belongs to a different provider. Switch back to that provider or start a new chat.")];return NO;}return YES;
}


- (void)setBusy:(BOOL)busy
{
    if (self.isBusy == busy) return;
    self.isBusy = busy;
    [self.delegate chatEngineDidChangeBusyState:self];
    [[NSNotificationCenter defaultCenter] postNotificationName:busy ? ORChatEngineDidStartNotification : ORChatEngineDidFinishNotification
                                                        object:self
                                                      userInfo:busy ? nil : @{ @"message": self.conversation.messages.lastObject ?: [NSNull null] }];
}

#pragma mark - Public

- (void)sendText:(NSString *)text attachments:(NSArray *)attachments model:(ORModelInfo *)model
{
    if (self.isBusy || !self.conversation || ![self providerMatches]) return;
    if(![ORProvider isOpenRouter])for(ORAttachment *a in attachments)if(a.kind==ORAttachmentKindPDF){[self appendError:L(@"PDF parsing is available through OpenRouter. Convert this PDF to text before using another provider.")];return;}
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
    if (self.isBusy || !self.conversation || ![self providerMatches]) return;
    // Drop everything after the last user message.
    NSInteger lastUser = -1;
    for (NSInteger i = (NSInteger)self.conversation.messages.count - 1; i >= 0; i--) {
        if (((ORMessage *)self.conversation.messages[i]).role == ORMessageRoleUser) { lastUser = i; break; }
    }
    if (lastUser < 0) return;
    while ((NSInteger)self.conversation.messages.count > lastUser + 1) {
        ORMessage *m = self.conversation.messages.lastObject;
        for (ORAttachment *a in m.attachments) [a deleteFile];
        [self.conversation.messages removeLastObject];
    }
    [self runAssistantTurnWithModel:model];
}

- (void)continueMessage:(ORMessage *)message model:(ORModelInfo *)model
{
    if (self.isBusy || !self.conversation || !model || ![self providerMatches]) return;
    if (!message || message.role != ORMessageRoleAssistant || message != self.conversation.messages.lastObject) return;
    self.cancelled = NO;
    [self setBusy:YES];
    message.isStreaming = YES;
    message.statusText = nil;
    message.finishReason = nil;
    message.canContinue = NO;
    self.pendingAssistant = message;
    self.continuing = YES;
    self.pendingImageURLs = [NSMutableArray array];
    [self.delegate chatEngine:self didUpdateMessage:message];
    [self sendMainRequestWithModel:model];
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

- (void)truncateFromMessage:(ORMessage *)message
{
    NSUInteger idx = [self.conversation.messages indexOfObjectIdenticalTo:message];
    if (idx == NSNotFound) return;
    while (self.conversation.messages.count > idx) {
        ORMessage *m = self.conversation.messages.lastObject;
        if (m != message) {
            for (ORAttachment *a in m.attachments) [a deleteFile];   // the edited message keeps its files
        }
        [self.conversation.messages removeLastObject];
    }
    if (self.conversation.isEmpty) [[ORStore shared] deleteConversation:self.conversation.conversationId];
    else [[ORStore shared] saveConversation:self.conversation];
}

#pragma mark - Turn

- (void)runAssistantTurnWithModel:(ORModelInfo *)model
{
    if (!model) {
        [self appendError:L(@"No model selected. Tap the model name to choose one.")];
        return;
    }
    self.cancelled = NO;
    self.continuing = NO;
    self.pendingImageURLs = [NSMutableArray array];
    [self setBusy:YES];
    self.conversation.modelId = model.modelId;

    ORMessage *assistant = [ORMessage messageWithRole:ORMessageRoleAssistant text:@""];
    assistant.modelId = model.modelId;
    assistant.isStreaming = YES;
    assistant.statusText = L(@"Thinking…");
    assistant.usedWebSearch = [ORProvider isOpenRouter] && [ORSettings shared].webSearch;
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

#pragma mark - Response helpers

- (NSDictionary *)firstChoiceOf:(NSDictionary *)json
{
    NSArray *choices = json[@"choices"];
    if (![choices isKindOfClass:[NSArray class]] || !choices.count) return nil;
    id first = choices[0];
    return [first isKindOfClass:[NSDictionary class]] ? first : nil;
}

- (NSString *)contentStringFromResponse:(NSDictionary *)json
{
    NSDictionary *msg = [self firstChoiceOf:json][@"message"];
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

- (void)collectImagesFrom:(id)images
{
    if (![images isKindOfClass:[NSArray class]]) return;
    for (id item in images) {
        NSString *url = nil;
        if ([item isKindOfClass:[NSDictionary class]]) {
            id iu = item[@"image_url"];
            if ([iu isKindOfClass:[NSDictionary class]] && [iu[@"url"] isKindOfClass:[NSString class]]) url = iu[@"url"];
            else if ([item[@"url"] isKindOfClass:[NSString class]]) url = item[@"url"];
        } else if ([item isKindOfClass:[NSString class]]) {
            url = item;
        }
        if (url.length && ![self.pendingImageURLs containsObject:url]) [self.pendingImageURLs addObject:url];
    }
}

// Turns collected data URLs into image attachments on the assistant message.
- (void)storeGeneratedImagesOn:(ORMessage *)assistant
{
    if (!self.pendingImageURLs.count) return;
    NSMutableArray *atts = [assistant.attachments mutableCopy] ?: [NSMutableArray array];
    NSInteger n = (NSInteger)atts.count + 1;
    for (NSString *url in self.pendingImageURLs) {
        NSString *mime = nil;
        NSData *data = [ORUtils dataFromDataURL:url mime:&mime];
        if (!data.length) continue;
        NSString *name = [NSString stringWithFormat:@"generated-%ld.%@", (long)n++, [ORUtils extensionForMime:mime]];
        NSString *dest = [ORUtils uniqueAttachmentPathForName:name];
        if (![data writeToFile:dest atomically:YES]) continue;
        ORAttachment *a = [[ORAttachment alloc] init];
        a.attachmentId = [ORUtils uuid];
        a.storedName = [dest lastPathComponent];
        a.displayName = name;
        a.mime = mime ?: @"image/png";
        a.kind = ORAttachmentKindImage;
        a.size = data.length;
        UIImage *img = [ORUtils thumbnailForImageAtPath:dest maxPixels:64];
        if (img) {
            CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:dest], NULL);
            if (src) {
                NSDictionary *props = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(src, 0, NULL);
                a.pixelWidth = [props[(id)kCGImagePropertyPixelWidth] integerValue];
                a.pixelHeight = [props[(id)kCGImagePropertyPixelHeight] integerValue];
                CFRelease(src);
            }
        }
        [atts addObject:a];
    }
    assistant.attachments = atts;
    [self.pendingImageURLs removeAllObjects];
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
    NSString *sys = [settings activeSystemPrompt];
    if (sys.length) [messages addObject:@{ @"role": @"system", @"content": sys }];

    // History without local error bubbles and without the streaming placeholder
    // (when continuing a cut-off reply, the placeholder IS the last assistant message and stays in).
    NSMutableArray *history = [NSMutableArray array];
    for (ORMessage *m in self.conversation.messages) {
        if (m.role == ORMessageRoleError) continue;
        if (m == self.pendingAssistant && !self.continuing) continue;
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
    NSMutableArray *built = [NSMutableArray array];
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
    while (total > budget && built.count > 0 && dropFrom + 1 < built.count) {
        total -= [sizes[dropFrom] longLongValue];
        dropFrom++;
    }
    for (NSUInteger i = dropFrom; i < built.count; i++) [messages addObject:built[i]];

    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    if(self.continuing && ![ORProvider isOpenRouter])[messages addObject:@{@"role":@"user",@"content":@"Continue the previous answer from where it stopped. Do not repeat the text already written."}];
    body[@"model"] = model.modelId;
    body[@"messages"] = messages;
    if (settings.temperature >= 0 && [model supportsParameter:@"temperature"]) body[@"temperature"] = @(settings.temperature);
    if (settings.maxTokens > 0) body[@"max_tokens"] = @(settings.maxTokens);

    // Reasoning control (only for models that advertise it)
    NSString *effort = settings.reasoningEffort ?: @"default";
    if ([model supportsParameter:@"reasoning"] && ![effort isEqualToString:@"default"]) {
        if ([effort isEqualToString:@"off"]) body[@"reasoning"] = @{ @"enabled": @NO };
        else body[@"reasoning"] = @{ @"effort": effort };
    }

    // Image generation for models with image output
    if ([model supportsImageOutput]) body[@"modalities"] = @[ @"image", @"text" ];

    NSMutableArray *plugins = [NSMutableArray array];
    if ([ORProvider isOpenRouter] && settings.webSearch) [plugins addObject:@{ @"id": @"web", @"max_results": @5 }];
    if ([ORProvider isOpenRouter] && anyPDF) [plugins addObject:@{ @"id": @"file-parser", @"pdf": @{ @"engine": settings.pdfEngine ?: @"cloudflare-ai" } }];
    if ([ORProvider isOpenRouter] && settings.middleOut) [plugins addObject:@{ @"id": @"context-compression", @"engine": @"middle-out" }];
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
    if(self.cancelled||![self.conversation.providerIdentity isEqual:[ORSettings shared].providerIdentity]){[self finishCancelled];return;}
    ORMessage *assistant = self.pendingAssistant;
    NSDictionary *body = [self buildBodyWithModel:model];
    BOOL stream = [ORSettings shared].streaming;
    BOOL continuing = self.continuing;
    self.activeRequest = [[OROpenRouterClient shared] chatCompletionWithBody:body stream:stream onDelta:^(NSDictionary *chunk) {
        NSDictionary *first = [self firstChoiceOf:chunk];
        if (!first) return;
        id fr = first[@"finish_reason"];
        if ([fr isKindOfClass:[NSString class]]) assistant.finishReason = fr;
        NSDictionary *delta = first[@"delta"];
        if (![delta isKindOfClass:[NSDictionary class]]) return;
        id content = delta[@"content"];
        id reasoning = delta[@"reasoning"] ?: delta[@"reasoning_content"];
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
        if (delta[@"images"]) [self collectImagesFrom:delta[@"images"]];
        if (changed) {
            if (assistant.text.length) assistant.statusText = nil;
            [self scheduleUpdate];
        }
    } completion:^(NSDictionary *finalJSON, NSError *error) {
        self.activeRequest = nil;
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(flushUpdate) object:nil];
        self.updateScheduled = NO;
        if (!stream && finalJSON) {
            NSString *text = [self contentStringFromResponse:finalJSON] ?: @"";
            assistant.text = continuing ? [assistant.text stringByAppendingString:text] : text;
            NSDictionary *first = [self firstChoiceOf:finalJSON];
            id fr = first[@"finish_reason"];
            if ([fr isKindOfClass:[NSString class]]) assistant.finishReason = fr;
            NSDictionary *msg = first[@"message"];
            if ([msg isKindOfClass:[NSDictionary class]]) {
                id r = msg[@"reasoning"] ?: msg[@"reasoning_content"];
                if ([r isKindOfClass:[NSString class]] && [r length]) assistant.reasoning = r;
                if (msg[@"images"]) [self collectImagesFrom:msg[@"images"]];
            }
        }
        NSDictionary *usage = finalJSON[@"usage"];
        if ([usage isKindOfClass:[NSDictionary class]]) {
            assistant.promptTokens = [usage[@"prompt_tokens"] integerValue];
            assistant.completionTokens = [usage[@"completion_tokens"] integerValue];
            assistant.cost = [usage[@"cost"] doubleValue];
            assistant.hasUsage = YES;
        }
        [self storeGeneratedImagesOn:assistant];
        [self finishWithError:error];
    }];
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
    self.continuing = NO;
    assistant.isStreaming = NO;
    assistant.statusText = nil;
    BOOL cancelled = error && error.code == ORErrorCancelled && [error.domain isEqualToString:ORErrorDomain];
    BOOL hasContent = assistant.text.length > 0 || assistant.attachments.count > 0;

    if (!hasContent) {
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
