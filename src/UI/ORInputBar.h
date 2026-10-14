#import <UIKit/UIKit.h>
#import "ORAttachment.h"

@class ORInputBar;

@protocol ORInputBarDelegate <NSObject>
- (void)inputBarDidTapSend:(ORInputBar *)bar;
- (void)inputBarDidTapStop:(ORInputBar *)bar;
- (void)inputBarDidTapAttach:(ORInputBar *)bar;
- (void)inputBarDidChangeHeight:(ORInputBar *)bar;
- (void)inputBar:(ORInputBar *)bar didRemoveAttachment:(ORAttachment *)attachment;
- (void)inputBarDidToggleWebSearch:(ORInputBar *)bar;
@end

// Messages-style composer: attachment strip, growing text view, "+", web-search toggle and Send/Stop buttons.
@interface ORInputBar : UIView

@property (nonatomic, weak) id<ORInputBarDelegate> delegate;
@property (nonatomic, strong, readonly) UITextView *textView;
@property (nonatomic, strong, readonly) UIButton *attachButton;
@property (nonatomic, strong, readonly) UIButton *webButton;
@property (nonatomic) BOOL busy;
@property (nonatomic) BOOL webSearchOn;
@property (nonatomic, strong) NSArray *attachments;
// The part of the bar under the home indicator (bottom) and beside the notch (left/right) on iOS 11 and newer:
// the controls keep clear of it, the background still covers it. Zero on iOS 6. Counted into preferredHeight.
@property (nonatomic) UIEdgeInsets safeInsets;

- (NSString *)text;
- (void)setText:(NSString *)text;
- (void)clearText;
- (CGFloat)preferredHeight;
- (void)applyTheme;
- (void)refreshSendButton;

@end
