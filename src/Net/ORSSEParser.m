#import "ORSSEParser.h"

@interface ORSSEParser ()
@property (nonatomic, strong) NSMutableData *buffer;
@property (nonatomic, strong) NSMutableString *eventData;
@end

@implementation ORSSEParser

- (instancetype)init
{
    self = [super init];
    if (self) {
        _buffer = [NSMutableData data];
        _eventData = [NSMutableString string];
    }
    return self;
}

- (void)dispatchEvent
{
    if (self.eventData.length == 0) return;
    // Strip the trailing newline added after each data line.
    NSString *payload = [self.eventData hasSuffix:@"\n"] ? [self.eventData substringToIndex:self.eventData.length - 1] : [self.eventData copy];
    [self.eventData setString:@""];
    if (self.onEvent) self.onEvent(payload);
}

- (void)handleLine:(NSString *)line
{
    if ([line hasSuffix:@"\r"]) line = [line substringToIndex:line.length - 1];
    if (line.length == 0) {
        [self dispatchEvent];
        return;
    }
    if ([line hasPrefix:@":"]) return;   // comment / keep-alive
    NSRange colon = [line rangeOfString:@":"];
    NSString *field = colon.location == NSNotFound ? line : [line substringToIndex:colon.location];
    NSString *value = colon.location == NSNotFound ? @"" : [line substringFromIndex:colon.location + 1];
    if ([value hasPrefix:@" "]) value = [value substringFromIndex:1];
    if ([field isEqualToString:@"data"]) {
        [self.eventData appendString:value];
        [self.eventData appendString:@"\n"];
    }
    // "event", "id", "retry" are ignored.
}

- (void)feedData:(NSData *)data
{
    if (!data.length) return;
    [self.buffer appendData:data];
    for (;;) {
        const uint8_t *bytes = (const uint8_t *)self.buffer.bytes;
        NSUInteger len = self.buffer.length;
        NSUInteger nl = NSNotFound;
        for (NSUInteger i = 0; i < len; i++) {
            if (bytes[i] == '\n') { nl = i; break; }
        }
        if (nl == NSNotFound) break;
        NSString *line = [[NSString alloc] initWithBytes:bytes length:nl encoding:NSUTF8StringEncoding];
        if (!line) {
            // Invalid UTF-8 in the middle of a multibyte sequence should not happen at a newline,
            // but be defensive.
            line = [[NSString alloc] initWithBytes:bytes length:nl encoding:NSISOLatin1StringEncoding] ?: @"";
        }
        [self.buffer replaceBytesInRange:NSMakeRange(0, nl + 1) withBytes:NULL length:0];
        [self handleLine:line];
    }
}

- (void)finish
{
    if (self.buffer.length) {
        NSString *line = [[NSString alloc] initWithData:self.buffer encoding:NSUTF8StringEncoding];
        self.buffer.length = 0;
        if (line) [self handleLine:line];
    }
    [self dispatchEvent];
}

@end
