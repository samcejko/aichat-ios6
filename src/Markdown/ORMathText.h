#import <Foundation/Foundation.h>

// Text-level helpers for things models like to write that a plain Markdown renderer cannot show:
// inline LaTeX (converted to Unicode approximations), stray HTML tags and entities.
@interface ORMathText : NSObject

// Approximates a LaTeX math snippet with Unicode (greek letters, sub/superscripts, operators).
+ (NSString *)unicodeForLatex:(NSString *)latex;

// Replaces $...$ and \( ... \) spans outside of backtick code with their Unicode approximation.
+ (NSString *)convertInlineMathIn:(NSString *)text;

// <br> -> newline, common inline tags stripped, HTML entities decoded. Leaves code spans alone.
+ (NSString *)cleanupHTMLIn:(NSString *)text;

@end
