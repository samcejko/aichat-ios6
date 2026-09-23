#import "ORTLSSocket.h"
#import "ORCommon.h"

#include "mbedtls/build_info.h"
#include "mbedtls/ssl.h"
#include "mbedtls/net_sockets.h"
#include "mbedtls/entropy.h"
#include "mbedtls/ctr_drbg.h"
#include "mbedtls/x509_crt.h"
#include "mbedtls/error.h"
#if defined(MBEDTLS_PSA_CRYPTO_C)
#include "psa/crypto.h"
#endif

#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <poll.h>
#include <string.h>
#include <stdio.h>

static mbedtls_x509_crt g_cacert;
static BOOL g_caLoaded = NO;
static NSInteger g_caCount = 0;
static dispatch_once_t g_caOnce;

static NSString *ORMbedError(int ret)
{
    char buf[200];
    mbedtls_strerror(ret, buf, sizeof(buf));
    return [NSString stringWithFormat:@"%s (-0x%04x)", buf, (unsigned int)(-ret)];
}

static void ORSetError(NSError **error, NSInteger code, NSString *message)
{
    if (error) *error = ORMakeError(code, message);
}

static void ORLoadCABundle(void)
{
    mbedtls_x509_crt_init(&g_cacert);
#if defined(MBEDTLS_PSA_CRYPTO_C)
    psa_status_t st = psa_crypto_init();
    if (st != PSA_SUCCESS) ORLog(@"psa_crypto_init failed: %d", (int)st);
#endif
    NSString *path = [[NSBundle mainBundle] pathForResource:@"cacert" ofType:@"pem"];
    if (!path) {
        ORLog(@"cacert.pem is missing from the app bundle");
        return;
    }
    NSData *pem = [NSData dataWithContentsOfFile:path];
    if (!pem.length) {
        ORLog(@"cacert.pem is empty");
        return;
    }
    NSMutableData *buf = [pem mutableCopy];
    uint8_t zero = 0;
    [buf appendBytes:&zero length:1];   // PEM input must be NUL terminated, length includes the NUL
    int ret = mbedtls_x509_crt_parse(&g_cacert, (const unsigned char *)buf.bytes, buf.length);
    if (ret < 0) {
        ORLog(@"CA bundle parse failed: %@", ORMbedError(ret));
        return;
    }
    NSInteger n = 0;
    for (mbedtls_x509_crt *c = &g_cacert; c != NULL && c->version != 0; c = c->next) n++;
    g_caCount = n;
    g_caLoaded = n > 0;
    ORLog(@"CA bundle loaded: %ld roots (%d unparsable)", (long)n, ret);
}

@implementation ORTLSSocket {
    mbedtls_net_context _net;
    mbedtls_ssl_context _ssl;
    mbedtls_ssl_config _conf;
    mbedtls_entropy_context _entropy;
    mbedtls_ctr_drbg_context _ctr;
    BOOL _initialized;
    BOOL _connected;
    volatile BOOL _cancelled;
}

+ (void)ensureCALoaded
{
    dispatch_once(&g_caOnce, ^{ ORLoadCABundle(); });
}

+ (void)warmUp
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        [ORTLSSocket ensureCALoaded];
    });
}

+ (BOOL)caBundleAvailable
{
    [self ensureCALoaded];
    return g_caLoaded;
}

+ (NSInteger)caCertificateCount
{
    [self ensureCALoaded];
    return g_caCount;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        mbedtls_net_init(&_net);
        mbedtls_ssl_init(&_ssl);
        mbedtls_ssl_config_init(&_conf);
        mbedtls_entropy_init(&_entropy);
        mbedtls_ctr_drbg_init(&_ctr);
        _initialized = YES;
    }
    return self;
}

- (void)dealloc
{
    [self close];
}

#pragma mark - TCP connect with timeout

static int ORConnectTCP(NSString *host, int port, int timeoutMs, NSError **error)
{
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;
    char portStr[16];
    snprintf(portStr, sizeof(portStr), "%d", port);
    struct addrinfo *res = NULL;
    int gai = getaddrinfo([host UTF8String], portStr, &hints, &res);
    if (gai != 0 || !res) {
        ORSetError(error, ORErrorNetwork, [NSString stringWithFormat:L(@"Could not resolve %@ (%s). Is the device online?"), host, gai_strerror(gai)]);
        return -1;
    }
    int fd = -1;
    int lastErr = 0;
    for (struct addrinfo *ai = res; ai != NULL; ai = ai->ai_next) {
        fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
        if (fd < 0) { lastErr = errno; continue; }
        int one = 1;
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
        int flags = fcntl(fd, F_GETFL, 0);
        fcntl(fd, F_SETFL, flags | O_NONBLOCK);
        int rc = connect(fd, ai->ai_addr, ai->ai_addrlen);
        if (rc != 0 && errno != EINPROGRESS) {
            lastErr = errno;
            close(fd);
            fd = -1;
            continue;
        }
        if (rc != 0) {
            struct pollfd pfd;
            pfd.fd = fd;
            pfd.events = POLLOUT;
            pfd.revents = 0;
            int pr = poll(&pfd, 1, timeoutMs);
            if (pr <= 0) {
                lastErr = (pr == 0) ? ETIMEDOUT : errno;
                close(fd);
                fd = -1;
                continue;
            }
            int soerr = 0;
            socklen_t slen = sizeof(soerr);
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &soerr, &slen);
            if (soerr != 0) {
                lastErr = soerr;
                close(fd);
                fd = -1;
                continue;
            }
        }
        fcntl(fd, F_SETFL, flags);   // back to blocking mode
        break;
    }
    freeaddrinfo(res);
    if (fd < 0) {
        NSString *why = lastErr == ETIMEDOUT ? L(@"connection timed out") : [NSString stringWithUTF8String:strerror(lastErr)];
        ORSetError(error, lastErr == ETIMEDOUT ? ORErrorTimeout : ORErrorNetwork,
                   [NSString stringWithFormat:L(@"Could not connect to %@: %@"), host, why]);
    }
    return fd;
}

#pragma mark - TLS

- (BOOL)connectToHost:(NSString *)host port:(int)port verify:(BOOL)verify
     connectTimeoutMs:(int)connectMs readTimeoutMs:(int)readMs error:(NSError **)error
{
    [ORTLSSocket ensureCALoaded];
    int ret;
    const char *pers = "aichat-ios6";

    if ((ret = mbedtls_ctr_drbg_seed(&_ctr, mbedtls_entropy_func, &_entropy, (const unsigned char *)pers, strlen(pers))) != 0) {
        ORSetError(error, ORErrorTLS, [NSString stringWithFormat:@"RNG seed failed: %@", ORMbedError(ret)]);
        return NO;
    }
    if ((ret = mbedtls_ssl_config_defaults(&_conf, MBEDTLS_SSL_IS_CLIENT, MBEDTLS_SSL_TRANSPORT_STREAM, MBEDTLS_SSL_PRESET_DEFAULT)) != 0) {
        ORSetError(error, ORErrorTLS, [NSString stringWithFormat:@"TLS config failed: %@", ORMbedError(ret)]);
        return NO;
    }
    mbedtls_ssl_conf_min_tls_version(&_conf, MBEDTLS_SSL_VERSION_TLS1_2);
    if (verify) {
        if (!g_caLoaded) {
            ORSetError(error, ORErrorCertificate, L(@"The certificate bundle is missing, cannot verify the server. You can disable verification in Settings."));
            return NO;
        }
        mbedtls_ssl_conf_authmode(&_conf, MBEDTLS_SSL_VERIFY_REQUIRED);
        mbedtls_ssl_conf_ca_chain(&_conf, &g_cacert, NULL);
    } else {
        mbedtls_ssl_conf_authmode(&_conf, MBEDTLS_SSL_VERIFY_NONE);
    }
    mbedtls_ssl_conf_rng(&_conf, mbedtls_ctr_drbg_random, &_ctr);
    mbedtls_ssl_conf_read_timeout(&_conf, (uint32_t)readMs);

    if ((ret = mbedtls_ssl_setup(&_ssl, &_conf)) != 0) {
        ORSetError(error, ORErrorTLS, [NSString stringWithFormat:@"TLS setup failed: %@", ORMbedError(ret)]);
        return NO;
    }
    if ((ret = mbedtls_ssl_set_hostname(&_ssl, [host UTF8String])) != 0) {
        ORSetError(error, ORErrorTLS, [NSString stringWithFormat:@"TLS hostname failed: %@", ORMbedError(ret)]);
        return NO;
    }

    int fd = ORConnectTCP(host, port, connectMs, error);
    if (fd < 0) return NO;
    @synchronized (self) {
        _net.fd = fd;
    }
    if (_cancelled) {
        ORSetError(error, ORErrorCancelled, L(@"Cancelled"));
        return NO;
    }
    mbedtls_ssl_set_bio(&_ssl, &_net, mbedtls_net_send, NULL, mbedtls_net_recv_timeout);

    while ((ret = mbedtls_ssl_handshake(&_ssl)) != 0) {
        if (_cancelled) {
            ORSetError(error, ORErrorCancelled, L(@"Cancelled"));
            return NO;
        }
        if (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE) continue;
        if (ret == MBEDTLS_ERR_X509_CERT_VERIFY_FAILED) {
            uint32_t flags = mbedtls_ssl_get_verify_result(&_ssl);
            char vbuf[512];
            mbedtls_x509_crt_verify_info(vbuf, sizeof(vbuf), "", flags);
            NSString *info = [[NSString stringWithUTF8String:vbuf] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString *hint = (flags & (MBEDTLS_X509_BADCERT_EXPIRED | MBEDTLS_X509_BADCERT_FUTURE)) ?
                L(@"Check the date and time of this device.") : L(@"You can disable certificate verification in Settings.");
            ORSetError(error, ORErrorCertificate, [NSString stringWithFormat:L(@"Server certificate rejected: %@. %@"), info, hint]);
            return NO;
        }
        if (ret == MBEDTLS_ERR_SSL_TIMEOUT) {
            ORSetError(error, ORErrorTimeout, L(@"TLS handshake timed out."));
            return NO;
        }
        ORSetError(error, ORErrorTLS, [NSString stringWithFormat:L(@"TLS handshake failed: %@"), ORMbedError(ret)]);
        return NO;
    }
    _connected = YES;
    return YES;
}

- (NSString *)cipherSuite
{
    if (!_connected) return nil;
    const char *cs = mbedtls_ssl_get_ciphersuite(&_ssl);
    return cs ? [NSString stringWithUTF8String:cs] : nil;
}

- (NSString *)tlsVersion
{
    if (!_connected) return nil;
    const char *v = mbedtls_ssl_get_version(&_ssl);
    return v ? [NSString stringWithUTF8String:v] : nil;
}

- (BOOL)writeData:(NSData *)data error:(NSError **)error
{
    const unsigned char *p = (const unsigned char *)data.bytes;
    size_t left = data.length;
    while (left > 0) {
        if (_cancelled) {
            ORSetError(error, ORErrorCancelled, L(@"Cancelled"));
            return NO;
        }
        int ret = mbedtls_ssl_write(&_ssl, p, left);
        if (ret > 0) {
            p += ret;
            left -= (size_t)ret;
            continue;
        }
        if (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE) continue;
        ORSetError(error, ORErrorNetwork, [NSString stringWithFormat:L(@"Sending the request failed: %@"), ORMbedError(ret)]);
        return NO;
    }
    return YES;
}

- (NSInteger)readIntoBuffer:(void *)buffer maxLength:(NSUInteger)maxLength error:(NSError **)error
{
    for (;;) {
        if (_cancelled) {
            ORSetError(error, ORErrorCancelled, L(@"Cancelled"));
            return -1;
        }
        int ret = mbedtls_ssl_read(&_ssl, (unsigned char *)buffer, maxLength);
        if (ret > 0) return ret;
        if (ret == 0 || ret == MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY) return 0;
        if (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE) continue;
        if (ret == MBEDTLS_ERR_NET_CONN_RESET) return 0;   // abrupt close without close_notify
        if (ret == MBEDTLS_ERR_SSL_TIMEOUT) {
            ORSetError(error, ORErrorTimeout, L(@"The server stopped responding (timeout)."));
            return -1;
        }
        ORSetError(error, ORErrorNetwork, [NSString stringWithFormat:L(@"Receiving the response failed: %@"), ORMbedError(ret)]);
        return -1;
    }
}

- (void)cancel
{
    _cancelled = YES;
    @synchronized (self) {
        if (_net.fd >= 0) shutdown(_net.fd, SHUT_RDWR);
    }
}

- (void)close
{
    if (!_initialized) return;
    if (_connected && !_cancelled) {
        mbedtls_ssl_close_notify(&_ssl);
    }
    @synchronized (self) {
        mbedtls_net_free(&_net);
    }
    mbedtls_ssl_free(&_ssl);
    mbedtls_ssl_config_free(&_conf);
    mbedtls_ctr_drbg_free(&_ctr);
    mbedtls_entropy_free(&_entropy);
    _initialized = NO;
    _connected = NO;
}

@end
