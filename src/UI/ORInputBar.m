#import "ORInputBar.h"
#import "ORTheme.h"
#import "ORCommon.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kBarMinHeight = 44.0;
static const CGFloat kStripHeight = 64.0;
static const CGFloat kThumb = 48.0;
static const NSInteger kMaxLines = 5;

@interface ORInputBar () <UITextViewDelegate>
@property (nonatomic, strong) UIImageView *background;
@property (nonatomic, strong) UIImageView *fieldBackground;
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *placeholder;
@property (nonatomic, strong) UIButton *attachButton;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) UIScrollView *strip;
@property (nonatomic, strong) NSMutableArray *stripViews;
@property (nonatomic) CGFloat lastReportedHeight;
@end

@implementation ORInputBar

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        _stripViews = [NSMutableArray array];

        _strip = [[UIScrollView alloc] initWithFrame:CGRectZero];
        _strip.showsHorizontalScrollIndicator = NO;
        _strip.alwaysBounceHorizontal = YES;
        _strip.hidden = YES;
        [self addSubview:_strip];

        _background = [[UIImageView alloc] initWithFrame:CGRectZero];
        [self addSubview:_background];

        _attachButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [_attachButton addTarget:self action:@selector(attachTapped) forControlEvents:UIControlEventTouchUpInside];
        _attachButton.showsTouchWhenHighlighted = YES;
        [self addSubview:_attachButton];

        _fieldBackground = [[UIImageView alloc] initWithFrame:CGRectZero];
        _fieldBackground.userInteractionEnabled = YES;
        [self addSubview:_fieldBackground];

        _textView = [[UITextView alloc] initWithFrame:CGRectZero];
        _textView.delegate = self;
        _textView.backgroundColor = [UIColor clearColor];
        _textView.scrollsToTop = NO;
        _textView.autocorrectionType = UITextAutocorrectionTypeDefault;
        _textView.returnKeyType = UIReturnKeyDefault;
        _textView.enablesReturnKeyAutomatically = NO;
        [_fieldBackground addSubview:_textView];

        _placeholder = [[UILabel alloc] initWithFrame:CGRectZero];
        _placeholder.backgroundColor = [UIColor clearColor];
        _placeholder.text = L(@"Message");
        _placeholder.userInteractionEnabled = NO;
        [_fieldBackground addSubview:_placeholder];

        _sendButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _sendButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
        _sendButton.titleLabel.shadowOffset = CGSizeMake(0, -1);
        [_sendButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [_sendButton setTitleShadowColor:[UIColor colorWithWhite:0 alpha:0.35] forState:UIControlStateNormal];
        [_sendButton addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_sendButton];

        [self applyTheme];
    }
    return self;
}

#pragma mark - Theme

- (void)applyTheme
{
    ORTheme *t = [ORTheme shared];
    self.background.image = [t inputBarBackgroundImage];
    self.fieldBackground.image = [t textFieldBackgroundImage];
    self.textView.font = [t messageFont];
    self.textView.textColor = [t inputTextColor];
    self.textView.keyboardAppearance = t.isDark ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;
    self.placeholder.font = [t messageFont];
    self.placeholder.textColor = [t placeholderColor];
    [self.attachButton setImage:[t plusButtonImage] forState:UIControlStateNormal];
    self.strip.backgroundColor = t.isDark ? [UIColor colorWithWhite:0.12 alpha:1] : [UIColor colorWithWhite:0.88 alpha:1];
    [self refreshSendButton];
    [self setNeedsLayout];
}

- (void)refreshSendButton
{
    ORTheme *t = [ORTheme shared];
    BOOL hasContent = [self text].length > 0 || self.attachments.count > 0;
    if (self.busy) {
        [self.sendButton setTitle:L(@"Stop") forState:UIControlStateNormal];
        [self.sendButton setBackgroundImage:[t stopButtonImage] forState:UIControlStateNormal];
        self.sendButton.enabled = YES;
    } else {
        [self.sendButton setTitle:L(@"Send") forState:UIControlStateNormal];
        [self.sendButton setBackgroundImage:[t sendButtonImageHighlighted:NO disabled:!hasContent] forState:UIControlStateNormal];
        [self.sendButton setBackgroundImage:[t sendButtonImageHighlighted:YES disabled:NO] forState:UIControlStateHighlighted];
        self.sendButton.enabled = hasContent;
    }
    self.attachButton.enabled = !self.busy;
    self.attachButton.alpha = self.busy ? 0.4 : 1.0;
}

- (void)setBusy:(BOOL)busy
{
    _busy = busy;
    [self refreshSendButton];
}

#pragma mark - Text

- (NSString *)text
{
    return self.textView.text ?: @"";
}

- (void)clearText
{
    self.textView.text = @"";
    [self textViewDidChange:self.textView];
}

- (CGFloat)textHeight
{
    CGFloat lineHeight = self.textView.font.lineHeight;
    CGFloat minH = ceil(lineHeight) + 16;
    CGFloat maxH = ceil(lineHeight * kMaxLines) + 16;
    CGFloat h = self.textView.contentSize.height;
    if (h < minH) h = minH;
    if (h > maxH) h = maxH;
    return ceil(h);
}

- (CGFloat)preferredHeight
{
    CGFloat strip = self.attachments.count ? kStripHeight : 0;
    return strip + MAX(kBarMinHeight, [self textHeight] + 12);
}

- (void)textViewDidChange:(UITextView *)textView
{
    self.placeholder.hidden = textView.text.length > 0;
    [self refreshSendButton];
    CGFloat h = [self preferredHeight];
    if (fabs(h - self.lastReportedHeight) > 0.5) {
        self.lastReportedHeight = h;
        [self.delegate inputBarDidChangeHeight:self];
    }
    [self setNeedsLayout];
}

#pragma mark - Attachments

- (void)setAttachments:(NSArray *)attachments
{
    _attachments = [attachments copy] ?: @[];
    for (UIView *v in self.stripViews) [v removeFromSuperview];
    [self.stripViews removeAllObjects];
    ORTheme *t = [ORTheme shared];
    CGFloat x = 8;
    NSInteger i = 0;
    for (ORAttachment *a in _attachments) {
        CGFloat w = [a isImage] ? kThumb : 120;
        UIView *item;
        if ([a isImage]) {
            UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(x, 8, kThumb, kThumb)];
            iv.contentMode = UIViewContentModeScaleAspectFill;
            iv.clipsToBounds = YES;
            iv.layer.cornerRadius = 5;
            iv.image = [a thumbnailWithMaxPixels:kThumb * 2];
            iv.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.3];
            item = iv;
        } else {
            UIView *box = [[UIView alloc] initWithFrame:CGRectMake(x, 8, w, kThumb)];
            box.backgroundColor = t.isDark ? [UIColor colorWithWhite:0.25 alpha:1] : [UIColor whiteColor];
            box.layer.cornerRadius = 5;
            UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(6, 6, w - 26, 18)];
            name.font = [UIFont boldSystemFontOfSize:12];
            name.textColor = [t primaryTextColor];
            name.backgroundColor = [UIColor clearColor];
            name.lineBreakMode = NSLineBreakByTruncatingMiddle;
            name.text = a.displayName;
            [box addSubview:name];
            UILabel *size = [[UILabel alloc] initWithFrame:CGRectMake(6, 26, w - 26, 16)];
            size.font = [UIFont systemFontOfSize:11];
            size.textColor = [t secondaryTextColor];
            size.backgroundColor = [UIColor clearColor];
            size.text = [a sizeString];
            [box addSubview:size];
            item = box;
        }
        item.userInteractionEnabled = YES;
        [self.strip addSubview:item];
        [self.stripViews addObject:item];

        UIButton *remove = [UIButton buttonWithType:UIButtonTypeCustom];
        remove.frame = CGRectMake(x + w - 14, 2, 22, 22);
        remove.tag = i;
        [remove setTitle:@"✕" forState:UIControlStateNormal];
        remove.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        [remove setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        remove.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.85];
        remove.layer.cornerRadius = 11;
        [remove addTarget:self action:@selector(removeTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.strip addSubview:remove];
        [self.stripViews addObject:remove];

        x += w + 10;
        i++;
    }
    self.strip.contentSize = CGSizeMake(x, kStripHeight);
    self.strip.hidden = _attachments.count == 0;
    [self refreshSendButton];
    CGFloat h = [self preferredHeight];
    if (fabs(h - self.lastReportedHeight) > 0.5) {
        self.lastReportedHeight = h;
        [self.delegate inputBarDidChangeHeight:self];
    }
    [self setNeedsLayout];
}

- (void)removeTapped:(UIButton *)b
{
    NSInteger idx = b.tag;
    if (idx < 0 || (NSUInteger)idx >= self.attachments.count) return;
    ORAttachment *a = self.attachments[idx];
    [self.delegate inputBar:self didRemoveAttachment:a];
}

#pragma mark - Buttons

- (void)attachTapped
{
    [self.delegate inputBarDidTapAttach:self];
}

- (void)sendTapped
{
    if (self.busy) [self.delegate inputBarDidTapStop:self];
    else [self.delegate inputBarDidTapSend:self];
}

#pragma mark - Layout

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    CGFloat stripH = self.attachments.count ? kStripHeight : 0;
    self.strip.frame = CGRectMake(0, 0, w, stripH);
    self.background.frame = CGRectMake(0, stripH, w, h - stripH);

    CGFloat barH = h - stripH;
    self.attachButton.frame = CGRectMake(6, h - 37, 30, 30);
    CGFloat sendW = 62;
    self.sendButton.frame = CGRectMake(w - 8 - sendW, h - 38, sendW, 31);

    CGFloat fieldX = 42;
    CGFloat fieldW = w - fieldX - sendW - 16;
    CGFloat fieldH = barH - 12;
    self.fieldBackground.frame = CGRectMake(fieldX, stripH + 6, fieldW, fieldH);
    self.textView.frame = CGRectMake(4, 0, fieldW - 8, fieldH);
    self.placeholder.frame = CGRectMake(12, 8, fieldW - 24, 20);
}

@end
