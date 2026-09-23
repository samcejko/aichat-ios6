#import <Foundation/Foundation.h>
#import "ORAttachment.h"

typedef NS_ENUM(NSInteger, ORMessageRole) {
    ORMessageRoleUser = 0,
    ORMessageRoleAssistant = 1,
    ORMessageRoleError = 2,     // local error bubble, never sent to the API
};

@interface ORMessage : NSObject

@property (nonatomic, copy) NSString *messageId;
@property (nonatomic) ORMessageRole role;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *reasoning;         // reasoning tokens if the model returned them
@property (nonatomic, copy) NSString *modelId;           // model that produced an assistant message
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic, strong) NSArray *attachments;      // ORAttachment
@property (nonatomic, copy) NSString *visionNote;        // description produced by the vision helper
@property (nonatomic, copy) NSString *visionModelId;
@property (nonatomic) NSInteger promptTokens;
@property (nonatomic) NSInteger completionTokens;
@property (nonatomic) double cost;
@property (nonatomic) BOOL hasUsage;
@property (nonatomic, copy) NSString *finishReason;      // "stop", "length", ...
@property (nonatomic) BOOL usedWebSearch;

// transient UI state
@property (nonatomic) BOOL isStreaming;
@property (nonatomic) BOOL visionNoteExpanded;
@property (nonatomic) BOOL reasoningExpanded;
@property (nonatomic) BOOL canContinue;                  // set by the chat screen for the last reply
@property (nonatomic, copy) NSString *statusText;       // e.g. "Analyzing image..." while streaming

+ (instancetype)messageWithRole:(ORMessageRole)role text:(NSString *)text;
+ (instancetype)messageFromJSON:(NSDictionary *)json;
- (NSDictionary *)toJSON;

- (NSArray *)imageAttachments;
- (NSArray *)pdfAttachments;
- (NSArray *)textAttachments;
- (BOOL)hasImages;

@end
