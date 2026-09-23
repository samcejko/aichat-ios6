#import <Foundation/Foundation.h>

// One entry of GET /api/v1/models, trimmed to what the app needs.
@interface ORModelInfo : NSObject

@property (nonatomic, copy) NSString *modelId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *modelDescription;
@property (nonatomic, copy) NSString *promptPrice;       // USD per token, as string ("0", "-1", "0.0000025"); nil when unknown
@property (nonatomic, copy) NSString *completionPrice;
@property (nonatomic, copy) NSString *imagePrice;
@property (nonatomic, copy) NSString *requestPrice;
@property (nonatomic) NSInteger contextLength;
@property (nonatomic) NSInteger maxCompletionTokens;
@property (nonatomic) NSTimeInterval created;
@property (nonatomic, strong) NSArray *inputModalities;   // "text","image","file","audio","video"
@property (nonatomic, strong) NSArray *outputModalities;
@property (nonatomic, strong) NSArray *supportedParameters;

+ (instancetype)modelWithJSON:(NSDictionary *)json;
- (NSDictionary *)toJSON;   // trimmed dictionary suitable for the cache file

- (BOOL)isFree;
- (BOOL)isRouter;
- (BOOL)supportsImages;
- (BOOL)supportsFiles;
- (BOOL)supportsTextOutput;
- (BOOL)supportsParameter:(NSString *)name;

- (NSString *)displayName;    // name, or id when name is missing
- (NSString *)detailLine;     // "128k ctx · $2.50 / $10 per 1M · image"
- (NSString *)priceLine;

@end
