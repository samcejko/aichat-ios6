#include <limits.h>
#import "ORHTTPRequest.h"
#import "ORTLSSocket.h"
#import "ORCommon.h"
#import "ORSettings.h"
#import "ORUtils.h"

typedef NS_ENUM(NSInteger, ORChunkState) {
    ORChunkStateSize = 0,
    ORChunkStateData,
    ORChunkStateDataEnd,
    ORChunkStateTrailer,
    ORChunkStateDone,
};

@interface ORHTTPRequest ()
@property (nonatomic, strong) ORTLSSocket *socket;
@property (nonatomic, strong) ORHTTPRequest *selfRetain;
@property (nonatomic) NSInteger statusCode;
@property (nonatomic, strong) NSDictionary *responseHeaders;
@property (nonatomic) BOOL isCancelled;
@property (nonatomic) BOOL isFinished;
@property (nonatomic, copy) NSString *tlsInfo;
@property (nonatomic, strong) NSMutableData *accumulated;

// body decoding state
@property (nonatomic) BOOL chunked;
@property (nonatomic) long long contentLength;      // -1 unknown
@property (nonatomic) long long bodyReceived;
@property (nonatomic) ORChunkState chunkState;
@property (nonatomic) BOOL bodyError;
@property (nonatomic) long long chunkRemaining;
@end

@implementation ORHTTPRequest

+ (instancetype)requestWithMethod:(NSString *)method host:(NSString *)host path:(NSString *)path
{
    ORHTTPRequest *r = [[ORHTTPRequest alloc] init];
    r.method = method;
    r.host = host;
    r.path = path;
    return r;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _port = 443;
        _secure = YES;
        _connectTimeout = 15;
        _readTimeout = 120;
        _verifyTLS = [ORSettings shared].verifyTLS;
        _contentLength = -1;
        _accumulated = [NSMutableData data];
    }
    return self;
}

- (void)start
{
    self.selfRetain = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self run];
    });
}

- (void)cancel
{
    if (self.isFinished) return;
    self.isCancelled = YES;
    [self.socket cancel];
}

#pragma mark - Request

- (NSData *)serializedRequest
{
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"%@ %@ HTTP/1.1\r\n", self.method ?: @"GET", self.path ?: @"/"];
    NSString *authority=[self.host rangeOfString:@":"].location!=NSNotFound?[NSString stringWithFormat:@"[%@]",self.host]:self.host;
    if(self.port!=(self.secure?443:80))authority=[authority stringByAppendingFormat:@":%ld",(long)self.port];
    [s appendFormat:@"Host: %@\r\n", authority];
    [s appendFormat:@"User-Agent: %@\r\n", [ORUtils userAgent]];
    [s appendString:@"Connection: close\r\n"];
    BOOL hasContentType = NO;
    for (NSString *key in self.headers) {
        if ([[key lowercaseString] isEqualToString:@"content-type"]) hasContentType = YES;
        NSString *value = [[[self.headers[key] description] stringByReplacingOccurrencesOfString:@"\n" withString:@" "] stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
        [s appendFormat:@"%@: %@\r\n", key, value];
    }
    if (self.body) {
        if (!hasContentType) [s appendString:@"Content-Type: application/json\r\n"];
        [s appendFormat:@"Content-Length: %lu\r\n", (unsigned long)self.body.length];
    }
    [s appendString:@"\r\n"];
    NSMutableData *d = [[s dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    if (self.body) [d appendData:self.body];
    return d;
}

#pragma mark - Worker

- (void)finishWithError:(NSError *)error
{
    if (self.isFinished) return;
    self.isFinished = YES;
    [self.socket close];
    self.socket = nil;
    NSData *body = self.streamBody ? nil : [self.accumulated copy];
    NSInteger status = self.statusCode;
    ORHTTPCompleteBlock done = self.onComplete;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (done) done(status, body, error);
        self.onComplete = nil;
        self.onData = nil;
        self.onHeaders = nil;
        self.selfRetain = nil;
    });
}

- (void)deliverBodyBytes:(const void *)bytes length:(NSUInteger)length
{
    if (length == 0) return;
    self.bodyReceived += length;
    if (self.streamBody) {
        NSData *chunk = [NSData dataWithBytes:bytes length:length];
        ORHTTPDataBlock cb = self.onData;
        if (cb) dispatch_async(dispatch_get_main_queue(), ^{ cb(chunk); });
    } else {
        [self.accumulated appendBytes:bytes length:length];
    }
}

// Returns YES when the whole body has been consumed.
- (BOOL)consumeBody:(NSMutableData *)buffer
{
    if (!self.chunked) {
        if (buffer.length) {
            [self deliverBodyBytes:buffer.bytes length:buffer.length];
            buffer.length = 0;
        }
        return self.contentLength >= 0 && self.bodyReceived >= self.contentLength;
    }
    // Chunked transfer encoding state machine.
    for (;;) {
        const uint8_t *bytes = (const uint8_t *)buffer.bytes;
        NSUInteger len = buffer.length;
        if (self.chunkState == ORChunkStateSize || self.chunkState == ORChunkStateTrailer) {
            NSUInteger lineEnd = NSNotFound;
            for (NSUInteger i = 0; i + 1 < len; i++) {
                if (bytes[i] == '\r' && bytes[i + 1] == '\n') { lineEnd = i; break; }
            }
            if (lineEnd == NSNotFound) return NO;   // need more data
            NSString *line = [[NSString alloc] initWithBytes:bytes length:lineEnd encoding:NSASCIIStringEncoding];
            if (!line) { self.bodyError = YES; return YES; }
            [buffer replaceBytesInRange:NSMakeRange(0, lineEnd + 2) withBytes:NULL length:0];
            if (self.chunkState == ORChunkStateTrailer) {
                if (line.length == 0) { self.chunkState = ORChunkStateDone; return YES; }
                continue;
            }
            if (line.length == 0) { self.bodyError = YES; return YES; }
            NSRange semi = [line rangeOfString:@";"];
            NSString *hex = semi.location == NSNotFound ? line : [line substringToIndex:semi.location];
            // Parse every digit and reject overflow before narrowing to signed storage.
            const char *digits = [hex UTF8String];
            unsigned long long size = 0;
            if (!digits || !*digits) { self.bodyError = YES; return YES; }
            NSUInteger digitCount = [hex lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
            for (NSUInteger i = 0; i < digitCount; i++) {
                unsigned char c = (unsigned char)digits[i];
                unsigned int digit;
                if (c >= '0' && c <= '9') digit = c - '0';
                else if (c >= 'a' && c <= 'f') digit = c - 'a' + 10;
                else if (c >= 'A' && c <= 'F') digit = c - 'A' + 10;
                else { self.bodyError = YES; return YES; }
                if (size > ((unsigned long long)LLONG_MAX - digit) / 16) {
                    self.bodyError = YES; return YES;
                }
                size = size * 16 + digit;
            }
            if (size == 0) {
                self.chunkState = ORChunkStateTrailer;
                continue;
            }
            self.chunkRemaining = (long long)size;
            self.chunkState = ORChunkStateData;
            continue;
        }
        if (self.chunkState == ORChunkStateData) {
            if (len == 0) return NO;
            NSUInteger take = (NSUInteger)MIN((long long)len, self.chunkRemaining);
            [self deliverBodyBytes:bytes length:take];
            [buffer replaceBytesInRange:NSMakeRange(0, take) withBytes:NULL length:0];
            self.chunkRemaining -= take;
            if (self.chunkRemaining == 0) self.chunkState = ORChunkStateDataEnd;
            continue;
        }
        if (self.chunkState == ORChunkStateDataEnd) {
            if (len < 2) return NO;
            if (bytes[0] != '\r' || bytes[1] != '\n') {
                self.bodyError = YES; return YES;
            }
            // expect CRLF
            [buffer replaceBytesInRange:NSMakeRange(0, 2) withBytes:NULL length:0];
            self.chunkState = ORChunkStateSize;
            continue;
        }
        return YES; // done
    }
}

- (BOOL)parseHeadersFromBuffer:(NSMutableData *)buffer error:(NSError **)error
{
    const uint8_t *bytes = (const uint8_t *)buffer.bytes;
    NSUInteger len = buffer.length;
    NSUInteger end = NSNotFound;
    for (NSUInteger i = 0; i + 3 < len; i++) {
        if (bytes[i] == '\r' && bytes[i + 1] == '\n' && bytes[i + 2] == '\r' && bytes[i + 3] == '\n') { end = i; break; }
    }
    if (end == NSNotFound) {
        if (len > 64 * 1024) {
            if (error) *error = ORMakeError(ORErrorBadResponse, L(@"The server sent an invalid response."));
            return NO;
        }
        return NO;
    }
    NSString *head = [[NSString alloc] initWithBytes:bytes length:end encoding:NSISOLatin1StringEncoding] ?: @"";
    [buffer replaceBytesInRange:NSMakeRange(0, end + 4) withBytes:NULL length:0];
    NSArray *lines = [head componentsSeparatedByString:@"\r\n"];
    if (lines.count == 0) {
        if (error) *error = ORMakeError(ORErrorBadResponse, L(@"The server sent an invalid response."));
        return NO;
    }
    NSString *statusLine = lines[0];
    NSArray *parts = [statusLine componentsSeparatedByString:@" "];
    NSInteger status = parts.count >= 2 ? [parts[1] integerValue] : 0;
    if (status <= 0) {
        if (error) *error = ORMakeError(ORErrorBadResponse, [NSString stringWithFormat:L(@"Unexpected response: %@"), [ORUtils truncate:statusLine to:80]]);
        return NO;
    }
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    for (NSUInteger i = 1; i < lines.count; i++) {
        NSString *line = lines[i];
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location == NSNotFound) continue;
        NSString *name = [[[line substringToIndex:colon.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString];
        NSString *value = [[line substringFromIndex:colon.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *existing = headers[name];
        headers[name] = existing ? [NSString stringWithFormat:@"%@, %@", existing, value] : value;
    }
    self.statusCode = status;
    self.responseHeaders = headers;
    NSString *te = [[headers objectForKey:@"transfer-encoding"] lowercaseString];
    self.chunked = te && [te rangeOfString:@"chunked"].location != NSNotFound;
    NSString *cl = [headers objectForKey:@"content-length"];
    self.contentLength = (cl && !self.chunked) ? [cl longLongValue] : -1;
    return YES;
}

- (void)run
{
    self.socket = [[ORTLSSocket alloc] init];
    NSError *error = nil;
    if (self.isCancelled) {
        [self finishWithError:ORMakeError(ORErrorCancelled, L(@"Cancelled"))];
        return;
    }
    self.socket.plain = !self.secure;
    if (![self.socket connectToHost:self.host port:(int)self.port verify:self.verifyTLS
                   connectTimeoutMs:(int)(self.connectTimeout * 1000) readTimeoutMs:(int)(self.readTimeout * 1000) error:&error]) {
        [self finishWithError:error ?: ORMakeError(ORErrorNetwork, L(@"Connection failed."))];
        return;
    }
    self.tlsInfo = [NSString stringWithFormat:@"%@ %@", self.socket.tlsVersion ?: @"", self.socket.cipherSuite ?: @""];
    if (![self.socket writeData:[self serializedRequest] error:&error]) {
        [self finishWithError:error ?: ORMakeError(ORErrorNetwork, L(@"Sending the request failed."))];
        return;
    }

    NSMutableData *buffer = [NSMutableData data];
    BOOL headersDone = NO;
    BOOL bodyDone = NO;
    const NSUInteger chunkSize = 16384;
    uint8_t *tmp = (uint8_t *)malloc(chunkSize);
    if (!tmp) {
        [self finishWithError:ORMakeError(ORErrorNetwork, @"Out of memory")];
        return;
    }
    while (!bodyDone) {
        NSError *readError = nil;
        NSInteger n = [self.socket readIntoBuffer:tmp maxLength:chunkSize error:&readError];
        if (n < 0) {
            free(tmp);
            [self finishWithError:readError ?: ORMakeError(ORErrorNetwork, L(@"Connection lost."))];
            return;
        }
        if (n == 0) {
            // EOF
            if (!headersDone) {
                free(tmp);
                [self finishWithError:ORMakeError(ORErrorBadResponse, L(@"The server closed the connection without responding."))];
                return;
            }
            if (!self.chunked && self.contentLength < 0) {
                // body ends with the connection
                [self consumeBody:buffer];
                bodyDone = YES;
                break;
            }
            // Incomplete chunked / content-length body: deliver what we have.
            [self consumeBody:buffer];
            ORLog(@"HTTP body ended early (chunked=%d, received=%lld)", self.chunked, self.bodyReceived);
            bodyDone = YES;
            break;
        }
        [buffer appendBytes:tmp length:(NSUInteger)n];
        if (!headersDone) {
            NSError *hErr = nil;
            if ([self parseHeadersFromBuffer:buffer error:&hErr]) {
                headersDone = YES;
                NSInteger status = self.statusCode;
                NSDictionary *hdrs = self.responseHeaders;
                ORHTTPHeadersBlock hb = self.onHeaders;
                if (hb) dispatch_async(dispatch_get_main_queue(), ^{ hb(status, hdrs); });
                if ([self.method isEqualToString:@"HEAD"] || status == 204 || status == 304 || (status >= 100 && status < 200)) {
                    bodyDone = YES;
                    break;
                }
            } else if (hErr) {
                free(tmp);
                [self finishWithError:hErr];
                return;
            } else {
                continue;   // need more header bytes
            }
        }
        if ([self consumeBody:buffer]) bodyDone = YES;
    }
    free(tmp);
    [self finishWithError:self.bodyError ? ORMakeError(ORErrorBadResponse, L(@"The server sent an invalid response.")) : nil];
}

@end
