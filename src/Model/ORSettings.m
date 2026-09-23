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

@end
