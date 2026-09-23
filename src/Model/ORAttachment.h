#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, ORAttachmentKind) {
    ORAttachmentKindImage = 0,
    ORAttachmentKindPDF = 1,
    ORAttachmentKindText = 2,
    ORAttachmentKindDocument = 3,   // docx / xlsx / pptx / html: converted to text on device
    ORAttachmentKindOther = 4,
};

// A file attached to a message. Files live in Library/Attachments; only the file name is persisted
// because the app container path changes between installs.
@interface ORAttachment : NSObject

@property (nonatomic, copy) NSString *attachmentId;
@property (nonatomic, copy) NSString *storedName;      // file name inside Library/Attachments
@property (nonatomic, copy) NSString *displayName;     // original file name
@property (nonatomic, copy) NSString *mime;
@property (nonatomic) ORAttachmentKind kind;
@property (nonatomic) unsigned long long size;
@property (nonatomic) NSInteger pixelWidth;
@property (nonatomic) NSInteger pixelHeight;

// Imports a file into the attachment store (copying it). Returns nil on failure.
+ (instancetype)attachmentByImportingFileAtPath:(NSString *)path displayName:(NSString *)name error:(NSError **)error;
// Downscales/encodes a picked image and stores it as JPEG.
+ (instancetype)attachmentWithImage:(UIImage *)image displayName:(NSString *)name;

+ (instancetype)attachmentFromJSON:(NSDictionary *)json;
- (NSDictionary *)toJSON;

- (NSString *)path;
- (NSData *)data;
- (BOOL)isImage;
- (BOOL)isPDF;
- (BOOL)isTextLike;    // text or convertible document
- (NSString *)textContentWithLimit:(NSInteger)maxBytes truncated:(BOOL *)truncated;
- (UIImage *)thumbnailWithMaxPixels:(CGFloat)maxPixels;
- (NSString *)sizeString;
- (void)deleteFile;

@end
