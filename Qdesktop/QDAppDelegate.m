/**
 * Tae Won Ha
 * http://qvacua.com
 * https://github.com/qvacua
 *
 * See LICENSE
 */

#import "QDAppDelegate.h"
#import "QDWindow.h"
#import "WebView+QDZoom.h"


static NSString *const qDefaultUrlKey = @"url";
static NSString *const qDefaultUrlValue = @"http://localhost:26497/templates/jquery/";
static NSString *const qDefaultReloadRegularlyKey = @"update-regularly";
static NSString *const qDefaultIntervalKey = @"interval";
static const int qDefaultIntervalValue = 15;
static NSString *const qDefaultInteractWhenLaunchesKey = @"interact-when-launches";
static const BOOL qDefaultInteractWhenLaunchesValue = NO;
static NSString *const qDefaultLaunchAtLoginKey = @"launch-at-login";
static const BOOL qDefaultLaunchAtLoginValue = NO;

@interface QDAppDelegate ()

@property NSUserDefaults *userDefaults;
@property NSStatusItem *statusItem;
@property NSURL *url;
@property BOOL reloadRegularly;
@property NSInteger interval;
@property NSTimer *timer;
@property BOOL interactWhenLaunches;
@property BOOL launchAtLogin;

@end

@implementation QDAppDelegate{
    LSSharedFileListRef loginItems;
}

#pragma mark NSUserInterfaceValidations
- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem {
    const SEL action = anItem.action;

    if (action == @selector(toggleBackground:)
            || action == @selector(prefsWindowOk:)
            || action == @selector(openPrefsWindow:)
            || action == @selector(zoomIn:)
            || action == @selector(zoomToActualSize:)
            || action == @selector(zoomOut:)) {
        return YES;
    }

    return NO;
}

#pragma mark IBActions
- (IBAction)openPrefsWindow:(id)sender {
    NSApplication *const application = [NSApplication sharedApplication];
    [application activateIgnoringOtherApps:YES];

    [self syncPrefsUiElements];

    [self.urlWindow makeKeyAndOrderFront:self];
    [self.urlWindow orderFront:self];

    [application deactivate];
}

- (IBAction)prefsWindowOk:(id)sender {
    [self.urlWindow orderOut:self];

    [self storeNewDefaults];

    [self updateWebView];
    [self resetTimer];
}

- (IBAction)toggleRegularReload:(id)sender {
    // noop: the timer is reset in -prefsWindowOk:
}

- (IBAction)toggleBackground:(id)sender {
    [self.window toggleDesktopBackground];
    self.webView.mainFrame.frameView.allowsScrolling = !self.window.background;
    [self.webView setDrawsBackground:NO];
}

- (IBAction)zoomIn:(id)sender {
    [self.webView zoomPageIn:self];
}

- (IBAction)zoomToActualSize:(id)sender {
    [self.webView resetPageZoom:self];
}

- (IBAction)zoomOut:(id)sender {
    [self.webView zoomPageOut:self];
}

- (IBAction)launchAtLogin:(id)sender {
    if (true) {
        NSLog(@"adding login item");
        NSURL *bundleURL = [NSURL fileURLWithPath:@"com.liorhakim.Qnonky"];
        LSSharedFileListInsertItemURL(loginItems,
                                      kLSSharedFileListItemLast,
                                      NULL,
                                      NULL,
                                      (__bridge CFURLRef)bundleURL,
                                      
                                      NULL,
                                      NULL);
    } else {
        LSSharedFileListItemRef loginItemRef = [self getLoginItem];
        if (loginItemRef) {
            LSSharedFileListItemRemove(loginItems, loginItemRef);
            CFRelease(loginItemRef);
        }
        
    }
}

// MIT license
- (BOOL)isLaunchAtStartup {
    // See if the app is currently in LoginItems.
    LSSharedFileListItemRef itemRef = [self itemRefInLoginItems];
    // Store away that boolean.
    BOOL isInList = itemRef != nil;
    // Release the reference if it exists.
    if (itemRef != nil) CFRelease(itemRef);
    
    return isInList;
}

- (IBAction)toggleLaunchAtStartup:(id)sender {
    // Toggle the state.
    BOOL shouldBeToggled = ![self isLaunchAtStartup];
    // Get the LoginItems list.
    LSSharedFileListRef loginItemsRef = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
    if (loginItemsRef == nil) return;
    if (shouldBeToggled) {
        self.launchAtLogin = YES;
        // Add the app to the LoginItems list.
        CFURLRef appUrl = (__bridge CFURLRef)[NSURL fileURLWithPath:[[NSBundle mainBundle] bundlePath]];
        LSSharedFileListItemRef itemRef = LSSharedFileListInsertItemURL(loginItemsRef, kLSSharedFileListItemLast, NULL, NULL, appUrl, NULL, NULL);
        if (itemRef) CFRelease(itemRef);
        
    }
    else {
        self.launchAtLogin = NO;
        // Remove the app from the LoginItems list.
        LSSharedFileListItemRef itemRef = [self itemRefInLoginItems];
        LSSharedFileListItemRemove(loginItemsRef,itemRef);
        if (itemRef != nil) CFRelease(itemRef);
    }
    [self.userDefaults setBool:self.launchAtLogin forKey:qDefaultLaunchAtLoginKey];
    CFRelease(loginItemsRef);
}

- (LSSharedFileListItemRef)itemRefInLoginItems {
    LSSharedFileListItemRef itemRef = nil;
    
    // Get the app's URL.
    NSURL *appUrl = [NSURL fileURLWithPath:[[NSBundle mainBundle] bundlePath]];
    // Get the LoginItems list.
    LSSharedFileListRef loginItemsRef = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
    if (loginItemsRef == nil) return nil;
    // Iterate over the LoginItems.
    NSArray *loginItems = (__bridge NSArray *)LSSharedFileListCopySnapshot(loginItemsRef, nil);
    for (int currentIndex = 0; currentIndex < [loginItems count]; currentIndex++) {
        // Get the current LoginItem and resolve its URL.
        CFURLRef itemURLRef;
        LSSharedFileListItemRef currentItemRef = (__bridge LSSharedFileListItemRef)[loginItems objectAtIndex:currentIndex];
        if (LSSharedFileListItemResolve(currentItemRef, 0, &itemURLRef, NULL) == noErr) {
            // Compare the URLs for the current LoginItem and the app.
            if ([appUrl isEqual:((__bridge NSURL *)itemURLRef)]) {
                // Save the LoginItem reference.
                itemRef = currentItemRef;
            }
        }
    }
    // Retain the LoginItem reference.
    if (itemRef != nil) CFRetain(itemRef);
    // Release the LoginItems lists.
    //[loginItems release];
    CFRelease(loginItemsRef);
    
    return itemRef;
}

#pragma mark NSAppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    self.userDefaults = [NSUserDefaults standardUserDefaults];

    [self setDefaultsIfNecessary];
    [self readDefaults];

    [self initStatusMenu];

    [self setDefaultFontSize];
    [self updateWebView];

    [self resetTimer];

    if (!self.interactWhenLaunches) {
        [self toggleBackground:self];
    }
}

#pragma mark Private
- (void)setDefaultFontSize {
    self.webView.preferences.defaultFontSize = 16;
    self.webView.preferences.defaultFixedFontSize = 16;
    self.webView.preferences.minimumFontSize = 9;
}

- (void)updateWebView {
    [self.webView.mainFrame loadRequest:[NSURLRequest requestWithURL:self.url]];

    NSLog(@"updated webview with %@", self.url);
}

- (void)initStatusMenu {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];

    self.statusItem.title = @"😎";
    self.statusItem.highlightMode = YES;
    self.statusItem.menu = self.statusMenu;
}

- (void)setDefaultsIfNecessary {
    if ([self.userDefaults objectForKey:qDefaultUrlKey] == nil) {
        [self.userDefaults setObject:qDefaultUrlValue forKey:qDefaultUrlKey];
    }

    if ([self.userDefaults objectForKey:qDefaultIntervalKey] == nil) {
        [self.userDefaults setInteger:qDefaultIntervalValue forKey:qDefaultIntervalKey];
    }

    if ([self.userDefaults objectForKey:qDefaultInteractWhenLaunchesKey] == nil) {
        [self.userDefaults setBool:qDefaultInteractWhenLaunchesValue forKey:qDefaultInteractWhenLaunchesKey];
    }
    if ([self.userDefaults objectForKey:qDefaultLaunchAtLoginKey] == nil) {
        [self.userDefaults setBool:qDefaultLaunchAtLoginValue forKey:qDefaultLaunchAtLoginKey];
    }
    
}

- (void)readDefaults {
    self.url = [NSURL URLWithString:[self.userDefaults objectForKey:qDefaultUrlKey]];
    self.reloadRegularly = [self.userDefaults boolForKey:qDefaultReloadRegularlyKey];
    self.interval = [self.userDefaults integerForKey:qDefaultIntervalKey];
    self.interactWhenLaunches = [self.userDefaults boolForKey:qDefaultInteractWhenLaunchesKey];
    self.launchAtLogin = [self.userDefaults boolForKey:qDefaultLaunchAtLoginKey];
}

- (void)storeNewDefaults {
    self.url = [NSURL URLWithString:[self.urlField stringValue]];
    [self.userDefaults setObject:self.url.absoluteString forKey:qDefaultUrlKey];

    self.reloadRegularly = NO;
    if (self.regularReloadCheckbox.state == NSOnState) {
        self.reloadRegularly = YES;
    }
    [self.userDefaults setBool:self.reloadRegularly forKey:qDefaultReloadRegularlyKey];

    self.interval = self.intervalTextField.integerValue;
    [self.userDefaults setInteger:self.interval forKey:qDefaultIntervalKey];

    self.interactWhenLaunches = NO;
    if (self.interactWhenLaunchesCheckbox.state == NSOnState) {
        self.interactWhenLaunches = YES;
    }
    [self.userDefaults setBool:self.interactWhenLaunches forKey:qDefaultInteractWhenLaunchesKey];
}

- (void)syncPrefsUiElements {
    self.urlField.stringValue = self.url.absoluteString;

    self.regularReloadCheckbox.state = NSOffState;
    if (self.reloadRegularly) {
        self.regularReloadCheckbox.state = NSOnState;
    }

    self.intervalTextField.integerValue = self.interval;

    self.interactWhenLaunchesCheckbox.state = NSOffState;
    if (self.interactWhenLaunches) {
        self.interactWhenLaunchesCheckbox.state = NSOnState;
    }
}

- (void)resetTimer {
    [self.timer invalidate];
    self.timer = nil;

    if (!self.reloadRegularly) {
        return;
    }

    self.timer = [NSTimer timerWithTimeInterval:(self.interval * 60) target:self selector:@selector(timerFireMethod:) userInfo:nil repeats:YES];

    [[NSRunLoop currentRunLoop] addTimer:self.timer forMode:NSDefaultRunLoopMode];
}

- (void)timerFireMethod:(NSTimer *)theTimer {
    [self updateWebView];
}
- (LSSharedFileListItemRef)getLoginItem
{
    CFArrayRef snapshotRef = LSSharedFileListCopySnapshot(loginItems, NULL);
    NSURL *bundleURL = [NSURL fileURLWithPath:[[NSBundle mainBundle] bundlePath]];
    
    LSSharedFileListItemRef itemRef = NULL;
    CFURLRef itemURLRef;
    
    for (id item in (__bridge NSArray*)snapshotRef) {
        itemRef = (__bridge LSSharedFileListItemRef)item;
        if (LSSharedFileListItemResolve(itemRef, 0, &itemURLRef, NULL) == noErr) {
            if ([bundleURL isEqual:((__bridge NSURL *)itemURLRef)]) {
                CFRetain(itemRef);
                break;
            }
        }
        itemRef = NULL;
    }
    
    CFRelease(snapshotRef);
    return itemRef;
}

@end
