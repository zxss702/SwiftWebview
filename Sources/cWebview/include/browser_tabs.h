#pragma once
#include "webview/types.h"
#ifdef __cplusplus
extern "C" {
#endif
// UI-thread API. Event strings are borrowed for the duration of the callback.
// "popup" returns the newly created webview_t, without navigating it again.
typedef void *(*webview_tabs_event_fn)(const char *, const char *, const char *, void *);
void *webview_tabs_create(webview_t root, webview_tabs_event_fn callback, void *context);
void webview_tabs_attach(void *tabs, webview_t page, const char *page_id);
void webview_tabs_remove(void *tabs, const char *page_id);
void webview_tabs_select(void *tabs, const char *page_id, int show);
void webview_tabs_interactive(void *tabs, const char *page_id, int enabled);
void webview_tabs_title(void *tabs, const char *page_id, const char *title);
void webview_tabs_visible(void *tabs, int visible);
void webview_tabs_destroy(void *tabs);
// Used only while WebKit synchronously creates an adopted popup.
extern void *webview_tabs_next_configuration;
extern void *webview_tabs_next_related;
#ifdef __cplusplus
}
#endif
#ifdef __cplusplus
extern "C" {
#endif
void webview_tabs_configure(void *configuration);
#ifdef __cplusplus
}
#endif
