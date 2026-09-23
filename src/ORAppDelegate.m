#import "ORAppDelegate.h"
#import "ORChatViewController.h"
#import "ORChatEngine.h"
#import "ORTheme.h"
#import "ORTLSSocket.h"
#import "ORModelCatalog.h"
#import "ORSettings.h"
#import "ORAttachment.h"
#import "ORUtils.h"
#import "ORCommon.h"

@interface ORAppDelegate ()
@property (nonatomic) UIBackgroundTaskIdentifier backgroundTask;
@property (nonatomic) BOOL engineBusy;
@end

@implementation ORAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    ORLog(@"AIChat %@ starting on %@ (iOS %@)", [ORUtils appVersion], [UIDevice currentDevice].model, [UIDevice currentDevice].systemVersion);
    self.backgroundTask = UIBackgroundTaskInvalid;
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

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
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
