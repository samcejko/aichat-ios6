#import "ORStore.h"
#import "ORUtils.h"
#import "ORCommon.h"

@interface ORStore ()
@property (nonatomic, strong) NSMutableArray *index;   // mutable dictionaries
@property (nonatomic) dispatch_queue_t ioQueue;
@end

@implementation ORStore

+ (instancetype)shared
{
    static ORStore *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[ORStore alloc] init]; });
    return s;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _ioQueue = dispatch_queue_create("com.samcejko.aichat.store", DISPATCH_QUEUE_SERIAL);
        [self loadIndex];
    }
    return self;
}

- (NSString *)indexPath
{
    return [[ORUtils chatsPath] stringByAppendingPathComponent:@"index.json"];
}

- (NSString *)pathForConversation:(NSString *)conversationId
{
    return [[ORUtils chatsPath] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.json", conversationId]];
}

- (void)loadIndex
{
    NSData *data = [NSData dataWithContentsOfFile:[self indexPath]];
    id json = [ORUtils JSONObjectFromData:data];
    NSMutableArray *idx = [NSMutableArray array];
    if ([json isKindOfClass:[NSArray class]]) {
        for (id item in json) {
            if ([item isKindOfClass:[NSDictionary class]] && item[@"id"]) [idx addObject:[item mutableCopy]];
        }
    } else {
        // Rebuild from files if the index is missing/corrupt.
        NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[ORUtils chatsPath] error:NULL];
        for (NSString *f in files) {
            if (![f hasSuffix:@".json"] || [f isEqualToString:@"index.json"]) continue;
            ORConversation *c = [self loadConversation:[f stringByDeletingPathExtension]];
            if (c && !c.isEmpty) [idx addObject:[[self summaryForConversation:c] mutableCopy]];
        }
    }
    self.index = idx;
    [self sortIndex];
}

- (void)sortIndex
{
    [self.index sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        double ua = [a[@"updated"] doubleValue], ub = [b[@"updated"] doubleValue];
        if (ua == ub) return NSOrderedSame;
        return ua > ub ? NSOrderedAscending : NSOrderedDescending;
    }];
}

- (NSDictionary *)summaryForConversation:(ORConversation *)c
{
    [c updateTitleIfNeeded];
    return @{
        @"id": c.conversationId,
        @"title": c.title ?: L(@"New chat"),
        @"updated": @([c.updatedAt timeIntervalSince1970]),
        @"model": c.modelId ?: @"",
        @"preview": [c preview],
        @"count": @(c.messages.count),
    };
}

- (void)writeIndex
{
    NSData *data = [ORUtils JSONDataFromObject:self.index];
    NSString *path = [self indexPath];
    dispatch_async(self.ioQueue, ^{
        [data writeToFile:path atomically:YES];
    });
}

- (NSArray *)conversationSummaries
{
    return [self.index copy];
}

- (NSUInteger)conversationCount
{
    return self.index.count;
}

- (ORConversation *)loadConversation:(NSString *)conversationId
{
    if (!conversationId) return nil;
    NSData *data = [NSData dataWithContentsOfFile:[self pathForConversation:conversationId]];
    return [ORConversation conversationFromJSON:[ORUtils JSONObjectFromData:data]];
}

- (void)saveConversation:(ORConversation *)conversation
{
    if (!conversation || conversation.isEmpty) return;
    conversation.updatedAt = [NSDate date];
    NSDictionary *summary = [self summaryForConversation:conversation];
    NSData *data = [ORUtils JSONDataFromObject:[conversation toJSON]];
    NSString *path = [self pathForConversation:conversation.conversationId];
    dispatch_async(self.ioQueue, ^{
        [data writeToFile:path atomically:YES];
    });

    NSInteger existing = NSNotFound;
    for (NSUInteger i = 0; i < self.index.count; i++) {
        if ([self.index[i][@"id"] isEqualToString:conversation.conversationId]) { existing = i; break; }
    }
    if (existing != NSNotFound) [self.index removeObjectAtIndex:existing];
    [self.index insertObject:[summary mutableCopy] atIndex:0];
    [self writeIndex];
}

- (void)deleteConversation:(NSString *)conversationId
{
    if (!conversationId) return;
    ORConversation *c = [self loadConversation:conversationId];
    for (ORMessage *m in c.messages) {
        for (ORAttachment *a in m.attachments) [a deleteFile];
    }
    [[NSFileManager defaultManager] removeItemAtPath:[self pathForConversation:conversationId] error:NULL];
    NSMutableArray *keep = [NSMutableArray array];
    for (NSDictionary *d in self.index) if (![d[@"id"] isEqualToString:conversationId]) [keep addObject:d];
    self.index = keep;
    [self writeIndex];
}

- (void)deleteAllConversations
{
    NSArray *ids = [self.index valueForKey:@"id"];
    for (NSString *cid in ids) [self deleteConversation:cid];
    // Remove any orphaned attachment files as well.
    NSString *dir = [ORUtils attachmentsPath];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL];
    for (NSString *f in files) {
        [[NSFileManager defaultManager] removeItemAtPath:[dir stringByAppendingPathComponent:f] error:NULL];
    }
}

@end
