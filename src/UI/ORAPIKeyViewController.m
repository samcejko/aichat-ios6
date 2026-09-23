#import "ORAPIKeyViewController.h"
#import "OROpenRouterClient.h"
#import "ORSettings.h"
#import "ORTheme.h"
#import "ORUtils.h"
#import "ORCommon.h"

@interface ORAPIKeyViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UILabel *intro;
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, strong) UIButton *pasteButton;
@property (nonatomic, strong) UIButton *verifyButton;
@property (nonatomic, strong) UIButton *saveButton;
@property (nonatomic, strong) UIButton *linkButton;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) ORHTTPRequest *request;
@end

@implementation ORAPIKeyViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = L(@"API Key");
    self.contentSizeForViewInPopover = CGSizeMake(420, 420);

    self.scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scroll.alwaysBounceVertical = YES;
    [self.view addSubview:self.scroll];

    self.intro = [[UILabel alloc] initWithFrame:CGRectZero];
    self.intro.numberOfLines = 0;
    self.intro.font = [UIFont systemFontOfSize:15];
    self.intro.backgroundColor = [UIColor clearColor];
    self.intro.text = L(@"Paste your OpenRouter API key. It is stored only on this device and sent directly to openrouter.ai.");
    [self.scroll addSubview:self.intro];

    self.field = [[UITextField alloc] initWithFrame:CGRectZero];
    self.field.borderStyle = UITextBorderStyleRoundedRect;
    self.field.placeholder = @"sk-or-v1-…";
    self.field.font = [UIFont fontWithName:@"Courier" size:14] ?: [UIFont systemFontOfSize:14];
    self.field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.field.autocorrectionType = UITextAutocorrectionTypeNo;
    self.field.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.field.returnKeyType = UIReturnKeyDone;
    self.field.delegate = self;
    self.field.text = [ORSettings shared].apiKey ?: @"";
    [self.scroll addSubview:self.field];

    self.pasteButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [self.pasteButton setTitle:L(@"Paste from clipboard") forState:UIControlStateNormal];
    [self.pasteButton addTarget:self action:@selector(pasteTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.scroll addSubview:self.pasteButton];

    self.verifyButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [self.verifyButton setTitle:L(@"Verify and save") forState:UIControlStateNormal];
    self.verifyButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [self.verifyButton addTarget:self action:@selector(verifyTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.scroll addSubview:self.verifyButton];

    self.saveButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [self.saveButton setTitle:L(@"Save without verifying") forState:UIControlStateNormal];
    [self.saveButton addTarget:self action:@selector(saveTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.scroll addSubview:self.saveButton];

    self.linkButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.linkButton setTitle:L(@"Get a key at openrouter.ai/keys") forState:UIControlStateNormal];
    self.linkButton.titleLabel.font = [UIFont systemFontOfSize:14];
    [self.linkButton addTarget:self action:@selector(linkTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.scroll addSubview:self.linkButton];

    self.status = [[UILabel alloc] initWithFrame:CGRectZero];
    self.status.numberOfLines = 0;
    self.status.font = [UIFont systemFontOfSize:14];
    self.status.backgroundColor = [UIColor clearColor];
    [self.scroll addSubview:self.status];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.hidesWhenStopped = YES;
    [self.scroll addSubview:self.spinner];

    if (!self.onboarding) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelTapped)];
    }
    [self applyTheme];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self applyTheme];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if (!self.field.text.length) [self.field becomeFirstResponder];
}

- (void)applyTheme
{
    ORTheme *t = [ORTheme shared];
    self.view.backgroundColor = [t tableBackgroundColor];
    self.intro.textColor = [t primaryTextColor];
    self.status.textColor = [t secondaryTextColor];
    [self.linkButton setTitleColor:[t accentColor] forState:UIControlStateNormal];
    self.spinner.activityIndicatorViewStyle = t.isDark ? UIActivityIndicatorViewStyleWhite : UIActivityIndicatorViewStyleGray;
    [t applyToNavigationBar:self.navigationController.navigationBar];
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    CGFloat margin = ORIsPad() ? 40 : 16;
    CGFloat cw = w - 2 * margin;
    CGFloat y = 20;
    CGSize introSize = [self.intro.text sizeWithFont:self.intro.font constrainedToSize:CGSizeMake(cw, 400) lineBreakMode:NSLineBreakByWordWrapping];
    self.intro.frame = CGRectMake(margin, y, cw, introSize.height);
    y += introSize.height + 16;
    self.field.frame = CGRectMake(margin, y, cw, 36);
    y += 46;
    self.pasteButton.frame = CGRectMake(margin, y, cw, 40);
    y += 50;
    self.verifyButton.frame = CGRectMake(margin, y, cw, 44);
    y += 54;
    self.saveButton.frame = CGRectMake(margin, y, cw, 40);
    y += 50;
    self.spinner.frame = CGRectMake(margin, y + 2, 20, 20);
    self.status.frame = CGRectMake(margin + 28, y, cw - 28, 80);
    y += 90;
    self.linkButton.frame = CGRectMake(margin, y, cw, 30);
    y += 40;
    self.scroll.contentSize = CGSizeMake(w, y + 20);
}

#pragma mark - Actions

- (void)pasteTapped
{
    NSString *s = [UIPasteboard generalPasteboard].string;
    if (s.length) {
        self.field.text = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [self verifyTapped];
    } else {
        self.status.text = L(@"The clipboard is empty.");
    }
}

- (NSString *)enteredKey
{
    return [self.field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (void)finishSaved
{
    if (self.completion) self.completion(YES);
}

- (void)verifyTapped
{
    NSString *key = [self enteredKey];
    if (!key.length) {
        self.status.text = L(@"Enter a key first.");
        return;
    }
    [self.field resignFirstResponder];
    [self.spinner startAnimating];
    self.status.text = L(@"Verifying…");
    self.verifyButton.enabled = NO;
    self.request = [[OROpenRouterClient shared] fetchKeyInfoWithKey:key completion:^(NSDictionary *info, NSError *error) {
        [self.spinner stopAnimating];
        self.verifyButton.enabled = YES;
        self.request = nil;
        if (error) {
            self.status.text = [NSString stringWithFormat:L(@"Verification failed: %@"), error.localizedDescription];
            return;
        }
        [ORSettings shared].apiKey = key;
        NSString *label = [info[@"label"] isKindOfClass:[NSString class]] ? info[@"label"] : @"";
        [ORSettings shared].apiKeyLabel = label;
        [[ORSettings shared] save];
        NSMutableString *msg = [NSMutableString stringWithString:L(@"Key verified.")];
        if ([info[@"is_free_tier"] boolValue]) [msg appendFormat:@" %@", L(@"Free tier account.")];
        NSDictionary *daily = info[@"free_model_daily_requests"];
        if ([daily isKindOfClass:[NSDictionary class]]) {
            [msg appendFormat:@" %@", [NSString stringWithFormat:L(@"Free requests today: %@ of %@."), daily[@"used"] ?: @"?", daily[@"limit"] ?: @"?"]];
        }
        self.status.text = msg;
        [self performSelector:@selector(finishSaved) withObject:nil afterDelay:0.6];
    }];
}

- (void)saveTapped
{
    NSString *key = [self enteredKey];
    if (!key.length) {
        self.status.text = L(@"Enter a key first.");
        return;
    }
    [ORSettings shared].apiKey = key;
    [[ORSettings shared] save];
    [self finishSaved];
}

- (void)linkTapped
{
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://openrouter.ai/keys"]];
}

- (void)cancelTapped
{
    [self.request cancel];
    if (self.completion) self.completion(NO);
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    [self verifyTapped];
    return YES;
}

@end
