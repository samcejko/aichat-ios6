#import "ORChatViewController.h"
#import "ORChatEngine.h"
#import "ORMessageCell.h"
#import "ORInputBar.h"
#import "ORModelPickerViewController.h"
#import "ORHistoryViewController.h"
#import "ORSettingsViewController.h"
#import "ORAPIKeyViewController.h"
#import "ORFileBrowserViewController.h"
#import "ORPersonaViewController.h"
#import "ORPhotoPickerViewController.h"
#import "ORImageViewerViewController.h"
#import "ORImageLoader.h"
#import "ORModelCatalog.h"
#import "ORSettings.h"
#import "ORProvider.h"
#import "ORStore.h"
#import "ORTheme.h"
#import "ORUtils.h"
#import "ORModern.h"
#import "ORCommon.h"
#import <QuickLook/QuickLook.h>
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 140000
// iOS 14 and newer (the arm64 build): the system's multi-select photo picker, no photo permission needed
#import <PhotosUI/PhotosUI.h>
#endif

static NSString * const kCellId = @"msg";
static const NSInteger kWebSearchAlertTag = 4201;

@interface ORChatViewController () <UITableViewDataSource, UITableViewDelegate, ORChatEngineDelegate, ORMessageCellDelegate,
                                    ORInputBarDelegate, UIActionSheetDelegate, UIAlertViewDelegate, UIImagePickerControllerDelegate,
                                    UINavigationControllerDelegate, UIPopoverControllerDelegate, QLPreviewControllerDataSource
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 140000
                                    , PHPickerViewControllerDelegate
#endif
                                    >
@property (nonatomic, strong) ORChatEngine *engine;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) ORInputBar *inputBar;
@property (nonatomic, strong) UIButton *modelButton;
@property (nonatomic, strong) ORModelInfo *currentModel;
@property (nonatomic, strong) NSMutableArray *pendingAttachments;
@property (nonatomic, strong) UIPopoverController *popover;
@property (nonatomic) CGFloat keyboardOverlap;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic) BOOL keyPromptShown;
@property (nonatomic) BOOL autoPickerShown;
@property (nonatomic, strong) NSURL *previewURL;
@property (nonatomic, strong) UIActivityIndicatorView *navSpinner;
@property (nonatomic) BOOL historyClearedWhileInSettings;
@end

@implementation ORChatViewController

- (instancetype)init
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _pendingAttachments = [NSMutableArray array];
        _engine = [[ORChatEngine alloc] init];
        _engine.delegate = self;
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [[ORTheme shared] chatBackgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.backgroundColor = [UIColor clearColor];
    [self.tableView registerClass:[ORMessageCell class] forCellReuseIdentifier:kCellId];
    [self.view addSubview:self.tableView];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(backgroundTapped)];
    tap.cancelsTouchesInView = NO;
    [self.tableView addGestureRecognizer:tap];

    self.emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.font = [UIFont systemFontOfSize:16];
    self.emptyLabel.backgroundColor = [UIColor clearColor];
    self.emptyLabel.text = L(@"Ask anything.\nTap + to attach photos or files.");
    self.emptyLabel.userInteractionEnabled = NO;
    [self.view addSubview:self.emptyLabel];

    self.inputBar = [[ORInputBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    self.inputBar.delegate = self;
    self.inputBar.webSearchOn = [ORProvider isOpenRouter] && [ORSettings shared].webSearch;
    self.inputBar.attachments = [self.pendingAttachments copy];
    [self.view addSubview:self.inputBar];

    self.modelButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.modelButton.titleLabel.font = [UIFont boldSystemFontOfSize:ORIsPad() ? 17 : 15];
    self.modelButton.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.modelButton.titleLabel.shadowOffset = CGSizeMake(0, -1);
    [self.modelButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.modelButton setTitleShadowColor:[UIColor colorWithWhite:0 alpha:0.5] forState:UIControlStateNormal];
    [self.modelButton addTarget:self action:@selector(modelTapped) forControlEvents:UIControlEventTouchUpInside];
    self.navigationItem.titleView = self.modelButton;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemBookmarks target:self action:@selector(historyTapped)];
    UIBarButtonItem *settings = [[UIBarButtonItem alloc] initWithTitle:L(@"Settings") style:UIBarButtonItemStyleBordered target:self action:@selector(settingsTapped)];
    UIBarButtonItem *compose = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose target:self action:@selector(newChatTapped)];
    self.navigationItem.rightBarButtonItems = @[ compose, settings ];

    self.navSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.navSpinner.hidesWhenStopped = YES;

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(keyboardWillChangeFrame:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [nc addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
    [nc addObserver:self selector:@selector(themeChanged) name:ORThemeDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(modelsUpdated) name:ORModelsDidUpdateNotification object:nil];
    [nc addObserver:self selector:@selector(settingsChanged) name:ORSettingsDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(apiKeyChanged) name:ORAPIKeyDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(remoteImageLoaded:) name:ORImageDidLoadNotification object:nil];

    [self startConversationResuming:YES];
    [self updateModelFromSettings];
    [self applyTheme];
    if ([ORSettings shared].hasAPIKey) [[ORModelCatalog shared] refreshIfStale];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[ORTheme shared] applyToNavigationBar:self.navigationController.navigationBar];
    [self verifyConversationExists];
    [self updateModelButton];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if (![ORSettings shared].hasAPIKey) {
        if (!self.keyPromptShown) {
            self.keyPromptShown = YES;
            [self presentKeyEntryOnboarding:YES];
        }
        return;
    }
    [self maybeAutoPresentPicker];
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    [self layoutChrome];
}

- (void)layoutChrome
{
    CGRect b = self.view.bounds;
    // the notch and the home indicator (iOS 11+): the composer keeps clear of them unless the keyboard covers them
    UIEdgeInsets safe = ORSafeAreaInsets(self.view);
    self.inputBar.safeInsets = UIEdgeInsetsMake(0, safe.left, self.keyboardOverlap > 0 ? 0 : safe.bottom, safe.right);
    CGFloat inputH = [self.inputBar preferredHeight];
    CGFloat bottom = b.size.height - self.keyboardOverlap;
    self.inputBar.frame = CGRectMake(0, bottom - inputH, b.size.width, inputH);
    CGRect tf = CGRectMake(0, 0, b.size.width, bottom - inputH);
    if (!CGRectEqualToRect(self.tableView.frame, tf)) self.tableView.frame = tf;
    self.emptyLabel.frame = CGRectMake(24 + safe.left, tf.size.height * 0.35, tf.size.width - 48 - safe.left - safe.right, 80);
}

// The width the message cells lay out in: on iOS 11+ the table keeps the cells' content clear of the notch itself
- (CGFloat)messageLayoutWidth
{
    UIEdgeInsets safe = ORSafeAreaInsets(self.tableView);
    return self.tableView.bounds.size.width - safe.left - safe.right;
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    [super willAnimateRotationToInterfaceOrientation:toInterfaceOrientation duration:duration];
    [ORMessageCell invalidateLayoutCache];
    [self layoutChrome];
    [self.tableView reloadData];
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];
    [self scrollToBottomAnimated:NO];
}

#pragma mark - Theme

- (void)applyTheme
{
    ORTheme *t = [ORTheme shared];
    self.view.backgroundColor = [t chatBackgroundColor];
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.indicatorStyle = t.isDark ? UIScrollViewIndicatorStyleWhite : UIScrollViewIndicatorStyleDefault;
    self.emptyLabel.textColor = [t secondaryTextColor];
    [self.inputBar applyTheme];
    [t applyToNavigationBar:self.navigationController.navigationBar];
    [[UIApplication sharedApplication] setStatusBarStyle:[t statusBarStyle] animated:NO];
    [ORMessageCell invalidateLayoutCache];
    [self.tableView reloadData];
    [self.view setNeedsLayout];
}

- (void)themeChanged
{
    [self applyTheme];
}

- (void)settingsChanged
{
    [ORMessageCell invalidateLayoutCache];
    [self.tableView reloadData];
    [self updateModelFromSettings];
    self.inputBar.webSearchOn = [ORProvider isOpenRouter] && [ORSettings shared].webSearch;
}

- (void)cancelActiveRequest
{
    [self.engine cancel];
}

- (void)remoteImageLoaded:(NSNotification *)n
{
    // Image heights are only known after download: recompute layouts and refresh.
    BOOL wasNear = [self isNearBottom];
    [ORMessageCell invalidateLayoutCache];
    [self.tableView reloadData];
    if (wasNear) [self scrollToBottomAnimated:NO];
}

- (void)messageCell:(ORMessageCell *)cell didTapImageURL:(NSString *)url
{
    UIImage *img = [[ORImageLoader shared] imageForURL:url];
    if (!img) return;
    ORImageViewerViewController *vc = [[ORImageViewerViewController alloc] init];
    vc.image = img;
    vc.title = [url lastPathComponent];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - Conversation

- (ORConversation *)conversation
{
    return self.engine.conversation;
}

- (void)startConversationResuming:(BOOL)resume
{
    ORSettings *s = [ORSettings shared];
    ORConversation *c = nil;
    if (resume && s.resumeLastChat && s.lastConversationId.length) c = [[ORStore shared] loadConversation:s.lastConversationId];
    if (!c) c = [ORConversation newConversation];
    self.engine.conversation = c;
    s.lastConversationId = c.conversationId;
    if (c.modelId) {
        ORModelInfo *m = [[ORModelCatalog shared] modelWithId:c.modelId];
        if (m) { self.currentModel = m; }
    }
    [self.tableView reloadData];
    [self updateEmptyState];
    [self updateModelButton];
    [self scrollToBottomAnimated:NO];
}

- (void)openConversationWithId:(NSString *)conversationId
{
    if (self.engine.isBusy) {
        [ORUtils alertWithTitle:L(@"Please wait") message:L(@"Wait for the current reply to finish or stop it first.")];
        return;
    }
    ORConversation *c = [[ORStore shared] loadConversation:conversationId];
    if (!c) return;
    self.engine.conversation = c;
    [ORSettings shared].lastConversationId = c.conversationId;
    ORModelInfo *m = [[ORModelCatalog shared] modelWithId:c.modelId];
    if (m) self.currentModel = m;
    [self.tableView reloadData];
    [self updateEmptyState];
    [self updateModelButton];
    [self scrollToBottomAnimated:NO];
}

- (void)verifyConversationExists
{
    ORConversation *c = self.conversation;
    if (!c || c.isEmpty) return;
    BOOL exists = NO;
    for (NSDictionary *d in [[ORStore shared] conversationSummaries]) {
        if ([d[@"id"] isEqualToString:c.conversationId]) { exists = YES; break; }
    }
    if (!exists && !self.engine.isBusy) [self startConversationResuming:NO];
}

- (void)updateEmptyState
{
    self.emptyLabel.hidden = self.conversation.messages.count > 0;
}

#pragma mark - Model

- (void)updateModelFromSettings
{
    NSString *mid = [ORSettings shared].lastModelId;
    ORModelInfo *m = [[ORModelCatalog shared] modelWithId:mid];
    self.currentModel = m;
    [self updateModelButton];
}

- (void)updateModelButton
{
    NSString *title;
    ORModelCatalog *c = [ORModelCatalog shared];
    if (self.currentModel) title = [self.currentModel displayName];
    else if (!c.hasModels && c.isRefreshing) title = L(@"Loading models…");
    else title = L(@"Choose model");
    [self.modelButton setTitle:[title stringByAppendingString:@" ▾"] forState:UIControlStateNormal];
    [self.modelButton sizeToFit];
    CGRect f = self.modelButton.frame;
    f.size.width = MIN(f.size.width + 10, ORIsPad() ? 440 : 190);
    f.size.height = 32;
    self.modelButton.frame = f;
    self.navigationItem.titleView = nil;
    self.navigationItem.titleView = self.modelButton;
}

- (void)modelsUpdated
{
    [self updateModelFromSettings];
    [self maybeAutoPresentPicker];
}

- (void)apiKeyChanged
{
    if ([ORSettings shared].hasAPIKey) [[ORModelCatalog shared] refreshIfStale];
}

- (void)maybeAutoPresentPicker
{
    if (self.currentModel || self.autoPickerShown || self.presentedViewController || self.popover) return;
    if (![ORModelCatalog shared].hasModels) return;
    self.autoPickerShown = YES;
    [self presentModelPickerImagesOnly:NO completion:^(ORModelInfo *m) {
        if (m) [self selectModel:m];
    }];
}

- (void)selectModel:(ORModelInfo *)m
{
    self.currentModel = m;
    [ORSettings shared].lastModelId = m.modelId;
    [[ORSettings shared] save];
    [self updateModelButton];
}

- (void)modelTapped
{
    if (![ORModelCatalog shared].hasModels && ![ORModelCatalog shared].isRefreshing) {
        [[ORModelCatalog shared] refreshWithCompletion:^(NSError *error) {
            [self updateModelButton];
            if (error) [ORUtils alertWithTitle:L(@"Could not load models") message:error.localizedDescription];
        }];
        [self updateModelButton];
    }
    [self presentModelPickerImagesOnly:NO completion:^(ORModelInfo *m) {
        if (m) [self selectModel:m];
    }];
}

- (void)presentModelPickerImagesOnly:(BOOL)imagesOnly completion:(void (^)(ORModelInfo *))completion
{
    ORModelPickerViewController *vc = [[ORModelPickerViewController alloc] init];
    vc.selectedModelId = imagesOnly ? [ORSettings shared].visionModelId : self.currentModel.modelId;
    vc.forceImagesOnly = imagesOnly;
    vc.showsCancelButton = YES;
    vc.titleText = imagesOnly ? L(@"Vision helper") : L(@"Model");
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    __weak ORChatViewController *weakSelf = self;
    vc.completion = ^(ORModelInfo *m) {
        [weakSelf dismissAuxiliaryAnimated:YES completion:^{ if (completion) completion(m); }];
    };
    if (ORIsPad() && !imagesOnly) {
        self.popover = [[UIPopoverController alloc] initWithContentViewController:nav];
        self.popover.delegate = self;
        [self.popover presentPopoverFromRect:self.modelButton.bounds inView:self.modelButton permittedArrowDirections:UIPopoverArrowDirectionUp animated:YES];
    } else {
        nav.modalPresentationStyle = ORIsPad() ? UIModalPresentationFormSheet : UIModalPresentationFullScreen;
        [self presentViewController:nav animated:YES completion:nil];
    }
}

- (void)dismissAuxiliaryAnimated:(BOOL)animated completion:(void (^)(void))completion
{
    if (self.popover) {
        [self.popover dismissPopoverAnimated:animated];
        self.popover = nil;
        if (completion) completion();
    } else if (self.presentedViewController) {
        [self dismissViewControllerAnimated:animated completion:completion];
    } else if (completion) {
        completion();
    }
}

- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController
{
    self.popover = nil;
}

#pragma mark - History / new chat / settings

- (void)historyTapped
{
    ORHistoryViewController *h = [[ORHistoryViewController alloc] init];
    h.currentConversationId = self.conversation.conversationId;
    __weak ORChatViewController *weakSelf = self;
    h.onSelect = ^(NSString *cid) {
        if (ORIsPad()) [weakSelf dismissAuxiliaryAnimated:YES completion:^{ [weakSelf openConversationWithId:cid]; }];
        else { [weakSelf.navigationController popToViewController:weakSelf animated:YES]; [weakSelf openConversationWithId:cid]; }
    };
    h.onChange = ^{ [weakSelf verifyConversationExists]; };
    if (ORIsPad()) {
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:h];
        self.popover = [[UIPopoverController alloc] initWithContentViewController:nav];
        self.popover.delegate = self;
        [self.popover presentPopoverFromBarButtonItem:self.navigationItem.leftBarButtonItem permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
    } else {
        [self.navigationController pushViewController:h animated:YES];
    }
}

- (void)newChatTapped
{
    if (self.engine.isBusy) {
        [ORUtils alertWithTitle:L(@"Please wait") message:L(@"Wait for the current reply to finish or stop it first.")];
        return;
    }
    if (self.conversation.isEmpty) return;
    [self startConversationResuming:NO];
}

- (void)settingsTapped
{
    ORSettingsViewController *vc = [[ORSettingsViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = ORIsPad() ? UIModalPresentationFormSheet : UIModalPresentationFullScreen;
    __weak ORChatViewController *weakSelf = self;
    self.historyClearedWhileInSettings = NO;
    vc.onHistoryCleared = ^{ weakSelf.historyClearedWhileInSettings = YES; };
    vc.completion = ^{
        [weakSelf dismissViewControllerAnimated:YES completion:^{
            [weakSelf applyTheme];
            [weakSelf updateModelFromSettings];
            if (weakSelf.historyClearedWhileInSettings) [weakSelf startConversationResuming:NO];
            [weakSelf.tableView reloadData];
            [weakSelf scrollToBottomAnimated:NO];
        }];
    };
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)presentKeyEntryOnboarding:(BOOL)onboarding
{
    ORAPIKeyViewController *vc = [[ORAPIKeyViewController alloc] init];
    vc.onboarding = onboarding;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = ORIsPad() ? UIModalPresentationFormSheet : UIModalPresentationFullScreen;
    __weak ORChatViewController *weakSelf = self;
    vc.completion = ^(BOOL saved) {
        [weakSelf dismissViewControllerAnimated:YES completion:^{
            if (saved) {
                [[ORModelCatalog shared] refreshIfStale];
                [weakSelf updateModelButton];
                [weakSelf maybeAutoPresentPicker];
            }
        }];
    };
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - Keyboard

- (void)keyboardWillChangeFrame:(NSNotification *)n
{
    CGRect end = [n.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect kb = [self.view convertRect:end fromView:nil];
    CGFloat overlap = CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(kb);
    if (overlap < 0 || overlap > self.view.bounds.size.height) overlap = 0;
    [self animateKeyboardChange:overlap userInfo:n.userInfo];
}

- (void)keyboardWillHide:(NSNotification *)n
{
    [self animateKeyboardChange:0 userInfo:n.userInfo];
}

- (void)animateKeyboardChange:(CGFloat)overlap userInfo:(NSDictionary *)info
{
    if (fabs(overlap - self.keyboardOverlap) < 0.5) return;
    BOOL wasNear = [self isNearBottom];
    self.keyboardOverlap = overlap;
    NSTimeInterval duration = [info[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    NSInteger curve = [info[UIKeyboardAnimationCurveUserInfoKey] integerValue];
    [UIView animateWithDuration:duration delay:0 options:(UIViewAnimationOptions)(curve << 16) animations:^{
        [self layoutChrome];
        if (wasNear) [self scrollToBottomAnimated:NO];
    } completion:nil];
}

- (void)backgroundTapped
{
    [self.inputBar.textView resignFirstResponder];
}

#pragma mark - Scrolling

- (BOOL)isNearBottom
{
    CGFloat visibleBottom = self.tableView.contentOffset.y + self.tableView.bounds.size.height;
    return visibleBottom >= self.tableView.contentSize.height - 160;
}

- (void)scrollToBottomAnimated:(BOOL)animated
{
    NSInteger n = (NSInteger)self.conversation.messages.count;
    if (n <= 0) return;
    [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:n - 1 inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:animated];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)self.conversation.messages.count;
}

// Transient flags that depend on the position of the message in the conversation.
- (ORMessage *)messageAtRow:(NSInteger)row
{
    ORMessage *m = self.conversation.messages[row];
    BOOL last = (NSUInteger)row == self.conversation.messages.count - 1;
    m.canContinue = last && m.role == ORMessageRoleAssistant && [m.finishReason isEqualToString:@"length"] && !self.engine.isBusy;
    return m;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return [ORMessageCell heightForMessage:[self messageAtRow:indexPath.row] width:[self messageLayoutWidth]];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    ORMessageCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellId forIndexPath:indexPath];
    cell.delegate = self;
    [cell configureWithMessage:[self messageAtRow:indexPath.row] width:[self messageLayoutWidth]];
    return cell;
}

- (NSIndexPath *)indexPathForMessage:(ORMessage *)m
{
    NSUInteger idx = [self.conversation.messages indexOfObjectIdenticalTo:m];
    if (idx == NSNotFound) return nil;
    return [NSIndexPath indexPathForRow:(NSInteger)idx inSection:0];
}

#pragma mark - Engine delegate

- (void)chatEngine:(ORChatEngine *)engine didAddMessage:(ORMessage *)message
{
    [self.tableView reloadData];
    [self updateEmptyState];
    [self scrollToBottomAnimated:YES];
}

- (void)chatEngine:(ORChatEngine *)engine didUpdateMessage:(ORMessage *)message
{
    NSIndexPath *ip = [self indexPathForMessage:message];
    if (!ip) return;
    BOOL wasNear = [self isNearBottom];
    CGFloat width = [self messageLayoutWidth];
    ORMessageCell *cell = (ORMessageCell *)[self.tableView cellForRowAtIndexPath:ip];
    if (cell) {
        CGFloat oldH = cell.bounds.size.height;
        [cell configureWithMessage:message width:width];
        CGFloat newH = [ORMessageCell heightForMessage:message width:width];
        if (fabs(newH - oldH) > 0.5) {
            [UIView setAnimationsEnabled:NO];
            [self.tableView beginUpdates];
            [self.tableView endUpdates];
            [UIView setAnimationsEnabled:YES];
        }
    } else {
        [self.tableView reloadRowsAtIndexPaths:@[ ip ] withRowAnimation:UITableViewRowAnimationNone];
    }
    if (wasNear) [self scrollToBottomAnimated:NO];
}

- (void)chatEngine:(ORChatEngine *)engine didFinishMessage:(ORMessage *)message
{
    BOOL wasNear = [self isNearBottom];
    [self.tableView reloadData];
    [self updateEmptyState];
    if (wasNear) [self scrollToBottomAnimated:YES];
}

- (void)chatEngineDidChangeBusyState:(ORChatEngine *)engine
{
    self.inputBar.busy = engine.isBusy;
}

- (void)chatEngine:(ORChatEngine *)engine needsVisionModelWithCompletion:(void (^)(ORModelInfo *))completion
{
    [self presentModelPickerImagesOnly:YES completion:^(ORModelInfo *m) {
        completion(m);
    }];
}

#pragma mark - Cell delegate

- (void)messageCell:(ORMessageCell *)cell didLongPressMessage:(ORMessage *)message
{
    [self.inputBar.textView resignFirstResponder];
    [cell showMenu];
}

- (void)messageCell:(ORMessageCell *)cell didTapAttachment:(ORAttachment *)attachment
{
    NSString *path = [attachment path];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [ORUtils alertWithTitle:attachment.displayName message:L(@"The file is no longer available.")];
        return;
    }
    self.previewURL = [NSURL fileURLWithPath:path];
    QLPreviewController *ql = [[QLPreviewController alloc] init];
    ql.dataSource = self;
    [self presentViewController:ql animated:YES completion:nil];
}

- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller
{
    return self.previewURL ? 1 : 0;
}

- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index
{
    return self.previewURL;
}

- (void)messageCell:(ORMessageCell *)cell didToggleVisionNoteForMessage:(ORMessage *)message
{
    message.visionNoteExpanded = !message.visionNoteExpanded;
    NSIndexPath *ip = [self indexPathForMessage:message];
    if (ip) [self.tableView reloadRowsAtIndexPaths:@[ ip ] withRowAnimation:UITableViewRowAnimationFade];
}

- (void)messageCell:(ORMessageCell *)cell didToggleReasoningForMessage:(ORMessage *)message
{
    message.reasoningExpanded = !message.reasoningExpanded;
    NSIndexPath *ip = [self indexPathForMessage:message];
    if (ip) [self.tableView reloadRowsAtIndexPaths:@[ ip ] withRowAnimation:UITableViewRowAnimationFade];
}

- (BOOL)messageCell:(ORMessageCell *)cell canEditMessage:(ORMessage *)message
{
    return message.role == ORMessageRoleUser && !self.engine.isBusy;
}

- (void)messageCell:(ORMessageCell *)cell editMessage:(ORMessage *)message
{
    if (self.engine.isBusy || message.role != ORMessageRoleUser) return;
    // Put the text and attachments back into the composer and drop the message with everything after it.
    NSString *text = message.text ?: @"";
    NSArray *atts = message.attachments ?: @[];
    [self.engine truncateFromMessage:message];
    [self.pendingAttachments removeAllObjects];
    [self.pendingAttachments addObjectsFromArray:atts];
    self.inputBar.attachments = [self.pendingAttachments copy];
    [self.inputBar setText:text];
    [self.tableView reloadData];
    [self updateEmptyState];
    [self layoutChrome];
    [self.inputBar.textView becomeFirstResponder];
}

- (void)messageCell:(ORMessageCell *)cell continueMessage:(ORMessage *)message
{
    if (!self.currentModel) { [self modelTapped]; return; }
    if(![self.conversation.providerIdentity isEqual:[ORSettings shared].providerIdentity]){[ORUtils alertWithTitle:L(@"AI provider") message:L(@"This conversation belongs to a different provider. Switch back to that provider or start a new chat.")];return;}

    [self.engine continueMessage:message model:self.currentModel];
}

- (void)messageCell:(ORMessageCell *)cell saveImagesOfMessage:(ORMessage *)message
{
    NSInteger saved = 0;
    for (ORAttachment *a in message.attachments) {
        if (![a isImage]) continue;
        UIImage *img = [UIImage imageWithContentsOfFile:[a path]];
        if (!img) continue;
        UIImageWriteToSavedPhotosAlbum(img, nil, NULL, NULL);
        saved++;
    }
    [ORUtils alertWithTitle:L(@"Saved to Photos") message:[NSString stringWithFormat:L(@"%ld image(s) saved to the Camera Roll."), (long)saved]];
}

- (BOOL)messageCell:(ORMessageCell *)cell canRegenerateMessage:(ORMessage *)message
{
    if (self.engine.isBusy) return NO;
    if (message != self.conversation.messages.lastObject) return NO;
    if (message.role == ORMessageRoleUser) return NO;
    return [self.conversation lastUserMessage] != nil;
}

- (void)messageCell:(ORMessageCell *)cell regenerateMessage:(ORMessage *)message
{
    if (!self.currentModel) { [self modelTapped]; return; }
    [self.engine regenerateWithModel:self.currentModel];
}

- (void)messageCell:(ORMessageCell *)cell deleteMessage:(ORMessage *)message
{
    [self.engine deleteMessage:message];
    [self.tableView reloadData];
    [self updateEmptyState];
}

#pragma mark - Input bar delegate

- (void)inputBarDidChangeHeight:(ORInputBar *)bar
{
    BOOL wasNear = [self isNearBottom];
    [UIView animateWithDuration:0.15 animations:^{
        [self layoutChrome];
    }];
    if (wasNear) [self scrollToBottomAnimated:NO];
}

- (void)inputBarDidTapSend:(ORInputBar *)bar
{
    NSString *text = [[bar text] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray *atts = [self.pendingAttachments copy];
    if (!text.length && !atts.count) return;
    if (![ORSettings shared].hasAPIKey) { [self presentKeyEntryOnboarding:NO]; return; }
    if (!self.currentModel) { [self modelTapped]; return; }
    if (self.engine.isBusy) return;
    if(![self.conversation.providerIdentity isEqual:[ORSettings shared].providerIdentity]){[ORUtils alertWithTitle:L(@"AI provider") message:L(@"This conversation belongs to a different provider. Switch back to that provider or start a new chat.")];return;}
    if(![ORProvider isOpenRouter])for(ORAttachment *a in atts)if(a.kind==ORAttachmentKindPDF){[ORUtils alertWithTitle:L(@"Attachments") message:L(@"PDF parsing is available through OpenRouter. Convert this PDF to text before using another provider.")];return;}
    [bar clearText];
    [self.pendingAttachments removeAllObjects];
    bar.attachments = @[];
    [self layoutChrome];
    [self.engine sendText:text attachments:atts model:self.currentModel];
}

- (void)inputBarDidTapStop:(ORInputBar *)bar
{
    [self.engine cancel];
}

- (void)inputBarDidToggleWebSearch:(ORInputBar *)bar
{
    ORSettings *s = [ORSettings shared];
    if(![ORProvider isOpenRouter]){[ORUtils alertWithTitle:L(@"Web search") message:L(@"This option is an OpenRouter feature.")];return;}
    if (!s.webSearch && !s.webSearchWarningHidden) {
        // Web search is billed by OpenRouter even with free models, so ask before turning it on.
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:L(@"Web search is paid")
                                                        message:L(@"OpenRouter charges extra for every message sent with web search on – usually around one cent, depending on the model. It is paid from your OpenRouter credits, even when the model itself is free.")
                                                       delegate:self
                                              cancelButtonTitle:L(@"Cancel")
                                              otherButtonTitles:L(@"Turn On"), L(@"Don't Show Again"), nil];
        alert.tag = kWebSearchAlertTag;
        [alert show];
        return;
    }
    [self setWebSearchEnabled:!s.webSearch];
}

- (void)setWebSearchEnabled:(BOOL)on
{
    [ORSettings shared].webSearch = on;
    [[ORSettings shared] save];
    self.inputBar.webSearchOn = on;
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (alertView.tag != kWebSearchAlertTag || buttonIndex == alertView.cancelButtonIndex) return;
    // "Don't Show Again" also turns the search on, it only skips this alert next time.
    if (buttonIndex != alertView.firstOtherButtonIndex) [ORSettings shared].webSearchWarningHidden = YES;
    [self setWebSearchEnabled:YES];
}

- (void)inputBar:(ORInputBar *)bar didRemoveAttachment:(ORAttachment *)attachment
{
    [attachment deleteFile];
    [self.pendingAttachments removeObject:attachment];
    bar.attachments = [self.pendingAttachments copy];
    [self layoutChrome];
}

- (void)inputBarDidTapAttach:(ORInputBar *)bar
{
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    [sheet addButtonWithTitle:L(@"Photos")];
    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) [sheet addButtonWithTitle:L(@"Take Photo")];
    [sheet addButtonWithTitle:L(@"Choose File")];
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 100000
    // (asking for the image itself would show iOS 16's "Allow Paste" question every time the menu opens)
    BOOL pasteboardHasImage = [UIPasteboard generalPasteboard].hasImages;
#else
    BOOL pasteboardHasImage = [UIPasteboard generalPasteboard].image != nil;
#endif
    if (pasteboardHasImage) [sheet addButtonWithTitle:L(@"Paste Image")];
    NSDictionary *persona = [[ORSettings shared] activePersona];
    NSString *personaTitle = [NSString stringWithFormat:@"%@: %@", L(@"Persona"), persona[@"name"] ?: L(@"No persona")];
    [sheet addButtonWithTitle:personaTitle];
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:L(@"Cancel")];
    if (ORIsPad()) [sheet showFromRect:bar.attachButton.frame inView:bar animated:YES];
    else [sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex < 0 || buttonIndex == actionSheet.cancelButtonIndex) return;
    NSString *title = [actionSheet buttonTitleAtIndex:buttonIndex];
    if ([title isEqualToString:L(@"Photos")]) [self pickPhotos];
    else if ([title isEqualToString:L(@"Take Photo")]) [self pickPhotoFromSource:UIImagePickerControllerSourceTypeCamera];
    else if ([title isEqualToString:L(@"Choose File")]) [self chooseFile];
    else if ([title isEqualToString:L(@"Paste Image")]) [self addImageAttachment:[UIPasteboard generalPasteboard].image name:nil];
    else if ([title hasPrefix:L(@"Persona")]) [self showPersonas];
}

- (void)showPersonas
{
    ORPersonaListViewController *vc = [[ORPersonaListViewController alloc] init];
    vc.showsDoneButton = !ORIsPad();
    __weak ORChatViewController *weakSelf = self;
    vc.onDone = ^{ [weakSelf dismissAuxiliaryAnimated:YES completion:nil]; };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    if (ORIsPad()) {
        self.popover = [[UIPopoverController alloc] initWithContentViewController:nav];
        self.popover.delegate = self;
        [self.popover presentPopoverFromRect:self.inputBar.attachButton.frame inView:self.inputBar permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
    } else {
        [self presentViewController:nav animated:YES completion:nil];
    }
}

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 140000
// iOS 14 and newer: the system picker (multi-select, runs outside the app, needs no photo permission)
- (void)pickPhotosWithSystemPicker
{
    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] init];
    config.selectionLimit = 8;
    config.filter = [PHPickerFilter imagesFilter];
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results
{
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (!results.count) return;
    // the images arrive one by one, in any order: slots keep the order the user picked them in
    NSMutableArray *slots = [NSMutableArray arrayWithCapacity:results.count];
    for (NSUInteger i = 0; i < results.count; i++) [slots addObject:[NSNull null]];
    dispatch_group_t group = dispatch_group_create();
    [results enumerateObjectsUsingBlock:^(PHPickerResult *result, NSUInteger idx, BOOL *stop) {
        if (![result.itemProvider canLoadObjectOfClass:[UIImage class]]) return;
        dispatch_group_enter(group);
        [result.itemProvider loadObjectOfClass:[UIImage class] completionHandler:^(id<NSItemProviderReading> object, NSError *error) {
            if ([object isKindOfClass:[UIImage class]]) {
                @synchronized(slots) { slots[idx] = object; }
            } else {
                ORLog(@"photo %lu could not be loaded: %@", (unsigned long)idx, error);
            }
            dispatch_group_leave(group);
        }];
    }];
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        NSMutableArray *images = [NSMutableArray array];
        for (id slot in slots) if ([slot isKindOfClass:[UIImage class]]) [images addObject:slot];
        if (images.count) [self addImageAttachments:images];
        else [ORUtils alertWithTitle:L(@"Could not add image") message:L(@"Some photos could not be processed.")];
    });
}
#endif

- (void)pickPhotos
{
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 140000
    if (ORModernIOS()) { [self pickPhotosWithSystemPicker]; return; }
#endif
    ORPhotoPickerViewController *picker = [[ORPhotoPickerViewController alloc] init];
    __weak ORChatViewController *weakSelf = self;
    picker.completion = ^(NSArray *images) {
        [weakSelf dismissAuxiliaryAnimated:YES completion:^{
            if (images.count) [weakSelf addImageAttachments:images];
        }];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
    if (ORIsPad()) {
        self.popover = [[UIPopoverController alloc] initWithContentViewController:nav];
        self.popover.delegate = self;
        [self.popover presentPopoverFromRect:self.inputBar.attachButton.frame inView:self.inputBar permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
    } else {
        [self presentViewController:nav animated:YES completion:nil];
    }
}

- (void)addImageAttachments:(NSArray *)images
{
    if (!images.count) return;
    [self.navSpinner startAnimating];
    UIBarButtonItem *spinnerItem = [[UIBarButtonItem alloc] initWithCustomView:self.navSpinner];
    NSArray *savedItems = self.navigationItem.rightBarButtonItems;
    self.navigationItem.rightBarButtonItems = @[ spinnerItem ];
    NSTimeInterval stamp = [[NSDate date] timeIntervalSince1970];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray *made = [NSMutableArray array];
        NSInteger i = 1;
        for (UIImage *img in images) {
            @autoreleasepool {
                NSString *name = [NSString stringWithFormat:@"photo-%.0f-%ld.jpg", stamp, (long)i++];
                ORAttachment *a = [ORAttachment attachmentWithImage:img displayName:name];
                if (a) [made addObject:a];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.navSpinner stopAnimating];
            self.navigationItem.rightBarButtonItems = savedItems;
            for (ORAttachment *a in made) [self.pendingAttachments addObject:a];
            self.inputBar.attachments = [self.pendingAttachments copy];
            [self layoutChrome];
            if (made.count < images.count) [ORUtils alertWithTitle:L(@"Could not add image") message:L(@"Some photos could not be processed.")];
        });
    });
}

#pragma mark - Attachments

- (void)addPendingAttachment:(ORAttachment *)a
{
    if (!a) return;
    [self.pendingAttachments addObject:a];
    self.inputBar.attachments = [self.pendingAttachments copy];
    [self layoutChrome];
}

- (void)attachIncomingAttachment:(id)attachment
{
    if (![attachment isKindOfClass:[ORAttachment class]]) return;
    [self view];   // make sure the composer exists even when we are launched by "Open in…"
    [self dismissAuxiliaryAnimated:NO completion:nil];
    [self addPendingAttachment:attachment];
}

- (void)addImageAttachment:(UIImage *)image name:(NSString *)name
{
    if (!image) return;
    [self.navSpinner startAnimating];
    UIBarButtonItem *spinnerItem = [[UIBarButtonItem alloc] initWithCustomView:self.navSpinner];
    NSArray *savedItems = self.navigationItem.rightBarButtonItems;
    self.navigationItem.rightBarButtonItems = @[ spinnerItem ];
    NSString *fileName = name ?: [NSString stringWithFormat:@"photo-%.0f.jpg", [[NSDate date] timeIntervalSince1970]];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        ORAttachment *a = [ORAttachment attachmentWithImage:image displayName:fileName];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.navSpinner stopAnimating];
            self.navigationItem.rightBarButtonItems = savedItems;
            if (a) [self addPendingAttachment:a];
            else [ORUtils alertWithTitle:L(@"Could not add image") message:L(@"The image could not be processed.")];
        });
    });
}

- (void)addFileAttachmentAtPath:(NSString *)path
{
    NSError *error = nil;
    ORAttachment *a = [ORAttachment attachmentByImportingFileAtPath:path displayName:[path lastPathComponent] error:&error];
    if (!a) {
        [ORUtils alertWithTitle:L(@"Could not add file") message:error.localizedDescription ?: @""];
        return;
    }
    if (a.kind == ORAttachmentKindOther) {
        [ORUtils alertWithTitle:L(@"Unsupported file") message:L(@"Only images, PDF, text, code and office documents can be sent. The file will be attached by name only.")];
    }
    [self addPendingAttachment:a];
}

- (void)pickPhotoFromSource:(UIImagePickerControllerSourceType)source
{
    if (![UIImagePickerController isSourceTypeAvailable:source]) return;
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = source;
    picker.mediaTypes = @[ @"public.image" ];   // kUTTypeImage without importing MobileCoreServices
    picker.delegate = self;
    if (ORIsPad() && source != UIImagePickerControllerSourceTypeCamera) {
        self.popover = [[UIPopoverController alloc] initWithContentViewController:picker];
        self.popover.delegate = self;
        [self.popover presentPopoverFromRect:self.inputBar.attachButton.frame inView:self.inputBar permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
    } else {
        [self presentViewController:picker animated:YES completion:nil];
    }
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    UIImage *img = info[UIImagePickerControllerOriginalImage];
    [self dismissAuxiliaryAnimated:YES completion:^{
        [self addImageAttachment:img name:nil];
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    [self dismissAuxiliaryAnimated:YES completion:nil];
}

- (void)chooseFile
{
    ORFileBrowserViewController *fb = [[ORFileBrowserViewController alloc] init];
    __weak ORChatViewController *weakSelf = self;
    fb.completion = ^(NSString *path) {
        [weakSelf dismissViewControllerAnimated:YES completion:^{
            if (path) [weakSelf addFileAttachmentAtPath:path];
        }];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:fb];
    nav.modalPresentationStyle = ORIsPad() ? UIModalPresentationFormSheet : UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
}

@end
