#import <UIKit/UIKit.h>
#import "ORModelInfo.h"

typedef void (^ORModelPickerCompletion)(ORModelInfo *model);

// Searchable model list with "free only" / "images" filters and sorting.
@interface ORModelPickerViewController : UIViewController

@property (nonatomic, copy) NSString *selectedModelId;
@property (nonatomic) BOOL forceImagesOnly;
@property (nonatomic) BOOL showsCancelButton;
@property (nonatomic, copy) NSString *titleText;
@property (nonatomic, copy) ORModelPickerCompletion completion;   // called with nil on cancel

@end
