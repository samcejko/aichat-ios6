#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// Install only missing entry points, before the collection-view constructor runs.
// Some iOS 5 Foundation releases lack the public subscript/firstObject selectors.
static void ORAddMissing(Class cls, SEL destination, SEL implementation)
{
    if (class_getInstanceMethod(cls, destination)) return;
    Method method = class_getInstanceMethod(cls, implementation);
    class_addMethod(cls, destination, method_getImplementation(method), method_getTypeEncoding(method));
}

@implementation NSArray (OREarlierFoundation)
+ (void)load
{
    ORAddMissing(self, @selector(firstObject), @selector(or_firstObject));
    ORAddMissing(self, @selector(objectAtIndexedSubscript:), @selector(objectAtIndex:));
}
- (id)or_firstObject { return self.count ? [self objectAtIndex:0] : nil; }
@end

@implementation NSMutableArray (OREarlierFoundation)
+ (void)load { ORAddMissing(self, @selector(setObject:atIndexedSubscript:), @selector(or_setObject:atIndex:)); }
- (void)or_setObject:(id)object atIndex:(NSUInteger)index
{
    if (index == self.count) [self addObject:object];
    else [self replaceObjectAtIndex:index withObject:object];
}
@end

@implementation NSDictionary (OREarlierFoundation)
+ (void)load { ORAddMissing(self, @selector(objectForKeyedSubscript:), @selector(objectForKey:)); }
@end

@implementation NSMutableDictionary (OREarlierFoundation)
+ (void)load { ORAddMissing(self, @selector(setObject:forKeyedSubscript:), @selector(or_setObject:forKey:)); }
- (void)or_setObject:(id)object forKey:(id<NSCopying>)key
{
    if (object) [self setObject:object forKey:key];
    else [self removeObjectForKey:key];
}
@end

NSDictionary *ORFoundationCompatibilityTest(void) {
    NSMutableArray *array=[NSMutableArray array];[array or_setObject:@"first" atIndex:0];[array or_setObject:@"replacement" atIndex:0];[array or_setObject:@"second" atIndex:1];
    NSMutableDictionary *dict=[NSMutableDictionary dictionary];[dict or_setObject:@"value" forKey:@"key"];[dict or_setObject:nil forKey:@"key"];
    return @{@"arrayAppendReplace":@(array.count==2 && [[array objectAtIndex:0] isEqual:@"replacement"]),@"nilRemovesDictionaryValue":@(dict.count==0),@"firstObjectEmpty":@([[@[] copy] or_firstObject]==nil),@"firstObjectValue":@([[array or_firstObject] isEqual:@"replacement"])};
}
