#import "ORModelDetailViewController.h"
#import "ORTheme.h"
#import "ORUtils.h"
#import "ORModern.h"
#import "ORCommon.h"

@interface ORModelDetailViewController ()
@property (nonatomic, strong) NSArray *rows;     // section 0: pairs (title, value)
@end

@implementation ORModelDetailViewController

- (instancetype)init
{
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) self.contentSizeForViewInPopover = CGSizeMake(440, 640);
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = L(@"Model info");
    ORModelInfo *m = self.model;
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:@[ L(@"Name"), [m displayName] ?: @"" ]];
    [rows addObject:@[ @"ID", m.modelId ?: @"" ]];
    [rows addObject:@[ L(@"Context"), [NSString stringWithFormat:@"%@ tokens", [ORUtils formatContextLength:m.contextLength]] ]];
    if (m.maxCompletionTokens > 0) [rows addObject:@[ L(@"Max output"), [NSString stringWithFormat:@"%@ tokens", [ORUtils formatContextLength:m.maxCompletionTokens]] ]];
    [rows addObject:@[ L(@"Price"), [m priceLine] ]];
    if (m.imagePrice && [m.imagePrice doubleValue] > 0) [rows addObject:@[ L(@"Image input"), [NSString stringWithFormat:@"$%.4f / %@", [m.imagePrice doubleValue], L(@"image")] ]];
    [rows addObject:@[ L(@"Input"), [m.inputModalities componentsJoinedByString:@", "] ?: @"text" ]];
    [rows addObject:@[ L(@"Output"), [m.outputModalities componentsJoinedByString:@", "] ?: @"text" ]];
    if (m.supportedParameters.count) [rows addObject:@[ L(@"Parameters"), [m.supportedParameters componentsJoinedByString:@", "] ]];
    if (m.created > 0) {
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.dateStyle = NSDateFormatterMediumStyle;
        [rows addObject:@[ L(@"Added"), [df stringFromDate:[NSDate dateWithTimeIntervalSince1970:m.created]] ]];
    }
    self.rows = rows;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    ORTheme *t = [ORTheme shared];
    [t applyToTableView:self.tableView grouped:YES];
    [t applyToNavigationBar:self.navigationController.navigationBar];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0) return (NSInteger)self.rows.count;
    if (section == 1) return self.model.modelDescription.length ? 1 : 0;
    return [self.model supportsImages] ? 2 : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (section == 1 && self.model.modelDescription.length) return L(@"Description");
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    // (the margins of grouped cells: iOS 6's, or the rounded groups' of iOS 13+ / none of iOS 7-12)
    CGFloat width = self.tableView.bounds.size.width - ORModernGroupedCellMargins(ORIsPad() ? 90 : 40);
    if (indexPath.section == 1) {
        CGSize s = [self.model.modelDescription sizeWithFont:[UIFont systemFontOfSize:14] constrainedToSize:CGSizeMake(width, 4000) lineBreakMode:NSLineBreakByWordWrapping];
        return MAX(44, s.height + 24);
    }
    if (indexPath.section == 0) {
        NSString *value = [[self.rows objectAtIndex:indexPath.row] objectAtIndex:1];
        CGSize s = [value sizeWithFont:[UIFont systemFontOfSize:14] constrainedToSize:CGSizeMake(width - 90, 400) lineBreakMode:NSLineBreakByWordWrapping];
        return MAX(44, s.height + 22);
    }
    return 44;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell;
    if (indexPath.section == 0) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue2 reuseIdentifier:nil];
        NSArray *pair = self.rows[indexPath.row];
        cell.textLabel.text = pair[0];
        cell.detailTextLabel.text = pair[1];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:14];
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == 1) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.textLabel.text = self.model.modelDescription;
        cell.textLabel.font = [UIFont systemFontOfSize:14];
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.lineBreakMode = NSLineBreakByWordWrapping;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.text = indexPath.row == 0 ? L(@"Use this model") : L(@"Use as vision helper");
    }
    [[ORTheme shared] styleCell:cell];
    if (indexPath.section == 0) cell.detailTextLabel.textColor = [[ORTheme shared] primaryTextColor];
    if (indexPath.section == 2) cell.textLabel.textColor = [[ORTheme shared] accentColor];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 2) return;
    if (indexPath.row == 0) { if (self.onUse) self.onUse(self.model); }
    else { if (self.onUseAsVision) self.onUseAsVision(self.model); }
}

@end
