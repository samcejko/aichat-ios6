#import "ORSettings.h"
#import "ORCommon.h"
#import <Security/Security.h>

static NSString * const kKeychainService = @"com.samcejko.aichat";
static NSString * const kKeychainAccount = @"openrouter-api-key";
static NSString * const kFallbackKey     = @"apiKey.fallback";

#define DEF [NSUserDefaults standardUserDefaults]

@interface ORSettings ()
@property (nonatomic, copy) NSString *cachedKey;
@property (nonatomic) BOOL keyLoaded;
@end

@implementation ORSettings

+ (instancetype)shared
{
    static ORSettings *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[ORSettings alloc] init]; });
    return s;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        [DEF registerDefaults:@{
            @"temperature": @(-1.0),
            @"maxTokens": @0,
            @"streaming": @YES,
            @"showUsage": @YES,
            @"middleOut": @YES,
            @"darkTheme": @NO,
            @"fontSize": @(ORFontSizeMedium),
            @"imageMaxDimension": @1024,
            @"pdfEngine": @"cloudflare-ai",
            @"verifyTLS": @YES,
            @"pickerFreeOnly": @YES,
            @"pickerImagesOnly": @NO,
            @"pickerSort": @(ORModelSortName),
            @"resumeLastChat": @NO,
            @"imageHistoryDepth": @3,
            @"maxTextAttachmentBytes": @300000,
            @"showVisionNotes": @YES,
            @"webSearch": @NO,
            @"reasoningEffort": @"default",
            @"showReasoning": @YES,
            @"activePersonaId": @"none",
        }];
    }
    return self;
}

- (void)save
{
    [DEF synchronize];
}

- (void)notify
{
    [[NSNotificationCenter defaultCenter] postNotificationName:ORSettingsDidChangeNotification object:self];
}

#pragma mark - Keychain

- (NSDictionary *)keychainQuery
{
    return @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kKeychainService,
        (__bridge id)kSecAttrAccount: kKeychainAccount,
    };
}

- (NSString *)loadKeyFromKeychain
{
    NSMutableDictionary *q = [[self keychainQuery] mutableCopy];
    q[(__bridge id)kSecReturnData] = @YES;
    q[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)q, &result);
    if (st == errSecSuccess && result) {
        NSData *d = (__bridge_transfer NSData *)result;
        return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    }
    if (st != errSecItemNotFound) ORLog(@"Keychain read failed: %ld", (long)st);
    return nil;
}

- (BOOL)saveKeyToKeychain:(NSString *)key
{
    NSDictionary *q = [self keychainQuery];
    SecItemDelete((__bridge CFDictionaryRef)q);
    if (key.length == 0) return YES;
    NSMutableDictionary *add = [q mutableCopy];
    add[(__bridge id)kSecValueData] = [key dataUsingEncoding:NSUTF8StringEncoding];
    add[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
    OSStatus st = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    if (st != errSecSuccess) ORLog(@"Keychain write failed: %ld", (long)st);
    return st == errSecSuccess;
}

- (NSString *)apiKey
{
    if (!self.keyLoaded) {
        self.keyLoaded = YES;
        NSString *k = [self loadKeyFromKeychain];
        if (k.length == 0) k = [DEF stringForKey:kFallbackKey];
        self.cachedKey = k;
    }
    return self.cachedKey;
}

- (void)setApiKey:(NSString *)apiKey
{
    NSString *trimmed = [apiKey stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    self.cachedKey = trimmed;
    self.keyLoaded = YES;
    if ([self saveKeyToKeychain:trimmed]) {
        [DEF removeObjectForKey:kFallbackKey];
    } else {
        if (trimmed.length) [DEF setObject:trimmed forKey:kFallbackKey];
        else [DEF removeObjectForKey:kFallbackKey];
    }
    [DEF synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:ORAPIKeyDidChangeNotification object:self];
}

- (BOOL)hasAPIKey
{
    return self.apiKey.length > 0;
}

#pragma mark - Simple properties

- (NSString *)apiKeyLabel { return [DEF stringForKey:@"apiKeyLabel"]; }
- (void)setApiKeyLabel:(NSString *)v { [DEF setObject:v forKey:@"apiKeyLabel"]; }

- (NSString *)lastModelId { return [DEF stringForKey:@"lastModelId"]; }
- (void)setLastModelId:(NSString *)v { [DEF setObject:v forKey:@"lastModelId"]; [self notify]; }

- (NSString *)visionModelId { return [DEF stringForKey:@"visionModelId"]; }
- (void)setVisionModelId:(NSString *)v { [DEF setObject:v forKey:@"visionModelId"]; [self notify]; }

- (NSString *)systemPrompt { return [DEF stringForKey:@"systemPrompt"]; }
- (void)setSystemPrompt:(NSString *)v { [DEF setObject:v forKey:@"systemPrompt"]; }

- (double)temperature { return [DEF doubleForKey:@"temperature"]; }
- (void)setTemperature:(double)v { [DEF setDouble:v forKey:@"temperature"]; }

- (NSInteger)maxTokens { return [DEF integerForKey:@"maxTokens"]; }
- (void)setMaxTokens:(NSInteger)v { [DEF setInteger:v forKey:@"maxTokens"]; }

- (BOOL)streaming { return [DEF boolForKey:@"streaming"]; }
- (void)setStreaming:(BOOL)v { [DEF setBool:v forKey:@"streaming"]; }

- (BOOL)showUsage { return [DEF boolForKey:@"showUsage"]; }
- (void)setShowUsage:(BOOL)v { [DEF setBool:v forKey:@"showUsage"]; [self notify]; }

- (BOOL)middleOut { return [DEF boolForKey:@"middleOut"]; }
- (void)setMiddleOut:(BOOL)v { [DEF setBool:v forKey:@"middleOut"]; }

- (BOOL)darkTheme { return [DEF boolForKey:@"darkTheme"]; }
- (void)setDarkTheme:(BOOL)v { [DEF setBool:v forKey:@"darkTheme"]; }

- (ORFontSize)fontSize { return (ORFontSize)[DEF integerForKey:@"fontSize"]; }
- (void)setFontSize:(ORFontSize)v { [DEF setInteger:v forKey:@"fontSize"]; [self notify]; }

- (NSInteger)imageMaxDimension { return [DEF integerForKey:@"imageMaxDimension"]; }
- (void)setImageMaxDimension:(NSInteger)v { [DEF setInteger:v forKey:@"imageMaxDimension"]; }

- (NSString *)pdfEngine { return [DEF stringForKey:@"pdfEngine"] ?: @"cloudflare-ai"; }
- (void)setPdfEngine:(NSString *)v { [DEF setObject:v forKey:@"pdfEngine"]; }

- (BOOL)verifyTLS { return [DEF boolForKey:@"verifyTLS"]; }
- (void)setVerifyTLS:(BOOL)v { [DEF setBool:v forKey:@"verifyTLS"]; }

- (BOOL)pickerFreeOnly { return [DEF boolForKey:@"pickerFreeOnly"]; }
- (void)setPickerFreeOnly:(BOOL)v { [DEF setBool:v forKey:@"pickerFreeOnly"]; }

- (BOOL)pickerImagesOnly { return [DEF boolForKey:@"pickerImagesOnly"]; }
- (void)setPickerImagesOnly:(BOOL)v { [DEF setBool:v forKey:@"pickerImagesOnly"]; }

- (ORModelSort)pickerSort { return (ORModelSort)[DEF integerForKey:@"pickerSort"]; }
- (void)setPickerSort:(ORModelSort)v { [DEF setInteger:v forKey:@"pickerSort"]; }

- (BOOL)resumeLastChat { return [DEF boolForKey:@"resumeLastChat"]; }
- (void)setResumeLastChat:(BOOL)v { [DEF setBool:v forKey:@"resumeLastChat"]; }

- (NSString *)lastConversationId { return [DEF stringForKey:@"lastConversationId"]; }
- (void)setLastConversationId:(NSString *)v { [DEF setObject:v forKey:@"lastConversationId"]; }

- (NSInteger)imageHistoryDepth { return [DEF integerForKey:@"imageHistoryDepth"]; }
- (void)setImageHistoryDepth:(NSInteger)v { [DEF setInteger:v forKey:@"imageHistoryDepth"]; }

- (NSInteger)maxTextAttachmentBytes { return [DEF integerForKey:@"maxTextAttachmentBytes"]; }
- (void)setMaxTextAttachmentBytes:(NSInteger)v { [DEF setInteger:v forKey:@"maxTextAttachmentBytes"]; }

- (NSDate *)lastModelsRefresh { return [DEF objectForKey:@"lastModelsRefresh"]; }
- (void)setLastModelsRefresh:(NSDate *)v { [DEF setObject:v forKey:@"lastModelsRefresh"]; }

- (BOOL)showVisionNotes { return [DEF boolForKey:@"showVisionNotes"]; }
- (void)setShowVisionNotes:(BOOL)v { [DEF setBool:v forKey:@"showVisionNotes"]; [self notify]; }

- (BOOL)webSearch { return [DEF boolForKey:@"webSearch"]; }
- (void)setWebSearch:(BOOL)v { [DEF setBool:v forKey:@"webSearch"]; [self notify]; }

- (BOOL)webSearchWarningHidden { return [DEF boolForKey:@"webSearchWarningHidden"]; }
- (void)setWebSearchWarningHidden:(BOOL)v { [DEF setBool:v forKey:@"webSearchWarningHidden"]; }

- (NSString *)reasoningEffort { return [DEF stringForKey:@"reasoningEffort"] ?: @"default"; }
- (void)setReasoningEffort:(NSString *)v { [DEF setObject:v forKey:@"reasoningEffort"]; }

- (BOOL)showReasoning { return [DEF boolForKey:@"showReasoning"]; }
- (void)setShowReasoning:(BOOL)v { [DEF setBool:v forKey:@"showReasoning"]; [self notify]; }

#pragma mark - Personas

+ (NSArray *)defaultPersonas
{
    return @[
        @{ @"id": @"none", @"name": L(@"No persona"), @"prompt": @"" },
        @{ @"id": @"concise", @"name": L(@"Concise assistant"),
           @"prompt": @"You are a helpful assistant. Answer directly and concisely. Use Markdown only when it helps." },
        @{ @"id": @"translator", @"name": L(@"Translator"),
           @"prompt": @"You are a professional translator between Czech and English. Detect the language of the user's text and translate it into the other language. Output only the translation, keep formatting." },
        @{ @"id": @"coder", @"name": L(@"Programmer"),
           @"prompt": @"You are an expert software engineer. Give precise, working code with short explanations. Prefer complete, runnable examples and mention pitfalls." },
        @{ @"id": @"teacher", @"name": L(@"Teacher"),
           @"prompt": @"You are a patient teacher. Explain step by step in simple language, use concrete examples, and end with a short check question." },
    ];
}

- (NSArray *)personas
{
    NSArray *stored = [DEF arrayForKey:@"personas"];
    if (![stored isKindOfClass:[NSArray class]] || stored.count == 0) {
        NSMutableArray *seed = [[[self class] defaultPersonas] mutableCopy];
        NSString *legacy = [[DEF stringForKey:@"systemPrompt"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (legacy.length) {
            [seed addObject:@{ @"id": @"custom", @"name": L(@"My prompt"), @"prompt": legacy }];
            [DEF setObject:@"custom" forKey:@"activePersonaId"];
        }
        [DEF setObject:seed forKey:@"personas"];
        return seed;
    }
    return stored;
}

- (void)setPersonas:(NSArray *)personas
{
    [DEF setObject:personas ?: @[] forKey:@"personas"];
    [self notify];
}

- (NSString *)activePersonaId { return [DEF stringForKey:@"activePersonaId"] ?: @"none"; }
- (void)setActivePersonaId:(NSString *)v { [DEF setObject:v ?: @"none" forKey:@"activePersonaId"]; [self notify]; }

- (NSDictionary *)activePersona
{
    NSString *pid = self.activePersonaId;
    for (NSDictionary *p in self.personas) {
        if ([p[@"id"] isEqualToString:pid]) return p;
    }
    return nil;
}

- (NSString *)activeSystemPrompt
{
    NSString *prompt = [[self activePersona][@"prompt"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return prompt.length ? prompt : nil;
}

- (void)addOrUpdatePersona:(NSDictionary *)persona
{
    if (!persona[@"id"]) return;
    NSMutableArray *list = [self.personas mutableCopy];
    NSUInteger idx = NSNotFound;
    for (NSUInteger i = 0; i < list.count; i++) {
        if ([list[i][@"id"] isEqualToString:persona[@"id"]]) { idx = i; break; }
    }
    if (idx == NSNotFound) [list addObject:persona];
    else list[idx] = persona;
    [self setPersonas:list];
}

- (void)removePersonaWithId:(NSString *)personaId
{
    if (!personaId || [personaId isEqualToString:@"none"]) return;
    NSMutableArray *list = [NSMutableArray array];
    for (NSDictionary *p in self.personas) if (![p[@"id"] isEqualToString:personaId]) [list addObject:p];
    if ([self.activePersonaId isEqualToString:personaId]) self.activePersonaId = @"none";
    [self setPersonas:list];
}

@end
