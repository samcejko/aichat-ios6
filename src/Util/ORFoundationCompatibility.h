#import <Foundation/Foundation.h>

// These selectors are implemented by ORFoundationCompatibility.m on iOS 5.
// Redeclarations make the backported API visible to availability checking.
@interface NSArray (OREarlierFoundation)
- (id)firstObject;
- (id)objectAtIndexedSubscript:(NSUInteger)index;
@end
@interface NSMutableArray (OREarlierFoundation)
- (void)setObject:(id)object atIndexedSubscript:(NSUInteger)index;
@end
@interface NSDictionary (OREarlierFoundation)
- (id)objectForKeyedSubscript:(id)key;
@end
@interface NSMutableDictionary (OREarlierFoundation)
- (void)setObject:(id)object forKeyedSubscript:(id<NSCopying>)key;
@end

NSDictionary *ORFoundationCompatibilityTest(void);
