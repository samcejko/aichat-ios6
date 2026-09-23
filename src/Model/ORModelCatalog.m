#import "ORModelCatalog.h"
#import "ORUtils.h"
#import "ORCommon.h"
#import "OROpenRouterClient.h"

static const NSTimeInterval kStaleInterval = 12 * 60 * 60;

@interface ORModelCatalog ()
@property (nonatomic, strong) NSArray *models;
@property (nonatomic, strong) NSDate *lastUpdated;
@property (nonatomic) BOOL isRefreshing;
@property (nonatomic, strong) NSDictionary *byId;
@property (nonatomic, strong) NSMutableArray *pendingCompletions;
@end

@implementation ORModelCatalog

+ (instancetype)shared
{
    static ORModelCatalog *c = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ c = [[ORModelCatalog alloc] init]; });
    return c;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _models = @[];
        _byId = @{};
        _pendingCompletions = [NSMutableArray array];
    }
    return self;
}

- (NSString *)cacheFile
{
    return [[ORUtils cachesPath] stringByAppendingPathComponent:@"models.json"];
}

- (BOOL)hasModels
{
    return self.models.count > 0;
}

- (void)setModelsFromJSONArray:(NSArray *)array
{
    NSMutableArray *list = [NSMutableArray arrayWithCapacity:array.count];
    NSMutableDictionary *map = [NSMutableDictionary dictionaryWithCapacity:array.count];
    for (id item in array) {
        ORModelInfo *m = [ORModelInfo modelWithJSON:item];
        if (!m) continue;
        [list addObject:m];
        map[m.modelId] = m;
    }
    [list sortUsingComparator:^NSComparisonResult(ORModelInfo *a, ORModelInfo *b) {
        return [[a displayName] compare:[b displayName] options:NSCaseInsensitiveSearch];
    }];
    self.models = list;
    self.byId = map;
}

- (void)loadCache
{
    NSData *data = [NSData dataWithContentsOfFile:[self cacheFile]];
    id json = [ORUtils JSONObjectFromData:data];
    if ([json isKindOfClass:[NSDictionary class]]) {
        NSArray *arr = json[@"data"];
        if ([arr isKindOfClass:[NSArray class]]) {
            [self setModelsFromJSONArray:arr];
            NSNumber *ts = json[@"updated"];
            if ([ts isKindOfClass:[NSNumber class]]) self.lastUpdated = [NSDate dateWithTimeIntervalSince1970:[ts doubleValue]];
            ORLog(@"Loaded %lu models from cache", (unsigned long)self.models.count);
        }
    }
}

- (void)writeCache
{
    NSMutableArray *arr = [NSMutableArray arrayWithCapacity:self.models.count];
    for (ORModelInfo *m in self.models) [arr addObject:[m toJSON]];
    NSDictionary *doc = @{ @"data": arr, @"updated": @([self.lastUpdated timeIntervalSince1970]) };
    NSData *data = [ORUtils JSONDataFromObject:doc];
    NSString *file = [self cacheFile];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        [data writeToFile:file atomically:YES];
    });
}

- (void)clearCache
{
    [[NSFileManager defaultManager] removeItemAtPath:[self cacheFile] error:NULL];
    self.lastUpdated = nil;
}

- (void)refreshIfStale
{
    if (self.isRefreshing) return;
    if (!self.hasModels || !self.lastUpdated || -[self.lastUpdated timeIntervalSinceNow] > kStaleInterval) {
        [self refreshWithCompletion:nil];
    }
}

- (void)refreshWithCompletion:(void (^)(NSError *))completion
{
    if (completion) [self.pendingCompletions addObject:[completion copy]];
    if (self.isRefreshing) return;
    self.isRefreshing = YES;
    [[OROpenRouterClient shared] fetchModels:^(NSArray *modelsJSON, NSError *error) {
        self.isRefreshing = NO;
        if (!error && modelsJSON.count > 0) {
            [self setModelsFromJSONArray:modelsJSON];
            self.lastUpdated = [NSDate date];
            [ORSettings shared].lastModelsRefresh = self.lastUpdated;
            [self writeCache];
            [[NSNotificationCenter defaultCenter] postNotificationName:ORModelsDidUpdateNotification object:self];
        } else if (!error) {
            error = ORMakeError(ORErrorBadResponse, L(@"The model list was empty."));
        }
        NSArray *pending = [self.pendingCompletions copy];
        [self.pendingCompletions removeAllObjects];
        for (void (^cb)(NSError *) in pending) cb(error);
    }];
}

- (ORModelInfo *)modelWithId:(NSString *)modelId
{
    if (!modelId) return nil;
    return self.byId[modelId];
}

- (NSArray *)filteredModelsFreeOnly:(BOOL)freeOnly imagesOnly:(BOOL)imagesOnly query:(NSString *)query sort:(ORModelSort)sort
{
    NSString *q = [[query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    NSMutableArray *out = [NSMutableArray array];
    for (ORModelInfo *m in self.models) {
        if (![m supportsTextOutput]) continue;
        if (freeOnly && ![m isFree]) continue;
        if (imagesOnly && ![m supportsImages]) continue;
        if (q.length) {
            BOOL hit = [[m.modelId lowercaseString] rangeOfString:q].location != NSNotFound ||
                       [[m.name lowercaseString] rangeOfString:q].location != NSNotFound;
            if (!hit) continue;
        }
        [out addObject:m];
    }
    switch (sort) {
        case ORModelSortNewest:
            [out sortUsingComparator:^NSComparisonResult(ORModelInfo *a, ORModelInfo *b) {
                if (a.created == b.created) return [[a displayName] compare:[b displayName] options:NSCaseInsensitiveSearch];
                return a.created > b.created ? NSOrderedAscending : NSOrderedDescending;
            }];
            break;
        case ORModelSortPrice:
            [out sortUsingComparator:^NSComparisonResult(ORModelInfo *a, ORModelInfo *b) {
                double pa = [a.promptPrice doubleValue] + [a.completionPrice doubleValue];
                double pb = [b.promptPrice doubleValue] + [b.completionPrice doubleValue];
                if (pa < 0) pa = 1e9;
                if (pb < 0) pb = 1e9;
                if (pa == pb) return [[a displayName] compare:[b displayName] options:NSCaseInsensitiveSearch];
                return pa < pb ? NSOrderedAscending : NSOrderedDescending;
            }];
            break;
        case ORModelSortContext:
            [out sortUsingComparator:^NSComparisonResult(ORModelInfo *a, ORModelInfo *b) {
                if (a.contextLength == b.contextLength) return [[a displayName] compare:[b displayName] options:NSCaseInsensitiveSearch];
                return a.contextLength > b.contextLength ? NSOrderedAscending : NSOrderedDescending;
            }];
            break;
        default:
            break; // already sorted by name
    }
    return out;
}

- (ORModelInfo *)suggestedVisionModel
{
    // Prefer well known free vision families, then any free model with image input, then any vision model.
    NSArray *preferred = @[ @"google/gemma", @"qwen/qwen", @"meta-llama/llama", @"mistralai/", @"nvidia/", @"openrouter/free" ];
    NSArray *freeVision = [self filteredModelsFreeOnly:YES imagesOnly:YES query:nil sort:ORModelSortContext];
    for (NSString *prefix in preferred) {
        for (ORModelInfo *m in freeVision) {
            if ([m.modelId hasPrefix:prefix] && ![m isRouter]) return m;
        }
    }
    for (ORModelInfo *m in freeVision) if (![m isRouter]) return m;
    if (freeVision.count) return freeVision[0];
    NSArray *anyVision = [self filteredModelsFreeOnly:NO imagesOnly:YES query:nil sort:ORModelSortName];
    return anyVision.count ? anyVision[0] : nil;
}

- (ORModelInfo *)suggestedDefaultModel
{
    NSArray *free = [self filteredModelsFreeOnly:YES imagesOnly:NO query:nil sort:ORModelSortContext];
    for (ORModelInfo *m in free) if (![m isRouter]) return m;
    return self.models.count ? self.models[0] : nil;
}

@end
