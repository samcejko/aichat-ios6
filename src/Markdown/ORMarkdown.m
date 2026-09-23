#import "ORMarkdown.h"
#import "ORMathText.h"
#import "ORTheme.h"

@implementation ORMDBlock
@end

@interface ORInlineParser : NSObject
@property (nonatomic, strong) UIColor *textColor;
@property (nonatomic) BOOL inUser;
@property (nonatomic, strong) NSMutableParagraphStyle *paragraphStyle;
- (NSMutableAttributedString *)parse:(NSString *)s;
@end

@implementation ORInlineParser

- (UIFont *)fontBold:(BOOL)bold italic:(BOOL)italic
{
    ORTheme *t = [ORTheme shared];
    if (bold && italic) return [t boldItalicMessageFont];
    if (bold) return [t boldMessageFont];
    if (italic) return [t italicMessageFont];
    return [t messageFont];
}

- (UIColor *)safeColor
{
    return self.textColor ?: [[ORTheme shared] primaryTextColor];
}

- (NSDictionary *)attributesBold:(BOOL)bold italic:(BOOL)italic strike:(BOOL)strike
{
    NSMutableDictionary *a = [NSMutableDictionary dictionary];
    a[NSFontAttributeName] = [self fontBold:bold italic:italic];
    a[NSForegroundColorAttributeName] = [self safeColor];
    if (self.paragraphStyle) a[NSParagraphStyleAttributeName] = self.paragraphStyle;
    if (strike) a[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
    return a;
}

- (NSDictionary *)codeAttributes
{
    NSMutableDictionary *a = [NSMutableDictionary dictionary];
    a[NSFontAttributeName] = [[ORTheme shared] codeFont];
    a[NSForegroundColorAttributeName] = [self safeColor];
    a[NSBackgroundColorAttributeName] = [[ORTheme shared] codeBackgroundColorInUserBubble:self.inUser];
    if (self.paragraphStyle) a[NSParagraphStyleAttributeName] = self.paragraphStyle;
    return a;
}

- (NSDictionary *)linkAttributesBold:(BOOL)bold italic:(BOOL)italic
{
    NSMutableDictionary *a = [[self attributesBold:bold italic:italic strike:NO] mutableCopy];
    a[NSForegroundColorAttributeName] = self.inUser ? [self safeColor] : [[ORTheme shared] linkColor];
    a[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
    return a;
}

static BOOL ORIsSpace(unichar c)
{
    return c == ' ' || c == '\n' || c == '\t' || c == '\r';
}

static BOOL ORIsWordChar(unichar c)
{
    return [[NSCharacterSet alphanumericCharacterSet] characterIsMember:c];
}

// Does a closing delimiter `delim` exist after position `from` (with a non-space before it)?
static BOOL ORHasCloser(NSString *s, NSString *delim, NSUInteger from)
{
    NSUInteger len = s.length;
    if (from >= len) return NO;
    NSRange r = NSMakeRange(from, len - from);
    while (r.length > 0) {
        NSRange f = [s rangeOfString:delim options:NSLiteralSearch range:r];
        if (f.location == NSNotFound) return NO;
        if (f.location > 0 && !ORIsSpace([s characterAtIndex:f.location - 1])) return YES;
        NSUInteger next = f.location + f.length;
        if (next >= len) return NO;
        r = NSMakeRange(next, len - next);
    }
    return NO;
}

- (NSMutableAttributedString *)parse:(NSString *)s
{
    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];
    NSUInteger len = s.length;
    NSUInteger i = 0;
    __block BOOL bold = NO, italic = NO, strike = NO;
    unichar boldOpen = 0, italicOpen = 0;
    NSMutableString *run = [NSMutableString string];

    void (^flush)(void) = ^{
        if (run.length) {
            [out appendAttributedString:[[NSAttributedString alloc] initWithString:run attributes:[self attributesBold:bold italic:italic strike:strike]]];
            [run setString:@""];
        }
    };

    while (i < len) {
        unichar c = [s characterAtIndex:i];

        // Escapes
        if (c == '\\' && i + 1 < len) {
            unichar n = [s characterAtIndex:i + 1];
            if ([@"\\`*_{}[]()#+-.!~|>" rangeOfString:[NSString stringWithFormat:@"%C", n]].location != NSNotFound) {
                [run appendFormat:@"%C", n];
                i += 2;
                continue;
            }
        }

        // Code spans
        if (c == '`') {
            NSUInteger ticks = 0;
            while (i + ticks < len && [s characterAtIndex:i + ticks] == '`') ticks++;
            NSString *fence = [@"" stringByPaddingToLength:ticks withString:@"`" startingAtIndex:0];
            NSRange close = [s rangeOfString:fence options:0 range:NSMakeRange(i + ticks, len - i - ticks)];
            if (close.location != NSNotFound) {
                NSString *code = [s substringWithRange:NSMakeRange(i + ticks, close.location - i - ticks)];
                if ([code hasPrefix:@" "] && [code hasSuffix:@" "] && code.length > 2) code = [code substringWithRange:NSMakeRange(1, code.length - 2)];
                flush();
                [out appendAttributedString:[[NSAttributedString alloc] initWithString:code attributes:[self codeAttributes]]];
                i = close.location + ticks;
                continue;
            }
            [run appendString:fence];
            i += ticks;
            continue;
        }

        // Strong emphasis
        if ((c == '*' || c == '_') && i + 1 < len && [s characterAtIndex:i + 1] == c) {
            NSString *delim = [NSString stringWithFormat:@"%C%C", c, c];
            if (bold) {
                BOOL prevOk = i > 0 && !ORIsSpace([s characterAtIndex:i - 1]);
                if (prevOk && c == boldOpen) { flush(); bold = NO; i += 2; continue; }
            } else {
                BOOL nextOk = i + 2 < len && !ORIsSpace([s characterAtIndex:i + 2]);
                if (nextOk && ORHasCloser(s, delim, i + 2)) { flush(); bold = YES; boldOpen = c; i += 2; continue; }
            }
            [run appendString:delim];
            i += 2;
            continue;
        }

        // Emphasis
        if (c == '*' || c == '_') {
            BOOL intraword = (c == '_') && i > 0 && i + 1 < len && ORIsWordChar([s characterAtIndex:i - 1]) && ORIsWordChar([s characterAtIndex:i + 1]);
            if (!intraword) {
                NSString *delim = [NSString stringWithFormat:@"%C", c];
                if (italic) {
                    BOOL prevOk = i > 0 && !ORIsSpace([s characterAtIndex:i - 1]);
                    if (prevOk && c == italicOpen) { flush(); italic = NO; i += 1; continue; }
                } else {
                    BOOL nextOk = i + 1 < len && !ORIsSpace([s characterAtIndex:i + 1]);
                    if (nextOk && ORHasCloser(s, delim, i + 1)) { flush(); italic = YES; italicOpen = c; i += 1; continue; }
                }
            }
            [run appendFormat:@"%C", c];
            i += 1;
            continue;
        }

        // Strikethrough
        if (c == '~' && i + 1 < len && [s characterAtIndex:i + 1] == '~') {
            if (strike) { flush(); strike = NO; i += 2; continue; }
            if (i + 2 < len && !ORIsSpace([s characterAtIndex:i + 2]) && ORHasCloser(s, @"~~", i + 2)) { flush(); strike = YES; i += 2; continue; }
            [run appendString:@"~~"];
            i += 2;
            continue;
        }

        // Images ![alt](url) and links [text](url)
        if ((c == '[' || (c == '!' && i + 1 < len && [s characterAtIndex:i + 1] == '[')) ) {
            BOOL isImage = (c == '!');
            NSUInteger open = isImage ? i + 1 : i;
            NSRange rb = (open + 1 < len) ? [s rangeOfString:@"]" options:NSLiteralSearch range:NSMakeRange(open + 1, len - open - 1)] : NSMakeRange(NSNotFound, 0);
            if (rb.location != NSNotFound && rb.location + 1 < len && [s characterAtIndex:rb.location + 1] == '(') {
                NSRange closeParen = [s rangeOfString:@")" options:NSLiteralSearch range:NSMakeRange(rb.location + 2, len - rb.location - 2)];
                if (closeParen.location != NSNotFound) {
                    NSString *label = [s substringWithRange:NSMakeRange(open + 1, rb.location - open - 1)];
                    NSString *url = [s substringWithRange:NSMakeRange(rb.location + 2, closeParen.location - rb.location - 2)];
                    if ([label rangeOfString:@"\n"].location == NSNotFound && label.length < 400) {
                        flush();
                        if (isImage) {
                            NSString *t = [NSString stringWithFormat:@"[image: %@]", label.length ? label : url];
                            [out appendAttributedString:[[NSAttributedString alloc] initWithString:t attributes:[self attributesBold:NO italic:YES strike:NO]]];
                        } else {
                            ORInlineParser *sub = [[ORInlineParser alloc] init];
                            sub.textColor = self.textColor;
                            sub.inUser = self.inUser;
                            sub.paragraphStyle = self.paragraphStyle;
                            NSMutableAttributedString *inner = [sub parse:label];
                            [inner setAttributes:[self linkAttributesBold:bold italic:italic] range:NSMakeRange(0, inner.length)];
                            [out appendAttributedString:inner];
                            if (![label isEqualToString:url] && ![url hasPrefix:@"#"]) {
                                NSString *shown = url.length > 60 ? [[url substringToIndex:60] stringByAppendingString:@"…"] : url;
                                [out appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@" (%@)", shown]
                                                                                            attributes:[self attributesBold:NO italic:NO strike:NO]]];
                            }
                        }
                        i = closeParen.location + 1;
                        continue;
                    }
                }
            }
        }

        [run appendFormat:@"%C", c];
        i++;
    }
    flush();
    return out;
}

@end

@implementation ORMarkdown

+ (NSAttributedString *)plainAttributedString:(NSString *)text color:(UIColor *)color font:(UIFont *)font
{
    ORTheme *theme = [ORTheme shared];
    return [[NSAttributedString alloc] initWithString:text ?: @"" attributes:@{
        NSFontAttributeName: font ?: [theme messageFont],
        NSForegroundColorAttributeName: color ?: [theme primaryTextColor] }];
}

static NSString *ORTrimRight(NSString *s)
{
    NSUInteger end = s.length;
    while (end > 0 && ORIsSpace([s characterAtIndex:end - 1])) end--;
    return [s substringToIndex:end];
}

static NSUInteger ORLeadingSpaces(NSString *line)
{
    NSUInteger n = 0;
    while (n < line.length) {
        unichar c = [line characterAtIndex:n];
        if (c == ' ') n++;
        else if (c == '\t') n += 4;
        else break;
    }
    return n;
}

static BOOL ORIsFence(NSString *line, NSString **lang)
{
    NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (t.length < 3) return NO;
    unichar f = [t characterAtIndex:0];
    if (f != '`' && f != '~') return NO;
    NSUInteger n = 0;
    while (n < t.length && [t characterAtIndex:n] == f) n++;
    if (n < 3) return NO;
    NSString *info = [[t substringFromIndex:n] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    // ```inline code``` on one line is a code span, not a fence
    if (f == '`' && [info rangeOfString:@"`"].location != NSNotFound) return NO;
    if (lang) *lang = info;
    return YES;
}

static BOOL ORIsRule(NSString *line)
{
    NSString *t = [line stringByReplacingOccurrencesOfString:@" " withString:@""];
    if (t.length < 3) return NO;
    unichar c = [t characterAtIndex:0];
    if (c != '-' && c != '*' && c != '_') return NO;
    for (NSUInteger i = 0; i < t.length; i++) if ([t characterAtIndex:i] != c) return NO;
    return YES;
}

static BOOL ORIsTableRow(NSString *line)
{
    NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    return [t hasPrefix:@"|"] && t.length > 1;
}

static BOOL ORIsTableSeparator(NSString *line)
{
    NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (![t hasPrefix:@"|"]) return NO;
    NSString *stripped = [[[t stringByReplacingOccurrencesOfString:@"|" withString:@""] stringByReplacingOccurrencesOfString:@":" withString:@""] stringByReplacingOccurrencesOfString:@" " withString:@""];
    if (stripped.length == 0) return NO;
    for (NSUInteger i = 0; i < stripped.length; i++) if ([stripped characterAtIndex:i] != '-') return NO;
    return YES;
}

// Returns marker text and content when the line is a list item.
static BOOL ORParseListItem(NSString *line, NSString **marker, NSString **content, NSInteger *indent)
{
    NSUInteger lead = ORLeadingSpaces(line);
    NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (t.length < 2) return NO;
    unichar c = [t characterAtIndex:0];
    if ((c == '-' || c == '*' || c == '+') && [t characterAtIndex:1] == ' ') {
        NSString *body = [t substringFromIndex:2];
        NSString *mark = @"•";
        // task list items: "- [ ] todo" / "- [x] done"
        if ([body hasPrefix:@"[ ] "]) { mark = @"☐"; body = [body substringFromIndex:4]; }
        else if ([body hasPrefix:@"[x] "] || [body hasPrefix:@"[X] "]) { mark = @"☑"; body = [body substringFromIndex:4]; }
        if (marker) *marker = mark;
        if (content) *content = body;
        if (indent) *indent = (NSInteger)(lead / 2);
        return YES;
    }
    NSUInteger j = 0;
    while (j < t.length && j < 4 && [t characterAtIndex:j] >= '0' && [t characterAtIndex:j] <= '9') j++;
    if (j > 0 && j + 1 < t.length && ([t characterAtIndex:j] == '.' || [t characterAtIndex:j] == ')') && [t characterAtIndex:j + 1] == ' ') {
        if (marker) *marker = [NSString stringWithFormat:@"%@.", [t substringToIndex:j]];
        if (content) *content = [t substringFromIndex:j + 2];
        if (indent) *indent = (NSInteger)(lead / 2);
        return YES;
    }
    return NO;
}

// Moves single-line "$$...$$" / "\[...\]" spans onto their own lines so the block parser sees them,
// but leaves fenced code untouched.
static NSString *ORNormalizeDisplayMath(NSString *markdown)
{
    if ([markdown rangeOfString:@"$$"].location == NSNotFound && [markdown rangeOfString:@"\\["].location == NSNotFound) return markdown;
    NSMutableString *out = [NSMutableString string];
    NSArray *lines = [markdown componentsSeparatedByString:@"\n"];
    BOOL inFence = NO;
    NSRegularExpression *dollar = [NSRegularExpression regularExpressionWithPattern:@"\\$\\$(.+?)\\$\\$" options:0 error:NULL];
    NSRegularExpression *bracket = [NSRegularExpression regularExpressionWithPattern:@"\\\\\\[(.+?)\\\\\\]" options:0 error:NULL];
    NSUInteger idx = 0;
    for (NSString *line in lines) {
        NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([t hasPrefix:@"```"] || [t hasPrefix:@"~~~"]) inFence = !inFence;
        NSString *l = line;
        if (!inFence && !([t hasPrefix:@"$$"] && [t hasSuffix:@"$$"] && t.length >= 4)) {
            // template: literal $$ must be escaped as \$ in NSRegularExpression templates
            l = [dollar stringByReplacingMatchesInString:l options:0 range:NSMakeRange(0, l.length) withTemplate:@"\n\\$\\$$1\\$\\$\n"];
            l = [bracket stringByReplacingMatchesInString:l options:0 range:NSMakeRange(0, l.length) withTemplate:@"\n\\$\\$$1\\$\\$\n"];
        }
        [out appendString:l];
        if (++idx < lines.count) [out appendString:@"\n"];
    }
    return out;
}

// A line that opens or closes a display-math block.
static BOOL ORIsMathDelimiter(NSString *trimmed, BOOL *isBracket)
{
    if ([trimmed hasPrefix:@"$$"]) { if (isBracket) *isBracket = NO; return YES; }
    if ([trimmed isEqualToString:@"\\["]) { if (isBracket) *isBracket = YES; return YES; }
    return NO;
}

// Fenced code labelled as LaTeX is almost always a formula the model wants shown, not source code.
static BOOL ORIsMathLanguage(NSString *lang)
{
    NSString *l = [[lang lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    return [l isEqualToString:@"latex"] || [l isEqualToString:@"tex"] || [l isEqualToString:@"math"] ||
           [l isEqualToString:@"katex"] || [l isEqualToString:@"mathjax"];
}

// \begin{equation} ... \end{equation} and friends written without $$ delimiters.
static NSString *ORMathEnvironmentName(NSString *trimmed)
{
    for (NSString *env in @[ @"equation*", @"equation", @"align*", @"align", @"gather*", @"gather", @"displaymath", @"math" ]) {
        if ([trimmed hasPrefix:[NSString stringWithFormat:@"\\begin{%@}", env]]) return env;
    }
    return nil;
}

// Strips alignment markers so that iosMath can render multi-line environments as one display block.
static NSString *ORStripAlignment(NSString *latex)
{
    NSString *s = [latex stringByReplacingOccurrencesOfString:@"&" withString:@" "];
    s = [s stringByReplacingOccurrencesOfString:@"\\\\" withString:@" \\quad "];
    s = [s stringByReplacingOccurrencesOfString:@"\\nonumber" withString:@""];
    return s;
}

+ (NSArray *)blocksFromMarkdown:(NSString *)markdown textColor:(UIColor *)textColor inUserBubble:(BOOL)inUser
{
    NSMutableArray *blocks = [NSMutableArray array];
    if (!markdown) return blocks;
    NSString *normalized = [markdown stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    normalized = [ORMathText cleanupHTMLIn:normalized];
    normalized = ORNormalizeDisplayMath(normalized);
    NSArray *lines = [normalized componentsSeparatedByString:@"\n"];
    NSMutableArray *para = [NSMutableArray array];
    ORTheme *theme = [ORTheme shared];

    ORInlineParser *inlineParser = [[ORInlineParser alloc] init];
    if (!textColor) textColor = [theme primaryTextColor];
    inlineParser.textColor = textColor;
    inlineParser.inUser = inUser;

    void (^flushPara)(void) = ^{
        if (!para.count) return;
        NSString *joined = [ORMathText cleanupTextLatexIn:[ORMathText convertInlineMathIn:[para componentsJoinedByString:@"\n"]]];
        [para removeAllObjects];
        ORMDBlock *b = [[ORMDBlock alloc] init];
        b.type = ORMDBlockParagraph;
        inlineParser.paragraphStyle = nil;
        b.text = [inlineParser parse:joined];
        [blocks addObject:b];
    };

    NSUInteger i = 0;
    NSUInteger n = lines.count;
    while (i < n) {
        NSString *line = lines[i];
        NSString *lang = nil;

        // Standalone remote image: ![alt](url)
        {
            NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if ([t hasPrefix:@"!["] && [t hasSuffix:@")"]) {
                NSRange mid = [t rangeOfString:@"]("];
                if (mid.location != NSNotFound) {
                    NSString *alt = [t substringWithRange:NSMakeRange(2, mid.location - 2)];
                    NSString *url = [t substringWithRange:NSMakeRange(mid.location + 2, t.length - mid.location - 3)];
                    NSRange sp = [url rangeOfString:@" "];
                    if (sp.location != NSNotFound) url = [url substringToIndex:sp.location];   // drop "title"
                    if ([url hasPrefix:@"http://"] || [url hasPrefix:@"https://"]) {
                        flushPara();
                        ORMDBlock *b = [[ORMDBlock alloc] init];
                        b.type = ORMDBlockImage;
                        b.rawText = url;
                        b.language = alt;
                        [blocks addObject:b];
                        i++;
                        continue;
                    }
                }
            }
            // Text-mode LaTeX structure: \section{..}, \item, environments
            if ([t hasPrefix:@"\\section{"] || [t hasPrefix:@"\\subsection{"] || [t hasPrefix:@"\\subsubsection{"] || [t hasPrefix:@"\\chapter{"] || [t hasPrefix:@"\\section*{"] || [t hasPrefix:@"\\subsection*{"]) {
                flushPara();
                NSInteger level = [t hasPrefix:@"\\chapter"] ? 1 : [t hasPrefix:@"\\subsubsection"] ? 4 : [t hasPrefix:@"\\subsection"] ? 3 : 2;
                NSRange open = [t rangeOfString:@"{"];
                NSString *content = [t substringFromIndex:open.location + 1];
                if ([content hasSuffix:@"}"]) content = [content substringToIndex:content.length - 1];
                ORMDBlock *b = [[ORMDBlock alloc] init];
                b.type = ORMDBlockHeading;
                b.level = level;
                inlineParser.paragraphStyle = nil;
                NSMutableAttributedString *h = [inlineParser parse:[ORMathText cleanupTextLatexIn:[ORMathText convertInlineMathIn:content]]];
                [h addAttribute:NSFontAttributeName value:[theme headingFontForLevel:level] range:NSMakeRange(0, h.length)];
                b.text = h;
                [blocks addObject:b];
                i++;
                continue;
            }
            if ([t hasPrefix:@"\\item"]) {
                flushPara();
                NSString *content = [[t substringFromIndex:5] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if ([content hasPrefix:@"["]) {
                    NSRange rb = [content rangeOfString:@"]"];
                    if (rb.location != NSNotFound) content = [[content substringFromIndex:rb.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                }
                NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
                CGFloat markerWidth = ceil([@"•  " sizeWithFont:[theme messageFont]].width);
                ps.headIndent = markerWidth;
                ps.lineBreakMode = NSLineBreakByWordWrapping;
                inlineParser.paragraphStyle = ps;
                NSMutableAttributedString *m = [[NSMutableAttributedString alloc] initWithString:@"•  " attributes:@{ NSFontAttributeName: [theme messageFont], NSForegroundColorAttributeName: textColor, NSParagraphStyleAttributeName: ps }];
                [m appendAttributedString:[inlineParser parse:[ORMathText cleanupTextLatexIn:[ORMathText convertInlineMathIn:content]]]];
                ORMDBlock *b = [[ORMDBlock alloc] init];
                b.type = ORMDBlockListItem;
                b.text = m;
                [blocks addObject:b];
                i++;
                continue;
            }
            if ([t hasPrefix:@"\\begin{itemize"] || [t hasPrefix:@"\\begin{enumerate"] || [t hasPrefix:@"\\end{itemize"] || [t hasPrefix:@"\\end{enumerate"] ||
                [t hasPrefix:@"\\begin{document"] || [t hasPrefix:@"\\end{document"] || [t hasPrefix:@"\\documentclass"] || [t hasPrefix:@"\\usepackage"] ||
                [t isEqualToString:@"\\maketitle"] || [t isEqualToString:@"\\tableofcontents"] || [t hasPrefix:@"\\pagestyle{"] || [t isEqualToString:@"\\newpage"] ||
                [t hasPrefix:@"\\begin{center"] || [t hasPrefix:@"\\end{center"]) {
                flushPara();
                i++;
                continue;
            }
        }

        // Display math: $$ ... $$ or \[ ... \]
        {
            NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            BOOL bracket = NO;
            if (ORIsMathDelimiter(t, &bracket)) {
                flushPara();
                NSMutableArray *math = [NSMutableArray array];
                NSString *closer = bracket ? @"\\]" : @"$$";
                if (!bracket && t.length >= 4 && [t hasSuffix:@"$$"]) {
                    [math addObject:[t substringWithRange:NSMakeRange(2, t.length - 4)]];
                    i++;
                } else {
                    NSString *rest = bracket ? @"" : [t substringFromIndex:2];
                    if (rest.length) [math addObject:rest];
                    i++;
                    while (i < n) {
                        NSString *ml = lines[i];
                        NSString *mt = [ml stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                        i++;
                        if ([mt hasSuffix:closer]) {
                            NSString *head = [mt substringToIndex:mt.length - closer.length];
                            if (head.length) [math addObject:head];
                            break;
                        }
                        [math addObject:ml];
                    }
                }
                ORMDBlock *b = [[ORMDBlock alloc] init];
                b.type = ORMDBlockMath;
                b.rawText = [[math componentsJoinedByString:@"\n"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (b.rawText.length) [blocks addObject:b];
                continue;
            }

            // \begin{equation} ... \end{equation}
            NSString *env = ORMathEnvironmentName(t);
            if (env) {
                flushPara();
                NSString *endTag = [NSString stringWithFormat:@"\\end{%@}", env];
                NSMutableArray *math = [NSMutableArray array];
                NSString *first = [t substringFromIndex:[NSString stringWithFormat:@"\\begin{%@}", env].length];
                i++;
                BOOL closed = NO;
                NSRange endInFirst = [first rangeOfString:endTag];
                if (endInFirst.location != NSNotFound) {
                    first = [first substringToIndex:endInFirst.location];
                    closed = YES;
                }
                if (first.length) [math addObject:first];
                while (!closed && i < n) {
                    NSString *ml = lines[i];
                    i++;
                    NSRange r = [ml rangeOfString:endTag];
                    if (r.location != NSNotFound) {
                        NSString *head = [ml substringToIndex:r.location];
                        if ([head stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].length) [math addObject:head];
                        closed = YES;
                        break;
                    }
                    [math addObject:ml];
                }
                ORMDBlock *b = [[ORMDBlock alloc] init];
                b.type = ORMDBlockMath;
                b.rawText = ORStripAlignment([[math componentsJoinedByString:@" "] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]);
                if (b.rawText.length) [blocks addObject:b];
                continue;
            }
        }

        if (ORIsFence(line, &lang)) {
            flushPara();
            NSMutableArray *code = [NSMutableArray array];
            i++;
            while (i < n && !ORIsFence(lines[i], NULL)) {
                [code addObject:lines[i]];
                i++;
            }
            if (i < n) i++;   // closing fence
            ORMDBlock *b = [[ORMDBlock alloc] init];
            NSString *joined = [code componentsJoinedByString:@"\n"];
            if (ORIsMathLanguage(lang) && [joined rangeOfString:@"\\documentclass"].location == NSNotFound) {
                // A LaTeX snippet: render it as a formula (the cell falls back to source if it does not parse).
                b.type = ORMDBlockMath;
                NSString *body = [joined stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if ([body hasPrefix:@"$$"] && [body hasSuffix:@"$$"] && body.length >= 4) body = [body substringWithRange:NSMakeRange(2, body.length - 4)];
                else if ([body hasPrefix:@"\\["] && [body hasSuffix:@"\\]"] && body.length >= 4) body = [body substringWithRange:NSMakeRange(2, body.length - 4)];
                else if ([body hasPrefix:@"$"] && [body hasSuffix:@"$"] && body.length >= 2) body = [body substringWithRange:NSMakeRange(1, body.length - 2)];
                NSString *env = ORMathEnvironmentName(body);
                if (env) {
                    NSString *beginTag = [NSString stringWithFormat:@"\\begin{%@}", env];
                    NSString *endTag = [NSString stringWithFormat:@"\\end{%@}", env];
                    body = [body stringByReplacingOccurrencesOfString:beginTag withString:@""];
                    body = [body stringByReplacingOccurrencesOfString:endTag withString:@""];
                    body = ORStripAlignment(body);
                }
                b.rawText = [[body stringByReplacingOccurrencesOfString:@"\n" withString:@" "] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            } else {
                b.type = ORMDBlockCode;
                b.language = lang;
                b.rawText = joined;
            }
            [blocks addObject:b];
            continue;
        }

        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length == 0) {
            flushPara();
            i++;
            continue;
        }

        // Heading
        if ([trimmed hasPrefix:@"#"]) {
            NSUInteger level = 0;
            while (level < trimmed.length && level < 6 && [trimmed characterAtIndex:level] == '#') level++;
            if (level < trimmed.length && [trimmed characterAtIndex:level] == ' ') {
                flushPara();
                NSString *content = [[trimmed substringFromIndex:level + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                while ([content hasSuffix:@"#"]) content = ORTrimRight([content substringToIndex:content.length - 1]);
                ORMDBlock *b = [[ORMDBlock alloc] init];
                b.type = ORMDBlockHeading;
                b.level = (NSInteger)level;
                inlineParser.paragraphStyle = nil;
                NSMutableAttributedString *t = [inlineParser parse:[ORMathText convertInlineMathIn:content]];
                [t addAttribute:NSFontAttributeName value:[theme headingFontForLevel:(NSInteger)level] range:NSMakeRange(0, t.length)];
                b.text = t;
                [blocks addObject:b];
                i++;
                continue;
            }
        }

        // Horizontal rule
        if (ORIsRule(trimmed) && !para.count) {
            ORMDBlock *b = [[ORMDBlock alloc] init];
            b.type = ORMDBlockRule;
            [blocks addObject:b];
            i++;
            continue;
        }

        // Table
        if (ORIsTableRow(line) && (i + 1 < n && ORIsTableSeparator(lines[i + 1])) ) {
            flushPara();
            NSMutableArray *rows = [NSMutableArray array];
            while (i < n && ORIsTableRow(lines[i])) {
                if (!ORIsTableSeparator(lines[i])) {
                    NSString *t = [lines[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    if ([t hasPrefix:@"|"]) t = [t substringFromIndex:1];
                    if ([t hasSuffix:@"|"]) t = [t substringToIndex:t.length - 1];
                    NSMutableArray *cells = [NSMutableArray array];
                    for (NSString *c in [t componentsSeparatedByString:@"|"]) {
                        [cells addObject:[[c stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] stringByReplacingOccurrencesOfString:@"\\|" withString:@"|"]];
                    }
                    [rows addObject:cells];
                }
                i++;
            }
            // Column widths for a monospace layout.
            NSUInteger cols = 0;
            for (NSArray *r in rows) cols = MAX(cols, r.count);
            NSMutableArray *widths = [NSMutableArray array];
            for (NSUInteger c = 0; c < cols; c++) {
                NSUInteger w = 1;
                for (NSArray *r in rows) if (c < r.count) w = MAX(w, [r[c] length]);
                [widths addObject:@(MIN(w, (NSUInteger)28))];
            }
            NSMutableString *table = [NSMutableString string];
            NSUInteger rowIndex = 0;
            for (NSArray *r in rows) {
                NSMutableArray *padded = [NSMutableArray array];
                for (NSUInteger c = 0; c < cols; c++) {
                    NSString *cell = c < r.count ? r[c] : @"";
                    NSUInteger w = [widths[c] unsignedIntegerValue];
                    if (cell.length > w) cell = [[cell substringToIndex:w - 1] stringByAppendingString:@"…"];
                    [padded addObject:[cell stringByPaddingToLength:w withString:@" " startingAtIndex:0]];
                }
                [table appendString:[padded componentsJoinedByString:@"  "]];
                if (rowIndex == 0 && rows.count > 1) {
                    [table appendString:@"\n"];
                    NSMutableArray *seps = [NSMutableArray array];
                    for (NSUInteger c = 0; c < cols; c++) [seps addObject:[@"" stringByPaddingToLength:[widths[c] unsignedIntegerValue] withString:@"-" startingAtIndex:0]];
                    [table appendString:[seps componentsJoinedByString:@"  "]];
                }
                rowIndex++;
                if (rowIndex < rows.count) [table appendString:@"\n"];
            }
            ORMDBlock *b = [[ORMDBlock alloc] init];
            b.type = ORMDBlockTable;
            b.rawText = table;
            [blocks addObject:b];
            continue;
        }

        // List item
        NSString *marker = nil, *content = nil;
        NSInteger indent = 0;
        if (ORParseListItem(line, &marker, &content, &indent)) {
            flushPara();
            // Continuation lines: indented non-empty lines that are not new items.
            NSMutableArray *cont = [NSMutableArray arrayWithObject:content];
            i++;
            while (i < n) {
                NSString *next = lines[i];
                NSString *nt = [next stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if (nt.length == 0 || ORParseListItem(next, NULL, NULL, NULL) || ORLeadingSpaces(next) < 2 || ORIsFence(next, NULL)) break;
                [cont addObject:nt];
                i++;
            }
            ORMDBlock *b = [[ORMDBlock alloc] init];
            b.type = ORMDBlockListItem;
            b.level = indent;
            CGFloat base = 14.0 * MIN(indent, 4);
            NSString *prefix = [marker stringByAppendingString:@"  "];
            // sizeWithFont: is deprecated after iOS 6 but it is the only measuring API available there.
            CGFloat markerWidth = ceil([prefix sizeWithFont:[theme messageFont]].width);
            NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
            ps.firstLineHeadIndent = base;
            ps.headIndent = base + markerWidth;
            ps.lineBreakMode = NSLineBreakByWordWrapping;
            inlineParser.paragraphStyle = ps;
            NSMutableAttributedString *t = [inlineParser parse:[ORMathText convertInlineMathIn:[cont componentsJoinedByString:@" "]]];
            NSMutableAttributedString *m = [[NSMutableAttributedString alloc] initWithString:prefix
                                                                                  attributes:@{ NSFontAttributeName: [theme messageFont], NSForegroundColorAttributeName: textColor, NSParagraphStyleAttributeName: ps }];
            [m appendAttributedString:t];
            b.text = m;
            [blocks addObject:b];
            continue;
        }

        // Block quote
        if ([trimmed hasPrefix:@">"]) {
            flushPara();
            NSMutableArray *q = [NSMutableArray array];
            while (i < n) {
                NSString *qt = [lines[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if (![qt hasPrefix:@">"]) break;
                NSString *c = [qt substringFromIndex:1];
                if ([c hasPrefix:@" "]) c = [c substringFromIndex:1];
                [q addObject:c];
                i++;
            }
            ORMDBlock *b = [[ORMDBlock alloc] init];
            b.type = ORMDBlockQuote;
            NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
            ps.firstLineHeadIndent = 12;
            ps.headIndent = 12;
            inlineParser.paragraphStyle = ps;
            b.text = [inlineParser parse:[ORMathText convertInlineMathIn:[q componentsJoinedByString:@"\n"]]];
            [blocks addObject:b];
            continue;
        }

        [para addObject:ORTrimRight(line)];
        i++;
    }
    flushPara();
    return blocks;
}

+ (NSString *)plainTextFromMarkdown:(NSString *)markdown
{
    return markdown ?: @"";
}

@end
