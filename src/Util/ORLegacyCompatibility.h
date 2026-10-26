#import <UIKit/UIKit.h>
#import "ORFoundationCompatibility.h"
#import <CoreText/CoreText.h>
@interface ORCompatibleParagraphStyle : NSObject <NSCopying>
@property(nonatomic) CGFloat headIndent,firstLineHeadIndent;
@property(nonatomic) NSInteger lineBreakMode;
@end
NSString *ORFontKey(void);NSString *ORColorKey(void);NSString *ORParagraphKey(void);NSString *ORBackgroundKey(void);NSString *ORUnderlineKey(void);NSString *ORStrikeKey(void);
NSAttributedString *ORCoreTextString(NSAttributedString *text);
UIImage *ORStretchImage(UIImage *image,UIEdgeInsets insets);
CGSize ORMeasureAttributed(NSAttributedString *text,CGFloat width);
@interface ORAttributedLabel : UILabel
@property(nonatomic,copy) NSAttributedString *attributedText;
@end
@interface UILabel (OREarlierLabelDeclaration)
@property(nonatomic,copy) NSAttributedString *attributedText;
@end
#if __IPHONE_OS_VERSION_MIN_REQUIRED < 60000
#define NSMutableParagraphStyle ORCompatibleParagraphStyle
#define NSFontAttributeName ORFontKey()
#define NSForegroundColorAttributeName ORColorKey()
#define NSParagraphStyleAttributeName ORParagraphKey()
#define NSBackgroundColorAttributeName ORBackgroundKey()
#define NSUnderlineStyleAttributeName ORUnderlineKey()
#define NSStrikethroughStyleAttributeName ORStrikeKey()
#define NSUnderlineStyleSingle 1
#define NSTextAlignmentCenter UITextAlignmentCenter
#define NSTextAlignmentLeft UITextAlignmentLeft
#define NSTextAlignmentRight UITextAlignmentRight
#define NSLineBreakByWordWrapping UILineBreakModeWordWrap
#define NSLineBreakByCharWrapping UILineBreakModeCharacterWrap
#define NSLineBreakByTruncatingMiddle UILineBreakModeMiddleTruncation
#define NSLineBreakByTruncatingTail UILineBreakModeTailTruncation
#endif
