#import "ORTheme.h"
#import "ORSettings.h"
#import "ORCommon.h"

static UIColor *RGB(NSInteger r, NSInteger g, NSInteger b)
{
    return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1.0];
}

// Draws a rounded, vertically shaded rectangle with an optional glossy top half and
// returns it as a stretchable image.
static UIImage *ORRoundedGradientImage(UIColor *top, UIColor *bottom, UIColor *stroke, CGFloat radius, BOOL gloss)
{
    CGFloat side = radius * 2 + 12;
    CGRect rect = CGRectMake(0, 0, side, side);
    UIGraphicsBeginImageContextWithOptions(rect.size, NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGRect inner = CGRectInset(rect, 0.5, 0.5);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:inner cornerRadius:radius];

    CGContextSaveGState(ctx);
    CGContextAddPath(ctx, path.CGPath);
    CGContextClip(ctx);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = @[ (id)top.CGColor, (id)bottom.CGColor ];
    CGFloat locs[2] = { 0.0, 1.0 };
    CGGradientRef grad = CGGradientCreateWithColors(cs, (__bridge CFArrayRef)colors, locs);
    CGContextDrawLinearGradient(ctx, grad, CGPointMake(0, 0), CGPointMake(0, side), 0);
    CGGradientRelease(grad);
    CGColorSpaceRelease(cs);
    if (gloss) {
        CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:1.0 alpha:0.20].CGColor);
        CGContextFillRect(ctx, CGRectMake(0, 0, side, floor(side / 2)));
    }
    CGContextRestoreGState(ctx);

    if (stroke) {
        [stroke setStroke];
        path.lineWidth = 1.0;
        [path stroke];
    }
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    CGFloat cap = radius + 5;
    return [img resizableImageWithCapInsets:UIEdgeInsetsMake(cap, cap, cap, cap) resizingMode:UIImageResizingModeStretch];
}

// A vertical bar background: top hairline, gradient body.
static UIImage *ORBarBackgroundImage(UIColor *top, UIColor *bottom, UIColor *line, CGFloat height)
{
    CGSize size = CGSizeMake(4, height);
    UIGraphicsBeginImageContextWithOptions(size, YES, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = @[ (id)top.CGColor, (id)bottom.CGColor ];
    CGFloat locs[2] = { 0.0, 1.0 };
    CGGradientRef grad = CGGradientCreateWithColors(cs, (__bridge CFArrayRef)colors, locs);
    CGContextDrawLinearGradient(ctx, grad, CGPointMake(0, 0), CGPointMake(0, height), 0);
    CGGradientRelease(grad);
    CGColorSpaceRelease(cs);
    [line setFill];
    UIRectFill(CGRectMake(0, 0, size.width, 1));
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [img resizableImageWithCapInsets:UIEdgeInsetsMake(2, 1, 2, 1) resizingMode:UIImageResizingModeStretch];
}

@interface ORTheme ()
@property (nonatomic) BOOL dark;
@property (nonatomic, strong) NSMutableDictionary *imageCache;
@end

@implementation ORTheme

+ (instancetype)shared
{
    static ORTheme *t = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ t = [[ORTheme alloc] init]; });
    return t;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _dark = [ORSettings shared].darkTheme;
        _imageCache = [NSMutableDictionary dictionary];
    }
    return self;
}

- (BOOL)isDark { return self.dark; }

- (void)setDark:(BOOL)dark
{
    _dark = dark;
    [ORSettings shared].darkTheme = dark;
    [[ORSettings shared] save];
    [self.imageCache removeAllObjects];
    [[UIApplication sharedApplication] setStatusBarStyle:[self statusBarStyle] animated:YES];
    [[NSNotificationCenter defaultCenter] postNotificationName:ORThemeDidChangeNotification object:self];
}

- (void)reloadFromSettings
{
    [self.imageCache removeAllObjects];
    [[NSNotificationCenter defaultCenter] postNotificationName:ORThemeDidChangeNotification object:self];
}

#pragma mark - Colors

- (UIColor *)chatBackgroundColor { return self.dark ? RGB(28, 28, 30) : RGB(233, 235, 240); }
- (UIColor *)tableBackgroundColor { return self.dark ? RGB(0, 0, 0) : RGB(235, 236, 240); }
- (UIColor *)cellBackgroundColor { return self.dark ? RGB(30, 30, 33) : [UIColor whiteColor]; }
- (UIColor *)cellSelectedBackgroundColor { return self.dark ? RGB(50, 50, 55) : RGB(215, 222, 235); }
- (UIColor *)primaryTextColor { return self.dark ? RGB(240, 240, 242) : RGB(20, 20, 22); }
- (UIColor *)secondaryTextColor { return self.dark ? RGB(150, 150, 158) : RGB(110, 110, 118); }
- (UIColor *)accentColor { return self.dark ? RGB(88, 150, 235) : RGB(42, 105, 205); }
- (UIColor *)separatorColor { return self.dark ? RGB(55, 55, 60) : RGB(200, 200, 206); }
- (UIColor *)userBubbleTextColor { return [UIColor whiteColor]; }
- (UIColor *)assistantBubbleTextColor { return self.dark ? RGB(240, 240, 242) : RGB(20, 20, 22); }
- (UIColor *)errorTextColor { return self.dark ? RGB(255, 170, 170) : RGB(150, 20, 20); }
- (UIColor *)linkColor { return self.dark ? RGB(120, 175, 245) : RGB(30, 90, 200); }
- (UIColor *)inputTextColor { return self.dark ? RGB(240, 240, 242) : RGB(20, 20, 22); }
- (UIColor *)placeholderColor { return self.dark ? RGB(120, 120, 128) : RGB(160, 160, 168); }
- (UIColor *)noteBackgroundColor { return self.dark ? RGB(40, 40, 44) : RGB(222, 224, 230); }

- (UIColor *)codeBackgroundColorInUserBubble:(BOOL)inUser
{
    if (inUser) return [UIColor colorWithWhite:1.0 alpha:0.22];
    return self.dark ? [UIColor colorWithWhite:1.0 alpha:0.10] : [UIColor colorWithWhite:0.0 alpha:0.07];
}

#pragma mark - Artwork

- (UIImage *)cachedImage:(NSString *)key builder:(UIImage *(^)(void))builder
{
    UIImage *img = self.imageCache[key];
    if (!img) {
        img = builder();
        if (img) self.imageCache[key] = img;
    }
    return img;
}

- (UIImage *)userBubbleImage
{
    return [self cachedImage:@"userBubble" builder:^UIImage *{
        if (self.dark) return ORRoundedGradientImage(RGB(90, 150, 240), RGB(38, 95, 200), RGB(30, 75, 160), 12, YES);
        return ORRoundedGradientImage(RGB(120, 170, 245), RGB(45, 110, 215), RGB(35, 85, 170), 12, YES);
    }];
}

- (UIImage *)assistantBubbleImage
{
    return [self cachedImage:@"assistantBubble" builder:^UIImage *{
        if (self.dark) return ORRoundedGradientImage(RGB(62, 62, 68), RGB(44, 44, 48), RGB(75, 75, 80), 12, YES);
        return ORRoundedGradientImage(RGB(252, 252, 253), RGB(226, 227, 232), RGB(190, 192, 200), 12, YES);
    }];
}

- (UIImage *)errorBubbleImage
{
    return [self cachedImage:@"errorBubble" builder:^UIImage *{
        if (self.dark) return ORRoundedGradientImage(RGB(95, 45, 45), RGB(65, 28, 28), RGB(120, 60, 60), 12, NO);
        return ORRoundedGradientImage(RGB(255, 232, 232), RGB(247, 205, 205), RGB(215, 150, 150), 12, NO);
    }];
}

- (UIImage *)inputBarBackgroundImage
{
    return [self cachedImage:@"inputBar" builder:^UIImage *{
        if (self.dark) return ORBarBackgroundImage(RGB(62, 62, 66), RGB(36, 36, 40), RGB(15, 15, 17), 44);
        return ORBarBackgroundImage(RGB(245, 245, 248), RGB(214, 214, 220), RGB(170, 170, 178), 44);
    }];
}

- (UIImage *)textFieldBackgroundImage
{
    return [self cachedImage:@"textField" builder:^UIImage *{
        if (self.dark) return ORRoundedGradientImage(RGB(40, 40, 44), RGB(44, 44, 48), RGB(80, 80, 86), 8, NO);
        return ORRoundedGradientImage([UIColor whiteColor], [UIColor whiteColor], RGB(160, 160, 168), 8, NO);
    }];
}

- (UIImage *)sendButtonImageHighlighted:(BOOL)highlighted disabled:(BOOL)disabled
{
    NSString *key = [NSString stringWithFormat:@"send-%d-%d", (int)highlighted, (int)disabled];
    return [self cachedImage:key builder:^UIImage *{
        if (disabled) return ORRoundedGradientImage(RGB(190, 190, 196), RGB(160, 160, 168), RGB(140, 140, 148), 7, YES);
        if (highlighted) return ORRoundedGradientImage(RGB(60, 110, 200), RGB(25, 70, 160), RGB(20, 55, 130), 7, YES);
        return ORRoundedGradientImage(RGB(110, 160, 240), RGB(40, 100, 205), RGB(30, 75, 160), 7, YES);
    }];
}

- (UIImage *)stopButtonImage
{
    return [self cachedImage:@"stop" builder:^UIImage *{
        return ORRoundedGradientImage(RGB(235, 100, 90), RGB(190, 45, 40), RGB(150, 35, 30), 7, YES);
    }];
}

- (UIImage *)plusButtonImage
{
    return [self cachedImage:@"plus" builder:^UIImage *{
        CGSize size = CGSizeMake(30, 30);
        UIGraphicsBeginImageContextWithOptions(size, NO, 0);
        UIColor *stroke = self.dark ? RGB(200, 200, 205) : RGB(90, 90, 98);
        UIBezierPath *circle = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(1.5, 1.5, 27, 27)];
        circle.lineWidth = 2.0;
        [stroke setStroke];
        [circle stroke];
        UIBezierPath *plus = [UIBezierPath bezierPath];
        [plus moveToPoint:CGPointMake(15, 8)];
        [plus addLineToPoint:CGPointMake(15, 22)];
        [plus moveToPoint:CGPointMake(8, 15)];
        [plus addLineToPoint:CGPointMake(22, 15)];
        plus.lineWidth = 2.5;
        plus.lineCapStyle = kCGLineCapRound;
        [plus stroke];
        UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return img;
    }];
}

- (UIImage *)disclosureArrowImage
{
    return [self cachedImage:@"disclosure" builder:^UIImage *{
        CGSize size = CGSizeMake(12, 12);
        UIGraphicsBeginImageContextWithOptions(size, NO, 0);
        UIBezierPath *p = [UIBezierPath bezierPath];
        [p moveToPoint:CGPointMake(2, 4)];
        [p addLineToPoint:CGPointMake(6, 8.5)];
        [p addLineToPoint:CGPointMake(10, 4)];
        p.lineWidth = 2.0;
        p.lineCapStyle = kCGLineCapRound;
        p.lineJoinStyle = kCGLineJoinRound;
        [(self.dark ? [UIColor whiteColor] : [UIColor whiteColor]) setStroke];
        [p stroke];
        UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return img;
    }];
}

#pragma mark - Fonts

- (CGFloat)messageFontSize
{
    switch ([ORSettings shared].fontSize) {
        case ORFontSizeSmall: return 14.0;
        case ORFontSizeLarge: return 18.0;
        default: return 16.0;
    }
}

- (UIFont *)messageFont { return [UIFont systemFontOfSize:[self messageFontSize]]; }
- (UIFont *)boldMessageFont { return [UIFont boldSystemFontOfSize:[self messageFontSize]]; }
- (UIFont *)italicMessageFont { return [UIFont italicSystemFontOfSize:[self messageFontSize]]; }
- (UIFont *)boldItalicMessageFont
{
    UIFont *f = [UIFont fontWithName:@"Helvetica-BoldOblique" size:[self messageFontSize]];
    return f ?: [self boldMessageFont];
}
- (UIFont *)codeFont
{
    UIFont *f = [UIFont fontWithName:@"Courier" size:[self messageFontSize] - 1.0];
    return f ?: [UIFont systemFontOfSize:[self messageFontSize] - 1.0];
}
- (UIFont *)smallFont { return [UIFont systemFontOfSize:11.0]; }
- (UIFont *)headingFontForLevel:(NSInteger)level
{
    CGFloat base = [self messageFontSize];
    CGFloat size = base + MAX(0, (4 - level)) * 2.0;
    if (level >= 4) size = base;
    return [UIFont boldSystemFontOfSize:size];
}

#pragma mark - UIKit

- (UIBarStyle)barStyle { return self.dark ? UIBarStyleBlack : UIBarStyleDefault; }
- (UIStatusBarStyle)statusBarStyle { return self.dark ? UIStatusBarStyleBlackOpaque : UIStatusBarStyleDefault; }

- (void)applyToNavigationBar:(UINavigationBar *)bar
{
    bar.barStyle = [self barStyle];
    bar.translucent = NO;
    bar.tintColor = nil;
}

- (void)applyToToolbar:(UIToolbar *)bar
{
    bar.barStyle = [self barStyle];
    bar.translucent = NO;
    bar.tintColor = nil;
}

- (void)applyToTableView:(UITableView *)tableView grouped:(BOOL)grouped
{
    tableView.backgroundView = nil;
    tableView.backgroundColor = grouped ? [self tableBackgroundColor] : [self cellBackgroundColor];
    tableView.separatorColor = [self separatorColor];
    tableView.indicatorStyle = self.dark ? UIScrollViewIndicatorStyleWhite : UIScrollViewIndicatorStyleDefault;
}

- (void)styleCell:(UITableViewCell *)cell
{
    cell.backgroundColor = [self cellBackgroundColor];
    cell.textLabel.textColor = [self primaryTextColor];
    cell.textLabel.backgroundColor = [UIColor clearColor];
    cell.detailTextLabel.textColor = self.dark ? [self secondaryTextColor] : RGB(56, 84, 135);
    cell.detailTextLabel.backgroundColor = [UIColor clearColor];
    if (self.dark) {
        UIView *sel = [[UIView alloc] init];
        sel.backgroundColor = [self cellSelectedBackgroundColor];
        cell.selectedBackgroundView = sel;
    } else {
        cell.selectedBackgroundView = nil;
    }
}

- (void)applyToSearchBar:(UISearchBar *)bar
{
    bar.barStyle = [self barStyle];
    bar.tintColor = nil;
}

- (void)applyToView:(UIView *)view
{
    view.backgroundColor = [self tableBackgroundColor];
}

@end
