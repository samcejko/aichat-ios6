#import "ORAppDelegate.h"
#import "ORChatViewController.h"
#import "ORTheme.h"
#import "ORTLSSocket.h"
#import "ORModelCatalog.h"
#import "ORSettings.h"
#import "ORAttachment.h"
#import "ORUtils.h"
#import "ORCommon.h"

@implementation ORAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    ORLog(@"AIChat %@ starting on %@ (iOS %@)", [ORUtils appVersion], [UIDevice currentDevice].model, [UIDevice currentDevice].systemVersion);
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

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application
{
    ORLog(@"Memory warning");
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    [[ORSettings shared] save];
}

@end
