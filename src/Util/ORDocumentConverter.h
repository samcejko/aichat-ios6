#import <Foundation/Foundation.h>

// On-device "mini MarkItDown": converts office documents to Markdown-ish text so that any
// text model can read them. Supports docx/xlsx/pptx (OOXML), odt/ods/odp (OpenDocument),
// html/htm and rtf. PDFs are handled by OpenRouter's file parser instead.
@interface ORDocumentConverter : NSObject

+ (BOOL)canConvertPath:(NSString *)path;
+ (NSString *)markdownForFileAtPath:(NSString *)path;   // nil on failure

@end

// Minimal read-only ZIP archive (stored + deflate entries, no ZIP64, no encryption).
@interface ORZipArchive : NSObject
- (instancetype)initWithData:(NSData *)data;
- (NSArray *)entryNames;
- (NSData *)dataForEntry:(NSString *)name;
@end
