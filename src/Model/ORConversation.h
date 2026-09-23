#import <Foundation/Foundation.h>
#import "ORMessage.h"

@interface ORConversation : NSObject

@property (nonatomic, copy) NSString *conversationId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *modelId;
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic, strong) NSDate *updatedAt;
@property (nonatomic, strong) NSMutableArray *messages;   // ORMessage

+ (instancetype)newConversation;
+ (instancetype)conversationFromJSON:(NSDictionary *)json;
- (NSDictionary *)toJSON;

- (BOOL)isEmpty;                 // no user/assistant messages
- (NSString *)preview;
- (void)updateTitleIfNeeded;     // derives the title from the first user message
- (ORMessage *)lastMessage;
- (ORMessage *)lastUserMessage;

@end
