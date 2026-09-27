#define WEBVIEW_STATIC
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#include "browser_tabs.h"
#include "webview/api.h"
void *webview_tabs_next_configuration = nullptr;
void *webview_tabs_next_related = nullptr;
@class LogorythiaTabs;
@interface LogorythiaTabPage : NSObject <WKNavigationDelegate, WKUIDelegate>
@property(assign) LogorythiaTabs *owner;
@property(copy) NSString *identifier;
@property(retain) WKWebView *web;
@property(retain) NSView *widget;
@property(retain) NSView *shield;
@property(retain) id oldUI;
@property(retain) NSTabViewItem *item;
@property(assign) BOOL interactive;
@end
@interface LogorythiaTabs : NSObject <NSWindowDelegate, NSTabViewDelegate>
@property(assign) NSWindow *window;
@property(retain) id oldDelegate;
@property(retain) NSTabView *tabs;
@property(retain) NSMutableDictionary<NSString *, LogorythiaTabPage *> *pages;
@property(assign) webview_tabs_event_fn callback;
@property(assign) void *context;
@property(retain) id eventMonitor;
@end
@implementation LogorythiaTabPage
- (void)webView:(WKWebView *)web didStartProvisionalNavigation:(WKNavigation *)navigation {
    self.item.label = @"Loading…";
    self.owner.callback("navigation_started", self.identifier.UTF8String, "", self.owner.context);
}
- (void)webView:(WKWebView *)web didReceiveServerRedirectForProvisionalNavigation:(WKNavigation *)navigation {
    self.owner.callback("redirect", self.identifier.UTF8String, "", self.owner.context);
}
- (void)webView:(WKWebView *)web didFinishNavigation:(WKNavigation *)navigation {
    self.item.label = web.title.length ? web.title : (web.URL.host ?: @"Page");
    self.owner.callback("navigation_finished", self.identifier.UTF8String, "", self.owner.context);
}
- (void)webView:(WKWebView *)web didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    if (error.code == NSURLErrorCancelled) return;
    NSString *value = [NSString stringWithFormat:@"%@: %ld", error.domain, (long)error.code];
    self.owner.callback("navigation_error", self.identifier.UTF8String, value.UTF8String, self.owner.context);
}
- (void)webView:(WKWebView *)web didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self webView:web didFailProvisionalNavigation:navigation withError:error];
}
- (void)webView:(WKWebView *)web decidePolicyForNavigationResponse:(WKNavigationResponse *)response decisionHandler:(void (^)(WKNavigationResponsePolicy))completion {
    if (response.isForMainFrame && [response.response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response.response;
        NSDictionary *state = @{ @"code": @(http.statusCode), @"retryAfter": [http valueForHTTPHeaderField:@"Retry-After"] ?: @"" };
        NSData *data = [NSJSONSerialization dataWithJSONObject:state options:0 error:nil];
        NSString *value = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
        self.owner.callback("http_status", self.identifier.UTF8String, value.UTF8String, self.owner.context);
    }
    completion(WKNavigationResponsePolicyAllow);
}
- (WKWebView *)webView:(WKWebView *)web createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)action windowFeatures:(WKWindowFeatures *)features {
    webview_tabs_next_configuration = configuration;
    void *page = self.owner.callback("popup", self.identifier.UTF8String, "", self.owner.context);
    webview_tabs_next_configuration = nullptr;
    return page ? (WKWebView *)webview_get_native_handle(page, WEBVIEW_NATIVE_HANDLE_KIND_BROWSER_CONTROLLER) : nil;
}
- (void)webViewDidClose:(WKWebView *)web {
    self.owner.callback("close_requested", self.identifier.UTF8String, "", self.owner.context);
}
- (void)requestClose:(id)sender {
    self.owner.callback("close_requested", self.identifier.UTF8String, "", self.owner.context);
}
- (void)webView:(WKWebView *)web runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completion {
    if (!self.interactive || !self.owner.window.visible) { completion(); return; }
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    alert.messageText = frame.request.URL.host ?: @"Website"; alert.informativeText = message;
    [alert addButtonWithTitle:@"OK"];
    [alert beginSheetModalForWindow:self.owner.window completionHandler:^(NSModalResponse response) { completion(); }];
}
- (void)webView:(WKWebView *)web runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL))completion {
    if (!self.interactive || !self.owner.window.visible) { completion(NO); return; }
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    alert.messageText = frame.request.URL.host ?: @"Website"; alert.informativeText = message;
    [alert addButtonWithTitle:@"OK"]; [alert addButtonWithTitle:@"Cancel"];
    [alert beginSheetModalForWindow:self.owner.window completionHandler:^(NSModalResponse response) { completion(response == NSAlertFirstButtonReturn); }];
}
- (void)dealloc {
    self.web.navigationDelegate = nil; self.web.UIDelegate = self.oldUI;
    [_identifier release]; [_web release]; [_widget release]; [_shield release]; [_oldUI release]; [_item release];
    [super dealloc];
}
@end
@implementation LogorythiaTabs
- (BOOL)windowShouldClose:(NSWindow *)window {
    [window orderOut:nil]; self.callback("visibility", "", "hidden", self.context); return NO;
}
- (void)tabView:(NSTabView *)view didSelectTabViewItem:(NSTabViewItem *)item {
    if (!item) return;
    self.callback("selected", [(NSString *)item.identifier UTF8String], "", self.context);
}
- (void)dealloc {
    if (self.eventMonitor) [NSEvent removeMonitor:self.eventMonitor];
    [_eventMonitor release];
    self.window.delegate = self.oldDelegate;
    for (LogorythiaTabPage *page in self.pages.allValues) {
        page.web.navigationDelegate = nil; page.web.UIDelegate = page.oldUI;
        [page.widget removeFromSuperview];
    }
    [_pages release]; [_tabs release]; [_oldDelegate release]; [super dealloc];
}
@end
void *webview_tabs_create(webview_t root, webview_tabs_event_fn callback, void *context) {
    LogorythiaTabs *state = [LogorythiaTabs new];
    state.window = (NSWindow *)webview_get_window(root); state.oldDelegate = state.window.delegate;
    state.callback = callback; state.context = context; state.pages = [NSMutableDictionary dictionary];
    state.tabs = [[[NSTabView alloc] initWithFrame:state.window.contentView.bounds] autorelease];
    state.tabs.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    state.tabs.delegate = state; state.window.contentView = state.tabs; state.window.delegate = state;
    // The monitor owns no window/page; remove it before releasing this state.
    __block LogorythiaTabs *unretained = state;
    state.eventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:(NSEventMaskKeyDown | NSEventMaskKeyUp | NSEventMaskFlagsChanged) handler:^NSEvent *(NSEvent *event) {
        LogorythiaTabPage *page = unretained.pages[unretained.tabs.selectedTabViewItem.identifier];
        if (event.window == unretained.window && page && !page.interactive) return nil;
        return event;
    }];
    return state;
}
void webview_tabs_attach(void *raw, webview_t web, const char *identifier) {
    LogorythiaTabs *state = (LogorythiaTabs *)raw;
    LogorythiaTabPage *page = [[[LogorythiaTabPage alloc] init] autorelease];
    page.owner = state; page.identifier = [NSString stringWithUTF8String:identifier];
    page.web = (WKWebView *)webview_get_native_handle(web, WEBVIEW_NATIVE_HANDLE_KIND_BROWSER_CONTROLLER);
    page.widget = (NSView *)webview_get_native_handle(web, WEBVIEW_NATIVE_HANDLE_KIND_UI_WIDGET);
    page.oldUI = page.web.UIDelegate; page.web.UIDelegate = page; page.web.navigationDelegate = page;
    NSView *container = [[[NSView alloc] initWithFrame:state.tabs.contentRect] autorelease];
    page.widget.frame = NSMakeRect(0, 24, container.bounds.size.width, MAX(0, container.bounds.size.height - 24)); page.widget.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [container addSubview:page.widget];
    page.shield = [[[NSView alloc] initWithFrame:page.widget.frame] autorelease];
    page.shield.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable; [container addSubview:page.shield];
    NSButton *close = [NSButton buttonWithTitle:@"Close tab" target:page action:@selector(requestClose:)];
    close.frame = NSMakeRect(0, 0, 80, 24); [container addSubview:close positioned:NSWindowAbove relativeTo:nil];
    page.item = [[[NSTabViewItem alloc] initWithIdentifier:page.identifier] autorelease];
    page.item.label = @"New tab"; page.item.view = container;
    state.pages[page.identifier] = page; [state.tabs addTabViewItem:page.item];
    // The legacy page constructor installs its content view; restore the tab container.
    state.window.contentView = state.tabs;
}
void webview_tabs_remove(void *raw, const char *identifier) {
    LogorythiaTabs *state = (LogorythiaTabs *)raw;
    NSString *key = [NSString stringWithUTF8String:identifier]; LogorythiaTabPage *page = state.pages[key];
    if (!page) return;
    page.web.navigationDelegate = nil; page.web.UIDelegate = page.oldUI;
    [page.widget removeFromSuperview]; [state.tabs removeTabViewItem:page.item]; [state.pages removeObjectForKey:key];
}
void webview_tabs_select(void *raw, const char *identifier, int show) {
    LogorythiaTabs *state = (LogorythiaTabs *)raw;
    LogorythiaTabPage *page = state.pages[[NSString stringWithUTF8String:identifier]];
    if (page) [state.tabs selectTabViewItem:page.item];
    if (show) { [NSApp activateIgnoringOtherApps:YES]; [state.window makeKeyAndOrderFront:nil]; state.callback("visibility", "", "visible", state.context); }
}
void webview_tabs_interactive(void *raw, const char *identifier, int enabled) {
    LogorythiaTabs *state = (LogorythiaTabs *)raw;
    LogorythiaTabPage *page = state.pages[[NSString stringWithUTF8String:identifier]];
    page.interactive = enabled; page.shield.hidden = enabled; [page.web setAccessibilityHidden:!enabled];
    if (!enabled) [state.window makeFirstResponder:nil];
}
void webview_tabs_title(void *raw, const char *identifier, const char *title) {
    LogorythiaTabs *state = (LogorythiaTabs *)raw;
    state.pages[[NSString stringWithUTF8String:identifier]].item.label = [NSString stringWithUTF8String:title];
}
void webview_tabs_visible(void *raw, int visible) {
    LogorythiaTabs *state = (LogorythiaTabs *)raw;
    if (visible) [state.window makeKeyAndOrderFront:nil]; else [state.window orderOut:nil];
    state.callback("visibility", "", visible ? "visible" : "hidden", state.context);
}
void webview_tabs_destroy(void *raw) { [(LogorythiaTabs *)raw release]; }
void webview_tabs_configure(void *raw) {
    const char *profile = getenv("LOGORYTHIA_BROWSER_PROFILE_ID");
    if (!profile) return;
    if (@available(macOS 14.0, *)) {
        NSUUID *identifier = [[[NSUUID alloc] initWithUUIDString:[NSString stringWithUTF8String:profile]] autorelease];
        if (identifier) ((WKWebViewConfiguration *)raw).websiteDataStore = [WKWebsiteDataStore dataStoreForIdentifier:identifier];
    }
}
