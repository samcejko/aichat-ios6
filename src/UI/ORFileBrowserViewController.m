#import "ORFileBrowserViewController.h"
#import "ORTheme.h"
#import "ORUtils.h"
#import "ORCommon.h"

@interface ORFileBrowserViewController ()
@property (nonatomic, strong) NSArray *entries;   // dicts: name, path, isDir, size, date
@property (nonatomic, strong) UILabel *emptyLabel;
@end

@implementation ORFileBrowserViewController

- (instancetype)init
{
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        self.contentSizeForViewInPopover = CGSizeMake(420, 560);
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    if (!self.directory) self.directory = [ORUtils documentsPath];
    self.title = [self.directory isEqualToString:[ORUtils documentsPath]] ? L(@"Files") : [self.directory lastPathComponent];
    self.tableView.rowHeight = 52;
    if (self.navigationController.viewControllers.count <= 1) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelTapped)];
    }
    self.emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.font = [UIFont systemFontOfSize:15];
    self.emptyLabel.backgroundColor = [UIColor clearColor];
    self.emptyLabel.text = L(@"No files. Copy files here with iTunes File Sharing (or iFunBox), or use \"Open in…\" from another app.");
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    ORTheme *t = [ORTheme shared];
    [t applyToTableView:self.tableView grouped:NO];
    [t applyToNavigationBar:self.navigationController.navigationBar];
    self.emptyLabel.textColor = [t secondaryTextColor];
    [self reload];
}

- (void)reload
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *names = [fm contentsOfDirectoryAtPath:self.directory error:NULL];
    NSMutableArray *dirs = [NSMutableArray array];
    NSMutableArray *files = [NSMutableArray array];
    for (NSString *name in names) {
        if ([name hasPrefix:@"."]) continue;
        NSString *path = [self.directory stringByAppendingPathComponent:name];
        NSDictionary *attrs = [fm attributesOfItemAtPath:path error:NULL];
        BOOL isDir = [attrs[NSFileType] isEqualToString:NSFileTypeDirectory];
        NSDictionary *e = @{ @"name": name, @"path": path, @"isDir": @(isDir), @"size": @([attrs fileSize]),
                             @"date": [attrs fileModificationDate] ?: [NSDate date] };
        if (isDir) [dirs addObject:e];
        else [files addObject:e];
    }
    NSComparator byName = ^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] compare:b[@"name"] options:NSCaseInsensitiveSearch | NSNumericSearch];
    };
    [dirs sortUsingComparator:byName];
    [files sortUsingComparator:byName];
    self.entries = [dirs arrayByAddingObjectsFromArray:files];
    [self.tableView reloadData];
    if (self.entries.count == 0) {
        self.emptyLabel.frame = CGRectInset(self.tableView.bounds, 24, 0);
        self.tableView.backgroundView = self.emptyLabel;
        self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    } else {
        self.tableView.backgroundView = nil;
        self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    }
}

- (void)cancelTapped
{
    if (self.completion) self.completion(nil);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)self.entries.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cid = @"file";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    }
    NSDictionary *e = self.entries[indexPath.row];
    BOOL isDir = [e[@"isDir"] boolValue];
    cell.textLabel.text = e[@"name"];
    if (isDir) {
        NSArray *inner = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:e[@"path"] error:NULL];
        cell.detailTextLabel.text = [NSString stringWithFormat:L(@"Folder · %lu items"), (unsigned long)inner.count];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", [ORUtils formatFileSize:[e[@"size"] unsignedLongLongValue]], [ORUtils shortDateString:e[@"date"]]];
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    [[ORTheme shared] styleCell:cell];
    cell.detailTextLabel.textColor = [[ORTheme shared] secondaryTextColor];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *e = self.entries[indexPath.row];
    if ([e[@"isDir"] boolValue]) {
        ORFileBrowserViewController *sub = [[ORFileBrowserViewController alloc] init];
        sub.directory = e[@"path"];
        sub.completion = self.completion;
        [self.navigationController pushViewController:sub animated:YES];
        return;
    }
    if (self.completion) self.completion(e[@"path"]);
}

@end
