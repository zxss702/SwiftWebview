import cWebview
import Foundation

#if canImport(WebKit)
import WebKit
#elseif canImport(cWebkit2gtk)
import cWebkit2gtk
#endif

// MARK: - 辅助类型

/// C 层回调函数签名
typealias CCallback = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void

/// JS 回调函数签名
public typealias JSCallback = @Sendable ([Any]) throws -> Codable

/// 通用包装类，用于将值类型/闭包通过指针传给 C 层
private final class Box<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// 解析 JS 回调参数 JSON
private func parseCallbackArgs(_ json: String) -> [Any]? {
    guard let data = json.data(using: .utf8) else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [Any]
}

/// 回调上下文，持有 webview 指针和 Swift 回调闭包
private final class CallbackContext: @unchecked Sendable {
    let webview: webview_t
    let callback: JSCallback

    init(_ wv: webview_t, _ cb: @escaping JSCallback) {
        webview = wv
        callback = cb
    }
}

// MARK: - SizeHint

/// 窗口大小提示
public enum SizeHint: Int32, Sendable {
    /// 默认大小
    case None = 0
    /// 固定大小，用户不可调整
    case Fixed = 1
    /// 最小边界
    case Min = 2
    /// 最大边界
    case Max = 3
}

// MARK: - Webview

/// 跨平台 Webview 封装。
///
/// 标记为 `@MainActor` 确保所有 UI 操作在主线程执行。
/// 注意：在 Linux 上 `run()` 启动 GTK 主循环，它与 Swift 的
/// `@MainActor`/libdispatch 主队列互不兼容，因此从后台线程操作
/// webview 时应通过 `dispatch(_:)` 进行调度。
@available(macOS 10.15, *)
public final class Webview: @unchecked Sendable {
    /// C 层 webview 指针。标记为 nonisolated(unsafe) 使
    /// nonisolated 方法（dispatch、terminate）可直接访问。
    /// 指针本身只读且线程安全，实际操作由各方法保证安全性。
    nonisolated(unsafe) private let wv: webview_t

    /// 是否已销毁。nonisolated(unsafe) 因为 deinit（nonisolated）需要读取，
    /// dispatch（nonisolated）也需要检查。写入只在 destroy() 中发生（@MainActor）。
    nonisolated(unsafe) private var destroyed: Bool = false

    private var callbacks: [String: CallbackContext] = [:]

    /// 初始化 Webview。
    /// - Parameter debug: 是否启用开发者工具。
    public init(_ debug: Bool = false) {
        let created = webview_create(debug ? 1 : 0, nil)
        guard let validWv = created else {
            fatalError("初始化 Webview 失败。在 Linux 上通常意味着没有可用的 Display/X11（尝试使用 xvfb-run）。")
        }
        wv = validWv
    }

    deinit {
        // deinit 是 nonisolated，不能调用 @MainActor 的 destroy()。
        // 直接调用 C API 做最小清理（跳过 callback unbind，因为 webview 即将销毁）。
        if !destroyed {
            webview_destroy(wv)
            destroyed = true
        }
    }

    // MARK: - 主循环

    /// 启动 webview 主循环，阻塞当前线程。
    public func run() {
        if !destroyed {
            webview_run(wv)
        }
    }

    /// 将闭包调度到 webview 的 UI 事件循环线程上执行。
    ///
    /// 在 Linux 上 `webview_run()` 启动 GTK 主循环，与 Swift 的
    /// `@MainActor`(libdispatch 主队列) 互不兼容。从后台线程操作
    /// webview 时，必须通过此方法调度，而不是依赖 `@MainActor`。
    ///
    /// `nonisolated` 使其可从任意线程/Actor 调用。
    nonisolated public func dispatch(_ work: @escaping @Sendable () -> Void) {
        guard !destroyed else { return }
        let boxed = Unmanaged.passRetained(Box(work)).toOpaque()
        webview_dispatch(wv, { _, arg in
            guard let arg = arg else { return }
            let box = Unmanaged<Box<@Sendable () -> Void>>.fromOpaque(arg).takeRetainedValue()
            box.value()
        }, boxed)
    }

    // MARK: - 导航与内容

    /// 导航到指定 URL。
    @discardableResult
    public func navigate(_ url: String) -> Webview {
        if !destroyed {
            webview_navigate(wv, url)
        }
        return self
    }

    /// 设置 HTML 内容。
    @discardableResult
    public func setHtml(_ html: String) -> Webview {
        if !destroyed {
            webview_set_html(wv, html)
        }
        return self
    }

    // MARK: - 窗口属性

    /// 设置窗口标题。
    @discardableResult
    public func setTitle(_ title: String) -> Webview {
        if !destroyed {
            webview_set_title(wv, title)
        }
        return self
    }

    /// 设置窗口大小。
    @discardableResult
    public func setSize(_ width: Int32, _ height: Int32, _ hint: SizeHint) -> Webview {
        if !destroyed {
            webview_set_size(wv, width, height, webview_hint_t(rawValue: UInt32(hint.rawValue)))
        }
        return self
    }

    // MARK: - JavaScript

    /// 注入 JS 代码到每个新页面，保证在 `window.onload` 之前执行。
    @discardableResult
    public func inject(_ js: String) -> Webview {
        if !destroyed {
            webview_init(wv, js)
        }
        return self
    }

    /// 执行 JS 代码（fire-and-forget，不返回结果）。
    @discardableResult
    public func eval(_ js: String) -> Webview {
        if !destroyed {
            webview_eval(wv, js)
        }
        return self
    }

    /// 绑定 Swift 函数到全局 JS 函数。
    @discardableResult
    public func bind(_ name: String, _ callback: @escaping JSCallback) -> Webview {
        guard !destroyed else { return self }

        let context = CallbackContext(wv, callback)
        callbacks[name] = context

        let bridge: CCallback = { seq, req, arg in
            guard let seq = seq, let req = req, let arg = arg else { return }

            let ctx = Unmanaged<CallbackContext>.fromOpaque(arg).takeUnretainedValue()
            let args = parseCallbackArgs(String(cString: req)) ?? []

            do {
                let encoder = JSONEncoder()
                let cbResult = try ctx.callback(args)
                let jsonData = try encoder.encode(cbResult)
                if let json = String(data: jsonData, encoding: .utf8) {
                    webview_return(ctx.webview, seq, 0, json)
                } else {
                    webview_return(ctx.webview, seq, 0, "{}")
                }
            } catch {
                webview_return(ctx.webview, seq, 1, "{\"error\":\"\(error)\"}")
            }
        }

        let contextPtr = Unmanaged.passRetained(context).toOpaque()
        webview_bind(wv, name, bridge, contextPtr)
        return self
    }

    /// 解绑全局 JS 函数。
    @discardableResult
    public func unbind(_ name: String) -> Webview {
        if !destroyed {
            if let context = callbacks.removeValue(forKey: name) {
                Unmanaged.passUnretained(context).release()
            }
            webview_unbind(wv, name)
        }
        return self
    }

    // MARK: - 生命周期

    /// 销毁 webview 并关闭窗口。销毁后不可再使用。
    @discardableResult
    public func destroy() -> Webview {
        if !destroyed {
            let keys = Array(callbacks.keys)
            for key in keys {
                if let context = callbacks.removeValue(forKey: key) {
                    Unmanaged.passUnretained(context).release()
                }
                webview_unbind(wv, key)
            }
            callbacks.removeAll()
            webview_destroy(wv)
            destroyed = true
        }
        return self
    }

    /// 终止主循环并关闭窗口。此方法是线程安全的。
    ///
    /// `nonisolated` 因为 C API 文档明确声明 `webview_terminate` 线程安全。
    @discardableResult
    nonisolated public func terminate() -> Webview {
        webview_terminate(wv)
        return self
    }

    // MARK: - Loading State

    /// 当前页面是否正在加载。
    ///
    /// 通过 `webview_get_native_handle` 获取底层浏览器控制器，
    /// 在 macOS 上读取 `WKWebView.isLoading`，
    /// 在 Linux 上调用 `webkit_web_view_is_loading()`。
    public var isLoading: Bool {
        guard !destroyed else { return false }
        let handle = webview_get_native_handle(wv, WEBVIEW_NATIVE_HANDLE_KIND_BROWSER_CONTROLLER)
        guard let handle = handle else { return false }
        #if canImport(WebKit)
        let webView = Unmanaged<WKWebView>.fromOpaque(handle).takeUnretainedValue()
        return webView.isLoading
        #elseif canImport(cWebkit2gtk)
        return webkit_web_view_is_loading(OpaquePointer(handle)) != 0
        #else
        return false
        #endif
    }

    // MARK: - Async Evaluation

    private var continuations: [String: CheckedContinuation<String, Error>] = [:]
    private var isReturnHelperBound: Bool = false

    /// JavaScript 执行错误
    public enum EvalError: Error, Sendable {
        case destroyed
        case executionError(String)
        case scriptTimeout
    }

    private func bindReturnHelperIfNeeded() {
        guard !isReturnHelperBound else { return }
        isReturnHelperBound = true

        self.bind("__swift_webview_return__") { [weak self] args in
            guard let id = args.first as? String else { return "{}" }
            let isError = (args.count > 1 && args[1] as? Bool == true)
            let resultStr = args.count > 2 ? (args[2] as? String ?? "") : ""

            // dispatch 将闭包调度到 UI 事件循环线程（即主线程），
            // 使用 assumeIsolated 断言主线程隔离以访问 @MainActor 状态
            self?.dispatch { [weak self] in
                MainActor.assumeIsolated {
                    if let continuation = self?.continuations.removeValue(forKey: id) {
                        if isError {
                            continuation.resume(throwing: EvalError.executionError(resultStr))
                        } else {
                            continuation.resume(returning: resultStr)
                        }
                    }
                }
            }

            return "{}"
        }
    }

    /// 异步执行 JavaScript 代码并返回结果的 JSON 字符串。
    /// - Parameter js: 要执行的 JavaScript 代码。
    /// - Returns: 执行结果的 JSON 字符串。
    public func evaluateJavaScript(_ js: String) async throws -> String {
        guard !destroyed else {
            throw EvalError.destroyed
        }

        bindReturnHelperIfNeeded()

        let id = UUID().uuidString

        let wrappedJS = """
        (async function() {
            try {
                var __user_exec__ = (function() {
                    \(js)
                });
                var __res__ = __user_exec__();
                if (__res__ instanceof Promise) {
                    __res__ = await __res__;
                }
                var __json__ = JSON.stringify(__res__);
                window.__swift_webview_return__("\(id)", false, __json__ == undefined ? "" : __json__);
            } catch (e) {
                window.__swift_webview_return__("\(id)", true, e.toString());
            }
        })();
        """

        return try await withCheckedThrowingContinuation { continuation in
            // dispatch 调度到 UI 线程，assumeIsolated 断言隔离以操作 @MainActor 状态
            self.dispatch { [self] in
                MainActor.assumeIsolated {
                    self.continuations[id] = continuation
                    self.eval(wrappedJS)
                }
            }
        }
    }
}
