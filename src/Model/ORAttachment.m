#import "ORAttachment.h"
#import "ORUtils.h"
#import "ORCommon.h"
#import "ORSettings.h"
#import "ORDocumentConverter.h"

@interface ORAttachment ()
@property (nonatomic, strong) UIImage *cachedThumb;
@property (nonatomic) CGFloat cachedThumbPixels;
@end

@implementation ORAttachment

+ (ORAttachmentKind)kindForPath:(NSString *)path
{
    if ([ORUtils isImagePath:path]) return ORAttachmentKindImage;
    if ([ORUtils isPDFPath:path]) return ORAttachmentKindPDF;
    if ([ORDocumentConverter canConvertPath:path]) return ORAttachmentKindDocument;
    if ([ORUtils isTextPath:path]) return ORAttachmentKindText;
    return ORAttachmentKindOther;
}

+ (instancetype)attachmentByImportingFileAtPath:(NSString *)path displayName:(NSString *)name error:(NSError **)error
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = [fm attributesOfItemAtPath:path error:error];
    if (!attrs) return nil;
    if (!name.length) name = [path lastPathComponent];

    ORAttachment *a = [[ORAttachment alloc] init];
    a.attachmentId = [ORUtils uuid];
    a.displayName = name;
    a.mime = [ORUtils mimeTypeForPath:name];
    a.kind = [self kindForPath:name];
    a.size = [attrs fileSize];

    if (a.kind == ORAttachmentKindOther) {
        // Unknown extension: treat small UTF-8 files as text.
        NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
        NSData *head = [fh readDataOfLength:4096];
        [fh closeFile];
        if (a.size <= 2 * 1024 * 1024 && [ORUtils dataLooksLikeUTF8Text:head]) {
            a.kind = ORAttachmentKindText;
            a.mime = @"text/plain";
        }
    }

    NSString *dest = [ORUtils uniqueAttachmentPathForName:name];
    if (![fm copyItemAtPath:path toPath:dest error:error]) return nil;
    a.storedName = [dest lastPathComponent];

    if (a.kind == ORAttachmentKindImage) {
        UIImage *img = [ORUtils thumbnailForImageAtPath:dest maxPixels:64];
        if (!img) {
            // Not decodable by ImageIO (e.g. webp). Keep it as image anyway, models can read it.
        }
    }
    return a;
}

+ (instancetype)attachmentWithImage:(UIImage *)image displayName:(NSString *)name
{
    if (!image) return nil;
    NSInteger maxDim = [ORSettings shared].imageMaxDimension;
    if (maxDim <= 0) maxDim = 1024;
    NSData *jpeg = [ORUtils jpegDataForImage:image maxDimension:maxDim quality:0.82];
    if (!jpeg) return nil;
    if (!name.length) name = @"photo.jpg";
    if (![[[name pathExtension] lowercaseString] isEqualToString:@"jpg"]) {
        name = [[name stringByDeletingPathExtension] stringByAppendingPathExtension:@"jpg"];
    }
    NSString *dest = [ORUtils uniqueAttachmentPathForName:name];
    if (![jpeg writeToFile:dest atomically:YES]) return nil;

    ORAttachment *a = [[ORAttachment alloc] init];
    a.attachmentId = [ORUtils uuid];
    a.displayName = name;
    a.storedName = [dest lastPathComponent];
    a.mime = @"image/jpeg";
    a.kind = ORAttachmentKindImage;
    a.size = jpeg.length;
    CGFloat w = image.size.width * image.scale, h = image.size.height * image.scale;
    CGFloat scale = MAX(w, h) > maxDim ? maxDim / MAX(w, h) : 1.0;
    a.pixelWidth = (NSInteger)floor(w * scale);
    a.pixelHeight = (NSInteger)floor(h * scale);
    return a;
}

+ (instancetype)attachmentFromJSON:(NSDictionary *)json
{
    if (![json isKindOfClass:[NSDictionary class]]) return nil;
    ORAttachment *a = [[ORAttachment alloc] init];
    a.attachmentId = json[@"id"] ?: [ORUtils uuid];
    a.storedName = json[@"file"];
    a.displayName = json[@"name"] ?: a.storedName;
    a.mime = json[@"mime"] ?: @"application/octet-stream";
    a.kind = (ORAttachmentKind)[json[@"kind"] integerValue];
    a.size = [json[@"size"] unsignedLongLongValue];
    a.pixelWidth = [json[@"w"] integerValue];
    a.pixelHeight = [json[@"h"] integerValue];
    if (!a.storedName) return nil;
    return a;
}

- (NSDictionary *)toJSON
{
    return @{
        @"id": self.attachmentId ?: @"",
        @"file": self.storedName ?: @"",
        @"name": self.displayName ?: @"",
        @"mime": self.mime ?: @"",
        @"kind": @(self.kind),
        @"size": @(self.size),
        @"w": @(self.pixelWidth),
        @"h": @(self.pixelHeight),
    };
}

- (NSString *)path
{
    return [[ORUtils attachmentsPath] stringByAppendingPathComponent:self.storedName];
}

- (NSData *)data
{
    return [NSData dataWithContentsOfFile:[self path]];
}

- (BOOL)isImage { return self.kind == ORAttachmentKindImage; }
- (BOOL)isPDF { return self.kind == ORAttachmentKindPDF; }
- (BOOL)isTextLike { return self.kind == ORAttachmentKindText || self.kind == ORAttachmentKindDocument; }

- (NSString *)textContentWithLimit:(NSInteger)maxBytes truncated:(BOOL *)truncated
{
    if (truncated) *truncated = NO;
    NSString *text = nil;
    if (self.kind == ORAttachmentKindDocument) {
        text = [ORDocumentConverter markdownForFileAtPath:[self path]];
    } else {
        NSData *d = [self data];
        if (!d) return nil;
        text = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        if (!text) text = [[NSString alloc] initWithData:d encoding:NSISOLatin1StringEncoding];
    }
    if (!text) return nil;
    if (maxBytes > 0 && text.length > (NSUInteger)maxBytes) {
        text = [text substringToIndex:maxBytes];
        if (truncated) *truncated = YES;
    }
    return text;
}

- (UIImage *)thumbnailWithMaxPixels:(CGFloat)maxPixels
{
    if (self.cachedThumb && self.cachedThumbPixels == maxPixels) return self.cachedThumb;
    UIImage *img = [ORUtils thumbnailForImageAtPath:[self path] maxPixels:maxPixels];
    if (img) {
        self.cachedThumb = img;
        self.cachedThumbPixels = maxPixels;
    }
    return img;
}

- (NSString *)sizeString
{
    return [ORUtils formatFileSize:self.size];
}

- (void)deleteFile
{
    [[NSFileManager defaultManager] removeItemAtPath:[self path] error:NULL];
}

@end
