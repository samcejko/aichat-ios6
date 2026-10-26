#import "ORSettingsViewController.h"
#import "ORExternalOpen.h"
#import "ORSettings.h"
#import "ORProvider.h"
#import "ORTheme.h"
#import "ORModelCatalog.h"
#import "ORModelPickerViewController.h"
#import "ORAPIKeyViewController.h"
#import "ORPersonaViewController.h"
#import "ORChoiceViewController.h"
#import "OROpenRouterClient.h"
#import "ORTLSSocket.h"
#import "ORStore.h"
#import "ORMessageCell.h"
#import "ORUtils.h"
#import "ORCommon.h"

typedef NS_ENUM(NSInteger, ORSection) {
    ORSectionAccount = 0,
    ORSectionModels,
    ORSectionChat,
    ORSectionAppearance,
    ORSectionAttachments,
    ORSectionAdvanced,
    ORSectionAbout,
    ORSectionCount,
};

@interface ORSettingsViewController () <UIActionSheetDelegate>
@property (nonatomic, strong) NSDictionary *keyInfo;
@property (nonatomic, copy) NSString *keyStatusText;
@property (nonatomic, copy) NSString *connectionTestText;
@property (nonatomic, strong) ORHTTPRequest *testRequest;
@property (nonatomic, strong) NSArray *temperatureValues;
@property (nonatomic, strong) NSArray *maxTokenValues;
@property (nonatomic, strong) NSArray *imageSizeValues;
@end

@implementation ORSettingsViewController

- (instancetype)init
{
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _temperatureValues = @[ @(-1.0), @0.3, @0.7, @1.0, @1.3 ];
        _maxTokenValues = @[ @0, @1024, @4096, @16384 ];
        _imageSizeValues = @[ @512, @1024, @2048 ];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = L(@"Settings");
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(doneTapped)];
    self.keyStatusText = [ORSettings shared].hasAPIKey ? L(@"Tap to check") : L(@"No key");
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self applyTheme];
    [self.tableView reloadData];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if (!self.keyInfo && [ORSettings shared].hasAPIKey) [self refreshKeyInfo];
}

- (void)applyTheme
{
    ORTheme *t = [ORTheme shared];
    [t applyToTableView:self.tableView grouped:YES];
    [t applyToNavigationBar:self.navigationController.navigationBar];
}

- (void)doneTapped
{
    [[ORSettings shared] save];
    if (self.completion) self.completion();
}

#pragma mark - Helpers

- (NSInteger)tagForSection:(NSInteger)section row:(NSInteger)row
{
    return section * 100 + row;
}

- (UISegmentedControl *)segmentedWithItems:(NSArray *)items selected:(NSInteger)selected tag:(NSInteger)tag width:(CGFloat)width
{
    UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:items];
    seg.segmentedControlStyle = UISegmentedControlStyleBar;
    seg.frame = CGRectMake(0, 0, width, 30);
    seg.selectedSegmentIndex = selected;
    seg.tag = tag;
    [seg addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    return seg;
}

- (UISwitch *)switchOn:(BOOL)on tag:(NSInteger)tag
{
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
    sw.on = on;
    sw.tag = tag;
    [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    return sw;
}

- (NSInteger)indexOfNearestValue:(double)value inArray:(NSArray *)values
{
    NSInteger best = 0;
    double bestDiff = 1e18;
    for (NSUInteger i = 0; i < values.count; i++) {
        double d = fabs([values[i] doubleValue] - value);
        if (d < bestDiff) { bestDiff = d; best = (NSInteger)i; }
    }
    return best;
}

- (NSString *)modelNameForId:(NSString *)modelId
{
    if (!modelId.length) return L(@"Not set");
    ORModelInfo *m = [[ORModelCatalog shared] modelWithId:modelId];
    return m ? [m displayName] : modelId;
}

- (NSString *)maskedKey
{
    NSString *k = [ORSettings shared].apiKey;
    if (k.length < 12) return k.length ? @"••••" : L(@"Not set");
    return [NSString stringWithFormat:@"%@…%@", [k substringToIndex:8], [k substringFromIndex:k.length - 4]];
}

- (NSArray *)pdfEngines
{
    return @[ @"cloudflare-ai", @"native", @"mistral-ocr" ];
}

- (NSArray *)reasoningValues
{
    return @[ @"default", @"off", @"low", @"medium", @"high" ];
}

- (NSString *)reasoningTitleForValue:(NSString *)value
{
    if ([value isEqualToString:@"off"]) return L(@"Off");
    if ([value isEqualToString:@"low"]) return L(@"Low");
    if ([value isEqualToString:@"medium"]) return L(@"Medium");
    if ([value isEqualToString:@"high"]) return L(@"High");
    return L(@"Model default");
}

- (NSString *)pdfEngineTitle:(NSString *)engine
{
    if ([engine isEqualToString:@"native"]) return L(@"Native (model reads the PDF)");
    if ([engine isEqualToString:@"mistral-ocr"]) return L(@"Mistral OCR (paid, scans)");
    return L(@"Cloudflare AI (free)");
}

#pragma mark - Network actions

- (void)refreshKeyInfo
{
    NSString *key = [ORSettings shared].apiKey;
    if (!key.length) return;
    self.keyStatusText = L(@"Checking…");
    [self.tableView reloadData];
    [[OROpenRouterClient shared] fetchKeyInfoWithKey:key completion:^(NSDictionary *info, NSError *error) {
        if (error) {
            self.keyStatusText = error.localizedDescription;
        } else {
            self.keyInfo = info;
            NSMutableArray *parts = [NSMutableArray array];
            NSDictionary *daily = info[@"free_model_daily_requests"];
            if ([daily isKindOfClass:[NSDictionary class]]) {
                [parts addObject:[NSString stringWithFormat:L(@"Free today %@/%@"), daily[@"used"] ?: @"?", daily[@"limit"] ?: @"?"]];
            }
            double usage = [info[@"usage"] doubleValue];
            [parts addObject:[NSString stringWithFormat:L(@"$%.2f used"), usage]];
            id limit = info[@"limit"];
            if ([limit isKindOfClass:[NSNumber class]]) [parts addObject:[NSString stringWithFormat:L(@"limit $%.2f"), [limit doubleValue]]];
            if ([info[@"is_free_tier"] boolValue]) [parts addObject:L(@"free tier")];
            self.keyStatusText = [parts componentsJoinedByString:@" · "];
            NSString *label = info[@"label"];
            if ([label isKindOfClass:[NSString class]]) [ORSettings shared].apiKeyLabel = label;
        }
        [self.tableView reloadData];
    }];
}

- (void)runConnectionTest
{
    if (self.testRequest) return;
    self.connectionTestText = L(@"Testing…");
    [self.tableView reloadData];
    NSDate *start = [NSDate date];
    ORHTTPRequest *req = [ORProvider request:@"GET" suffix:@"/models" profile:[ORProvider current] key:[ORSettings shared].apiKey];
    req.readTimeout = 30;
    req.onComplete = ^(NSInteger status, NSData *body, NSError *error) {
        NSTimeInterval dt = -[start timeIntervalSinceNow];
        if (error) {
            self.connectionTestText = error.localizedDescription;
        } else {
            self.connectionTestText = [NSString stringWithFormat:@"HTTP %ld · %.1fs · %@ · %@", (long)status, dt, self.testRequest.tlsInfo ?: @"", [ORUtils formatFileSize:body.length]];
        }
        self.testRequest = nil;
        [self.tableView reloadData];
    };
    self.testRequest = req;
    [req start];
}

#pragma mark - Table structure

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return ORSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch ((ORSection)section) {
        case ORSectionAccount: return 2;
        case ORSectionModels: return 4;
        case ORSectionChat: return 9;
        case ORSectionAppearance: return 2;
        case ORSectionAttachments: return 2;
        case ORSectionAdvanced: return 4;
        case ORSectionAbout: return 5;
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch ((ORSection)section) {
        case ORSectionAccount: return L(@"AI provider");
        case ORSectionModels: return L(@"Models");
        case ORSectionChat: return L(@"Chat");
        case ORSectionAppearance: return L(@"Appearance");
        case ORSectionAttachments: return L(@"Attachments");
        case ORSectionAdvanced: return L(@"Advanced");
        case ORSectionAbout: return L(@"About");
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    switch ((ORSection)section) {
        case ORSectionModels: return L(@"The vision helper describes images for models that cannot see them. Pick a free model with image input.");
        case ORSectionChat: return L(@"Web search adds a paid search plugin (a few cents per request). Reasoning effort only applies to models that support it.");
        case ORSectionAdvanced: return L(@"Turn certificate verification off only if the device clock is wrong or the certificate bundle is outdated.");
        default: return nil;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == ORSectionAccount && indexPath.row == 1) return 56;
    if (indexPath.section == ORSectionAdvanced && indexPath.row == 2) return 56;
    if (indexPath.section == ORSectionChat && indexPath.row == 0) return 56;
    return 44;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    ORSettings *s = [ORSettings shared];
    ORTheme *t = [ORTheme shared];
    NSInteger sec = indexPath.section, row = indexPath.row;
    NSInteger tag = [self tagForSection:sec row:row];
    UITableViewCellStyle style = UITableViewCellStyleValue1;
    if ((sec == ORSectionAccount && row == 1) || (sec == ORSectionAdvanced && row == 2) || (sec == ORSectionChat && row == 0)) style = UITableViewCellStyleSubtitle;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:nil];
    cell.detailTextLabel.numberOfLines = 2;
    cell.detailTextLabel.font = [UIFont systemFontOfSize:style == UITableViewCellStyleSubtitle ? 12 : 15];
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    CGFloat segW = ORIsPad() ? 260 : 190;

    switch ((ORSection)sec) {
        case ORSectionAccount:
            if (row == 0) {
                cell.textLabel.text = L(@"Provider and API key");
                cell.detailTextLabel.text = [[ORProvider preset:s.providerID] objectForKey:@"name"];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            } else {
                cell.textLabel.text = L(@"Key status");
                cell.detailTextLabel.text = self.keyStatusText;
            }
            break;
        case ORSectionModels:
            if (row == 0) {
                cell.textLabel.text = L(@"Default model");
                cell.detailTextLabel.text = [self modelNameForId:s.lastModelId];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            } else if (row == 1) {
                cell.textLabel.text = L(@"Vision helper");
                cell.detailTextLabel.text = [self modelNameForId:s.visionModelId];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            } else if (row == 2) {
                cell.textLabel.text = L(@"PDF engine");
                cell.detailTextLabel.text = [self pdfEngineTitle:s.pdfEngine];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            } else {
                cell.textLabel.text = L(@"Refresh model list");
                ORModelCatalog *c = [ORModelCatalog shared];
                if (c.isRefreshing) cell.detailTextLabel.text = L(@"Loading…");
                else cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu · %@", (unsigned long)c.models.count, c.lastUpdated ? [ORUtils shortDateString:c.lastUpdated] : L(@"never")];
            }
            break;
        case ORSectionChat:
            if (row == 0) {
                cell.textLabel.text = L(@"Persona");
                NSDictionary *p = [s activePersona];
                NSString *prompt = [s activeSystemPrompt];
                cell.detailTextLabel.text = prompt.length ? [NSString stringWithFormat:@"%@ · %@", p[@"name"], [ORUtils truncate:prompt to:60]] : (p[@"name"] ?: L(@"None"));
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            } else if (row == 6) {
                cell.textLabel.text = L(@"Web search");
                cell.accessoryView = [self switchOn:[ORProvider isOpenRouter]&&s.webSearch tag:tag];((UISwitch *)cell.accessoryView).enabled=[ORProvider isOpenRouter];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            } else if (row == 7) {
                cell.textLabel.text = L(@"Reasoning effort");
                cell.detailTextLabel.text = [self reasoningTitleForValue:s.reasoningEffort];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            } else if (row == 8) {
                cell.textLabel.text = L(@"Show reasoning");
                cell.accessoryView = [self switchOn:s.showReasoning tag:tag];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            } else if (row == 1) {
                cell.textLabel.text = L(@"Temperature");
                cell.accessoryView = [self segmentedWithItems:@[ L(@"Auto"), @"0.3", @"0.7", @"1.0", @"1.3" ]
                                                     selected:[self indexOfNearestValue:s.temperature inArray:self.temperatureValues] tag:tag width:segW];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            } else if (row == 2) {
                cell.textLabel.text = L(@"Max tokens");
                cell.accessoryView = [self segmentedWithItems:@[ L(@"Auto"), @"1k", @"4k", @"16k" ]
                                                     selected:[self indexOfNearestValue:s.maxTokens inArray:self.maxTokenValues] tag:tag width:segW];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            } else if (row == 3) {
                cell.textLabel.text = L(@"Stream replies");
                cell.accessoryView = [self switchOn:s.streaming tag:tag];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            } else if (row == 4) {
                cell.textLabel.text = L(@"Show token usage");
                cell.accessoryView = [self switchOn:s.showUsage tag:tag];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            } else {
                cell.textLabel.text = L(@"Context compression");
                cell.accessoryView = [self switchOn:[ORProvider isOpenRouter]&&s.middleOut tag:tag];((UISwitch *)cell.accessoryView).enabled=[ORProvider isOpenRouter];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            }
            break;
        case ORSectionAppearance:
            if (row == 0) {
                cell.textLabel.text = L(@"Theme");
                cell.accessoryView = [self segmentedWithItems:@[ L(@"Light"), L(@"Dark") ] selected:s.darkTheme ? 1 : 0 tag:tag width:ORIsPad() ? 200 : 150];
            } else {
                cell.textLabel.text = L(@"Text size");
                cell.accessoryView = [self segmentedWithItems:@[ L(@"Small"), L(@"Medium"), L(@"Large") ] selected:(NSInteger)s.fontSize tag:tag width:ORIsPad() ? 260 : 200];
            }
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        case ORSectionAttachments:
            if (row == 0) {
                cell.textLabel.text = L(@"Image size");
                cell.accessoryView = [self segmentedWithItems:@[ @"512", @"1024", @"2048" ]
                                                     selected:[self indexOfNearestValue:s.imageMaxDimension inArray:self.imageSizeValues] tag:tag width:ORIsPad() ? 220 : 170];
            } else {
                cell.textLabel.text = L(@"Show image descriptions");
                cell.accessoryView = [self switchOn:s.showVisionNotes tag:tag];
            }
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        case ORSectionAdvanced:
            if (row == 0) {
                cell.textLabel.text = L(@"Verify certificates");
                cell.accessoryView = [self switchOn:s.verifyTLS tag:tag];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            } else if (row == 1) {
                cell.textLabel.text = L(@"Resume last chat on launch");
                cell.accessoryView = [self switchOn:s.resumeLastChat tag:tag];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            } else if (row == 2) {
                cell.textLabel.text = L(@"Connection test");
                cell.detailTextLabel.text = self.connectionTestText ?: L(@"Tap to test TLS to openrouter.ai");
            } else {
                cell.textLabel.text = L(@"Delete all chats");
                cell.textLabel.textColor = [UIColor colorWithRed:0.75 green:0.1 blue:0.1 alpha:1];
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)[[ORStore shared] conversationCount]];
            }
            break;
        case ORSectionAbout:
            if (row == 0) {
                cell.textLabel.text = L(@"Version");
                cell.detailTextLabel.text = [ORUtils appVersion];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            } else if (row == 1) {
                cell.textLabel.text = L(@"Author");
                cell.detailTextLabel.text = @"samcejko";
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            } else if (row == 2) {
                cell.textLabel.text = L(@"Root certificates");
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld", (long)[ORTLSSocket caCertificateCount]];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            } else if (row == 3) {
                cell.textLabel.text = L(@"Get an API key");
                cell.detailTextLabel.text = @"openrouter.ai/keys";
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            } else {
                cell.textLabel.text = L(@"Support the development");
                cell.detailTextLabel.text = @"ko-fi.com/samcejko";
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            }
            break;
        default:
            break;
    }
    UIColor *keepColor = (sec == ORSectionAdvanced && row == 3) ? cell.textLabel.textColor : nil;
    [t styleCell:cell];
    if (keepColor) cell.textLabel.textColor = keepColor;
    return cell;
}

#pragma mark - Controls

- (void)segmentChanged:(UISegmentedControl *)seg
{
    ORSettings *s = [ORSettings shared];
    NSInteger sec = seg.tag / 100, row = seg.tag % 100;
    NSInteger idx = seg.selectedSegmentIndex;
    if (sec == ORSectionChat && row == 1) s.temperature = [self.temperatureValues[idx] doubleValue];
    else if (sec == ORSectionChat && row == 2) s.maxTokens = [self.maxTokenValues[idx] integerValue];
    else if (sec == ORSectionAppearance && row == 0) [[ORTheme shared] setDark:idx == 1];
    else if (sec == ORSectionAppearance && row == 1) { s.fontSize = (ORFontSize)idx; [[ORTheme shared] reloadFromSettings]; }
    else if (sec == ORSectionAttachments && row == 0) s.imageMaxDimension = [self.imageSizeValues[idx] integerValue];
    [s save];
    if (sec == ORSectionAppearance) {
        [ORMessageCell invalidateLayoutCache];
        [self applyTheme];
        [self.tableView reloadData];
    }
}

- (void)switchChanged:(UISwitch *)sw
{
    ORSettings *s = [ORSettings shared];
    NSInteger sec = sw.tag / 100, row = sw.tag % 100;
    if (sec == ORSectionChat && row == 3) s.streaming = sw.on;
    else if (sec == ORSectionChat && row == 4) s.showUsage = sw.on;
    else if (sec == ORSectionChat && row == 5) s.middleOut = sw.on;
    else if (sec == ORSectionChat && row == 6) s.webSearch = sw.on;
    else if (sec == ORSectionChat && row == 8) s.showReasoning = sw.on;
    else if (sec == ORSectionAttachments && row == 1) s.showVisionNotes = sw.on;
    else if (sec == ORSectionAdvanced && row == 0) s.verifyTLS = sw.on;
    else if (sec == ORSectionAdvanced && row == 1) s.resumeLastChat = sw.on;
    [s save];
}

#pragma mark - Selection

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    ORSettings *s = [ORSettings shared];
    NSInteger sec = indexPath.section, row = indexPath.row;

    if (sec == ORSectionAccount && row == 0) {
        ORAPIKeyViewController *vc = [[ORAPIKeyViewController alloc] init];
        vc.completion = ^(BOOL saved) {
            [self.navigationController popViewControllerAnimated:YES];
            if (saved) { self.keyInfo = nil; [self refreshKeyInfo]; }
        };
        [self.navigationController pushViewController:vc animated:YES];
    } else if (sec == ORSectionAccount && row == 1) {
        [self refreshKeyInfo];
    } else if (sec == ORSectionModels && (row == 0 || row == 1)) {
        ORModelPickerViewController *vc = [[ORModelPickerViewController alloc] init];
        vc.forceImagesOnly = (row == 1);
        vc.selectedModelId = row == 0 ? s.lastModelId : s.visionModelId;
        vc.titleText = row == 0 ? L(@"Default model") : L(@"Vision helper");
        vc.completion = ^(ORModelInfo *model) {
            if (model) {
                if (row == 0) s.lastModelId = model.modelId;
                else s.visionModelId = model.modelId;
                [s save];
            }
            [self.navigationController popViewControllerAnimated:YES];
        };
        [self.navigationController pushViewController:vc animated:YES];
    } else if (sec == ORSectionModels && row == 2) {
        ORChoiceViewController *vc = [[ORChoiceViewController alloc] init];
        vc.title = L(@"PDF engine");
        NSMutableArray *titles = [NSMutableArray array];
        for (NSString *e in [self pdfEngines]) [titles addObject:[self pdfEngineTitle:e]];
        vc.titles = titles;
        vc.subtitles = @[ L(@"Text extraction on OpenRouter, no cost."), L(@"Only for models that accept PDF input; billed as tokens."), L(@"OCR for scanned documents, $2 per 1000 pages.") ];
        vc.selectedIndex = (NSInteger)[[self pdfEngines] indexOfObject:s.pdfEngine];
        if (vc.selectedIndex < 0 || vc.selectedIndex == NSNotFound) vc.selectedIndex = 0;
        vc.completion = ^(NSInteger index) {
            s.pdfEngine = [self pdfEngines][index];
            [s save];
        };
        [self.navigationController pushViewController:vc animated:YES];
    } else if (sec == ORSectionModels && row == 3) {
        [[ORModelCatalog shared] refreshWithCompletion:^(NSError *error) {
            [self.tableView reloadData];
            if (error) [ORUtils alertWithTitle:L(@"Could not load models") message:error.localizedDescription];
        }];
        [self.tableView reloadData];
    } else if (sec == ORSectionChat && row == 0) {
        ORPersonaListViewController *vc = [[ORPersonaListViewController alloc] init];
        [self.navigationController pushViewController:vc animated:YES];
    } else if (sec == ORSectionChat && row == 7) {
        ORChoiceViewController *vc = [[ORChoiceViewController alloc] init];
        vc.title = L(@"Reasoning effort");
        NSMutableArray *titles = [NSMutableArray array];
        for (NSString *v in [self reasoningValues]) [titles addObject:[self reasoningTitleForValue:v]];
        vc.titles = titles;
        vc.subtitles = @[ L(@"Let the model decide."), L(@"Disable thinking, faster and cheaper."), L(@"Brief thinking."), L(@"Balanced."), L(@"Deep thinking, slow and expensive.") ];
        NSUInteger idx = [[self reasoningValues] indexOfObject:s.reasoningEffort];
        vc.selectedIndex = idx == NSNotFound ? 0 : (NSInteger)idx;
        vc.completion = ^(NSInteger index) {
            s.reasoningEffort = [self reasoningValues][index];
            [s save];
        };
        [self.navigationController pushViewController:vc animated:YES];
    } else if (sec == ORSectionAdvanced && row == 2) {
        [self runConnectionTest];
    } else if (sec == ORSectionAdvanced && row == 3) {
        UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:L(@"Delete all saved chats and attachments?") delegate:self
                                                  cancelButtonTitle:L(@"Cancel") destructiveButtonTitle:L(@"Delete All") otherButtonTitles:nil];
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        [sheet showFromRect:cell.bounds inView:cell animated:YES];
    } else if (sec == ORSectionAbout && row == 3) {
        [ORExternalOpen presentOpenInForURL:[NSURL URLWithString:@"https://openrouter.ai/keys"] from:self anchor:[tableView cellForRowAtIndexPath:indexPath]];
    } else if (sec == ORSectionAbout && row == 4) {
        [ORExternalOpen presentOpenInForURL:[NSURL URLWithString:@"https://ko-fi.com/samcejko"] from:self anchor:[tableView cellForRowAtIndexPath:indexPath]];
    }
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex != actionSheet.destructiveButtonIndex) return;
    [[ORStore shared] deleteAllConversations];
    [self.tableView reloadData];
    if (self.onHistoryCleared) self.onHistoryCleared();
}

@end
