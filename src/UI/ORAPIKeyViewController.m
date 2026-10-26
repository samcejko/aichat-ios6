#import "ORAPIKeyViewController.h"
#import "ORChoiceViewController.h"
#import "ORProvider.h"
#import "ORSettings.h"
#import "OROpenRouterClient.h"
#import "ORModelCatalog.h"
#import "ORTheme.h"
#import "ORUtils.h"
#import "ORCommon.h"
@interface ORAPIKeyViewController () <UITextFieldDelegate>
@property(nonatomic,strong) UIScrollView *scroll;
@property(nonatomic,strong) UIButton *providerButton,*protocolButton,*saveButton,*testButton;
@property(nonatomic,strong) UITextField *baseField,*keyField,*modelField;
@property(nonatomic,strong) UISwitch *images;
@property(nonatomic,strong) UILabel *intro,*status,*imageLabel;
@property(nonatomic,strong) NSArray *labels;
@property(nonatomic,copy) NSString *draftID,*draftProtocol;
@property(nonatomic,strong) ORHTTPRequest *request;
@end
@implementation ORAPIKeyViewController
- (UITextField *)field:(NSString *)placeholder secure:(BOOL)secure {
 UITextField *f=[[UITextField alloc] initWithFrame:CGRectZero];f.borderStyle=UITextBorderStyleRoundedRect;f.font=[UIFont systemFontOfSize:15];f.placeholder=placeholder;f.secureTextEntry=secure;f.autocorrectionType=UITextAutocorrectionTypeNo;f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.delegate=self;f.returnKeyType=UIReturnKeyDone;[self.scroll addSubview:f];return f;
}
- (UIButton *)button:(NSString *)title action:(SEL)action {UIButton *b=[UIButton buttonWithType:UIButtonTypeRoundedRect];[b setTitle:title forState:UIControlStateNormal];b.titleLabel.font=[UIFont boldSystemFontOfSize:16];[b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];[self.scroll addSubview:b];return b;}
- (UILabel *)label:(NSString *)text {UILabel *l=[[UILabel alloc] initWithFrame:CGRectZero];l.text=text;l.font=[UIFont systemFontOfSize:14];l.backgroundColor=[UIColor clearColor];[self.scroll addSubview:l];return l;}
- (void)viewDidLoad {
 [super viewDidLoad];self.title=L(@"AI provider");self.contentSizeForViewInPopover=CGSizeMake(480,660);self.scroll=[[UIScrollView alloc] initWithFrame:self.view.bounds];self.scroll.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;self.scroll.alwaysBounceVertical=YES;[self.view addSubview:self.scroll];
 self.intro=[self label:L(@"Choose a provider or enter your own API address. Keys stay separate for each provider and address. For local models, use your computer's LAN address instead of 127.0.0.1.")];self.intro.numberOfLines=0;
 self.providerButton=[self button:@"" action:@selector(chooseProvider)];self.protocolButton=[self button:@"" action:@selector(chooseProtocol)];
 self.baseField=[self field:@"https://example.com/v1" secure:NO];self.baseField.keyboardType=UIKeyboardTypeURL;[self.baseField addTarget:self action:@selector(baseChanged) forControlEvents:UIControlEventEditingChanged];
 self.keyField=[self field:L(@"API key (optional for local servers)") secure:YES];self.keyField.accessibilityIdentifier=@"provider.key";
 self.modelField=[self field:L(@"Model ID (or load the list after saving)") secure:NO];
 self.baseField.accessibilityIdentifier=@"provider.base";self.modelField.accessibilityIdentifier=@"provider.model";
 self.labels=@[[self label:L(@"Provider")],[self label:L(@"API base URL")],[self label:L(@"API format")],[self label:L(@"API key")],[self label:L(@"Model ID")]];
 self.images=[[UISwitch alloc] initWithFrame:CGRectZero];[self.scroll addSubview:self.images];self.imageLabel=[self label:L(@"Selected model accepts images")];self.imageLabel.numberOfLines=2;
 self.testButton=[self button:L(@"Test connection and save") action:@selector(testTapped)];self.saveButton=[self button:L(@"Save without testing") action:@selector(saveTapped)];self.status=[self label:L(@"OpenRouter extras (web search, PDF parsing and compression) only work with OpenRouter. Other services use their own billing and model features.")];self.status.numberOfLines=0;
 self.draftID=[ORSettings shared].providerID;[self loadDraft];
 if(!self.onboarding)self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelTapped)];
 ORTheme *theme=[ORTheme shared];self.view.backgroundColor=[theme chatBackgroundColor];[theme applyToNavigationBar:self.navigationController.navigationBar];
}
- (void)viewDidLayoutSubviews {[super viewDidLayoutSubviews];CGFloat w=self.scroll.bounds.size.width,m=18,c=w-2*m,y=12;self.intro.frame=CGRectMake(m,y,c,88);y+=96;NSArray *fields=@[self.providerButton,self.baseField,self.protocolButton,self.keyField,self.modelField];for(NSUInteger i=0;i<fields.count;i++){((UILabel *)self.labels[i]).frame=CGRectMake(m,y,c,20);y+=23;((UIView *)fields[i]).frame=CGRectMake(m,y,c,40);y+=48;}self.images.frame=CGRectMake(m,y,79,31);self.imageLabel.frame=CGRectMake(m+90,y,c-90,35);y+=45;self.testButton.frame=CGRectMake(m,y,c,44);y+=52;self.saveButton.frame=CGRectMake(m,y,c,40);y+=48;self.status.frame=CGRectMake(m,y,c,125);self.scroll.contentSize=CGSizeMake(w,y+145);}
- (void)loadDraft {ORSettings *s=[ORSettings shared];NSDictionary *profile=[s profileForProvider:self.draftID];self.baseField.text=profile[@"baseURL"] ?: @"";self.draftProtocol=profile[@"protocol"] ?: @"openai";self.keyField.text=[s keyForProvider:self.draftID baseURL:self.baseField.text protocol:self.draftProtocol];self.modelField.text=profile[@"model"] ?: @"";self.images.on=[profile[@"images"] boolValue];[self updateTitles];}
- (void)updateTitles {[self.providerButton setTitle:[[ORProvider preset:self.draftID] objectForKey:@"name"] forState:UIControlStateNormal];[self.protocolButton setTitle:[self.draftProtocol isEqual:@"anthropic"]?@"Anthropic Messages":[self.draftProtocol isEqual:@"azure"]?@"Azure OpenAI v1":@"OpenAI Chat Completions" forState:UIControlStateNormal];}
- (void)chooseProvider {if(self.request)return;[self.view endEditing:YES];NSArray *presets=[ORProvider presets];NSMutableArray *titles=[NSMutableArray array];NSInteger selected=0;for(NSDictionary *p in presets){if([p[@"id"] isEqual:self.draftID])selected=titles.count;[titles addObject:p[@"name"]];}ORChoiceViewController *vc=[ORChoiceViewController new];vc.title=L(@"Provider");vc.titles=titles;vc.selectedIndex=selected;vc.completion=^(NSInteger index){self.draftID=[presets[index] objectForKey:@"id"];[self loadDraft];};[self.navigationController pushViewController:vc animated:YES];}
- (void)chooseProtocol {if(self.request)return;ORChoiceViewController *vc=[ORChoiceViewController new];NSArray *values=@[@"openai",@"anthropic",@"azure"];vc.title=L(@"API format");vc.titles=@[@"OpenAI Chat Completions",@"Anthropic Messages",@"Azure OpenAI v1"];vc.selectedIndex=[values indexOfObject:self.draftProtocol];vc.completion=^(NSInteger index){self.draftProtocol=values[index];self.keyField.text=@"";[self updateTitles];};[self.navigationController pushViewController:vc animated:YES];}
- (void)baseChanged {self.keyField.text=@"";}
- (NSDictionary *)validatedDraft {NSError *error=nil;NSString *base=[ORProvider normalizeBaseURL:self.baseField.text error:&error];if(!base){self.status.text=error.localizedDescription;return nil;}NSString *key=[self.keyField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];if([key rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location!=NSNotFound){self.status.text=L(@"The API key cannot contain spaces or line breaks.");return nil;}if([[[ORProvider preset:self.draftID] objectForKey:@"keyRequired"] boolValue]&&!key.length){self.status.text=L(@"Enter a key first.");return nil;}return @{@"id":self.draftID,@"baseURL":base,@"protocol":self.draftProtocol,@"key":key ?: @""};}
- (void)commit:(NSDictionary *)draft {NSString *model=[self.modelField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];[[ORSettings shared] configureProvider:self.draftID baseURL:draft[@"baseURL"] protocol:self.draftProtocol model:model key:draft[@"key"] images:self.images.on];[[ORModelCatalog shared] refreshWithCompletion:nil];if(self.completion)self.completion(YES);}
- (void)saveTapped {if(self.request)return;NSDictionary *draft=[self validatedDraft];if(draft){[self.view endEditing:YES];[self commit:draft];}}
- (void)testTapped {if(self.request)return;NSDictionary *draft=[self validatedDraft];if(!draft)return;[self.view endEditing:YES];BOOL router=[draft[@"id"] isEqual:@"openrouter"]&&[draft[@"baseURL"] isEqual:@"https://openrouter.ai/api/v1"];self.status.text=L(@"Testing…");self.saveButton.enabled=NO;self.testButton.enabled=NO;ORHTTPRequest *r=[ORProvider request:@"GET" suffix:router?@"/key":@"/models" profile:draft key:draft[@"key"]];r.readTimeout=30;r.onComplete=^(NSInteger status,NSData *data,NSError *error){self.request=nil;self.saveButton.enabled=YES;self.testButton.enabled=YES;id json=[ORUtils JSONObjectFromData:data];if(error||status!=200||![json isKindOfClass:[NSDictionary class]]||json[@"error"]){self.status.text=[NSString stringWithFormat:L(@"Connection test failed: %@. You can still save a service that does not list models."),(error ?: [OROpenRouterClient errorFromResponseJSON:json status:status]).localizedDescription];return;}[self commit:draft];};self.request=r;[r start];}
- (void)cancelTapped {[self.request cancel];if(self.completion)self.completion(NO);}
- (BOOL)textFieldShouldReturn:(UITextField *)f {[f resignFirstResponder];return YES;}
@end
