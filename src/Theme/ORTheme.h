#import <UIKit/UIKit.h>

// Central place for colors, fonts and the code-drawn glossy iOS 6 style artwork.
// Two styles: classic light (default UIKit look) and a dark variant (black bars).
@interface ORTheme : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) BOOL isDark;
- (void)setDark:(BOOL)dark;      // persists, posts ORThemeDidChangeNotification, updates status bar
- (void)reloadFromSettings;      // rebuild caches (font size changes etc.)

// Colors
- (UIColor *)chatBackgroundColor;
- (UIColor *)tableBackgroundColor;
- (UIColor *)cellBackgroundColor;
- (UIColor *)cellSelectedBackgroundColor;
- (UIColor *)primaryTextColor;
- (UIColor *)secondaryTextColor;
- (UIColor *)accentColor;
- (UIColor *)separatorColor;
- (UIColor *)userBubbleTextColor;
- (UIColor *)assistantBubbleTextColor;
- (UIColor *)errorTextColor;
- (UIColor *)codeBackgroundColorInUserBubble:(BOOL)inUser;
- (UIColor *)linkColor;
- (UIColor *)inputTextColor;
- (UIColor *)placeholderColor;
- (UIColor *)noteBackgroundColor;

// Artwork (stretchable)
- (UIImage *)userBubbleImage;
- (UIImage *)assistantBubbleImage;
- (UIImage *)errorBubbleImage;
- (UIImage *)inputBarBackgroundImage;
- (UIImage *)textFieldBackgroundImage;
- (UIImage *)sendButtonImageHighlighted:(BOOL)highlighted disabled:(BOOL)disabled;
- (UIImage *)stopButtonImage;
- (UIImage *)plusButtonImage;
- (UIImage *)disclosureArrowImage;

// Fonts
- (CGFloat)messageFontSize;
- (UIFont *)messageFont;
- (UIFont *)boldMessageFont;
- (UIFont *)italicMessageFont;
- (UIFont *)boldItalicMessageFont;
- (UIFont *)codeFont;
- (UIFont *)smallFont;
- (UIFont *)headingFontForLevel:(NSInteger)level;

// Applying to UIKit
- (UIBarStyle)barStyle;
- (UIStatusBarStyle)statusBarStyle;
- (void)applyToNavigationBar:(UINavigationBar *)bar;
- (void)applyToToolbar:(UIToolbar *)bar;
- (void)applyToTableView:(UITableView *)tableView grouped:(BOOL)grouped;
- (void)styleCell:(UITableViewCell *)cell;
- (void)applyToSearchBar:(UISearchBar *)bar;
- (void)applyToView:(UIView *)view;   // plain background

@end
