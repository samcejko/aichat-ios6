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
    NSString *mid = ORStr([json objectForKey:@"id"]);
    if (mid.length == 0) return nil;
    ORModelInfo *m = [[ORModelInfo alloc] init];
    m.modelId = mid;
    m.name = ORStr([json objectForKey:@"name"]) ?: mid;
    m.modelDescription = ORStr([json objectForKey:@"description"]) ?: @"";
    m.contextLength = ORInt([json objectForKey:@"context_length"]);
    m.created = [ORStr([json objectForKey:@"created"]) doubleValue];

    NSDictionary *pricing = [[json objectForKey:@"pricing"] isKindOfClass:[NSDictionary class]] ? [json objectForKey:@"pricing"] : @{};
    NSString *(^price)(id) = ^NSString *(id v) {
        NSString *s = ORStr(v);
        return s.length ? s : nil;
    };
    m.promptPrice = price([pricing objectForKey:@"prompt"]);
    m.completionPrice = price([pricing objectForKey:@"completion"]);
    m.imagePrice = price([pricing objectForKey:@"image"]);
    m.requestPrice = price([pricing objectForKey:@"request"]);

    NSDictionary *arch = [[json objectForKey:@"architecture"] isKindOfClass:[NSDictionary class]] ? [json objectForKey:@"architecture"] : @{};
    m.inputModalities = ORStringArray([arch objectForKey:@"input_modalities"]);
    m.outputModalities = ORStringArray([arch objectForKey:@"output_modalities"]);
    if (m.inputModalities.count == 0) {
        // Older shape: "modality": "text+image->text"
        NSString *modality = ORStr([arch objectForKey:@"modality"]) ?: @"text->text";
        NSRange arrow = [modality rangeOfString:@"->"];
        NSString *in = arrow.location != NSNotFound ? [modality substringToIndex:arrow.location] : modality;
        NSString *out = arrow.location != NSNotFound ? [modality substringFromIndex:arrow.location + 2] : @"text";
        m.inputModalities = [in componentsSeparatedByString:@"+"];
        m.outputModalities = [out componentsSeparatedByString:@"+"];
    }

    NSDictionary *top = [[json objectForKey:@"top_provider"] isKindOfClass:[NSDictionary class]] ? [json objectForKey:@"top_provider"] : @{};
    m.maxCompletionTokens = ORInt([top objectForKey:@"max_completion_tokens"]);
    if (m.contextLength == 0) m.contextLength = ORInt([top objectForKey:@"context_length"]);

    m.supportedParameters = ORStringArray([json objectForKey:@"supported_parameters"]);
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
        @"pricing": @{ @"prompt": self.promptPrice ?: @"", @"completion": self.completionPrice ?: @"", @"image": self.imagePrice ?: @"", @"request": self.requestPrice ?: @"" },
        @"architecture": @{ @"input_modalities": self.inputModalities ?: @[], @"output_modalities": self.outputModalities ?: @[] },
        @"top_provider": @{ @"max_completion_tokens": @(self.maxCompletionTokens) },
        @"supported_parameters": self.supportedParameters ?: @[],
    };
}

- (BOOL)isFree
{
    if ([self.modelId hasSuffix:@":free"]) return YES;
    if ([self.modelId isEqualToString:@"openrouter/free"]) return YES;
    if (!self.promptPrice || !self.completionPrice) return NO;          // unknown pricing is not "free"
    if ([self.promptPrice doubleValue] != 0 || [self.completionPrice doubleValue] != 0) return NO;
    if (self.requestPrice && [self.requestPrice doubleValue] != 0) return NO;
    if (self.imagePrice && [self.imagePrice doubleValue] != 0 && [self supportsImages]) return NO;
    return [self supportsTextOutput];
}

- (BOOL)isRouter
{
    return (self.promptPrice && [self.promptPrice doubleValue] < 0) || [self.modelId hasPrefix:@"openrouter/"];
}

- (BOOL)supportsImages { return [self.inputModalities containsObject:@"image"]; }
- (BOOL)supportsFiles { return [self.inputModalities containsObject:@"file"]; }
- (BOOL)supportsTextOutput { return self.outputModalities.count == 0 || [self.outputModalities containsObject:@"text"]; }
- (BOOL)supportsImageOutput { return [self.outputModalities containsObject:@"image"]; }
- (BOOL)supportsParameter:(NSString *)name { return [self.supportedParameters containsObject:name]; }

- (NSString *)displayName
{
    return self.name.length ? self.name : self.modelId;
}

- (NSString *)priceLine
{
    if ([self isFree]) return L(@"Free");
    if (!self.promptPrice || [self.promptPrice doubleValue] < 0) return L(@"Variable price");
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
    if ([self supportsImageOutput]) [parts addObject:L(@"image out")];
    if ([self supportsParameter:@"reasoning"]) [parts addObject:L(@"reasoning")];
    return [parts componentsJoinedByString:@" · "];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<ORModelInfo %@>", self.modelId];
}

@end
