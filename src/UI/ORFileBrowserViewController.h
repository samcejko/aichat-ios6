#import <UIKit/UIKit.h>

// Browses the app's Documents folder (iTunes File Sharing / "Open in…" inbox) to pick a file.
@interface ORFileBrowserViewController : UITableViewController

@property (nonatomic, copy) NSString *directory;                 // defaults to Documents
@property (nonatomic, copy) void (^completion)(NSString *path);  // nil on cancel

@end
