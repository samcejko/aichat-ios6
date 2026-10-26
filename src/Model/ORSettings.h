#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, ORFontSize) {
    ORFontSizeSmall = 0,
    ORFontSizeMedium = 1,
    ORFontSizeLarge = 2,
};

typedef NS_ENUM(NSInteger, ORModelSort) {
    ORModelSortName = 0,
    ORModelSortNewest = 1,
    ORModelSortPrice = 2,
    ORModelSortContext = 3,
};

// All user preferences. Non-secret values live in NSUserDefaults, the API key in the Keychain
// (with an NSUserDefaults fallback because fake-signed apps sometimes get keychain errors).
@interface ORSettings : NSObject

+ (instancetype)shared;
@property (nonatomic, readonly) NSString *providerID;
@property (nonatomic, readonly) NSString *apiBaseURL;
@property (nonatomic, readonly) NSString *apiProtocol;
@property (nonatomic, readonly) NSString *providerIdentity;
@property (nonatomic, readonly) BOOL requiresAPIKey;
@property (nonatomic) BOOL modelAcceptsImages;
- (NSDictionary *)profileForProvider:(NSString *)identifier;
- (NSString *)keyForProvider:(NSString *)identifier baseURL:(NSString *)base protocol:(NSString *)protocol;
- (void)configureProvider:(NSString *)identifier baseURL:(NSString *)base protocol:(NSString *)protocol model:(NSString *)model key:(NSString *)key images:(BOOL)images;


@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, copy) NSString *apiKeyLabel;
- (BOOL)hasAPIKey;

@property (nonatomic, copy) NSString *lastModelId;
@property (nonatomic, copy) NSString *visionModelId;
@property (nonatomic, copy) NSString *systemPrompt;
@property (nonatomic) double temperature;              // < 0 means "model default" (not sent)
@property (nonatomic) NSInteger maxTokens;             // 0 means not sent
@property (nonatomic) BOOL streaming;
@property (nonatomic) BOOL showUsage;
@property (nonatomic) BOOL middleOut;
@property (nonatomic) BOOL darkTheme;
@property (nonatomic) ORFontSize fontSize;
@property (nonatomic) NSInteger imageMaxDimension;     // pixels, longest side
@property (nonatomic, copy) NSString *pdfEngine;       // cloudflare-ai | native | mistral-ocr
@property (nonatomic) BOOL verifyTLS;
@property (nonatomic) BOOL pickerFreeOnly;
@property (nonatomic) BOOL pickerImagesOnly;
@property (nonatomic) ORModelSort pickerSort;
@property (nonatomic) BOOL resumeLastChat;
@property (nonatomic, copy) NSString *lastConversationId;
@property (nonatomic) NSInteger imageHistoryDepth;     // recent user turns that keep raw images in context
@property (nonatomic) NSInteger maxTextAttachmentBytes;
@property (nonatomic, strong) NSDate *lastModelsRefresh;
@property (nonatomic) BOOL showVisionNotes;

// New in 0.2
@property (nonatomic) BOOL webSearch;                       // OpenRouter "web" plugin on every request
@property (nonatomic, copy) NSString *reasoningEffort;      // default | off | low | medium | high
@property (nonatomic) BOOL showReasoning;

// New in 0.2.4
@property (nonatomic) BOOL webSearchWarningHidden;          // "Don't Show Again" on the paid web search alert

// Personas: array of dictionaries { id, name, prompt }. "none" means no system prompt.
@property (nonatomic, strong) NSArray *personas;
@property (nonatomic, copy) NSString *activePersonaId;
- (NSDictionary *)activePersona;
- (NSString *)activeSystemPrompt;
- (void)addOrUpdatePersona:(NSDictionary *)persona;
- (void)removePersonaWithId:(NSString *)personaId;

- (void)save;

@end
