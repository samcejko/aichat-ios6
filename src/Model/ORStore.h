#import <Foundation/Foundation.h>
#import "ORConversation.h"

// Conversation persistence: one JSON file per conversation in Library/Chats plus index.json.
@interface ORStore : NSObject

+ (instancetype)shared;

// Array of NSDictionary: id, title, updated (NSNumber seconds), model, preview, count. Newest first.
- (NSArray *)conversationSummaries;
- (ORConversation *)loadConversation:(NSString *)conversationId;
- (void)saveConversation:(ORConversation *)conversation;
- (void)deleteConversation:(NSString *)conversationId;
- (void)deleteAllConversations;
- (NSUInteger)conversationCount;

@end
