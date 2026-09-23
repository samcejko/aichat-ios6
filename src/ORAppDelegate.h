#import <UIKit/UIKit.h>

@class ORChatViewController;

@interface ORAppDelegate : UIResponder <UIApplicationDelegate>

@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UINavigationController *navigationController;
@property (nonatomic, strong) ORChatViewController *chatViewController;

@end
