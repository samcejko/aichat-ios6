#import "ORImageViewerViewController.h"
#import "ORTheme.h"
#import "ORUtils.h"
#import "ORCommon.h"

@interface ORImageViewerViewController () <UIScrollViewDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIImageView *imageView;
@end

@implementation ORImageViewerViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(doneTapped)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(saveTapped)];

    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.delegate = self;
    self.scrollView.backgroundColor = [UIColor blackColor];
    self.scrollView.minimumZoomScale = 1.0;
    self.scrollView.maximumZoomScale = 4.0;
    self.scrollView.showsHorizontalScrollIndicator = NO;
    self.scrollView.showsVerticalScrollIndicator = NO;
    [self.view addSubview:self.scrollView];

    self.imageView = [[UIImageView alloc] initWithImage:self.image];
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.scrollView addSubview:self.imageView];

    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTapped:)];
    doubleTap.numberOfTapsRequired = 2;
    [self.scrollView addGestureRecognizer:doubleTap];
    [[ORTheme shared] applyToNavigationBar:self.navigationController.navigationBar];
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    self.scrollView.zoomScale = 1.0;
    self.imageView.frame = self.scrollView.bounds;
    self.scrollView.contentSize = self.scrollView.bounds.size;
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView
{
    return self.imageView;
}

- (void)doubleTapped:(UITapGestureRecognizer *)g
{
    if (self.scrollView.zoomScale > 1.01) {
        [self.scrollView setZoomScale:1.0 animated:YES];
    } else {
        CGPoint p = [g locationInView:self.imageView];
        CGFloat w = self.scrollView.bounds.size.width / 2.5, h = self.scrollView.bounds.size.height / 2.5;
        [self.scrollView zoomToRect:CGRectMake(p.x - w / 2, p.y - h / 2, w, h) animated:YES];
    }
}

- (void)doneTapped
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)saveTapped
{
    if (!self.image) return;
    UIImageWriteToSavedPhotosAlbum(self.image, nil, NULL, NULL);
    [ORUtils alertWithTitle:L(@"Saved to Photos") message:[NSString stringWithFormat:L(@"%ld image(s) saved to the Camera Roll."), 1L]];
}

@end
