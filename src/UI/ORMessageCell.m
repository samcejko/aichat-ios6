#import "ORMessageCell.h"
#import "ORMarkdown.h"
#import "ORTheme.h"
#import "ORSettings.h"
#import "ORModelCatalog.h"
#import "ORUtils.h"
#import "ORCommon.h"
#import <QuartzCore/QuartzCore.h>
#import "MTMathUILabel.h"
#import "MTFontManager.h"

static const CGFloat kSideMargin = 8.0;
static const CGFloat kMathPad = 6.0;
static const CGFloat kMathMaxHeight = 420.0;

// Shared label used only for measuring formulas.
static MTMathUILabel *ORMathMeasureLabel(void)
{
    static MTMathUILabel *label = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ label = [[MTMathUILabel alloc] initWithFrame:CGRectZero]; });
    return label;
}

static CGFloat ORMathFontSize(void)
{
    return [[ORTheme shared] messageFontSize] + 1.0;
}

// Natural size of a rendered formula; width 0 means the LaTeX could not be parsed.
static CGSize ORMeasureMath(NSString *latex)
{
    MTMathUILabel *l = ORMathMeasureLabel();
    l.fontSize = ORMathFontSize();
    l.labelMode = kMTMathUILabelModeDisplay;
    l.latex = latex ?: @"";
    if (l.error || !latex.length) return CGSizeZero;
    CGSize s = [l sizeThatFits:CGSizeMake(10000, 10000)];
    if (s.width <= 0 || s.height <= 0) return CGSizeZero;
    return CGSizeMake(ceil(s.width), ceil(s.height));
}
static const CGFloat kBubblePadH = 11.0;
static const CGFloat kBubblePadV = 8.0;
static const CGFloat kBlockSpacing = 7.0;
static const CGFloat kListSpacing = 2.0;
static const CGFloat kCellPadV = 5.0;
static const CGFloat kThumbSize = 64.0;
static const CGFloat kThumbSpacing = 5.0;
static const CGFloat kMetaHeight = 15.0;
static const CGFloat kNoteCollapsedHeight = 36.0;
static const CGFloat kReasoningHeaderHeight = 26.0;
static const CGFloat kContinueHeight = 30.0;
static const CGFloat kCodePad = 7.0;
static const CGFloat kMaxGeneratedImage = 260.0;

#pragma mark - Layout description

@interface ORBlockFrame : NSObject
@property (nonatomic, strong) ORMDBlock *block;
@property (nonatomic) CGRect frame;      // relative to bubble content origin
@end
@implementation ORBlockFrame
@end

@interface ORMessageLayout : NSObject
@property (nonatomic, copy) NSString *signature;
@property (nonatomic, strong) NSArray *blockFrames;
@property (nonatomic, strong) NSArray *attachmentFrames;   // NSValue rects relative to bubble content
@property (nonatomic) CGRect reasoningFrame;               // in cell coordinates (above the bubble)
@property (nonatomic) CGRect bubbleFrame;                  // in cell coordinates
@property (nonatomic) CGRect metaFrame;
@property (nonatomic) CGRect noteFrame;
@property (nonatomic) CGRect statusFrame;
@property (nonatomic) CGRect continueFrame;
@property (nonatomic) CGFloat totalHeight;
@property (nonatomic, copy) NSString *metaText;
@property (nonatomic, strong) NSAttributedString *noteText;
@property (nonatomic, strong) NSAttributedString *reasoningText;
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
        NSForegroundColorAttributeName: color ?: [[ORTheme shared] primaryTextColor],
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
@property (nonatomic, strong) UIView *reasoningView;
@property (nonatomic, strong) UILabel *reasoningLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIButton *continueButton;
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

+ (NSString *)signatureForMessage:(ORMessage *)m width:(CGFloat)width
{
    return [NSString stringWithFormat:@"%.0f|%lu|%lu|%d|%lu|%d|%d|%@|%lu|%d|%@|%d",
            width, (unsigned long)m.text.length, (unsigned long)m.visionNote.length, (int)m.visionNoteExpanded,
            (unsigned long)m.reasoning.length, (int)m.reasoningExpanded, (int)m.isStreaming, m.statusText ?: @"",
            (unsigned long)m.attachments.count, (int)m.canContinue, m.finishReason ?: @"", (int)m.hasUsage];
}

+ (ORMessageLayout *)layoutForMessage:(ORMessage *)m width:(CGFloat)width
{
    if (!g_layoutCache) g_layoutCache = [NSMutableDictionary dictionary];
    NSString *key = m.messageId ?: @"";
    NSString *signature = [self signatureForMessage:m width:width];
    ORMessageLayout *cached = g_layoutCache[key];
    if (cached && [cached.signature isEqualToString:signature]) return cached;
    if (g_layoutCache.count > 400) [g_layoutCache removeAllObjects];

    ORTheme *theme = [ORTheme shared];
    ORSettings *settings = [ORSettings shared];
    BOOL isUser = m.role == ORMessageRoleUser;
    BOOL isError = m.role == ORMessageRoleError;
    BOOL isAssistant = m.role == ORMessageRoleAssistant;
    ORMessageLayout *layout = [[ORMessageLayout alloc] init];
    layout.signature = signature;

    CGFloat bubbleMax = [self bubbleMaxWidthForWidth:width];
    CGFloat contentMax = bubbleMax - 2 * kBubblePadH;
    UIColor *textColor = isUser ? [theme userBubbleTextColor] : (isError ? [theme errorTextColor] : [theme assistantBubbleTextColor]);
    CGFloat screenScale = [UIScreen mainScreen].scale;

    CGFloat cy = kCellPadV;

    // Reasoning box (assistant, above the bubble)
    layout.reasoningText = nil;
    if (isAssistant && m.reasoning.length && settings.showReasoning) {
        NSString *header;
        if (m.isStreaming && m.text.length == 0) header = [NSString stringWithFormat:@"%@ · %@", L(@"Reasoning…"), [ORUtils formatTokenCount:(NSInteger)m.reasoning.length]];
        else header = [NSString stringWithFormat:@"%@ %@ · %@", m.reasoningExpanded ? @"▾" : @"▸", L(@"Reasoning"), [ORUtils formatTokenCount:(NSInteger)m.reasoning.length]];
        NSString *full = m.reasoningExpanded ? [NSString stringWithFormat:@"%@\n%@", header, m.reasoning] : header;
        NSMutableAttributedString *att = [[NSMutableAttributedString alloc] initWithString:full attributes:@{
            NSFontAttributeName: [theme smallFont], NSForegroundColorAttributeName: [theme secondaryTextColor] }];
        [att addAttribute:NSFontAttributeName value:[UIFont boldSystemFontOfSize:11] range:NSMakeRange(0, header.length)];
        layout.reasoningText = att;
        CGFloat h = m.reasoningExpanded ? ORMeasure(att, bubbleMax - 16).height + 12 : kReasoningHeaderHeight;
        layout.reasoningFrame = CGRectMake(kSideMargin, cy, bubbleMax, h);
        cy += h + 4;
    }

    CGFloat y = 0;
    CGFloat maxBlockWidth = 0;

    // Attachments
    NSMutableArray *attFrames = [NSMutableArray array];
    if (m.attachments.count) {
        CGFloat x = 0;
        CGFloat rowH = 0;
        for (ORAttachment *a in m.attachments) {
            CGFloat w, h;
            if ([a isImage] && isAssistant) {
                CGFloat pw = a.pixelWidth > 0 ? a.pixelWidth : 512;
                CGFloat ph = a.pixelHeight > 0 ? a.pixelHeight : 512;
                CGFloat scale = MIN(contentMax / pw, kMaxGeneratedImage / ph);
                if (scale > 1.0) scale = 1.0;
                w = MAX(40, floor(pw * scale));
                h = MAX(40, floor(ph * scale));
            } else if ([a isImage]) {
                w = kThumbSize; h = kThumbSize;
            } else {
                w = MIN(contentMax, 180.0); h = 40.0;
            }
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
        if (m.text.length || (m.isStreaming && m.text.length == 0)) y += kBlockSpacing;
    }
    layout.attachmentFrames = attFrames;

    // Status (streaming, no text yet)
    if (m.isStreaming && m.text.length == 0) {
        NSString *status = m.statusText ?: L(@"Thinking…");
        NSAttributedString *st = [ORMarkdown plainAttributedString:status color:[theme secondaryTextColor] font:[theme messageFont]];
        CGSize sz = ORMeasure(st, contentMax - 26);
        layout.statusFrame = CGRectMake(0, y, sz.width + 26, MAX(sz.height, 20));
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
            case ORMDBlockMath: {
                CGSize s = ORMeasureMath(b.rawText);
                if (s.width <= 0) {
                    // unparsable LaTeX: fall back to the raw source in a code box
                    CGSize c = ORMeasure(ORCodeAttributed(b.rawText, textColor), contentMax - 2 * kCodePad);
                    size = CGSizeMake(contentMax, c.height + 2 * kCodePad);
                } else {
                    size = CGSizeMake(contentMax, MIN(s.height, kMathMaxHeight) + 2 * kMathPad);
                }
                break;
            }
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
    layout.blockFrames = frames;

    CGFloat contentHeight = y;
    CGFloat bubbleWidth = MIN(bubbleMax, MAX(maxBlockWidth, 24) + 2 * kBubblePadH);
    CGFloat bubbleHeight = contentHeight + 2 * kBubblePadV;
    CGFloat bubbleX = isUser ? width - kSideMargin - bubbleWidth : kSideMargin;
    layout.bubbleFrame = CGRectMake(bubbleX, cy, bubbleWidth, bubbleHeight);
    cy += bubbleHeight;

    // Meta line (assistant usage / model)
    layout.metaText = nil;
    if (isAssistant && !m.isStreaming) {
        NSMutableArray *parts = [NSMutableArray array];
        if (m.modelId) {
            ORModelInfo *info = [[ORModelCatalog shared] modelWithId:m.modelId];
            [parts addObject:info ? [info displayName] : m.modelId];
        }
        if (m.usedWebSearch) [parts addObject:L(@"web")];
        if (settings.showUsage && m.hasUsage) {
            [parts addObject:[NSString stringWithFormat:@"%@ → %@ tok", [ORUtils formatTokenCount:m.promptTokens], [ORUtils formatTokenCount:m.completionTokens]]];
            if (m.cost > 0) [parts addObject:[NSString stringWithFormat:@"$%.4f", m.cost]];
        }
        if ([m.finishReason isEqualToString:@"length"]) [parts addObject:L(@"cut off")];
        if (parts.count) {
            layout.metaText = [parts componentsJoinedByString:@" · "];
            layout.metaFrame = CGRectMake(bubbleX + 4, cy + 2, bubbleMax, kMetaHeight);
            cy += kMetaHeight + 2;
        }
    }

    // Continue button (last reply that was cut off)
    layout.continueFrame = CGRectZero;
    if (isAssistant && m.canContinue && !m.isStreaming) {
        layout.continueFrame = CGRectMake(bubbleX, cy + 4, 120, kContinueHeight);
        cy += kContinueHeight + 6;
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
        layout.noteText = att;
        CGFloat noteW = bubbleMax;
        CGFloat h = m.visionNoteExpanded ? ORMeasure(att, noteW - 16).height + 12 : kNoteCollapsedHeight;
        layout.noteFrame = CGRectMake(width - kSideMargin - noteW, cy + 3, noteW, h);
        cy += h + 3;
    }

    layout.totalHeight = cy + kCellPadV;
    g_layoutCache[key] = layout;
    (void)screenScale;
    return layout;
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

        _reasoningView = [[UIView alloc] initWithFrame:CGRectZero];
        _reasoningView.layer.cornerRadius = 6;
        _reasoningView.hidden = YES;
        _reasoningLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _reasoningLabel.numberOfLines = 0;
        _reasoningLabel.backgroundColor = [UIColor clearColor];
        [_reasoningView addSubview:_reasoningLabel];
        [self.contentView addSubview:_reasoningView];
        UITapGestureRecognizer *reasoningTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(reasoningTapped:)];
        [_reasoningView addGestureRecognizer:reasoningTap];

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

        _continueButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _continueButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
        [_continueButton addTarget:self action:@selector(continueTapped) forControlEvents:UIControlEventTouchUpInside];
        _continueButton.hidden = YES;
        [self.contentView addSubview:_continueButton];

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
    ORMessageLayout *layout = [ORMessageCell layoutForMessage:message width:width];
    self.layout = layout;
    ORTheme *theme = [ORTheme shared];
    BOOL isUser = message.role == ORMessageRoleUser;
    BOOL isError = message.role == ORMessageRoleError;
    BOOL isAssistant = message.role == ORMessageRoleAssistant;
    UIColor *textColor = isUser ? [theme userBubbleTextColor] : (isError ? [theme errorTextColor] : [theme assistantBubbleTextColor]);

    // Reasoning
    if (layout.reasoningText) {
        self.reasoningView.hidden = NO;
        self.reasoningView.frame = layout.reasoningFrame;
        self.reasoningView.backgroundColor = [theme noteBackgroundColor];
        self.reasoningLabel.frame = CGRectInset(self.reasoningView.bounds, 8, 6);
        self.reasoningLabel.attributedText = layout.reasoningText;
        self.reasoningLabel.lineBreakMode = message.reasoningExpanded ? NSLineBreakByWordWrapping : NSLineBreakByTruncatingTail;
        self.reasoningLabel.numberOfLines = message.reasoningExpanded ? 0 : 1;
    } else {
        self.reasoningView.hidden = YES;
    }

    self.bubbleView.image = isUser ? [theme userBubbleImage] : (isError ? [theme errorBubbleImage] : [theme assistantBubbleImage]);
    self.bubbleView.frame = layout.bubbleFrame;

    // Attachments
    for (UIView *v in self.attachmentViews) [v removeFromSuperview];
    [self.attachmentViews removeAllObjects];
    NSUInteger ai = 0;
    for (ORAttachment *a in message.attachments) {
        if (ai >= layout.attachmentFrames.count) break;
        CGRect f = [layout.attachmentFrames[ai] CGRectValue];
        f.origin.x += kBubblePadH;
        f.origin.y += kBubblePadV;
        UIView *v;
        if ([a isImage]) {
            UIImageView *iv = [[UIImageView alloc] initWithFrame:f];
            iv.contentMode = isAssistant ? UIViewContentModeScaleAspectFit : UIViewContentModeScaleAspectFill;
            iv.clipsToBounds = YES;
            iv.layer.cornerRadius = 6;
            iv.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.3];
            CGFloat px = MAX(f.size.width, f.size.height) * [UIScreen mainScreen].scale;
            iv.image = [a thumbnailWithMaxPixels:isAssistant ? px : kThumbSize * 2];
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
        CGRect sf = layout.statusFrame;
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
    for (ORBlockFrame *bf in layout.blockFrames) {
        CGRect f = bf.frame;
        f.origin.x += kBubblePadH;
        f.origin.y += kBubblePadV;
        UIView *v = nil;
        switch (bf.block.type) {
            case ORMDBlockMath: {
                CGSize natural = ORMeasureMath(bf.block.rawText);
                if (natural.width <= 0) {
                    ORCodeBlockView *cv = [[ORCodeBlockView alloc] initWithFrame:f];
                    cv.backgroundColor = [theme codeBackgroundColorInUserBubble:isUser];
                    cv.label.attributedText = ORCodeAttributed(bf.block.rawText, textColor);
                    v = cv;
                    break;
                }
                MTMathUILabel *math = [[MTMathUILabel alloc] initWithFrame:CGRectMake(0, 0, natural.width, natural.height)];
                math.fontSize = ORMathFontSize();
                math.labelMode = kMTMathUILabelModeDisplay;
                math.textColor = textColor;
                math.backgroundColor = [UIColor clearColor];
                math.latex = bf.block.rawText;
                UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:f];
                scroll.backgroundColor = [UIColor clearColor];
                scroll.showsVerticalScrollIndicator = NO;
                scroll.scrollsToTop = NO;
                CGFloat x = natural.width < f.size.width ? floor((f.size.width - natural.width) / 2) : 0;
                math.frame = CGRectMake(x, kMathPad, natural.width, natural.height);
                scroll.contentSize = CGSizeMake(MAX(natural.width, f.size.width), natural.height + 2 * kMathPad);
                [scroll addSubview:math];
                v = scroll;
                break;
            }
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
    if (layout.metaText) {
        self.metaLabel.hidden = NO;
        self.metaLabel.frame = layout.metaFrame;
        self.metaLabel.text = layout.metaText;
        self.metaLabel.textColor = [theme secondaryTextColor];
        self.metaLabel.font = [theme smallFont];
    } else {
        self.metaLabel.hidden = YES;
    }

    // Continue
    if (!CGRectIsEmpty(layout.continueFrame)) {
        self.continueButton.hidden = NO;
        self.continueButton.frame = layout.continueFrame;
        [self.continueButton setTitle:L(@"Continue") forState:UIControlStateNormal];
        [self.continueButton setTitleColor:[theme primaryTextColor] forState:UIControlStateNormal];
        [self.continueButton setBackgroundImage:[theme smallButtonImageHighlighted:NO] forState:UIControlStateNormal];
        [self.continueButton setBackgroundImage:[theme smallButtonImageHighlighted:YES] forState:UIControlStateHighlighted];
    } else {
        self.continueButton.hidden = YES;
    }

    // Vision note
    if (layout.noteText) {
        self.noteView.hidden = NO;
        self.noteView.frame = layout.noteFrame;
        self.noteView.backgroundColor = [theme noteBackgroundColor];
        self.noteLabel.frame = CGRectInset(self.noteView.bounds, 8, 6);
        self.noteLabel.attributedText = layout.noteText;
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

- (void)reasoningTapped:(UITapGestureRecognizer *)g
{
    [self.delegate messageCell:self didToggleReasoningForMessage:self.message];
}

- (void)continueTapped
{
    [self.delegate messageCell:self continueMessage:self.message];
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

- (BOOL)hasImageAttachments
{
    for (ORAttachment *a in self.message.attachments) if ([a isImage]) return YES;
    return NO;
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender
{
    if (action == @selector(copy:)) return self.message.text.length > 0;
    if (action == @selector(regenerateMessage:)) return [self.delegate messageCell:self canRegenerateMessage:self.message];
    if (action == @selector(editMessageAction:)) return [self.delegate messageCell:self canEditMessage:self.message];
    if (action == @selector(continueMessageAction:)) return self.message.canContinue && !self.message.isStreaming;
    if (action == @selector(saveImagesAction:)) return [self hasImageAttachments] && !self.message.isStreaming;
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

- (void)editMessageAction:(id)sender
{
    [self.delegate messageCell:self editMessage:self.message];
}

- (void)continueMessageAction:(id)sender
{
    [self.delegate messageCell:self continueMessage:self.message];
}

- (void)saveImagesAction:(id)sender
{
    [self.delegate messageCell:self saveImagesOfMessage:self.message];
}

- (void)deleteMessageAction:(id)sender
{
    [self.delegate messageCell:self deleteMessage:self.message];
}

- (void)showMenu
{
    [self becomeFirstResponder];
    UIMenuController *menu = [UIMenuController sharedMenuController];
    menu.menuItems = @[
        [[UIMenuItem alloc] initWithTitle:L(@"Edit") action:@selector(editMessageAction:)],
        [[UIMenuItem alloc] initWithTitle:L(@"Regenerate") action:@selector(regenerateMessage:)],
        [[UIMenuItem alloc] initWithTitle:L(@"Continue") action:@selector(continueMessageAction:)],
        [[UIMenuItem alloc] initWithTitle:L(@"Save Image") action:@selector(saveImagesAction:)],
        [[UIMenuItem alloc] initWithTitle:L(@"Delete") action:@selector(deleteMessageAction:)],
    ];
    [menu setTargetRect:self.bubbleView.frame inView:self.contentView];
    [menu setMenuVisible:YES animated:YES];
}

@end
