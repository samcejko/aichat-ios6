#import <UIKit/UIKit.h>
#import "ORModelInfo.h"

// Read-only details of one model with "use" actions.
@interface ORModelDetailViewController : UITableViewController

@property (nonatomic, strong) ORModelInfo *model;
@property (nonatomic, copy) void (^onUse)(ORModelInfo *model);
@property (nonatomic, copy) void (^onUseAsVision)(ORModelInfo *model);

@end
