#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface ORUtils : NSObject

// Encoding
+ (NSString *)base64EncodeData:(NSData *)data;
+ (NSData *)base64DecodeString:(NSString *)string;
+ (NSString *)dataURLWithMime:(NSString *)mime data:(NSData *)data;
// Splits "data:image/png;base64,...." into mime and decoded bytes; returns nil if not a data URL.
+ (NSData *)dataFromDataURL:(NSString *)dataURL mime:(NSString **)mime;
+ (NSString *)extensionForMime:(NSString *)mime;

// File types
+ (NSString *)mimeTypeForPath:(NSString *)path;
+ (BOOL)isImagePath:(NSString *)path;
+ (BOOL)isPDFPath:(NSString *)path;
+ (BOOL)isTextPath:(NSString *)path;
+ (BOOL)dataLooksLikeUTF8Text:(NSData *)data;

// Images
+ (NSData *)jpegDataForImage:(UIImage *)image maxDimension:(CGFloat)maxDim quality:(CGFloat)quality;
+ (UIImage *)thumbnailForImageAtPath:(NSString *)path maxPixels:(CGFloat)maxPixels;
+ (UIImage *)imageWithColor:(UIColor *)color size:(CGSize)size;

// Paths (created on demand)
+ (NSString *)documentsPath;
+ (NSString *)attachmentsPath;
+ (NSString *)chatsPath;
+ (NSString *)cachesPath;
+ (NSString *)inboxPath;

// Formatting
+ (NSString *)formatFileSize:(unsigned long long)bytes;
+ (NSString *)shortDateString:(NSDate *)date;
+ (NSString *)formatTokenCount:(NSInteger)tokens;
+ (NSString *)formatPricePerMillion:(NSString *)perTokenPriceString;
+ (NSString *)formatContextLength:(NSInteger)contextLength;
+ (NSString *)truncate:(NSString *)string to:(NSUInteger)length;

// Misc
+ (NSString *)uuid;
+ (NSString *)appVersion;
+ (NSString *)userAgent;
+ (id)JSONObjectFromData:(NSData *)data;
+ (NSData *)JSONDataFromObject:(id)object;
+ (void)alertWithTitle:(NSString *)title message:(NSString *)message;
+ (NSString *)safeFilename:(NSString *)name;
+ (NSString *)uniqueAttachmentPathForName:(NSString *)name;

@end
