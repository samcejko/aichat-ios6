#import "ORModelInfo.h"
#import "ORUtils.h"
#import "ORCommon.h"

static NSString *ORStr(id v)
{
    if ([v isKindOfClass:[NSString class]]) return v;
    if ([v isKindOfClass:[NSNumber class]]) return [v stringValue];
    return nil;
}

static NSInteger ORInt(id v)
{
    if ([v isKindOfClass:[NSNumber class]] || [v isKindOfClass:[NSString class]]) return [v integerValue];
    return 0;
}

static NSArray *ORStringArray(id v)
{
    if (![v isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (id x in v) if ([x isKindOfClass:[NSString class]]) [out addObject:x];
    return out;
}

@implementation ORModelInfo

+ (instancetype)modelWithJSON:(NSDictionary *)json
{
    if (![json isKindOfClass:[NSDictionary class]]) return nil;
    NSString *mid = ORStr(json[@"id"]);
    if (mid.length == 0) return nil;
    ORModelInfo *m = [[ORModelInfo alloc] init];
    m.modelId = mid;
    m.name = ORStr(json[@"name"]) ?: mid;
    m.modelDescription = ORStr(json[@"description"]) ?: @"";
    m.contextLength = ORInt(json[@"context_length"]);
    m.created = [ORStr(json[@"created"]) doubleValue];

    NSDictionary *pricing = [json[@"pricing"] isKindOfClass:[NSDictionary class]] ? json[@"pricing"] : @{};
    m.promptPrice = ORStr(pricing[@"prompt"]) ?: @"0";
    m.completionPrice = ORStr(pricing[@"completion"]) ?: @"0";
    m.imagePrice = ORStr(pricing[@"image"]);

    NSDictionary *arch = [json[@"architecture"] isKindOfClass:[NSDictionary class]] ? json[@"architecture"] : @{};
    m.inputModalities = ORStringArray(arch[@"input_modalities"]);
    m.outputModalities = ORStringArray(arch[@"output_modalities"]);
    if (m.inputModalities.count == 0) {
        // Older shape: "modality": "text+image->text"
        NSString *modality = ORStr(arch[@"modality"]) ?: @"text->text";
        NSRange arrow = [modality rangeOfString:@"->"];
        NSString *in = arrow.location != NSNotFound ? [modality substringToIndex:arrow.location] : modality;
        NSString *out = arrow.location != NSNotFound ? [modality substringFromIndex:arrow.location + 2] : @"text";
        m.inputModalities = [in componentsSeparatedByString:@"+"];
        m.outputModalities = [out componentsSeparatedByString:@"+"];
    }

    NSDictionary *top = [json[@"top_provider"] isKindOfClass:[NSDictionary class]] ? json[@"top_provider"] : @{};
    m.maxCompletionTokens = ORInt(top[@"max_completion_tokens"]);
    if (m.contextLength == 0) m.contextLength = ORInt(top[@"context_length"]);

    m.supportedParameters = ORStringArray(json[@"supported_parameters"]);
    return m;
}

- (NSDictionary *)toJSON
{
    return @{
        @"id": self.modelId ?: @"",
        @"name": self.name ?: @"",
        @"description": [ORUtils truncate:self.modelDescription ?: @"" to:400],
        @"context_length": @(self.contextLength),
        @"created": @(self.created),
        @"pricing": @{ @"prompt": self.promptPrice ?: @"0", @"completion": self.completionPrice ?: @"0", @"image": self.imagePrice ?: @"" },
        @"architecture": @{ @"input_modalities": self.inputModalities ?: @[], @"output_modalities": self.outputModalities ?: @[] },
        @"top_provider": @{ @"max_completion_tokens": @(self.maxCompletionTokens) },
        @"supported_parameters": self.supportedParameters ?: @[],
    };
}

- (BOOL)isFree
{
    if ([self.modelId hasSuffix:@":free"]) return YES;
    if ([self.modelId isEqualToString:@"openrouter/free"]) return YES;
    if ([self.promptPrice doubleValue] == 0 && [self.completionPrice doubleValue] == 0 && [self supportsTextOutput]) return YES;
    return NO;
}

- (BOOL)isRouter
{
    return [self.promptPrice doubleValue] < 0 || [self.modelId hasPrefix:@"openrouter/"];
}

- (BOOL)supportsImages { return [self.inputModalities containsObject:@"image"]; }
- (BOOL)supportsFiles { return [self.inputModalities containsObject:@"file"]; }
- (BOOL)supportsTextOutput { return self.outputModalities.count == 0 || [self.outputModalities containsObject:@"text"]; }
- (BOOL)supportsParameter:(NSString *)name { return [self.supportedParameters containsObject:name]; }

- (NSString *)displayName
{
    return self.name.length ? self.name : self.modelId;
}

- (NSString *)priceLine
{
    if ([self isFree]) return L(@"Free");
    if ([self.promptPrice doubleValue] < 0) return L(@"Variable price");
    return [NSString stringWithFormat:@"%@ / %@ %@", [ORUtils formatPricePerMillion:self.promptPrice],
            [ORUtils formatPricePerMillion:self.completionPrice], L(@"per 1M tokens")];
}

- (NSString *)detailLine
{
    NSMutableArray *parts = [NSMutableArray array];
    [parts addObject:[NSString stringWithFormat:@"%@ ctx", [ORUtils formatContextLength:self.contextLength]]];
    [parts addObject:[self priceLine]];
    if ([self supportsImages]) [parts addObject:L(@"image")];
    if ([self supportsFiles]) [parts addObject:@"PDF"];
    return [parts componentsJoinedByString:@" · "];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<ORModelInfo %@>", self.modelId];
}

@end
