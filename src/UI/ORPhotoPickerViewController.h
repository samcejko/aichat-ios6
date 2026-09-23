#import <UIKit/UIKit.h>

// Multi-select photo picker built on AssetsLibrary (iOS 6 has no multi-select in UIImagePickerController).
// Root: album list; pushes a thumbnail grid. Completion receives an array of UIImage (nil on cancel).
@interface ORPhotoPickerViewController : UITableViewController

@property (nonatomic, copy) void (^completion)(NSArray *images);
@property (nonatomic) NSUInteger maxSelection;   // default 8

@end
