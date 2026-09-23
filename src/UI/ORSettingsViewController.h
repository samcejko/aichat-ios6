#import <UIKit/UIKit.h>

@interface ORSettingsViewController : UITableViewController

@property (nonatomic, copy) void (^completion)(void);        // Done tapped
@property (nonatomic, copy) void (^onHistoryCleared)(void);

@end
