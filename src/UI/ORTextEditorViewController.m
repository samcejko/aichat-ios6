#import "ORTextEditorViewController.h"
#import "ORTheme.h"
#import "ORCommon.h"

@interface ORTextEditorViewController () <UITextViewDelegate>
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *placeholder;
@end

@implementation ORTextEditorViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.textView.font = [UIFont systemFontOfSize:16];
    self.textView.text = self.text ?: @"";
    self.textView.delegate = self;
    [self.view addSubview:self.textView];

    self.placeholder = [[UILabel alloc] initWithFrame:CGRectMake(12, 8, self.view.bounds.size.width - 24, 60)];
    self.placeholder.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.placeholder.numberOfLines = 0;
    self.placeholder.font = [UIFont systemFontOfSize:16];
    self.placeholder.backgroundColor = [UIColor clearColor];
    self.placeholder.text = self.placeholderText;
    self.placeholder.hidden = self.textView.text.length > 0;
    [self.textView addSubview:self.placeholder];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelTapped)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(doneTapped)];

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
    self.view.backgroundColor = [t cellBackgroundColor];
    self.textView.backgroundColor = [t cellBackgroundColor];
    self.textView.textColor = [t primaryTextColor];
    self.textView.keyboardAppearance = t.isDark ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;
    self.placeholder.textColor = [t placeholderColor];
    [t applyToNavigationBar:self.navigationController.navigationBar];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self.textView becomeFirstResponder];
}

- (void)keyboardChanged:(NSNotification *)n
{
    CGRect kb = [self.view convertRect:[n.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil];
    CGFloat overlap = MAX(0, CGRectGetMaxY(self.view.bounds) - kb.origin.y);
    UIEdgeInsets insets = UIEdgeInsetsMake(0, 0, overlap, 0);
    self.textView.contentInset = insets;
    self.textView.scrollIndicatorInsets = insets;
}

- (void)textViewDidChange:(UITextView *)textView
{
    self.placeholder.hidden = textView.text.length > 0;
}

- (void)cancelTapped
{
    if (self.completion) self.completion(nil);
}

- (void)doneTapped
{
    if (self.completion) self.completion(self.textView.text ?: @"");
}

@end
