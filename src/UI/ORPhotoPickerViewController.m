#import "ORPhotoPickerViewController.h"
#import "ORTheme.h"
#import "ORUtils.h"
#import "ORCommon.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import <QuartzCore/QuartzCore.h>

static const CGFloat kCellSize = 76.0;

#pragma mark - Grid cell

@interface ORPhotoCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIView *checkView;
@property (nonatomic, strong) UILabel *checkLabel;
- (void)setChecked:(BOOL)checked;
@end

@implementation ORPhotoCell
- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _imageView = [[UIImageView alloc] initWithFrame:self.contentView.bounds];
        _imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _imageView.contentMode = UIViewContentModeScaleAspectFill;
        _imageView.clipsToBounds = YES;
        _imageView.backgroundColor = [UIColor colorWithWhite:0.85 alpha:1];
        [self.contentView addSubview:_imageView];
        _checkView = [[UIView alloc] initWithFrame:CGRectMake(frame.size.width - 26, 4, 22, 22)];
        _checkView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        _checkView.layer.cornerRadius = 11;
        _checkView.layer.borderWidth = 2;
        _checkView.layer.borderColor = [UIColor whiteColor].CGColor;
        _checkView.backgroundColor = [UIColor colorWithRed:0.16 green:0.45 blue:0.85 alpha:1];
        _checkLabel = [[UILabel alloc] initWithFrame:_checkView.bounds];
        _checkLabel.text = @"✓";
        _checkLabel.textColor = [UIColor whiteColor];
        _checkLabel.font = [UIFont boldSystemFontOfSize:14];
        _checkLabel.textAlignment = NSTextAlignmentCenter;
        _checkLabel.backgroundColor = [UIColor clearColor];
        [_checkView addSubview:_checkLabel];
        [self.contentView addSubview:_checkView];
        _checkView.hidden = YES;
    }
    return self;
}
- (void)setChecked:(BOOL)checked
{
    self.checkView.hidden = !checked;
    self.imageView.alpha = checked ? 0.75 : 1.0;
}
@end

#pragma mark - Grid controller

@interface ORPhotoGridViewController : UICollectionViewController
@property (nonatomic, strong) ALAssetsLibrary *library;    // keeps the group alive
@property (nonatomic, strong) ALAssetsGroup *group;
@property (nonatomic, strong) NSMutableArray *assets;     // ALAsset, newest first
@property (nonatomic, strong) NSMutableSet *selected;     // NSNumber index
@property (nonatomic) NSUInteger maxSelection;
@property (nonatomic, copy) void (^completion)(NSArray *images);
@end

@implementation ORPhotoGridViewController

- (instancetype)init
{
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.itemSize = CGSizeMake(kCellSize, kCellSize);
    layout.minimumInteritemSpacing = 4;
    layout.minimumLineSpacing = 4;
    layout.sectionInset = UIEdgeInsetsMake(4, 4, 4, 4);
    self = [super initWithCollectionViewLayout:layout];
    if (self) {
        _selected = [NSMutableSet set];
        _assets = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = [self.group valueForProperty:ALAssetsGroupPropertyName] ?: L(@"Photos");
    [self.collectionView registerClass:[ORPhotoCell class] forCellWithReuseIdentifier:@"photo"];
    self.collectionView.backgroundColor = [[ORTheme shared] tableBackgroundColor];
    self.collectionView.alwaysBounceVertical = YES;
    [self updateDoneButton];

    [self.group setAssetsFilter:[ALAssetsFilter allPhotos]];
    NSMutableArray *list = [NSMutableArray array];
    [self.group enumerateAssetsUsingBlock:^(ALAsset *result, NSUInteger index, BOOL *stop) {
        if (result) [list addObject:result];
    }];
    // newest first
    for (NSInteger i = (NSInteger)list.count - 1; i >= 0; i--) [self.assets addObject:list[i]];
    [self.collectionView reloadData];
}

- (void)updateDoneButton
{
    NSString *title = self.selected.count ? [NSString stringWithFormat:@"%@ (%lu)", L(@"Add"), (unsigned long)self.selected.count] : L(@"Add");
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:title style:UIBarButtonItemStyleDone target:self action:@selector(doneTapped)];
    self.navigationItem.rightBarButtonItem.enabled = self.selected.count > 0;
}

- (void)doneTapped
{
    NSArray *indexes = [[self.selected allObjects] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray *images = [NSMutableArray array];
    for (NSNumber *n in indexes) {
        ALAsset *asset = self.assets[[n unsignedIntegerValue]];
        ALAssetRepresentation *rep = [asset defaultRepresentation];
        CGImageRef cg = [rep fullScreenImage];   // already rotated, capped at screen size
        if (!cg) cg = [rep fullResolutionImage];
        if (!cg) continue;
        [images addObject:[UIImage imageWithCGImage:cg]];
    }
    if (self.completion) self.completion(images);
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return (NSInteger)self.assets.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    ORPhotoCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"photo" forIndexPath:indexPath];
    ALAsset *asset = self.assets[indexPath.item];
    CGImageRef thumb = [asset thumbnail];
    cell.imageView.image = thumb ? [UIImage imageWithCGImage:thumb] : nil;
    [cell setChecked:[self.selected containsObject:@(indexPath.item)]];
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    NSNumber *key = @(indexPath.item);
    if ([self.selected containsObject:key]) {
        [self.selected removeObject:key];
    } else {
        if (self.selected.count >= self.maxSelection) {
            [ORUtils alertWithTitle:L(@"Limit reached") message:[NSString stringWithFormat:L(@"You can attach up to %lu photos at once."), (unsigned long)self.maxSelection]];
            return;
        }
        [self.selected addObject:key];
    }
    ORPhotoCell *cell = (ORPhotoCell *)[collectionView cellForItemAtIndexPath:indexPath];
    [cell setChecked:[self.selected containsObject:key]];
    [self updateDoneButton];
}

@end

#pragma mark - Album list

@interface ORPhotoPickerViewController ()
@property (nonatomic, strong) ALAssetsLibrary *library;
@property (nonatomic, strong) NSMutableArray *groups;
@property (nonatomic, strong) UILabel *statusLabel;
@end

@implementation ORPhotoPickerViewController

- (instancetype)init
{
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        _maxSelection = 8;
        _groups = [NSMutableArray array];
        self.contentSizeForViewInPopover = CGSizeMake(420, 600);
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = L(@"Albums");
    self.tableView.rowHeight = 64;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelTapped)];
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:15];
    self.statusLabel.backgroundColor = [UIColor clearColor];
    self.statusLabel.text = L(@"Loading albums…");
    [self loadGroups];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    ORTheme *t = [ORTheme shared];
    [t applyToTableView:self.tableView grouped:NO];
    [t applyToNavigationBar:self.navigationController.navigationBar];
    self.statusLabel.textColor = [t secondaryTextColor];
    [self.tableView reloadData];
}

- (void)showStatus:(NSString *)text
{
    self.statusLabel.text = text;
    self.statusLabel.frame = CGRectInset(self.tableView.bounds, 24, 0);
    self.tableView.backgroundView = text ? self.statusLabel : nil;
    self.tableView.separatorStyle = text ? UITableViewCellSeparatorStyleNone : UITableViewCellSeparatorStyleSingleLine;
}

- (void)loadGroups
{
    [self showStatus:L(@"Loading albums…")];
    self.library = [[ALAssetsLibrary alloc] init];
    [self.library enumerateGroupsWithTypes:ALAssetsGroupAll usingBlock:^(ALAssetsGroup *group, BOOL *stop) {
        if (group) {
            [group setAssetsFilter:[ALAssetsFilter allPhotos]];
            if ([group numberOfAssets] > 0) [self.groups addObject:group];
        } else {
            // enumeration finished
            [self showStatus:self.groups.count ? nil : L(@"No photos found.")];
            [self.tableView reloadData];
        }
    } failureBlock:^(NSError *error) {
        [self showStatus:L(@"Photo access was denied. Allow it in Settings > Privacy > Photos.")];
    }];
}

- (void)cancelTapped
{
    if (self.completion) self.completion(nil);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)self.groups.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cid = @"album";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:16];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    ALAssetsGroup *g = self.groups[indexPath.row];
    cell.textLabel.text = [g valueForProperty:ALAssetsGroupPropertyName];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld", (long)[g numberOfAssets]];
    CGImageRef poster = [g posterImage];
    cell.imageView.image = poster ? [UIImage imageWithCGImage:poster] : nil;
    [[ORTheme shared] styleCell:cell];
    cell.detailTextLabel.textColor = [[ORTheme shared] secondaryTextColor];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    ORPhotoGridViewController *grid = [[ORPhotoGridViewController alloc] init];
    grid.library = self.library;
    grid.group = self.groups[indexPath.row];
    grid.maxSelection = self.maxSelection;
    grid.completion = self.completion;
    [self.navigationController pushViewController:grid animated:YES];
}

@end
