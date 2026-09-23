#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, ORMDBlockType) {
    ORMDBlockParagraph = 0,
    ORMDBlockHeading,
    ORMDBlockCode,
    ORMDBlockListItem,
    ORMDBlockQuote,
    ORMDBlockRule,
    ORMDBlockTable,
    ORMDBlockMath,      // display math, rawText holds the LaTeX
    ORMDBlockImage,     // remote image, rawText = URL, language = alt text
};

@interface ORMDBlock : NSObject
@property (nonatomic) ORMDBlockType type;
@property (nonatomic, strong) NSAttributedString *text;   // paragraph, heading, list, quote
@property (nonatomic, copy) NSString *rawText;            // code, table (monospace)
@property (nonatomic) NSInteger level;                    // heading level / list indent
@property (nonatomic, copy) NSString *language;
@end

// A small Markdown renderer producing vertically stacked blocks. Tolerant of streaming input
// (unterminated fences are rendered as code).
@interface ORMarkdown : NSObject

+ (NSArray *)blocksFromMarkdown:(NSString *)markdown textColor:(UIColor *)textColor inUserBubble:(BOOL)inUser;
+ (NSAttributedString *)plainAttributedString:(NSString *)text color:(UIColor *)color font:(UIFont *)font;
+ (NSString *)plainTextFromMarkdown:(NSString *)markdown;   // for copy / previews

@end
