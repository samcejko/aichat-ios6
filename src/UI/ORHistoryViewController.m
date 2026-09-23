#import "ORHistoryViewController.h"
#import "ORStore.h"
#import "ORModelCatalog.h"
#import "ORTheme.h"
#import "ORUtils.h"
#import "ORCommon.h"

@interface ORHistoryViewController () <UIActionSheetDelegate>
@property (nonatomic, strong) NSArray *summaries;
@property (nonatomic, strong) UILabel *emptyLabel;
@end

@implementation ORHistoryViewController

- (instancetype)init
{
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        self.contentSizeForViewInPopover = CGSizeMake(380, 560);
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = L(@"History");
    self.tableView.rowHeight = 58;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:L(@"Clear") style:UIBarButtonItemStyleBordered target:self action:@selector(clearTapped)];
    if (self.showsDoneButton) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(doneTapped)];
    }
    self.emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.emptyLabel.text = L(@"No saved chats yet.");
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.font = [UIFont systemFontOfSize:15];
    self.emptyLabel.backgroundColor = [UIColor clearColor];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self applyTheme];
    [self reload];
}

- (void)applyTheme
{
    ORTheme *t = [ORTheme shared];
    [t applyToTableView:self.tableView grouped:NO];
    [t applyToNavigationBar:self.navigationController.navigationBar];
    self.emptyLabel.textColor = [t secondaryTextColor];
}

- (void)reload
{
    self.summaries = [[ORStore shared] conversationSummaries];
    [self.tableView reloadData];
    if (self.summaries.count == 0) {
        self.emptyLabel.frame = self.tableView.bounds;
        self.tableView.backgroundView = self.emptyLabel;
        self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    } else {
        self.tableView.backgroundView = nil;
        self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    }
    self.navigationItem.rightBarButtonItem.enabled = self.summaries.count > 0;
}

- (void)doneTapped
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)clearTapped
{
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:L(@"Delete all saved chats?") delegate:self
                                              cancelButtonTitle:L(@"Cancel") destructiveButtonTitle:L(@"Delete All") otherButtonTitles:nil];
    if (ORIsPad()) [sheet showFromBarButtonItem:self.navigationItem.rightBarButtonItem animated:YES];
    else [sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex != actionSheet.destructiveButtonIndex) return;
    [[ORStore shared] deleteAllConversations];
    [self reload];
    if (self.onChange) self.onChange();
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)self.summaries.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cid = @"conv";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
    }
    NSDictionary *d = self.summaries[indexPath.row];
    cell.textLabel.text = [d[@"title"] length] ? d[@"title"] : L(@"New chat");
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:[d[@"updated"] doubleValue]];
    ORModelInfo *m = [[ORModelCatalog shared] modelWithId:d[@"model"]];
    NSString *modelName = m ? [m displayName] : (d[@"model"] ?: @"");
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ · %@", [ORUtils shortDateString:date], modelName, [ORUtils truncate:d[@"preview"] to:60]];
    cell.accessoryType = [d[@"id"] isEqualToString:self.currentConversationId] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    [[ORTheme shared] styleCell:cell];
    cell.detailTextLabel.textColor = [[ORTheme shared] secondaryTextColor];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *d = self.summaries[indexPath.row];
    if (self.onSelect) self.onSelect(d[@"id"]);
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    NSDictionary *d = self.summaries[indexPath.row];
    [[ORStore shared] deleteConversation:d[@"id"]];
    self.summaries = [[ORStore shared] conversationSummaries];
    [tableView deleteRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationFade];
    if (self.summaries.count == 0) [self reload];
    if (self.onChange) self.onChange();
}

@end
