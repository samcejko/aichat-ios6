#import <UIKit/UIKit.h>

// Enter / verify the OpenRouter API key. Used for onboarding and from Settings.
@interface ORAPIKeyViewController : UIViewController

@property (nonatomic) BOOL onboarding;                 // no cancel button, must save a key
@property (nonatomic, copy) void (^completion)(BOOL saved);

@end
