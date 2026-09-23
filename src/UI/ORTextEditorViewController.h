#import <UIKit/UIKit.h>

// Full screen multi-line text editor (system prompt).
@interface ORTextEditorViewController : UIViewController

@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *placeholderText;
@property (nonatomic, copy) void (^completion)(NSString *text);   // nil on cancel

@end
