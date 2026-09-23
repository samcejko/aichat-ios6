#import <UIKit/UIKit.h>

// List of system-prompt personas: pick the active one, add, edit, delete.
@interface ORPersonaListViewController : UITableViewController
@property (nonatomic) BOOL showsDoneButton;
@property (nonatomic, copy) void (^onDone)(void);
@end

// Name + prompt editor for one persona.
@interface ORPersonaEditViewController : UIViewController
@property (nonatomic, strong) NSDictionary *persona;      // nil = new
@property (nonatomic, copy) void (^completion)(NSDictionary *persona);   // nil on cancel
@end
