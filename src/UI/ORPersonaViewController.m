#import "ORPersonaViewController.h"
#import "ORSettings.h"
#import "ORTheme.h"
#import "ORUtils.h"
#import "ORModern.h"
#import "ORCommon.h"

#pragma mark - List

@interface ORPersonaListViewController ()
@property (nonatomic, strong) NSArray *personas;
@end

@implementation ORPersonaListViewController

- (instancetype)init
{
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) self.contentSizeForViewInPopover = CGSizeMake(420, 560);
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = L(@"Persona");
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addTapped)];
    if (self.showsDoneButton) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(doneTapped)];
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    ORTheme *t = [ORTheme shared];
    [t applyToTableView:self.tableView grouped:YES];
    [t applyToNavigationBar:self.navigationController.navigationBar];
    [self reload];
}

- (void)reload
{
    self.personas = [ORSettings shared].personas;
    [self.tableView reloadData];
}

- (void)doneTapped
{
    if (self.onDone) self.onDone();
}

- (void)addTapped
{
    [self editPersona:nil];
}

- (void)editPersona:(NSDictionary *)persona
{
    ORPersonaEditViewController *vc = [[ORPersonaEditViewController alloc] init];
    vc.persona = persona;
    __weak ORPersonaListViewController *weakSelf = self;
    vc.completion = ^(NSDictionary *result) {
        if (result) [[ORSettings shared] addOrUpdatePersona:result];
        [weakSelf.navigationController popViewControllerAnimated:YES];
        [weakSelf reload];
    };
    [self.navigationController pushViewController:vc animated:YES];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    return L(@"The active persona is sent as the system prompt at the start of every conversation. Tap the blue arrow to edit.");
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)self.personas.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cid = @"persona";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
    }
    NSDictionary *p = self.personas[indexPath.row];
    cell.textLabel.text = p[@"name"];
    NSString *prompt = p[@"prompt"];
    cell.detailTextLabel.text = prompt.length ? [ORUtils truncate:prompt to:70] : L(@"No system prompt");
    BOOL active = [p[@"id"] isEqualToString:[ORSettings shared].activePersonaId];
    cell.accessoryType = [p[@"id"] isEqualToString:@"none"] ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDetailDisclosureButton;
    [[ORTheme shared] styleCell:cell];
    cell.detailTextLabel.textColor = [[ORTheme shared] secondaryTextColor];
    cell.textLabel.textColor = active ? [[ORTheme shared] accentColor] : [[ORTheme shared] primaryTextColor];
    cell.textLabel.font = active ? [UIFont boldSystemFontOfSize:17] : [UIFont systemFontOfSize:17];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 54;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *p = self.personas[indexPath.row];
    [ORSettings shared].activePersonaId = p[@"id"];
    [[ORSettings shared] save];
    [self.tableView reloadData];
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath
{
    [self editPersona:self.personas[indexPath.row]];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return ![self.personas[indexPath.row][@"id"] isEqualToString:@"none"];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    NSDictionary *p = self.personas[indexPath.row];
    [[ORSettings shared] removePersonaWithId:p[@"id"]];
    self.personas = [ORSettings shared].personas;
    [tableView deleteRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationFade];
    [tableView reloadData];
}

@end

#pragma mark - Editor

@interface ORPersonaEditViewController () <UITextViewDelegate>
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UITextView *promptView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *promptLabel;
@end

@implementation ORPersonaEditViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = self.persona ? L(@"Edit persona") : L(@"New persona");
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelTapped)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(doneTapped)];

    self.nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.nameLabel.text = L(@"Name");
    self.nameLabel.font = [UIFont boldSystemFontOfSize:13];
    self.nameLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.nameLabel];

    self.nameField = [[UITextField alloc] initWithFrame:CGRectZero];
    self.nameField.borderStyle = UITextBorderStyleRoundedRect;
    self.nameField.text = self.persona[@"name"] ?: @"";
    self.nameField.placeholder = L(@"e.g. Translator");
    self.nameField.clearButtonMode = UITextFieldViewModeWhileEditing;
    [self.view addSubview:self.nameField];

    self.promptLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.promptLabel.text = L(@"System prompt");
    self.promptLabel.font = [UIFont boldSystemFontOfSize:13];
    self.promptLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.promptLabel];

    self.promptView = [[UITextView alloc] initWithFrame:CGRectZero];
    self.promptView.font = [UIFont systemFontOfSize:15];
    self.promptView.text = self.persona[@"prompt"] ?: @"";
    self.promptView.layer.cornerRadius = 6;
    self.promptView.layer.borderWidth = 1;
    [self.view addSubview:self.promptView];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [self applyTheme];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyTheme
{
    ORTheme *t = [ORTheme shared];
    self.view.backgroundColor = [t tableBackgroundColor];
    self.nameLabel.textColor = [t secondaryTextColor];
    self.promptLabel.textColor = [t secondaryTextColor];
    self.promptView.backgroundColor = [t cellBackgroundColor];
    self.promptView.textColor = [t primaryTextColor];
    self.promptView.layer.borderColor = [t separatorColor].CGColor;
    self.promptView.keyboardAppearance = t.isDark ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;
    [t applyToNavigationBar:self.navigationController.navigationBar];
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    UIEdgeInsets safe = ORSafeAreaInsets(self.view);   // the notch and the home indicator (iOS 11+)
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height - safe.bottom;
    CGFloat m = 16;
    CGFloat x = m + safe.left, cw = w - 2 * m - safe.left - safe.right;
    self.nameLabel.frame = CGRectMake(x, 12, cw, 18);
    self.nameField.frame = CGRectMake(x, 32, cw, 36);
    self.promptLabel.frame = CGRectMake(x, 80, cw, 18);
    CGFloat bottom = h - m;
    if (self.promptView.contentInset.bottom > 0) bottom = self.view.bounds.size.height - self.promptView.contentInset.bottom - m;
    self.promptView.frame = CGRectMake(x, 100, cw, MAX(80, bottom - 100));
}

- (void)keyboardChanged:(NSNotification *)n
{
    CGRect kb = [self.view convertRect:[n.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil];
    CGFloat overlap = MAX(0, CGRectGetMaxY(self.view.bounds) - kb.origin.y);
    self.promptView.contentInset = UIEdgeInsetsMake(0, 0, overlap, 0);
    [self.view setNeedsLayout];
}

- (void)cancelTapped
{
    if (self.completion) self.completion(nil);
}

- (void)doneTapped
{
    NSString *name = [self.nameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!name.length) {
        [ORUtils alertWithTitle:L(@"Name required") message:L(@"Give the persona a short name.")];
        return;
    }
    NSString *pid = self.persona[@"id"] ?: [ORUtils uuid];
    NSDictionary *result = @{ @"id": pid, @"name": name, @"prompt": self.promptView.text ?: @"" };
    if (self.completion) self.completion(result);
}

@end
