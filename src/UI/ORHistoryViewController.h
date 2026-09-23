#import <UIKit/UIKit.h>

// List of saved conversations. onSelect is called with the conversation id, onChange when
// conversations were deleted (the presenter re-checks whether its own conversation still exists).
@interface ORHistoryViewController : UITableViewController

@property (nonatomic, copy) NSString *currentConversationId;
@property (nonatomic, copy) void (^onSelect)(NSString *conversationId);
@property (nonatomic, copy) void (^onChange)(void);
@property (nonatomic) BOOL showsDoneButton;

@end
