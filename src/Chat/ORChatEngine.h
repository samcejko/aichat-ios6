#import <Foundation/Foundation.h>
#import "ORConversation.h"
#import "ORModelInfo.h"

@class ORChatEngine;

extern NSString * const ORChatEngineDidStartNotification;    // object = engine
extern NSString * const ORChatEngineDidFinishNotification;   // object = engine, userInfo[@"message"] = ORMessage

@protocol ORChatEngineDelegate <NSObject>
- (void)chatEngine:(ORChatEngine *)engine didAddMessage:(ORMessage *)message;
- (void)chatEngine:(ORChatEngine *)engine didUpdateMessage:(ORMessage *)message;
- (void)chatEngine:(ORChatEngine *)engine didFinishMessage:(ORMessage *)message;
- (void)chatEngineDidChangeBusyState:(ORChatEngine *)engine;
// The selected model cannot see images and no vision helper is configured: ask the user for one.
- (void)chatEngine:(ORChatEngine *)engine needsVisionModelWithCompletion:(void (^)(ORModelInfo *model))completion;
@end

// Drives one conversation: appends messages, runs the vision relay when needed, builds the API
// request, streams the reply and persists everything.
@interface ORChatEngine : NSObject

@property (nonatomic, weak) id<ORChatEngineDelegate> delegate;
@property (nonatomic, strong) ORConversation *conversation;
@property (nonatomic, readonly) BOOL isBusy;
@property (nonatomic, readonly) ORMessage *pendingAssistant;

- (void)sendText:(NSString *)text attachments:(NSArray *)attachments model:(ORModelInfo *)model;
- (void)regenerateWithModel:(ORModelInfo *)model;
- (void)continueMessage:(ORMessage *)message model:(ORModelInfo *)model;   // reply cut off by max tokens
- (void)cancel;
- (void)deleteMessage:(ORMessage *)message;
// Removes the message and everything after it (used by "edit and resend").
- (void)truncateFromMessage:(ORMessage *)message;

@end
