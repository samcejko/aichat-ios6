#import "ORLegacyCompatibility.h"
#pragma clang diagnostic ignored "-Wunguarded-availability"
#import <objc/runtime.h>
@implementation ORCompatibleParagraphStyle
+ (id)allocWithZone:(NSZone *)zone {Class native=NSClassFromString(@"NSMutableParagraphStyle");return native?[native allocWithZone:zone]:[super allocWithZone:zone];}
- (id)copyWithZone:(NSZone *)zone {ORCompatibleParagraphStyle *p=[ORCompatibleParagraphStyle new];p.headIndent=self.headIndent;p.firstLineHeadIndent=self.firstLineHeadIndent;p.lineBreakMode=self.lineBreakMode;return p;}
@end
// Canonical NSAttributedString keys are also safe on iOS 5, where UIKit does not export their constants.
NSString *ORFontKey(void){return @"NSFont";}NSString *ORColorKey(void){return @"NSColor";}NSString *ORParagraphKey(void){return @"NSParagraphStyle";}NSString *ORBackgroundKey(void){return @"NSBackgroundColor";}NSString *ORUnderlineKey(void){return @"NSUnderline";}NSString *ORStrikeKey(void){return @"NSStrikethrough";}
NSAttributedString *ORCoreTextString(NSAttributedString *text) {
 NSMutableAttributedString *result=[[NSMutableAttributedString alloc] initWithString:text.string ?: @""];
 [text enumerateAttributesInRange:NSMakeRange(0,text.length) options:0 usingBlock:^(NSDictionary *attrs,NSRange range,BOOL *stop){
  NSMutableDictionary *out=[NSMutableDictionary dictionary];UIFont *font=[attrs objectForKey:ORFontKey()] ?: [UIFont systemFontOfSize:17];CTFontRef f=CTFontCreateWithName((__bridge CFStringRef)font.fontName,font.pointSize,NULL);out[(__bridge id)kCTFontAttributeName]=(__bridge id)f;CFRelease(f);
  UIColor *color=[attrs objectForKey:ORColorKey()] ?: [UIColor blackColor];out[(__bridge id)kCTForegroundColorAttributeName]=(__bridge id)color.CGColor;
  id paragraph=[attrs objectForKey:ORParagraphKey()];if(paragraph){CGFloat head=[paragraph headIndent],first=[paragraph firstLineHeadIndent];CTLineBreakMode mode=(CTLineBreakMode)[paragraph lineBreakMode];CTParagraphStyleSetting settings[]={{kCTParagraphStyleSpecifierHeadIndent,sizeof(head),&head},{kCTParagraphStyleSpecifierFirstLineHeadIndent,sizeof(first),&first},{kCTParagraphStyleSpecifierLineBreakMode,sizeof(mode),&mode}};CTParagraphStyleRef p=CTParagraphStyleCreate(settings,3);out[(__bridge id)kCTParagraphStyleAttributeName]=(__bridge id)p;CFRelease(p);}
  NSNumber *underline=[attrs objectForKey:ORUnderlineKey()];if(underline)out[(__bridge id)kCTUnderlineStyleAttributeName]=underline;[result setAttributes:out range:range];
 }];return result;
}
CGSize ORMeasureAttributed(NSAttributedString *text,CGFloat width) {
 if(!text.length)return CGSizeZero;
 if([text respondsToSelector:@selector(boundingRectWithSize:options:context:)]){CGRect r=[text boundingRectWithSize:CGSizeMake(width,CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading context:nil];return CGSizeMake(ceil(r.size.width),ceil(r.size.height)+1);}
 NSAttributedString *ct=ORCoreTextString(text);CTFramesetterRef frames=CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)ct);CGSize size=CTFramesetterSuggestFrameSizeWithConstraints(frames,CFRangeMake(0,0),NULL,CGSizeMake(width,CGFLOAT_MAX),NULL);CFRelease(frames);return CGSizeMake(ceil(size.width),ceil(size.height)+2);
}
@implementation ORAttributedLabel {NSAttributedString *_earlierAttributedText;}
- (void)setAttributedText:(NSAttributedString *)text {
 if([UILabel instancesRespondToSelector:@selector(setAttributedText:)]){[super setAttributedText:text];return;}
 _earlierAttributedText=[text copy];[super setText:text.string];[self setNeedsDisplay];
}
- (NSAttributedString *)attributedText {return [UILabel instancesRespondToSelector:@selector(attributedText)]?[super attributedText]:_earlierAttributedText;}
- (void)setText:(NSString *)text {_earlierAttributedText=nil;[super setText:text];}
- (void)drawTextInRect:(CGRect)rect {
 if(!_earlierAttributedText){[super drawTextInRect:rect];return;}
 NSAttributedString *ct=ORCoreTextString(_earlierAttributedText);CTFramesetterRef frames=CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)ct);CGContextRef context=UIGraphicsGetCurrentContext();CGContextSaveGState(context);CGContextSetTextMatrix(context,CGAffineTransformIdentity);CGContextTranslateCTM(context,0,self.bounds.size.height);CGContextScaleCTM(context,1,-1);CGMutablePathRef path=CGPathCreateMutable();CGPathAddRect(path,NULL,self.bounds);CTFrameRef frame=CTFramesetterCreateFrame(frames,CFRangeMake(0,0),path,NULL);CTFrameDraw(frame,context);CFRelease(frame);CGPathRelease(path);CFRelease(frames);CGContextRestoreGState(context);
}
@end

UIImage *ORStretchImage(UIImage *image,UIEdgeInsets insets){if([image respondsToSelector:@selector(resizableImageWithCapInsets:resizingMode:)])return [image resizableImageWithCapInsets:insets resizingMode:UIImageResizingModeStretch];return [image resizableImageWithCapInsets:insets];}

void ORSetAttributedText(UILabel *label,NSAttributedString *text){if([label respondsToSelector:@selector(setAttributedText:)])[label setAttributedText:text];else label.text=text.string;}
