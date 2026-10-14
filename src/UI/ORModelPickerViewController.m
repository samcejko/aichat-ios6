#import "ORModelPickerViewController.h"
#import "ORModelDetailViewController.h"
#import "ORModelCatalog.h"
#import "ORSettings.h"
#import "ORTheme.h"
#import "ORUtils.h"
#import "ORModern.h"
#import "ORCommon.h"

@interface ORModelPickerViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UISwitch *freeSwitch;
@property (nonatomic, strong) UISwitch *imagesSwitch;
@property (nonatomic, strong) UILabel *freeLabel;
@property (nonatomic, strong) UILabel *imagesLabel;
@property (nonatomic, strong) UISegmentedControl *sortControl;
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) NSArray *rows;
@property (nonatomic) BOOL finished;
@end

@implementation ORModelPickerViewController

- (instancetype)init
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.contentSizeForViewInPopover = CGSizeMake(440, 640);
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = self.titleText ?: L(@"Model");
    ORSettings *s = [ORSettings shared];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 54;
    [self.view addSubview:self.tableView];

    CGFloat w = self.view.bounds.size.width;
    self.headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 44 + 40 + 38)];
    self.headerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, w, 44)];
    self.searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.searchBar.delegate = self;
    self.searchBar.placeholder = L(@"Search models");
    self.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    [self.headerView addSubview:self.searchBar];

    self.freeSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    self.freeSwitch.on = s.pickerFreeOnly;
    [self.freeSwitch addTarget:self action:@selector(filtersChanged) forControlEvents:UIControlEventValueChanged];
    self.freeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.freeLabel.text = L(@"Free only");
    self.freeLabel.font = [UIFont boldSystemFontOfSize:14];
    self.freeLabel.backgroundColor = [UIColor clearColor];

    self.imagesSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    self.imagesSwitch.on = s.pickerImagesOnly || self.forceImagesOnly;
    self.imagesSwitch.enabled = !self.forceImagesOnly;
    [self.imagesSwitch addTarget:self action:@selector(filtersChanged) forControlEvents:UIControlEventValueChanged];
    self.imagesLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.imagesLabel.text = L(@"Images");
    self.imagesLabel.font = [UIFont boldSystemFontOfSize:14];
    self.imagesLabel.backgroundColor = [UIColor clearColor];

    [self.headerView addSubview:self.freeSwitch];
    [self.headerView addSubview:self.freeLabel];
    [self.headerView addSubview:self.imagesSwitch];
    [self.headerView addSubview:self.imagesLabel];

    self.sortControl = [[UISegmentedControl alloc] initWithItems:@[ L(@"Name"), L(@"Newest"), L(@"Price"), L(@"Context") ]];
    self.sortControl.segmentedControlStyle = UISegmentedControlStyleBar;
    self.sortControl.selectedSegmentIndex = MIN(MAX((NSInteger)s.pickerSort, 0), 3);
    [self.sortControl addTarget:self action:@selector(filtersChanged) forControlEvents:UIControlEventValueChanged];
    [self.headerView addSubview:self.sortControl];

    self.tableView.tableHeaderView = self.headerView;

    self.emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.font = [UIFont systemFontOfSize:15];
    self.emptyLabel.backgroundColor = [UIColor clearColor];
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.hidesWhenStopped = YES;

    if (self.showsCancelButton) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelTapped)];
    }
    [self updateRefreshButton];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(modelsUpdated) name:ORModelsDidUpdateNotification object:nil];
    [self applyTheme];
    [self reloadRows];

    if (![ORModelCatalog shared].hasModels) [self refreshTapped];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    // (the table header is not kept clear of the notch by the table itself: the side insets do it here)
    UIEdgeInsets safe = ORSafeAreaInsets(self.view);
    CGFloat left = safe.left, w = self.view.bounds.size.width - safe.left - safe.right;
    CGFloat y = 44;
    CGSize sw = [self.freeSwitch sizeThatFits:CGSizeZero];   // 79x27 on iOS 6, 51x31 from iOS 7 on
    if (sw.width < 40) sw = CGSizeMake(79, 27);
    CGFloat sy = y + 6 + (27 - sw.height) / 2;
    self.freeSwitch.frame = CGRectMake(left + 10, sy, sw.width, sw.height);
    self.freeLabel.frame = CGRectMake(left + 10 + sw.width + 7, y + 6, 90, 27);
    self.imagesSwitch.frame = CGRectMake(left + w / 2 + 4, sy, sw.width, sw.height);
    self.imagesLabel.frame = CGRectMake(left + w / 2 + 4 + sw.width + 7, y + 6, w / 2 - sw.width - 17, 27);
    self.sortControl.frame = CGRectMake(left + 10, y + 42, w - 20, 30);
    self.emptyLabel.frame = CGRectMake(left + 20, 160, w - 40, 80);
}

- (void)applyTheme
{
    ORTheme *t = [ORTheme shared];
    [t applyToTableView:self.tableView grouped:NO];
    [t applyToSearchBar:self.searchBar];
    self.headerView.backgroundColor = [t tableBackgroundColor];
    self.freeLabel.textColor = [t primaryTextColor];
    self.imagesLabel.textColor = [t primaryTextColor];
    self.emptyLabel.textColor = [t secondaryTextColor];
    self.view.backgroundColor = [t cellBackgroundColor];
    [t applyToNavigationBar:self.navigationController.navigationBar];
}

- (void)updateRefreshButton
{
    if ([ORModelCatalog shared].isRefreshing) {
        [self.spinner startAnimating];
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];
    } else {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refreshTapped)];
    }
}

#pragma mark - Data

- (void)reloadRows
{
    ORSettings *s = [ORSettings shared];
    self.rows = [[ORModelCatalog shared] filteredModelsFreeOnly:self.freeSwitch.on imagesOnly:self.imagesSwitch.on
                                                         query:self.searchBar.text sort:(ORModelSort)self.sortControl.selectedSegmentIndex];
    [self.tableView reloadData];
    if (self.rows.count == 0) {
        self.emptyLabel.hidden = NO;
        if (![ORModelCatalog shared].hasModels) {
            self.emptyLabel.text = [ORModelCatalog shared].isRefreshing ? L(@"Loading models…") : L(@"No models loaded. Tap refresh.");
        } else {
            self.emptyLabel.text = L(@"No models match the filters.");
        }
    } else {
        self.emptyLabel.hidden = YES;
    }
    (void)s;
}

- (void)filtersChanged
{
    ORSettings *s = [ORSettings shared];
    s.pickerFreeOnly = self.freeSwitch.on;
    if (!self.forceImagesOnly) s.pickerImagesOnly = self.imagesSwitch.on;
    s.pickerSort = (ORModelSort)self.sortControl.selectedSegmentIndex;
    [self reloadRows];
}

- (void)modelsUpdated
{
    [self updateRefreshButton];
    [self reloadRows];
}

- (void)refreshTapped
{
    [[ORModelCatalog shared] refreshWithCompletion:^(NSError *error) {
        [self updateRefreshButton];
        [self reloadRows];
        if (error) [ORUtils alertWithTitle:L(@"Could not load models") message:error.localizedDescription];
    }];
    [self updateRefreshButton];
    [self reloadRows];
}

- (void)cancelTapped
{
    if (self.finished) return;
    self.finished = YES;
    if (self.completion) self.completion(nil);
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)self.rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cid = @"model";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    }
    ORModelInfo *m = self.rows[indexPath.row];
    BOOL selected = [m.modelId isEqualToString:self.selectedModelId];
    cell.textLabel.text = selected ? [NSString stringWithFormat:@"✓ %@", [m displayName]] : [m displayName];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", m.modelId, [m detailLine]];
    cell.accessoryType = UITableViewCellAccessoryDetailDisclosureButton;
    [[ORTheme shared] styleCell:cell];
    cell.detailTextLabel.textColor = [[ORTheme shared] secondaryTextColor];
    if (selected) cell.textLabel.textColor = [[ORTheme shared] accentColor];
    return cell;
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath
{
    ORModelInfo *m = self.rows[indexPath.row];
    ORModelDetailViewController *vc = [[ORModelDetailViewController alloc] init];
    vc.model = m;
    __weak ORModelPickerViewController *weakSelf = self;
    vc.onUse = ^(ORModelInfo *model) {
        if (weakSelf.finished) return;
        weakSelf.selectedModelId = model.modelId;
        weakSelf.finished = YES;
        if (weakSelf.completion) weakSelf.completion(model);
    };
    vc.onUseAsVision = ^(ORModelInfo *model) {
        [ORSettings shared].visionModelId = model.modelId;
        [[ORSettings shared] save];
        [ORUtils alertWithTitle:L(@"Vision helper set") message:[model displayName]];
        [weakSelf.navigationController popViewControllerAnimated:YES];
    };
    [self.searchBar resignFirstResponder];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.finished) return;
    ORModelInfo *m = self.rows[indexPath.row];
    self.selectedModelId = m.modelId;
    self.finished = YES;
    [self.searchBar resignFirstResponder];
    if (self.completion) self.completion(m);
}

#pragma mark - Search

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText
{
    [self reloadRows];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
    [searchBar resignFirstResponder];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    [self.searchBar resignFirstResponder];
}

@end
