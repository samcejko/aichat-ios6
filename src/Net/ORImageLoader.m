#import "ORImageLoader.h"
#import "ORHTTPRequest.h"
#import "ORUtils.h"
#import "ORCommon.h"
#include <CommonCrypto/CommonDigest.h>

NSString * const ORImageDidLoadNotification = @"ORImageDidLoadNotification";

static const NSUInteger kMaxImageBytes = 4 * 1024 * 1024;
static const CGFloat kMaxDisplayPixels = 1024.0;
static const NSInteger kMaxRedirects = 4;

@interface ORImageLoader ()
@property (nonatomic, strong) NSMutableDictionary *memory;     // url -> UIImage
@property (nonatomic, strong) NSMutableSet *loading;           // urls in flight
@property (nonatomic, strong) NSMutableSet *failed;
@end

@implementation ORImageLoader

+ (instancetype)shared
{
    static ORImageLoader *l = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ l = [[ORImageLoader alloc] init]; });
    return l;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _memory = [NSMutableDictionary dictionary];
        _loading = [NSMutableSet set];
        _failed = [NSMutableSet set];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(memoryWarning) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    }
    return self;
}

- (void)memoryWarning
{
    [self.memory removeAllObjects];
}

- (NSString *)cacheDirectory
{
    NSString *dir = [[ORUtils cachesPath] stringByAppendingPathComponent:@"images"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    return dir;
}

- (NSString *)keyForURL:(NSString *)url
{
    NSData *d = [url dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(d.bytes, (CC_LONG)d.length, digest);
    NSMutableString *s = [NSMutableString string];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) [s appendFormat:@"%02x", digest[i]];
    return s;
}

- (NSString *)cachedFilePathForURL:(NSString *)url
{
    NSString *path = [[self cacheDirectory] stringByAppendingPathComponent:[[self keyForURL:url] stringByAppendingPathExtension:@"img"]];
    return [[NSFileManager defaultManager] fileExistsAtPath:path] ? path : nil;
}

- (BOOL)hasFailed:(NSString *)url
{
    return [self.failed containsObject:url];
}

- (void)clearCache
{
    [self.memory removeAllObjects];
    [self.failed removeAllObjects];
    [[NSFileManager defaultManager] removeItemAtPath:[self cacheDirectory] error:NULL];
}

- (UIImage *)imageForURL:(NSString *)url
{
    if (!url.length) return nil;
    UIImage *img = self.memory[url];
    if (img) return img;
    NSString *path = [self cachedFilePathForURL:url];
    if (path) {
        img = [ORUtils thumbnailForImageAtPath:path maxPixels:kMaxDisplayPixels];
        if (img) {
            self.memory[url] = img;
            return img;
        }
    }
    if ([self.failed containsObject:url] || [self.loading containsObject:url]) return nil;
    [self.loading addObject:url];
    [self fetchURL:url redirects:0];
    return nil;
}

- (void)finishURL:(NSString *)url data:(NSData *)data
{
    [self.loading removeObject:url];
    if (!data.length) {
        [self.failed addObject:url];
        [[NSNotificationCenter defaultCenter] postNotificationName:ORImageDidLoadNotification object:self userInfo:@{ @"url": url }];
        return;
    }
    NSString *path = [[self cacheDirectory] stringByAppendingPathComponent:[[self keyForURL:url] stringByAppendingPathExtension:@"img"]];
    [data writeToFile:path atomically:YES];
    UIImage *img = [ORUtils thumbnailForImageAtPath:path maxPixels:kMaxDisplayPixels];
    if (!img) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        [self.failed addObject:url];
    } else {
        self.memory[url] = img;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:ORImageDidLoadNotification object:self userInfo:@{ @"url": url }];
}

- (void)fetchURL:(NSString *)original redirects:(NSInteger)redirects
{
    NSString *current = original;
    // Resolve the last hop's URL: we follow redirects manually.
    NSURL *u = [NSURL URLWithString:[self urlForHop:original redirects:redirects]];
    if (!u.host) { [self finishURL:original data:nil]; return; }
    BOOL secure = [[u.scheme lowercaseString] isEqualToString:@"https"];
    NSInteger port = u.port ? [u.port integerValue] : (secure ? 443 : 80);
    NSString *path = u.path.length ? [u.path stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] : @"/";
    if (u.query.length) path = [path stringByAppendingFormat:@"?%@", u.query];

    ORHTTPRequest *req = [ORHTTPRequest requestWithMethod:@"GET" host:u.host path:path];
    req.port = port;
    req.secure = secure;
    req.readTimeout = 40;
    req.headers = @{ @"Accept": @"image/*,*/*;q=0.8", @"User-Agent": @"Mozilla/5.0 (iPad; CPU OS 6_1 like Mac OS X) AIChat" };
    __weak ORImageLoader *weakSelf = self;
    req.onComplete = ^(NSInteger status, NSData *body, NSError *error) {
        ORImageLoader *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (!error && status >= 300 && status < 400 && redirects < kMaxRedirects) {
            NSString *location = req.responseHeaders[@"location"];
            if (location.length) {
                NSURL *next = [NSURL URLWithString:location relativeToURL:u];
                strongSelf.redirectTargets[original] = [next absoluteString] ?: location;
                [strongSelf fetchURL:original redirects:redirects + 1];
                return;
            }
        }
        if (error || status != 200 || body.length == 0 || body.length > kMaxImageBytes) {
            if (error) ORLog(@"Image %@ failed: %@", current, error.localizedDescription);
            [strongSelf finishURL:original data:nil];
            return;
        }
        [strongSelf finishURL:original data:body];
    };
    [req start];
}

- (NSMutableDictionary *)redirectTargets
{
    static NSMutableDictionary *d = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ d = [NSMutableDictionary dictionary]; });
    return d;
}

- (NSString *)urlForHop:(NSString *)original redirects:(NSInteger)redirects
{
    if (redirects == 0) return original;
    return [self redirectTargets][original] ?: original;
}

@end
