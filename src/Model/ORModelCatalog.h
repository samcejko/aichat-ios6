#import <Foundation/Foundation.h>
#import "ORModelInfo.h"
#import "ORSettings.h"

// In-memory + on-disk cache of the OpenRouter model list.
@interface ORModelCatalog : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) NSArray *models;        // ORModelInfo, sorted by display name
@property (nonatomic, readonly) NSDate *lastUpdated;
@property (nonatomic, readonly) BOOL isRefreshing;
@property (nonatomic, readonly) BOOL hasModels;

- (void)loadCache;
- (void)refreshWithCompletion:(void (^)(NSError *error))completion;
- (void)refreshIfStale;
- (void)clearCache;

- (ORModelInfo *)modelWithId:(NSString *)modelId;
- (NSArray *)filteredModelsFreeOnly:(BOOL)freeOnly imagesOnly:(BOOL)imagesOnly query:(NSString *)query sort:(ORModelSort)sort;
- (ORModelInfo *)suggestedVisionModel;   // a free model with image input
- (ORModelInfo *)suggestedDefaultModel;

@end
