#import <UIKit/UIKit.h>
#import "ORMessage.h"

@class ORMessageCell;

@protocol ORMessageCellDelegate <NSObject>
- (void)messageCell:(ORMessageCell *)cell didLongPressMessage:(ORMessage *)message;
- (void)messageCell:(ORMessageCell *)cell didTapAttachment:(ORAttachment *)attachment;
- (void)messageCell:(ORMessageCell *)cell didToggleVisionNoteForMessage:(ORMessage *)message;
- (BOOL)messageCell:(ORMessageCell *)cell canRegenerateMessage:(ORMessage *)message;
- (void)messageCell:(ORMessageCell *)cell regenerateMessage:(ORMessage *)message;
- (void)messageCell:(ORMessageCell *)cell deleteMessage:(ORMessage *)message;
@end

// Chat bubble cell. Layout is computed once per (message, width) and reused for the height query.
@interface ORMessageCell : UITableViewCell

@property (nonatomic, weak) id<ORMessageCellDelegate> delegate;
@property (nonatomic, strong, readonly) ORMessage *message;

+ (CGFloat)heightForMessage:(ORMessage *)message width:(CGFloat)width;
+ (void)invalidateLayoutCache;
- (void)configureWithMessage:(ORMessage *)message width:(CGFloat)width;
- (void)showMenu;

@end
