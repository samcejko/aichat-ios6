#import "ORChoiceViewController.h"
#import "ORTheme.h"

@implementation ORChoiceViewController

- (instancetype)init
{
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    ORTheme *t = [ORTheme shared];
    [t applyToTableView:self.tableView grouped:YES];
    [t applyToNavigationBar:self.navigationController.navigationBar];
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)self.titles.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cid = @"choice";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.detailTextLabel.numberOfLines = 2;
    }
    cell.textLabel.text = self.titles[indexPath.row];
    cell.detailTextLabel.text = (indexPath.row < (NSInteger)self.subtitles.count) ? self.subtitles[indexPath.row] : nil;
    cell.accessoryType = indexPath.row == self.selectedIndex ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    [[ORTheme shared] styleCell:cell];
    cell.detailTextLabel.textColor = [[ORTheme shared] secondaryTextColor];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return self.subtitles.count ? 56 : 44;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    self.selectedIndex = indexPath.row;
    [tableView reloadData];
    if (self.completion) self.completion(indexPath.row);
    [self.navigationController popViewControllerAnimated:YES];
}

@end
