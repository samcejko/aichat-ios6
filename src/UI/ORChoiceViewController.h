#import <UIKit/UIKit.h>

// Single-choice list used by Settings.
@interface ORChoiceViewController : UITableViewController

@property (nonatomic, strong) NSArray *titles;
@property (nonatomic, strong) NSArray *subtitles;      // optional, same count
@property (nonatomic) NSInteger selectedIndex;
@property (nonatomic, copy) void (^completion)(NSInteger index);

@end
