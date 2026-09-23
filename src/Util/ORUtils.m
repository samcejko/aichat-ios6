#import "ORUtils.h"
#import "ORCommon.h"
#import <ImageIO/ImageIO.h>
#include <string.h>

static const char kBase64Table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

@implementation ORUtils

#pragma mark - Encoding

+ (NSString *)base64EncodeData:(NSData *)data
{
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSUInteger len = data.length;
    if (len == 0) return @"";
    NSUInteger outLen = ((len + 2) / 3) * 4;
    char *out = (char *)malloc(outLen + 1);
    if (!out) return @"";
    NSUInteger i = 0, j = 0;
    while (i + 2 < len) {
        uint32_t v = ((uint32_t)bytes[i] << 16) | ((uint32_t)bytes[i + 1] << 8) | (uint32_t)bytes[i + 2];
        out[j++] = kBase64Table[(v >> 18) & 63];
        out[j++] = kBase64Table[(v >> 12) & 63];
        out[j++] = kBase64Table[(v >> 6) & 63];
        out[j++] = kBase64Table[v & 63];
        i += 3;
    }
    if (i < len) {
        uint32_t v = (uint32_t)bytes[i] << 16;
        if (i + 1 < len) v |= (uint32_t)bytes[i + 1] << 8;
        out[j++] = kBase64Table[(v >> 18) & 63];
        out[j++] = kBase64Table[(v >> 12) & 63];
        out[j++] = (i + 1 < len) ? kBase64Table[(v >> 6) & 63] : '=';
        out[j++] = '=';
    }
    out[j] = 0;
    return [[NSString alloc] initWithBytesNoCopy:out length:j encoding:NSASCIIStringEncoding freeWhenDone:YES];
}

+ (NSData *)base64DecodeString:(NSString *)string
{
    if (!string.length) return nil;
    static int8_t table[256];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        memset(table, -1, sizeof(table));
        for (int i = 0; i < 64; i++) table[(uint8_t)kBase64Table[i]] = (int8_t)i;
        table[(uint8_t)'-'] = 62;   // URL-safe variants
        table[(uint8_t)'_'] = 63;
    });
    NSData *ascii = [string dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
    const uint8_t *in = (const uint8_t *)ascii.bytes;
    NSUInteger len = ascii.length;
    NSMutableData *out = [NSMutableData dataWithCapacity:len * 3 / 4 + 3];
    uint32_t acc = 0;
    int bits = 0;
    for (NSUInteger i = 0; i < len; i++) {
        uint8_t c = in[i];
        if (c == '=') break;
        int8_t v = table[c];
        if (v < 0) continue;   // whitespace / newlines
        acc = (acc << 6) | (uint32_t)v;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            uint8_t b = (uint8_t)((acc >> bits) & 0xFF);
            [out appendBytes:&b length:1];
        }
    }
    return out;
}

+ (NSString *)dataURLWithMime:(NSString *)mime data:(NSData *)data
{
    return [NSString stringWithFormat:@"data:%@;base64,%@", mime ?: @"application/octet-stream", [self base64EncodeData:data]];
}

+ (NSData *)dataFromDataURL:(NSString *)dataURL mime:(NSString **)mime
{
    if (![dataURL hasPrefix:@"data:"]) return nil;
    NSRange comma = [dataURL rangeOfString:@","];
    if (comma.location == NSNotFound) return nil;
    NSString *header = [dataURL substringWithRange:NSMakeRange(5, comma.location - 5)];   // "image/png;base64"
    NSArray *parts = [header componentsSeparatedByString:@";"];
    if (mime) *mime = parts.count ? parts[0] : @"application/octet-stream";
    NSString *payload = [dataURL substringFromIndex:comma.location + 1];
    if ([header rangeOfString:@"base64"].location == NSNotFound) {
        return [[payload stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding] dataUsingEncoding:NSUTF8StringEncoding];
    }
    return [self base64DecodeString:payload];
}

+ (NSString *)extensionForMime:(NSString *)mime
{
    NSString *m = [mime lowercaseString];
    if ([m isEqualToString:@"image/png"]) return @"png";
    if ([m isEqualToString:@"image/jpeg"] || [m isEqualToString:@"image/jpg"]) return @"jpg";
    if ([m isEqualToString:@"image/gif"]) return @"gif";
    if ([m isEqualToString:@"image/webp"]) return @"webp";
    if ([m isEqualToString:@"application/pdf"]) return @"pdf";
    if ([m hasPrefix:@"text/"]) return @"txt";
    return @"bin";
}

#pragma mark - File types

+ (NSDictionary *)mimeTable
{
    static NSDictionary *table = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = @{
            @"jpg": @"image/jpeg", @"jpeg": @"image/jpeg", @"png": @"image/png", @"gif": @"image/gif",
            @"webp": @"image/webp", @"bmp": @"image/bmp", @"tif": @"image/tiff", @"tiff": @"image/tiff",
            @"heic": @"image/heic",
            @"pdf": @"application/pdf",
            @"txt": @"text/plain", @"md": @"text/markdown", @"markdown": @"text/markdown",
            @"json": @"application/json", @"csv": @"text/csv", @"tsv": @"text/tab-separated-values",
            @"xml": @"application/xml", @"html": @"text/html", @"htm": @"text/html",
            @"yaml": @"text/yaml", @"yml": @"text/yaml", @"log": @"text/plain",
            @"js": @"text/javascript", @"css": @"text/css",
            @"zip": @"application/zip", @"mp3": @"audio/mpeg", @"m4a": @"audio/mp4", @"wav": @"audio/wav",
            @"mp4": @"video/mp4", @"mov": @"video/quicktime",
            @"doc": @"application/msword", @"docx": @"application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            @"xls": @"application/vnd.ms-excel", @"xlsx": @"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            @"ppt": @"application/vnd.ms-powerpoint", @"pptx": @"application/vnd.openxmlformats-officedocument.presentationml.presentation",
        };
    });
    return table;
}

+ (NSSet *)textExtensions
{
    static NSSet *set = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [NSSet setWithArray:@[
            @"txt", @"md", @"markdown", @"json", @"csv", @"tsv", @"xml", @"html", @"htm", @"yaml", @"yml", @"log",
            @"ini", @"cfg", @"conf", @"toml", @"env", @"properties", @"plist", @"strings",
            @"c", @"h", @"m", @"mm", @"cpp", @"cc", @"cxx", @"hpp", @"hh", @"cs", @"java", @"kt", @"kts", @"swift",
            @"py", @"rb", @"go", @"rs", @"php", @"pl", @"pm", @"lua", @"sh", @"bash", @"zsh", @"bat", @"cmd", @"ps1",
            @"js", @"jsx", @"ts", @"tsx", @"mjs", @"cjs", @"css", @"scss", @"less", @"sass", @"vue", @"svelte",
            @"sql", @"r", @"jl", @"tex", @"bib", @"rst", @"adoc", @"org", @"diff", @"patch", @"makefile", @"mk",
            @"gradle", @"cmake", @"dockerfile", @"srt", @"vtt", @"sub", @"ics", @"vcf", @"eml", @"asm", @"s", @"dart",
            @"scala", @"clj", @"hs", @"ex", @"exs", @"erl", @"ml", @"fs", @"nim", @"zig", @"v", @"sol", @"graphql", @"proto",
        ]];
    });
    return set;
}

+ (NSString *)mimeTypeForPath:(NSString *)path
{
    NSString *ext = [[path pathExtension] lowercaseString];
    NSString *mime = [self mimeTable][ext];
    if (mime) return mime;
    if ([[self textExtensions] containsObject:ext]) return @"text/plain";
    if ([self isTextPath:path]) return @"text/plain";
    return @"application/octet-stream";
}

+ (BOOL)isImagePath:(NSString *)path
{
    NSString *mime = [self mimeTypeForPath:path];
    return [mime hasPrefix:@"image/"];
}

+ (BOOL)isPDFPath:(NSString *)path
{
    return [[[path pathExtension] lowercaseString] isEqualToString:@"pdf"];
}

+ (BOOL)isTextPath:(NSString *)path
{
    NSString *ext = [[path pathExtension] lowercaseString];
    if ([[self textExtensions] containsObject:ext]) return YES;
    NSString *name = [[path lastPathComponent] lowercaseString];
    if ([name isEqualToString:@"makefile"] || [name isEqualToString:@"dockerfile"] || [name isEqualToString:@"readme"]) return YES;
    return NO;
}

+ (BOOL)dataLooksLikeUTF8Text:(NSData *)data
{
    if (data.length == 0) return NO;
    NSUInteger check = MIN(data.length, (NSUInteger)4096);
    const uint8_t *b = (const uint8_t *)data.bytes;
    for (NSUInteger i = 0; i < check; i++) {
        if (b[i] == 0) return NO;
    }
    // A cut in the middle of a multibyte sequence can make the sample invalid; retry up to 3 bytes shorter.
    for (NSUInteger cut = 0; cut <= 3 && cut < check; cut++) {
        NSString *s = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, check - cut)] encoding:NSUTF8StringEncoding];
        if (s) return YES;
        if (check == data.length) break;   // whole file was tested, nothing was cut
    }
    return NO;
}

#pragma mark - Images

+ (NSData *)jpegDataForImage:(UIImage *)image maxDimension:(CGFloat)maxDim quality:(CGFloat)quality
{
    if (!image) return nil;
    CGFloat w = image.size.width * image.scale;
    CGFloat h = image.size.height * image.scale;
    if (w < 1 || h < 1) return nil;
    CGFloat scale = 1.0;
    if (maxDim > 0 && MAX(w, h) > maxDim) scale = maxDim / MAX(w, h);
    CGSize target = CGSizeMake(MAX(1, floor(w * scale)), MAX(1, floor(h * scale)));

    UIGraphicsBeginImageContextWithOptions(target, YES, 1.0);
    [[UIColor whiteColor] setFill];
    UIRectFill(CGRectMake(0, 0, target.width, target.height));
    [image drawInRect:CGRectMake(0, 0, target.width, target.height)];
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return UIImageJPEGRepresentation(out, quality);
}

+ (UIImage *)thumbnailForImageAtPath:(NSString *)path maxPixels:(CGFloat)maxPixels
{
    if (!path) return nil;
    NSURL *url = [NSURL fileURLWithPath:path];
    CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!src) return nil;
    NSDictionary *opts = @{
        (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (id)kCGImageSourceThumbnailMaxPixelSize: @(maxPixels),
        (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
    };
    CGImageRef cg = CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)opts);
    CFRelease(src);
    if (!cg) return nil;
    UIImage *img = [UIImage imageWithCGImage:cg scale:[UIScreen mainScreen].scale orientation:UIImageOrientationUp];
    CGImageRelease(cg);
    return img;
}

+ (UIImage *)imageWithColor:(UIColor *)color size:(CGSize)size
{
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    [color setFill];
    UIRectFill(CGRectMake(0, 0, size.width, size.height));
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

#pragma mark - Paths

+ (NSString *)ensureDirectory:(NSString *)path
{
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:path isDirectory:&isDir] || !isDir) {
        [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL];
    }
    return path;
}

+ (NSString *)documentsPath
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [self ensureDirectory:[paths objectAtIndex:0]];
}

+ (NSString *)attachmentsPath
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    return [self ensureDirectory:[[paths objectAtIndex:0] stringByAppendingPathComponent:@"Attachments"]];
}

+ (NSString *)chatsPath
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    return [self ensureDirectory:[[paths objectAtIndex:0] stringByAppendingPathComponent:@"Chats"]];
}

+ (NSString *)cachesPath
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    return [self ensureDirectory:[paths objectAtIndex:0]];
}

+ (NSString *)inboxPath
{
    return [[self documentsPath] stringByAppendingPathComponent:@"Inbox"];
}

#pragma mark - Formatting

+ (NSString *)formatFileSize:(unsigned long long)bytes
{
    if (bytes < 1024) return [NSString stringWithFormat:@"%llu B", bytes];
    if (bytes < 1024 * 1024) return [NSString stringWithFormat:@"%.0f KB", bytes / 1024.0];
    if (bytes < 1024ULL * 1024 * 1024) return [NSString stringWithFormat:@"%.1f MB", bytes / (1024.0 * 1024.0)];
    return [NSString stringWithFormat:@"%.2f GB", bytes / (1024.0 * 1024.0 * 1024.0)];
}

+ (NSString *)shortDateString:(NSDate *)date
{
    if (!date) return @"";
    static NSDateFormatter *timeFmt = nil, *dateFmt = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        timeFmt = [[NSDateFormatter alloc] init];
        timeFmt.dateStyle = NSDateFormatterNoStyle;
        timeFmt.timeStyle = NSDateFormatterShortStyle;
        dateFmt = [[NSDateFormatter alloc] init];
        dateFmt.dateStyle = NSDateFormatterShortStyle;
        dateFmt.timeStyle = NSDateFormatterShortStyle;
        dateFmt.doesRelativeDateFormatting = YES;
    });
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *a = [cal components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:date];
    NSDateComponents *b = [cal components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:[NSDate date]];
    if (a.year == b.year && a.month == b.month && a.day == b.day) return [timeFmt stringFromDate:date];
    return [dateFmt stringFromDate:date];
}

+ (NSString *)formatTokenCount:(NSInteger)tokens
{
    if (tokens >= 1000000) return [NSString stringWithFormat:@"%.1fM", tokens / 1000000.0];
    if (tokens >= 10000) return [NSString stringWithFormat:@"%ldk", (long)(tokens / 1000)];
    if (tokens >= 1000) return [NSString stringWithFormat:@"%.1fk", tokens / 1000.0];
    return [NSString stringWithFormat:@"%ld", (long)tokens];
}

+ (NSString *)formatPricePerMillion:(NSString *)perTokenPriceString
{
    if (!perTokenPriceString) return @"?";
    double perToken = [perTokenPriceString doubleValue];
    if (perToken < 0) return @"var";
    if (perToken == 0) return @"$0";
    double perM = perToken * 1000000.0;
    if (perM >= 100) return [NSString stringWithFormat:@"$%.0f", perM];
    if (perM >= 10) return [NSString stringWithFormat:@"$%.1f", perM];
    if (perM >= 1) return [NSString stringWithFormat:@"$%.2f", perM];
    return [NSString stringWithFormat:@"$%.3f", perM];
}

+ (NSString *)formatContextLength:(NSInteger)contextLength
{
    if (contextLength <= 0) return @"?";
    if (contextLength >= 1000000) return [NSString stringWithFormat:@"%.1fM", contextLength / 1000000.0];
    if (contextLength >= 1000) return [NSString stringWithFormat:@"%ldk", (long)(contextLength / 1000)];
    return [NSString stringWithFormat:@"%ld", (long)contextLength];
}

+ (NSString *)truncate:(NSString *)string to:(NSUInteger)length
{
    if (!string) return @"";
    NSString *s = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    s = [s stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    if (s.length <= length) return s;
    return [[s substringToIndex:length] stringByAppendingString:@"…"];
}

#pragma mark - Misc

+ (NSString *)uuid
{
    CFUUIDRef uuid = CFUUIDCreate(NULL);
    NSString *s = (__bridge_transfer NSString *)CFUUIDCreateString(NULL, uuid);
    CFRelease(uuid);
    return [s lowercaseString];
}

+ (NSString *)appVersion
{
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    NSString *v = info[@"CFBundleShortVersionString"] ?: @"0";
    NSString *b = info[@"CFBundleVersion"] ?: @"0";
    return [NSString stringWithFormat:@"%@ (%@)", v, b];
}

+ (NSString *)userAgent
{
    UIDevice *d = [UIDevice currentDevice];
    NSString *v = [[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"] ?: @"0";
    return [NSString stringWithFormat:@"AIChat/%@ (%@; iOS %@)", v, d.model, d.systemVersion];
}

+ (id)JSONObjectFromData:(NSData *)data
{
    if (!data || data.length == 0) return nil;
    NSError *err = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if (err) return nil;
    return obj;
}

+ (NSData *)JSONDataFromObject:(id)object
{
    if (!object) return nil;
    NSError *err = nil;
    NSData *d = [NSJSONSerialization dataWithJSONObject:object options:0 error:&err];
    if (err) {
        ORLog(@"JSON serialization failed: %@", err);
        return nil;
    }
    return d;
}

+ (void)alertWithTitle:(NSString *)title message:(NSString *)message
{
    ORMain(^{
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title message:message delegate:nil cancelButtonTitle:L(@"OK") otherButtonTitles:nil];
        [alert show];
    });
}

+ (NSString *)safeFilename:(NSString *)name
{
    if (name.length == 0) return @"file";
    NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|\n\r\t"];
    NSArray *parts = [name componentsSeparatedByCharactersInSet:bad];
    NSString *s = [parts componentsJoinedByString:@"_"];
    if (s.length > 120) s = [s substringFromIndex:s.length - 120];
    return s;
}

+ (NSString *)uniqueAttachmentPathForName:(NSString *)name
{
    NSString *safe = [self safeFilename:name];
    NSString *prefix = [[self uuid] substringToIndex:8];
    return [[self attachmentsPath] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_%@", prefix, safe]];
}

@end
