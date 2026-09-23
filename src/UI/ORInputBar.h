#import <UIKit/UIKit.h>
#import "ORAttachment.h"

@class ORInputBar;

@protocol ORInputBarDelegate <NSObject>
- (void)inputBarDidTapSend:(ORInputBar *)bar;
- (void)inputBarDidTapStop:(ORInputBar *)bar;
- (void)inputBarDidTapAttach:(ORInputBar *)bar;
- (void)inputBarDidChangeHeight:(ORInputBar *)bar;
- (void)inputBar:(ORInputBar *)bar didRemoveAttachment:(ORAttachment *)attachment;
@end

// Messages-style composer: attachment strip, growing text view, "+" and Send/Stop buttons.
@interface ORInputBar : UIView

@property (nonatomic, weak) id<ORInputBarDelegate> delegate;
@property (nonatomic, strong, readonly) UITextView *textView;
@property (nonatomic, strong, readonly) UIButton *attachButton;
@property (nonatomic) BOOL busy;
@property (nonatomic, strong) NSArray *attachments;

- (NSString *)text;
- (void)clearText;
- (CGFloat)preferredHeight;
- (void)applyTheme;
- (void)refreshSendButton;

@end
