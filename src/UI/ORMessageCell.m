#import "ORMessageCell.h"
#import "ORMarkdown.h"
#import "ORTheme.h"
#import "ORSettings.h"
#import "ORModelCatalog.h"
#import "ORUtils.h"
#import "ORCommon.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kSideMargin = 8.0;
static const CGFloat kBubblePadH = 11.0;
static const CGFloat kBubblePadV = 8.0;
static const CGFloat kBlockSpacing = 7.0;
static const CGFloat kListSpacing = 2.0;
static const CGFloat kCellPadV = 5.0;
static const CGFloat kThumbSize = 64.0;
static const CGFloat kThumbSpacing = 5.0;
static const CGFloat kMetaHeight = 15.0;
static const CGFloat kNoteCollapsedHeight = 36.0;
static const CGFloat kCodePad = 7.0;

#pragma mark - Layout description

@interface ORBlockFrame : NSObject
@property (nonatomic, strong) ORMDBlock *block;
@property (nonatomic) CGRect frame;      // relative to bubble content origin
@end
@implementation ORBlockFrame
@end

@interface ORMessageLayout : NSObject
@property (nonatomic) CGFloat width;
@property (nonatomic) NSUInteger textLength;
@property (nonatomic) BOOL noteExpanded;
@property (nonatomic) BOOL streaming;
@property (nonatomic, copy) NSString *statusText;
@property (nonatomic, strong) NSArray *blockFrames;
@property (nonatomic, strong) NSArray *attachmentFrames;   // NSValue rects relative to bubble content
@property (nonatomic) CGRect bubbleFrame;                  // in cell coordinates
@property (nonatomic) CGRect metaFrame;
@property (nonatomic) CGRect noteFrame;
@property (nonatomic) CGRect statusFrame;
@property (nonatomic) CGFloat totalHeight;
@property (nonatomic, copy) NSString *metaText;
@property (nonatomic, strong) NSAttributedString *noteText;
@end
@implementation ORMessageLayout
@end

static NSMutableDictionary *g_layoutCache = nil;

static CGSize ORMeasure(NSAttributedString *text, CGFloat width)
{
    if (!text.length) return CGSizeZero;
    CGRect r = [text boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX)
                                  options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                  context:nil];
    return CGSizeMake(ceil(r.size.width), ceil(r.size.height) + 1);
}

static NSAttributedString *ORCodeAttributed(NSString *raw, UIColor *color)
{
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.lineBreakMode = NSLineBreakByCharWrapping;
    return [[NSAttributedString alloc] initWithString:raw ?: @"" attributes:@{
        NSFontAttributeName: [[ORTheme shared] codeFont],
        NSForegroundColorAttributeName: color,
        NSParagraphStyleAttributeName: ps,
    }];
}

#pragma mark - Code block view

@interface ORCodeBlockView : UIView
@property (nonatomic, strong) UILabel *label;
@end

@implementation ORCodeBlockView
- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.layer.cornerRadius = 5.0;
        self.clipsToBounds = YES;
        _label = [[UILabel alloc] initWithFrame:CGRectZero];
        _label.numberOfLines = 0;
        _label.backgroundColor = [UIColor clearColor];
        _label.lineBreakMode = NSLineBreakByCharWrapping;
        [self addSubview:_label];
    }
    return self;
}
- (void)layoutSubviews
{
    [super layoutSubviews];
    self.label.frame = CGRectInset(self.bounds, kCodePad, kCodePad);
}
@end

#pragma mark - Cell

@interface ORMessageCell ()
@property (nonatomic, strong) ORMessage *message;
@property (nonatomic, strong) ORMessageLayout *layout;
@property (nonatomic, strong) UIImageView *bubbleView;
@property (nonatomic, strong) NSMutableArray *blockViews;
@property (nonatomic, strong) NSMutableArray *attachmentViews;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UIView *noteView;
@property (nonatomic, strong) UILabel *noteLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILongPressGestureRecognizer *longPress;
@end

@implementation ORMessageCell

+ (void)invalidateLayoutCache
{
    [g_layoutCache removeAllObjects];
}

#pragma mark Layout computation

+ (CGFloat)bubbleMaxWidthForWidth:(CGFloat)width
{
    CGFloat max = ORIsPad() ? MIN(width * 0.78, 640.0) : width * 0.82;
    return floor(max);
}

+ (ORMessageLayout *)layoutForMessage:(ORMessage *)m width:(CGFloat)width
{
    if (!g_layoutCache) g_layoutCache = [NSMutableDictionary dictionary];
    NSString *key = m.messageId ?: @"";
    ORMessageLayout *cached = g_layoutCache[key];
    if (cached && cached.width == width && cached.textLength == m.text.length && cached.noteExpanded == m.visionNoteExpanded &&
        cached.streaming == m.isStreaming && ((cached.statusText == nil && m.statusText == nil) || [cached.statusText isEqualToString:m.statusText]) &&
        !(m.isStreaming && cached.textLength == 0)) {
        return cached;
    }

    ORTheme *theme = [ORTheme shared];
    ORSettings *settings = [ORSettings shared];
    BOOL isUser = m.role == ORMessageRoleUser;
    BOOL isError = m.role == ORMessageRoleError;
    ORMessageLayout *L = [[ORMessageLayout alloc] init];
    L.width = width;
    L.textLength = m.text.length;
    L.noteExpanded = m.visionNoteExpanded;
    L.streaming = m.isStreaming;
    L.statusText = m.statusText;

    CGFloat bubbleMax = [self bubbleMaxWidthForWidth:width];
    CGFloat contentMax = bubbleMax - 2 * kBubblePadH;
    UIColor *textColor = isUser ? [theme userBubbleTextColor] : (isError ? [theme errorTextColor] : [theme assistantBubbleTextColor]);

    CGFloat y = 0;
    CGFloat maxBlockWidth = 0;

    // Attachments (user messages)
    NSMutableArray *attFrames = [NSMutableArray array];
    if (m.attachments.count) {
        CGFloat x = 0;
        CGFloat rowH = 0;
        for (ORAttachment *a in m.attachments) {
            CGFloat w = [a isImage] ? kThumbSize : MIN(contentMax, 180.0);
            CGFloat h = [a isImage] ? kThumbSize : 40.0;
            if (x > 0 && x + w > contentMax) {
                x = 0;
                y += rowH + kThumbSpacing;
                rowH = 0;
            }
            [attFrames addObject:[NSValue valueWithCGRect:CGRectMake(x, y, w, h)]];
            x += w + kThumbSpacing;
            rowH = MAX(rowH, h);
            maxBlockWidth = MAX(maxBlockWidth, x - kThumbSpacing);
        }
        y += rowH;
        if (m.text.length) y += kBlockSpacing;
    }
    L.attachmentFrames = attFrames;

    // Status (streaming, no text yet)
    if (m.isStreaming && m.text.length == 0) {
        NSString *status = m.statusText ?: L(@"Thinking…");
        NSAttributedString *st = [ORMarkdown plainAttributedString:status color:[theme secondaryTextColor] font:[theme messageFont]];
        CGSize sz = ORMeasure(st, contentMax - 26);
        L.statusFrame = CGRectMake(0, y, sz.width + 26, MAX(sz.height, 20));
        maxBlockWidth = MAX(maxBlockWidth, sz.width + 26);
        y += MAX(sz.height, 20);
    }

    // Text blocks
    NSArray *blocks;
    if (isError) {
        ORMDBlock *b = [[ORMDBlock alloc] init];
        b.type = ORMDBlockParagraph;
        b.text = [ORMarkdown plainAttributedString:m.text color:textColor font:[theme messageFont]];
        blocks = @[ b ];
    } else if (isUser) {
        // User text is shown verbatim (no Markdown), preserving what was typed.
        if (m.text.length) {
            ORMDBlock *b = [[ORMDBlock alloc] init];
            b.type = ORMDBlockParagraph;
            b.text = [ORMarkdown plainAttributedString:m.text color:textColor font:[theme messageFont]];
            blocks = @[ b ];
        } else {
            blocks = @[];
        }
    } else {
        blocks = [ORMarkdown blocksFromMarkdown:m.text textColor:textColor inUserBubble:NO];
    }

    NSMutableArray *frames = [NSMutableArray array];
    NSInteger prevType = -1;
    BOOL first = YES;
    for (ORMDBlock *b in blocks) {
        if (!first) {
            y += (b.type == ORMDBlockListItem && prevType == ORMDBlockListItem) ? kListSpacing : kBlockSpacing;
        }
        first = NO;
        CGSize size = CGSizeZero;
        switch (b.type) {
            case ORMDBlockCode:
            case ORMDBlockTable: {
                CGSize s = ORMeasure(ORCodeAttributed(b.rawText, textColor), contentMax - 2 * kCodePad);
                size = CGSizeMake(contentMax, s.height + 2 * kCodePad);
                break;
            }
            case ORMDBlockRule:
                size = CGSizeMake(contentMax, 2);
                break;
            default:
                size = ORMeasure(b.text, contentMax);
                if (b.type == ORMDBlockQuote) size.width = MIN(contentMax, size.width + 12);
                break;
        }
        ORBlockFrame *bf = [[ORBlockFrame alloc] init];
        bf.block = b;
        bf.frame = CGRectMake(0, y, size.width, size.height);
        [frames addObject:bf];
        maxBlockWidth = MAX(maxBlockWidth, size.width);
        y += size.height;
        prevType = b.type;
    }
    L.blockFrames = frames;

    CGFloat contentHeight = y;
    CGFloat bubbleWidth = MIN(bubbleMax, MAX(maxBlockWidth, 24) + 2 * kBubblePadH);
    CGFloat bubbleHeight = contentHeight + 2 * kBubblePadV;
    CGFloat bubbleX = isUser ? width - kSideMargin - bubbleWidth : kSideMargin;
    L.bubbleFrame = CGRectMake(bubbleX, kCellPadV, bubbleWidth, bubbleHeight);
    CGFloat cy = kCellPadV + bubbleHeight;

    // Meta line (assistant usage / model)
    L.metaText = nil;
    if (m.role == ORMessageRoleAssistant && !m.isStreaming) {
        NSMutableArray *parts = [NSMutableArray array];
        if (m.modelId) {
            ORModelInfo *info = [[ORModelCatalog shared] modelWithId:m.modelId];
            [parts addObject:info ? [info displayName] : m.modelId];
        }
        if (settings.showUsage && m.hasUsage) {
            [parts addObject:[NSString stringWithFormat:@"%@ → %@ tok", [ORUtils formatTokenCount:m.promptTokens], [ORUtils formatTokenCount:m.completionTokens]]];
            if (m.cost > 0) [parts addObject:[NSString stringWithFormat:@"$%.4f", m.cost]];
        }
        if (parts.count) {
            L.metaText = [parts componentsJoinedByString:@" · "];
            L.metaFrame = CGRectMake(bubbleX + 4, cy + 2, bubbleMax, kMetaHeight);
            cy += kMetaHeight + 2;
        }
    }

    // Vision note (user message)
    if (isUser && m.visionNote.length && settings.showVisionNotes) {
        NSString *by = nil;
        if (m.visionModelId) {
            ORModelInfo *info = [[ORModelCatalog shared] modelWithId:m.visionModelId];
            by = info ? [info displayName] : m.visionModelId;
        }
        NSString *header = by ? [NSString stringWithFormat:L(@"Image described by %@"), by] : L(@"Image description");
        NSString *full = [NSString stringWithFormat:@"%@\n%@", header, m.visionNote];
        NSMutableAttributedString *att = [[NSMutableAttributedString alloc] initWithString:full attributes:@{
            NSFontAttributeName: [theme smallFont], NSForegroundColorAttributeName: [theme secondaryTextColor] }];
        [att addAttribute:NSFontAttributeName value:[UIFont boldSystemFontOfSize:11] range:NSMakeRange(0, header.length)];
        L.noteText = att;
        CGFloat noteW = bubbleMax;
        CGFloat h;
        if (m.visionNoteExpanded) {
            h = ORMeasure(att, noteW - 16).height + 12;
        } else {
            h = kNoteCollapsedHeight;
        }
        L.noteFrame = CGRectMake(width - kSideMargin - noteW, cy + 3, noteW, h);
        cy += h + 3;
    }

    L.totalHeight = cy + kCellPadV;
    g_layoutCache[key] = L;
    if (g_layoutCache.count > 400) [g_layoutCache removeAllObjects];
    return L;
}

+ (CGFloat)heightForMessage:(ORMessage *)message width:(CGFloat)width
{
    return [self layoutForMessage:message width:width].totalHeight;
}

#pragma mark Init

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        UIView *bg = [[UIView alloc] initWithFrame:CGRectZero];
        bg.backgroundColor = [UIColor clearColor];
        self.backgroundView = bg;

        _bubbleView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _bubbleView.userInteractionEnabled = YES;
        [self.contentView addSubview:_bubbleView];
        _blockViews = [NSMutableArray array];
        _attachmentViews = [NSMutableArray array];

        _metaLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _metaLabel.font = [[ORTheme shared] smallFont];
        _metaLabel.backgroundColor = [UIColor clearColor];
        _metaLabel.hidden = YES;
        [self.contentView addSubview:_metaLabel];

        _noteView = [[UIView alloc] initWithFrame:CGRectZero];
        _noteView.layer.cornerRadius = 6;
        _noteView.hidden = YES;
        _noteLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _noteLabel.numberOfLines = 0;
        _noteLabel.backgroundColor = [UIColor clearColor];
        [_noteView addSubview:_noteLabel];
        [self.contentView addSubview:_noteView];
        UITapGestureRecognizer *noteTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(noteTapped:)];
        [_noteView addGestureRecognizer:noteTap];

        _statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _statusLabel.backgroundColor = [UIColor clearColor];
        _statusLabel.hidden = YES;
        [_bubbleView addSubview:_statusLabel];
        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        _spinner.hidesWhenStopped = YES;
        [_bubbleView addSubview:_spinner];

        _longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressed:)];
        _longPress.minimumPressDuration = 0.45;
        [_bubbleView addGestureRecognizer:_longPress];
    }
    return self;
}

#pragma mark Configure

- (void)configureWithMessage:(ORMessage *)message width:(CGFloat)width
{
    self.message = message;
    ORMessageLayout *L = [ORMessageCell layoutForMessage:message width:width];
    self.layout = L;
    ORTheme *theme = [ORTheme shared];
    BOOL isUser = message.role == ORMessageRoleUser;
    BOOL isError = message.role == ORMessageRoleError;
    UIColor *textColor = isUser ? [theme userBubbleTextColor] : (isError ? [theme errorTextColor] : [theme assistantBubbleTextColor]);

    self.bubbleView.image = isUser ? [theme userBubbleImage] : (isError ? [theme errorBubbleImage] : [theme assistantBubbleImage]);
    self.bubbleView.frame = L.bubbleFrame;

    // Attachments
    for (UIView *v in self.attachmentViews) [v removeFromSuperview];
    [self.attachmentViews removeAllObjects];
    NSUInteger ai = 0;
    for (ORAttachment *a in message.attachments) {
        if (ai >= L.attachmentFrames.count) break;
        CGRect f = [L.attachmentFrames[ai] CGRectValue];
        f.origin.x += kBubblePadH;
        f.origin.y += kBubblePadV;
        UIView *v;
        if ([a isImage]) {
            UIImageView *iv = [[UIImageView alloc] initWithFrame:f];
            iv.contentMode = UIViewContentModeScaleAspectFill;
            iv.clipsToBounds = YES;
            iv.layer.cornerRadius = 6;
            iv.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.3];
            iv.image = [a thumbnailWithMaxPixels:kThumbSize * 2];
            v = iv;
        } else {
            UIView *box = [[UIView alloc] initWithFrame:f];
            box.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.22];
            box.layer.cornerRadius = 6;
            UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(8, 3, f.size.width - 16, 18)];
            name.font = [UIFont boldSystemFontOfSize:12];
            name.textColor = textColor;
            name.backgroundColor = [UIColor clearColor];
            name.text = a.displayName;
            name.lineBreakMode = NSLineBreakByTruncatingMiddle;
            [box addSubview:name];
            UILabel *size = [[UILabel alloc] initWithFrame:CGRectMake(8, 20, f.size.width - 16, 16)];
            size.font = [UIFont systemFontOfSize:11];
            size.textColor = textColor;
            size.backgroundColor = [UIColor clearColor];
            size.text = [NSString stringWithFormat:@"%@ · %@", [[a.mime componentsSeparatedByString:@"/"] lastObject] ?: @"", [a sizeString]];
            [box addSubview:size];
            v = box;
        }
        v.userInteractionEnabled = YES;
        v.tag = (NSInteger)ai;
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(attachmentTapped:)];
        [v addGestureRecognizer:tap];
        [self.bubbleView addSubview:v];
        [self.attachmentViews addObject:v];
        ai++;
    }

    // Status
    if (message.isStreaming && message.text.length == 0) {
        CGRect sf = L.statusFrame;
        sf.origin.x += kBubblePadH;
        sf.origin.y += kBubblePadV;
        self.spinner.frame = CGRectMake(sf.origin.x, sf.origin.y + (sf.size.height - 20) / 2, 20, 20);
        self.spinner.activityIndicatorViewStyle = theme.isDark ? UIActivityIndicatorViewStyleWhite : UIActivityIndicatorViewStyleGray;
        [self.spinner startAnimating];
        self.statusLabel.frame = CGRectMake(sf.origin.x + 26, sf.origin.y, sf.size.width - 26, sf.size.height);
        self.statusLabel.font = [theme messageFont];
        self.statusLabel.textColor = [theme secondaryTextColor];
        self.statusLabel.text = message.statusText ?: L(@"Thinking…");
        self.statusLabel.hidden = NO;
    } else {
        [self.spinner stopAnimating];
        self.statusLabel.hidden = YES;
    }

    // Blocks
    for (UIView *v in self.blockViews) [v removeFromSuperview];
    [self.blockViews removeAllObjects];
    for (ORBlockFrame *bf in L.blockFrames) {
        CGRect f = bf.frame;
        f.origin.x += kBubblePadH;
        f.origin.y += kBubblePadV;
        UIView *v = nil;
        switch (bf.block.type) {
            case ORMDBlockCode:
            case ORMDBlockTable: {
                ORCodeBlockView *cv = [[ORCodeBlockView alloc] initWithFrame:f];
                cv.backgroundColor = [theme codeBackgroundColorInUserBubble:isUser];
                cv.label.attributedText = ORCodeAttributed(bf.block.rawText, textColor);
                v = cv;
                break;
            }
            case ORMDBlockRule: {
                UIView *rule = [[UIView alloc] initWithFrame:CGRectMake(f.origin.x, f.origin.y, f.size.width, 1)];
                rule.backgroundColor = [textColor colorWithAlphaComponent:0.3];
                v = rule;
                break;
            }
            case ORMDBlockQuote: {
                UIView *wrap = [[UIView alloc] initWithFrame:f];
                wrap.backgroundColor = [UIColor clearColor];
                UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(2, 0, 3, f.size.height)];
                bar.backgroundColor = [textColor colorWithAlphaComponent:0.35];
                [wrap addSubview:bar];
                UILabel *l = [[UILabel alloc] initWithFrame:wrap.bounds];
                l.numberOfLines = 0;
                l.backgroundColor = [UIColor clearColor];
                l.attributedText = bf.block.text;
                [wrap addSubview:l];
                v = wrap;
                break;
            }
            default: {
                UILabel *l = [[UILabel alloc] initWithFrame:f];
                l.numberOfLines = 0;
                l.backgroundColor = [UIColor clearColor];
                l.attributedText = bf.block.text;
                v = l;
                break;
            }
        }
        [self.bubbleView addSubview:v];
        [self.blockViews addObject:v];
    }

    // Meta
    if (L.metaText) {
        self.metaLabel.hidden = NO;
        self.metaLabel.frame = L.metaFrame;
        self.metaLabel.text = L.metaText;
        self.metaLabel.textColor = [theme secondaryTextColor];
        self.metaLabel.font = [theme smallFont];
    } else {
        self.metaLabel.hidden = YES;
    }

    // Vision note
    if (L.noteText) {
        self.noteView.hidden = NO;
        self.noteView.frame = L.noteFrame;
        self.noteView.backgroundColor = [theme noteBackgroundColor];
        self.noteLabel.frame = CGRectInset(self.noteView.bounds, 8, 6);
        self.noteLabel.attributedText = L.noteText;
        self.noteLabel.lineBreakMode = message.visionNoteExpanded ? NSLineBreakByWordWrapping : NSLineBreakByTruncatingTail;
        self.noteLabel.numberOfLines = message.visionNoteExpanded ? 0 : 2;
    } else {
        self.noteView.hidden = YES;
    }
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    [self.spinner stopAnimating];
}

#pragma mark Actions

- (void)noteTapped:(UITapGestureRecognizer *)g
{
    [self.delegate messageCell:self didToggleVisionNoteForMessage:self.message];
}

- (void)attachmentTapped:(UITapGestureRecognizer *)g
{
    NSInteger idx = g.view.tag;
    if (idx >= 0 && (NSUInteger)idx < self.message.attachments.count) {
        [self.delegate messageCell:self didTapAttachment:self.message.attachments[idx]];
    }
}

- (void)longPressed:(UILongPressGestureRecognizer *)g
{
    if (g.state != UIGestureRecognizerStateBegan) return;
    [self.delegate messageCell:self didLongPressMessage:self.message];
}

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender
{
    if (action == @selector(copy:)) return self.message.text.length > 0;
    if (action == @selector(regenerateMessage:)) return [self.delegate messageCell:self canRegenerateMessage:self.message];
    if (action == @selector(deleteMessageAction:)) return !self.message.isStreaming;
    return NO;
}

- (void)copy:(id)sender
{
    [UIPasteboard generalPasteboard].string = self.message.text ?: @"";
}

- (void)regenerateMessage:(id)sender
{
    [self.delegate messageCell:self regenerateMessage:self.message];
}

- (void)deleteMessageAction:(id)sender
{
    [self.delegate messageCell:self deleteMessage:self.message];
}

- (void)showMenu
{
    [self becomeFirstResponder];
    UIMenuController *menu = [UIMenuController sharedMenuController];
    UIMenuItem *regen = [[UIMenuItem alloc] initWithTitle:L(@"Regenerate") action:@selector(regenerateMessage:)];
    UIMenuItem *del = [[UIMenuItem alloc] initWithTitle:L(@"Delete") action:@selector(deleteMessageAction:)];
    menu.menuItems = @[ regen, del ];
    [menu setTargetRect:self.bubbleView.frame inView:self.contentView];
    [menu setMenuVisible:YES animated:YES];
}

@end
