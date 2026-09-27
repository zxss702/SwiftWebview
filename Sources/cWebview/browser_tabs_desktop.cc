#define WEBVIEW_STATIC
#include "browser_tabs.h"
#include "webview/api.h"
#include <map>
#include <memory>
#include <string>
#include <vector>
void *webview_tabs_next_configuration = nullptr;
void *webview_tabs_next_related = nullptr;
#ifdef _WIN32
#include <windows.h>
#include <commctrl.h>
#include <wrl.h>
#include "WebView2.h"
using Microsoft::WRL::ComPtr;
using Microsoft::WRL::Callback;
struct TabWindow;
struct TabPage {
    TabWindow *owner{}; std::string id; HWND widget{};
    ComPtr<ICoreWebView2Controller> controller; ComPtr<ICoreWebView2> web;
    EventRegistrationToken popup{}, start{}, finish{}, closed{}, response{};
    ComPtr<ICoreWebView2_2> web2; std::wstring navigationURI;
};
struct TabWindow {
    webview_t root{}; HWND window{}, strip{}, close{}; WNDPROC original{};
    webview_tabs_event_fn callback{}; void *context{};
    std::map<std::string, std::unique_ptr<TabPage>> pages;
    std::vector<std::string> order; std::string selected;
};
static LRESULT CALLBACK tabs_window_proc(HWND window, UINT message, WPARAM wp, LPARAM lp) {
    auto *s = static_cast<TabWindow *>(GetPropW(window, L"LogorythiaTabs"));
    if (!s) return DefWindowProcW(window, message, wp, lp);
    if (message == WM_CLOSE) { ShowWindow(window, SW_HIDE); s->callback("visibility", "", "hidden", s->context); return 0; }
    if (message == WM_COMMAND && reinterpret_cast<HWND>(lp) == s->close) {
        s->callback("close_requested", s->selected.c_str(), "", s->context); return 0;
    }
    if (message == WM_NOTIFY && reinterpret_cast<NMHDR *>(lp)->hwndFrom == s->strip && reinterpret_cast<NMHDR *>(lp)->code == TCN_SELCHANGE) {
        auto index = TabCtrl_GetCurSel(s->strip);
        if (index >= 0 && static_cast<size_t>(index) < s->order.size()) webview_tabs_select(s, s->order[index].c_str(), 0);
        return 0;
    }
    auto result = CallWindowProcW(s->original, window, message, wp, lp);
    if (message == WM_SIZE) {
        RECT r{}; GetClientRect(window, &r);
        MoveWindow(s->strip, 0, 0, max(0, r.right - 80), 32, TRUE);
        MoveWindow(s->close, max(0, r.right - 80), 0, 80, 32, TRUE);
        for (auto &pair : s->pages) MoveWindow(pair.second->widget, 0, 32, r.right, max(0, r.bottom - 32), TRUE);
    }
    return result;
}
void *webview_tabs_create(webview_t root, webview_tabs_event_fn cb, void *context) {
    auto *s = new TabWindow(); s->root = root; s->window = static_cast<HWND>(webview_get_window(root)); s->callback = cb; s->context = context;
    INITCOMMONCONTROLSEX controls{sizeof(controls), ICC_TAB_CLASSES}; InitCommonControlsEx(&controls);
    ShowWindow(static_cast<HWND>(webview_get_native_handle(root, WEBVIEW_NATIVE_HANDLE_KIND_UI_WIDGET)), SW_HIDE);
    s->strip = CreateWindowExW(0, WC_TABCONTROLW, L"", WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS, 0,0,800,32,s->window,nullptr,GetModuleHandleW(nullptr),nullptr);
    s->close = CreateWindowW(L"BUTTON", L"Close tab", WS_CHILD | WS_VISIBLE, 800,0,80,32,s->window,nullptr,GetModuleHandleW(nullptr),nullptr);
    SetPropW(s->window,L"LogorythiaTabs",s);
    s->original = reinterpret_cast<WNDPROC>(SetWindowLongPtrW(s->window,GWLP_WNDPROC,reinterpret_cast<LONG_PTR>(tabs_window_proc)));
    return s;
}
void webview_tabs_attach(void *raw, webview_t child, const char *id) {
    auto *s = static_cast<TabWindow *>(raw); auto p = std::make_unique<TabPage>();
    p->owner=s; p->id=id; p->widget=static_cast<HWND>(webview_get_native_handle(child,WEBVIEW_NATIVE_HANDLE_KIND_UI_WIDGET));
    p->controller=static_cast<ICoreWebView2Controller *>(webview_get_native_handle(child,WEBVIEW_NATIVE_HANDLE_KIND_BROWSER_CONTROLLER));
    p->controller->get_CoreWebView2(&p->web); auto *page=p.get();
    p->web->add_NewWindowRequested(Callback<ICoreWebView2NewWindowRequestedEventHandler>([page](ICoreWebView2*,ICoreWebView2NewWindowRequestedEventArgs *args)->HRESULT {
        struct PendingPopup {
            TabWindow *owner; std::string opener;
            ComPtr<ICoreWebView2NewWindowRequestedEventArgs> args;
            ComPtr<ICoreWebView2Deferral> deferral;
        };
        auto *pending = new PendingPopup{page->owner, page->id, args, {}};
        args->GetDeferral(&pending->deferral);
        args->put_Handled(TRUE);
        // Exit the WebView2 event callback before initializing another controller.
        webview_dispatch(page->owner->root, [](webview_t, void *raw) {
            std::unique_ptr<PendingPopup> pending(static_cast<PendingPopup *>(raw));
            if (pending->owner->pages.count(pending->opener)) {
                void *child = pending->owner->callback("popup", pending->opener.c_str(), "", pending->owner->context);
                if (child) {
                    auto *controller = static_cast<ICoreWebView2Controller *>(webview_get_native_handle(child, WEBVIEW_NATIVE_HANDLE_KIND_BROWSER_CONTROLLER));
                    ComPtr<ICoreWebView2> web; controller->get_CoreWebView2(&web);
                    pending->args->put_NewWindow(web.Get());
                }
            }
            if (pending->deferral) pending->deferral->Complete();
        }, pending);
        return S_OK;
    }).Get(), &p->popup);
    p->web->add_NavigationStarting(Callback<ICoreWebView2NavigationStartingEventHandler>([page](ICoreWebView2*,ICoreWebView2NavigationStartingEventArgs *args)->HRESULT {
        LPWSTR uri=nullptr; args->get_Uri(&uri);
        page->navigationURI = uri ? uri : L""; CoTaskMemFree(uri);
        BOOL redirect=FALSE; args->get_IsRedirected(&redirect);
        page->owner->callback(redirect?"redirect":"navigation_started",page->id.c_str(),"",page->owner->context);
        webview_tabs_title(page->owner,page->id.c_str(),"Loading..."); return S_OK;
    }).Get(), &p->start);
    p->web->add_NavigationCompleted(Callback<ICoreWebView2NavigationCompletedEventHandler>([page](ICoreWebView2*,ICoreWebView2NavigationCompletedEventArgs *args)->HRESULT {
        BOOL success=FALSE; args->get_IsSuccess(&success);
        if(!success) { COREWEBVIEW2_WEB_ERROR_STATUS code{}; args->get_WebErrorStatus(&code); auto value=std::to_string(code); page->owner->callback("navigation_error",page->id.c_str(),value.c_str(),page->owner->context); }
        ComPtr<ICoreWebView2NavigationCompletedEventArgs2> status;
        if(SUCCEEDED(args->QueryInterface(IID_PPV_ARGS(&status)))) { int code=0; status->get_HttpStatusCode(&code); auto json="{\"code\":"+std::to_string(code)+"}"; page->owner->callback("http_status",page->id.c_str(),json.c_str(),page->owner->context); }
        page->owner->callback("navigation_finished",page->id.c_str(),"",page->owner->context); return S_OK;
    }).Get(), &p->finish);
    if (SUCCEEDED(p->web.As(&p->web2))) {
        p->web2->add_WebResourceResponseReceived(Callback<ICoreWebView2WebResourceResponseReceivedEventHandler>([page](ICoreWebView2*, ICoreWebView2WebResourceResponseReceivedEventArgs *args)->HRESULT {
            ComPtr<ICoreWebView2WebResourceRequest> request; args->get_Request(&request);
            LPWSTR uri=nullptr; if(request) request->get_Uri(&uri);
            bool mainCandidate = uri && page->navigationURI == uri; CoTaskMemFree(uri);
            if (!mainCandidate) return S_OK;
            ComPtr<ICoreWebView2WebResourceResponseView> response; args->get_Response(&response);
            ComPtr<ICoreWebView2HttpResponseHeaders> headers; if(response) response->get_Headers(&headers);
            LPWSTR retry=nullptr;
            if(headers && SUCCEEDED(headers->GetHeader(L"Retry-After", &retry)) && retry) {
                int size=WideCharToMultiByte(CP_UTF8,0,retry,-1,nullptr,0,nullptr,nullptr);
                std::string value(size,'\0'); WideCharToMultiByte(CP_UTF8,0,retry,-1,value.data(),size,nullptr,nullptr);
                page->owner->callback("retry_after",page->id.c_str(),value.c_str(),page->owner->context);
            }
            CoTaskMemFree(retry); return S_OK;
        }).Get(), &p->response);
    }
    p->web->add_WindowCloseRequested(Callback<ICoreWebView2WindowCloseRequestedEventHandler>([page](ICoreWebView2*,IUnknown*)->HRESULT {
        page->owner->callback("close_requested",page->id.c_str(),"",page->owner->context); return S_OK;
    }).Get(), &p->closed);
    TCITEMW item{}; item.mask=TCIF_TEXT; item.pszText=const_cast<wchar_t *>(L"New tab");
    TabCtrl_InsertItem(s->strip,static_cast<int>(s->order.size()),&item);
    s->order.push_back(id); s->pages[id]=std::move(p);
    ShowWindow(page->widget,SW_HIDE); EnableWindow(page->widget,FALSE);
    if(s->selected.empty()) webview_tabs_select(s,id,0);
    SendMessageW(s->window,WM_SIZE,0,0);
}
void webview_tabs_remove(void *raw,const char *id) {
    auto *s=static_cast<TabWindow *>(raw); auto found=s->pages.find(id); if(found==s->pages.end()) return;
    auto &p=*found->second;
    if(p.web2) p.web2->remove_WebResourceResponseReceived(p.response);
    p.web->remove_NewWindowRequested(p.popup); p.web->remove_NavigationStarting(p.start); p.web->remove_NavigationCompleted(p.finish); p.web->remove_WindowCloseRequested(p.closed);
    for(size_t i=0;i<s->order.size();++i) if(s->order[i]==id) { TabCtrl_DeleteItem(s->strip,static_cast<int>(i));s->order.erase(s->order.begin()+i);break; }
    s->pages.erase(found);
    if(s->selected==id) { s->selected.clear(); if(!s->order.empty()) webview_tabs_select(s,s->order.front().c_str(),0); }
}
void webview_tabs_select(void *raw,const char *id,int show) {
    auto *s=static_cast<TabWindow *>(raw); if(!s->pages.count(id)) return; s->selected=id;
    for(auto &pair:s->pages) ShowWindow(pair.second->widget,pair.first==id?SW_SHOW:SW_HIDE);
    for(size_t i=0;i<s->order.size();++i) if(s->order[i]==id) TabCtrl_SetCurSel(s->strip,static_cast<int>(i));
    s->callback("selected",id,"",s->context); if(show) webview_tabs_visible(s,1);
}
void webview_tabs_interactive(void *raw,const char *id,int enabled) {
    auto *s=static_cast<TabWindow *>(raw); auto p=s->pages.find(id); if(p==s->pages.end()) return;
    EnableWindow(p->second->widget,enabled); if(!enabled && GetFocus()==p->second->widget) SetFocus(s->strip);
}
void webview_tabs_title(void *raw,const char *id,const char *title) {
    auto *s=static_cast<TabWindow *>(raw); int count=MultiByteToWideChar(CP_UTF8,0,title,-1,nullptr,0);
    std::wstring wide(count,L'\0'); MultiByteToWideChar(CP_UTF8,0,title,-1,wide.data(),count);
    TCITEMW item{};item.mask=TCIF_TEXT;item.pszText=wide.data();
    for(size_t i=0;i<s->order.size();++i) if(s->order[i]==id) TabCtrl_SetItem(s->strip,static_cast<int>(i),&item);
}
void webview_tabs_visible(void *raw,int visible) {
    auto *s=static_cast<TabWindow *>(raw); ShowWindow(s->window,visible?SW_SHOW:SW_HIDE); if(visible) SetForegroundWindow(s->window);
    s->callback("visibility","",visible?"visible":"hidden",s->context);
}
void webview_tabs_destroy(void *raw) {
    auto *s=static_cast<TabWindow *>(raw); if(!s)return;
    while(!s->pages.empty()) { auto id=s->pages.begin()->first; webview_tabs_remove(s,id.c_str()); }
    SetWindowLongPtrW(s->window,GWLP_WNDPROC,reinterpret_cast<LONG_PTR>(s->original)); RemovePropW(s->window,L"LogorythiaTabs");
    DestroyWindow(s->strip);DestroyWindow(s->close);delete s;
}
#else
#include <gtk/gtk.h>
#include <webkit/webkit.h>
#include <libsoup/soup.h>
struct TabWindow;
struct TabPage { TabWindow *owner; std::string id; GtkWidget *widget,*label; };
struct TabWindow {
    GtkWindow *window; GtkWidget *notebook; webview_tabs_event_fn callback; void *context;
    std::map<std::string,std::unique_ptr<TabPage>> pages;
};
void *webview_tabs_create(webview_t root,webview_tabs_event_fn cb,void *context) {
    auto *s=new TabWindow{GTK_WINDOW(webview_get_window(root)),gtk_notebook_new(),cb,context,{}};
    g_object_ref_sink(s->notebook); gtk_notebook_set_scrollable(GTK_NOTEBOOK(s->notebook),TRUE);
    gtk_window_set_child(s->window,s->notebook);
    g_signal_connect(s->window,"close-request",G_CALLBACK(+[](GtkWindow *window,gpointer data)->gboolean {
        auto *s=static_cast<TabWindow *>(data);gtk_widget_set_visible(GTK_WIDGET(window),FALSE);s->callback("visibility","","hidden",s->context);return TRUE;
    }),s);
    g_signal_connect(s->notebook,"switch-page",G_CALLBACK(+[](GtkNotebook*,GtkWidget *widget,guint,gpointer data) {
        auto *s=static_cast<TabWindow *>(data);for(auto &pair:s->pages) if(pair.second->widget==widget) s->callback("selected",pair.first.c_str(),"",s->context);
    }),s); return s;
}
void webview_tabs_attach(void *raw,webview_t child,const char *id) {
    auto *s=static_cast<TabWindow *>(raw);auto p=std::make_unique<TabPage>();p->owner=s;p->id=id;
    p->widget=GTK_WIDGET(webview_get_native_handle(child,WEBVIEW_NATIVE_HANDLE_KIND_UI_WIDGET));p->label=gtk_label_new("New tab");
    auto *page=p.get(); auto *header=gtk_box_new(GTK_ORIENTATION_HORIZONTAL,6);auto *close=gtk_button_new_with_label("×");
    gtk_box_append(GTK_BOX(header),p->label);gtk_box_append(GTK_BOX(header),close);
    if(gtk_widget_get_parent(p->widget)==GTK_WIDGET(s->window))gtk_window_set_child(s->window,nullptr);
    s->pages[id]=std::move(p);
    gtk_notebook_append_page(GTK_NOTEBOOK(s->notebook),page->widget,header);gtk_widget_set_sensitive(page->widget,FALSE);
    gtk_window_set_child(s->window,s->notebook);
    g_signal_connect(close,"clicked",G_CALLBACK(+[](GtkButton*,gpointer data){auto *p=static_cast<TabPage *>(data);p->owner->callback("close_requested",p->id.c_str(),"",p->owner->context);}),page);
    g_signal_connect(page->widget,"create",G_CALLBACK(+[](WebKitWebView *web,WebKitNavigationAction*,gpointer data)->GtkWidget* {
        auto *p=static_cast<TabPage *>(data);webview_tabs_next_related=web;
        auto *child=p->owner->callback("popup",p->id.c_str(),"",p->owner->context);webview_tabs_next_related=nullptr;
        if(!child)return nullptr;
        return GTK_WIDGET(webview_get_native_handle(child,WEBVIEW_NATIVE_HANDLE_KIND_BROWSER_CONTROLLER));
    }),page);
    g_signal_connect(page->widget,"close",G_CALLBACK(+[](WebKitWebView*,gpointer data){auto *p=static_cast<TabPage *>(data);p->owner->callback("close_requested",p->id.c_str(),"",p->owner->context);}),page);
    g_signal_connect(page->widget,"load-changed",G_CALLBACK(+[](WebKitWebView *web,WebKitLoadEvent event,gpointer data){
        auto *p=static_cast<TabPage *>(data);const char *name=event==WEBKIT_LOAD_STARTED?"navigation_started":event==WEBKIT_LOAD_REDIRECTED?"redirect":event==WEBKIT_LOAD_FINISHED?"navigation_finished":nullptr;
        if(name)p->owner->callback(name,p->id.c_str(),"",p->owner->context);
        const char *title=webkit_web_view_get_title(web);gtk_label_set_text(GTK_LABEL(p->label),event==WEBKIT_LOAD_FINISHED?(title?title:"Page"):"Loading…");
    }),page);
    g_signal_connect(page->widget,"load-failed",G_CALLBACK(+[](WebKitWebView*,WebKitLoadEvent,const char*,GError *error,gpointer data)->gboolean {
        if (g_error_matches(error, WEBKIT_NETWORK_ERROR, WEBKIT_NETWORK_ERROR_CANCELLED)) return FALSE;
        auto *p=static_cast<TabPage *>(data);auto code=std::to_string(error->code);p->owner->callback("navigation_error",p->id.c_str(),code.c_str(),p->owner->context);return FALSE;
    }),page);
    g_signal_connect(page->widget,"decide-policy",G_CALLBACK(+[](WebKitWebView*,WebKitPolicyDecision *decision,WebKitPolicyDecisionType kind,gpointer data)->gboolean {
        if(kind!=WEBKIT_POLICY_DECISION_TYPE_RESPONSE)return FALSE;
        auto *response=WEBKIT_RESPONSE_POLICY_DECISION(decision);if(!webkit_response_policy_decision_is_main_frame_main_resource(response))return FALSE;
        auto *p=static_cast<TabPage *>(data);auto *http=webkit_response_policy_decision_get_response(response);
        auto code=webkit_uri_response_get_status_code(http);auto *headers=webkit_uri_response_get_http_headers(http);const char *retry=headers?soup_message_headers_get_one(headers,"Retry-After"):nullptr;
        // Retry-After is sent separately, without serializing any other response header.
        auto json="{\"code\":"+std::to_string(code)+"}";p->owner->callback("http_status",p->id.c_str(),json.c_str(),p->owner->context);
        if(retry)p->owner->callback("retry_after",p->id.c_str(),retry,p->owner->context);return FALSE;
    }),page);
}
void webview_tabs_remove(void *raw,const char *id) {
    auto *s=static_cast<TabWindow *>(raw);auto p=s->pages.find(id);if(p==s->pages.end())return;
    g_signal_handlers_disconnect_by_data(p->second->widget,p->second.get());
    int index=gtk_notebook_page_num(GTK_NOTEBOOK(s->notebook),p->second->widget);if(index>=0)gtk_notebook_remove_page(GTK_NOTEBOOK(s->notebook),index);
    s->pages.erase(p);
}
void webview_tabs_select(void *raw,const char *id,int show) {
    auto *s=static_cast<TabWindow *>(raw);auto p=s->pages.find(id);if(p==s->pages.end())return;
    gtk_notebook_set_current_page(GTK_NOTEBOOK(s->notebook),gtk_notebook_page_num(GTK_NOTEBOOK(s->notebook),p->second->widget));if(show)webview_tabs_visible(s,1);
}
void webview_tabs_interactive(void *raw,const char *id,int enabled) {auto *s=static_cast<TabWindow *>(raw);auto p=s->pages.find(id);if(p!=s->pages.end())gtk_widget_set_sensitive(p->second->widget,enabled);}
void webview_tabs_title(void *raw,const char *id,const char *title) {auto *s=static_cast<TabWindow *>(raw);auto p=s->pages.find(id);if(p!=s->pages.end())gtk_label_set_text(GTK_LABEL(p->second->label),title);}
void webview_tabs_visible(void *raw,int visible) {auto *s=static_cast<TabWindow *>(raw);if(visible)gtk_window_present(s->window);else gtk_widget_set_visible(GTK_WIDGET(s->window),FALSE);s->callback("visibility","",visible?"visible":"hidden",s->context);}
void webview_tabs_destroy(void *raw) {auto *s=static_cast<TabWindow *>(raw);if(!s)return;g_signal_handlers_disconnect_by_data(s->window,s);g_signal_handlers_disconnect_by_data(s->notebook,s);while(!s->pages.empty()){auto id=s->pages.begin()->first;webview_tabs_remove(s,id.c_str());}g_object_unref(s->notebook);delete s;}
#endif
void webview_tabs_configure(void *) {}
