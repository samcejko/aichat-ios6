#import "ORAppDelegate.h"
#import "ORChatViewController.h"
#import "ORExternalOpen.h"
#import "ORChatEngine.h"
#import "ORTheme.h"
#import "ORTLSSocket.h"
#import "ORModelCatalog.h"
#import "ORSettings.h"
#import "ORAttachment.h"
#import "ORUtils.h"
#import "ORModern.h"
#import "ORCommon.h"
#import <QuartzCore/QuartzCore.h>

@interface ORAppDelegate ()
@property (nonatomic) UIBackgroundTaskIdentifier backgroundTask;
@property (nonatomic) BOOL engineBusy;
@end

@implementation ORAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    ORLog(@"AIChat %@ starting on %@ (iOS %@)", [ORUtils appVersion], [UIDevice currentDevice].model, [UIDevice currentDevice].systemVersion);
    self.backgroundTask = UIBackgroundTaskInvalid;
    // iOS 7 and newer (the arm64 build): the iOS 6 look of the bars, full-screen modals; nothing on iOS 6
    ORModernSetUp([[ORTheme shared] barStyle]);
    [ORTLSSocket warmUp];
    [[ORModelCatalog shared] loadCache];

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.chatViewController = [[ORChatViewController alloc] init];
    self.navigationController = [[UINavigationController alloc] initWithRootViewController:self.chatViewController];
    [[ORTheme shared] applyToNavigationBar:self.navigationController.navigationBar];
    self.window.rootViewController = self.navigationController;
    self.window.backgroundColor = [[ORTheme shared] chatBackgroundColor];
    [self.window makeKeyAndVisible];
    [application setStatusBarStyle:[[ORTheme shared] statusBarStyle] animated:NO];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(engineStarted:) name:ORChatEngineDidStartNotification object:nil];
    [nc addObserver:self selector:@selector(engineFinished:) name:ORChatEngineDidFinishNotification object:nil];
    [application cancelAllLocalNotifications];
    application.applicationIconBadgeNumber = 0;
    return YES;
}

// iOS 9 and newer ask this way ("Open in…" from another app)
- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary *)options
{
    return [self application:app openURL:url sourceApplication:nil annotation:nil];
}

// aichat:snapshot draws every visible window into tmp/screen.png of the data container (checking the app over SSH:
// uiopen --url aichat:snapshot, then copy the file out). The command needs a file named "debug" in Documents.
- (BOOL)handleCommandURL:(NSURL *)url
{
    NSString *target = [url.absoluteString substringFromIndex:@"aichat:".length];
    while ([target hasPrefix:@"/"]) target = [target substringFromIndex:1];
    NSString *query = nil;
    NSRange q = [target rangeOfString:@"?"];
    if (q.location != NSNotFound) { query = [target substringFromIndex:q.location + 1]; target = [target substringToIndex:q.location]; }
    BOOL debug = [[NSFileManager defaultManager] fileExistsAtPath:[[ORUtils documentsPath] stringByAppendingPathComponent:@"debug"]];
    if (!debug) return YES;
    // link?url=<percent-encoded url>: what a tapped link in a reply does (the browser chooser), for the tests
    if ([target isEqualToString:@"link"] && [query hasPrefix:@"url="]) {
        NSString *link = [[query substringFromIndex:4] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        UIViewController *top = self.window.rootViewController;
        while (top.presentedViewController) top = top.presentedViewController;
        [ORExternalOpen presentOpenInForURL:[NSURL URLWithString:link ?: @""] from:top anchor:nil];
        return YES;
    }
    if ([target isEqualToString:@"snapshot"]) {
        // (alerts and sheets have windows of their own, so all of them go into the picture)
        CGSize size = [UIScreen mainScreen].bounds.size;
        UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w.hidden || w.alpha <= 0) continue;
            CGContextSaveGState(ctx);
            CGContextTranslateCTM(ctx, w.frame.origin.x, w.frame.origin.y);
            [w.layer renderInContext:ctx];
            CGContextRestoreGState(ctx);
        }
        UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"screen.png"];
        BOOL ok = [UIImagePNGRepresentation(image) writeToFile:path atomically:YES];
        ORLog(@"Snapshot %@: %@", ok ? @"written to" : @"failed for", path);
    }
    return YES;
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
    if ([[url.scheme lowercaseString] isEqualToString:@"aichat"]) return [self handleCommandURL:url];
    if (![url isFileURL]) return NO;
    NSString *path = [url path];
    NSError *error = nil;
    ORAttachment *a = [ORAttachment attachmentByImportingFileAtPath:path displayName:[path lastPathComponent] error:&error];
    // Files arrive in Documents/Inbox; remove the original once imported.
    if ([path rangeOfString:@"/Inbox/"].location != NSNotFound) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    }
    if (!a) {
        [ORUtils alertWithTitle:L(@"Could not open file") message:error.localizedDescription ?: @""];
        return NO;
    }
    [self.chatViewController attachIncomingAttachment:a];
    return YES;
}

#pragma mark - Background completion

- (void)engineStarted:(NSNotification *)n
{
    self.engineBusy = YES;
    // (the reply may finish in the background: iOS 8 and newer show its notification only once allowed)
    ORModernRequestNotificationPermission();
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) [self beginBackgroundTaskIfNeeded];
}

- (void)engineFinished:(NSNotification *)n
{
    self.engineBusy = NO;
    UIApplication *app = [UIApplication sharedApplication];
    if (app.applicationState != UIApplicationStateActive) {
        id msg = n.userInfo[@"message"];
        NSString *body = L(@"Your reply is ready.");
        if ([msg isKindOfClass:[ORMessage class]]) {
            ORMessage *m = msg;
            if (m.role == ORMessageRoleError) body = [NSString stringWithFormat:L(@"Reply failed: %@"), [ORUtils truncate:m.text to:120]];
            else if (m.text.length) body = [ORUtils truncate:m.text to:160];
        }
        UILocalNotification *note = [[UILocalNotification alloc] init];
        note.alertBody = body;
        note.soundName = UILocalNotificationDefaultSoundName;
        note.applicationIconBadgeNumber = 1;
        [app presentLocalNotificationNow:note];
    }
    [self endBackgroundTask];
}

- (void)beginBackgroundTaskIfNeeded
{
    if (self.backgroundTask != UIBackgroundTaskInvalid) return;
    UIApplication *app = [UIApplication sharedApplication];
    self.backgroundTask = [app beginBackgroundTaskWithExpirationHandler:^{
        ORLog(@"Background time expired, cancelling the request");
        [self.chatViewController cancelActiveRequest];
        UILocalNotification *note = [[UILocalNotification alloc] init];
        note.alertBody = L(@"The reply was interrupted because the app ran out of background time. Open AI Chat to continue.");
        [app presentLocalNotificationNow:note];
        [self endBackgroundTask];
    }];
    ORLog(@"Background task started (%.0f s left)", app.backgroundTimeRemaining);
}

- (void)endBackgroundTask
{
    if (self.backgroundTask == UIBackgroundTaskInvalid) return;
    [[UIApplication sharedApplication] endBackgroundTask:self.backgroundTask];
    self.backgroundTask = UIBackgroundTaskInvalid;
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    [[ORSettings shared] save];
    if (self.engineBusy) [self beginBackgroundTaskIfNeeded];
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    [application cancelAllLocalNotifications];
    application.applicationIconBadgeNumber = 0;
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    application.applicationIconBadgeNumber = 0;
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application
{
    ORLog(@"Memory warning");
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    [[ORSettings shared] save];
}

@end
