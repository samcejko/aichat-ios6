#import <Foundation/Foundation.h>

// Incremental Server-Sent-Events parser. Emits the concatenated "data:" payload of each event.
@interface ORSSEParser : NSObject

@property (nonatomic, copy) void (^onEvent)(NSString *data);

- (void)feedData:(NSData *)data;
- (void)finish;

@end
