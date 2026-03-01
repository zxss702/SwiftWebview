import cWebview
import Foundation

typealias CCallback = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void
public typealias JSCallback = ([Any]) throws -> Codable

func parseCallbackArgs(_ json: String) -> [Any]? {
    guard let data = json.data(using: .utf8) else {
        return nil
    }
    return try? JSONSerialization.jsonObject(with: data) as? [Any]
}

class CallbackContext {
    var webview: webview_t
    var callback: JSCallback

    init(_ wv: webview_t, _ cb: @escaping JSCallback) {
        webview = wv
        callback = cb
    }
}

private class DispatchContext {
    let closure: () -> Void
    init(_ closure: @escaping () -> Void) {
        self.closure = closure
    }
}

/// Used to set the width & height properties of a webview
public enum SizeHint: Int32 {
    /// Width and Height are the default size.
    case None = 0
    /// Window size cannot be changed by the user.
    case Fixed = 1
    /// Width and height are the minimum bounds.
    case Min = 2
    /// Width and height are the maximum bounds.
    case Max = 3
}

@available(macOS 10.15, *)
public class Webview: @unchecked Sendable {
    private var wv: webview_t
    private var destroyed: Bool = false
    private var callbacks: [String: CallbackContext] = [:]

    /// Initializes a Webview
    /// - Parameter debug: Debug mode flag.
    public init(_ debug: Bool = false) {
        let created = webview_create(debug ? 1 : 0, nil)
        guard let validWv = created else {
            fatalError("Failed to initialize Webview. On Linux this usually means no Display/X11 server is available (Try using xvfb-run).")
        }
        wv = validWv
    }

    deinit {
        if !destroyed {
            destroy()
        }
    }

    /// Runs the webview. This is blocks the main thread
    public func run() {
        if !destroyed {
            webview_run(wv)
        }
    }

    /// Safely schedules a closure to be executed on the webview's native UI thread.
    public func dispatch(_ closure: @escaping () -> Void) {
        if !destroyed {
            let context = DispatchContext(closure)
            let ptr = Unmanaged.passRetained(context).toOpaque()
            webview_dispatch(wv, { w, arg in
                guard let arg = arg else { return }
                let ctx = Unmanaged<DispatchContext>.fromOpaque(arg).takeRetainedValue()
                ctx.closure()
            }, ptr)
        }
    }

    /// Navigates the webview to the specified URL.
    /// - Parameter url: The URL to navigate to.
    /// - Returns: The current instance of Webview for chaining.
    @discardableResult
    public func navigate(_ url: String) -> Webview {
        let u = url
        self.dispatch { [weak self] in
            guard let self = self, !self.destroyed else { return }
            webview_navigate(self.wv, u)
        }
        return self
    }

    /// Sets the HTML content of the webview.
    /// - Parameter html: The HTML content to set.
    /// - Returns: The current instance of Webview for chaining.
    @discardableResult
    public func setHtml(_ html: String) -> Webview {
        let h = html
        self.dispatch { [weak self] in
            guard let self = self, !self.destroyed else { return }
            webview_set_html(self.wv, h)
        }
        return self
    }

    /// Sets the title of the webview.
    /// - Parameter title: The title to set.
    /// - Returns: The current instance of Webview for chaining.
    @discardableResult
    public func setTitle(_ title: String) -> Webview {
        let t = title
        self.dispatch { [weak self] in
            guard let self = self, !self.destroyed else { return }
            webview_set_title(self.wv, t)
        }
        return self
    }

    /// Sets the title of the webview.
    /// - Parameter title: The title to set.
    /// - Returns: The current instance of Webview for chaining.
    @discardableResult
    public func setSize(_ width: Int32, _ height: Int32, _ hint: SizeHint) -> Webview {
        self.dispatch { [weak self] in
            guard let self = self, !self.destroyed else { return }
            webview_set_size(self.wv, width, height, webview_hint_t(rawValue: UInt32(hint.rawValue)))
        }
        return self
    }

    /// Injects & executes JavaScript code into every new page in the webview.
    /// It is guaranteed that this will execute before `window.onload`
    /// - Parameter js: The JavaScript code to inject.
    /// - Returns: The current instance of Webview for chaining.
    @discardableResult
    public func inject(_ js: String) -> Webview {
        let j = js
        self.dispatch { [weak self] in
            guard let self = self, !self.destroyed else { return }
            webview_init(self.wv, j)
        }
        return self
    }

    /// Evaluates JavaScript code in the webview. Evaluation happens asynchronously.
    /// The result of the JavaScript is ignored.
    /// Execute a function bound with `bind` if you need two way communication.
    /// - Parameter js: The JavaScript code to evaluate.
    /// - Returns: The current instance of Webview for chaining.
    @discardableResult
    public func eval(_ js: String) -> Webview {
        let j = js
        self.dispatch { [weak self] in
            guard let self = self, !self.destroyed else { return }
            webview_eval(self.wv, j)
        }
        return self
    }

    /// Binds a swift function to a named JavaScript function in the global scope.
    /// - Parameter name: The name that will be used to invoke the function in JavaScript.
    /// - Parameter callback: The swift function to execute when the JS function is invoked
    /// - Returns: The current instance of Webview for chaining.
    @discardableResult
    public func bind(_ name: String, _ callback: @escaping JSCallback) -> Webview {
        guard !destroyed else {
            return self
        }
        let context = CallbackContext(wv, callback)
        callbacks[name] = context

        let bridge: CCallback = { seq, req, arg in
            guard let seq = seq, let req = req, let arg = arg else {
                return
            }

            // 使用 takeUnretainedValue 读取，不消耗引用计数（引用由 passRetained 持有）
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

        // 使用 passRetained 确保 C 层持有的指针有有效的引用计数保护
        let contextPtr = Unmanaged.passRetained(context).toOpaque()

        webview_bind(wv, name, bridge, contextPtr)
        return self
    }

    /// Unbinds a function and removes it from the global JavaScript scope
    /// Parameter name: The name of the JavaScript function to unbind.
    @discardableResult
    public func unbind(_ name: String) -> Webview {
        let n = name
        self.dispatch { [weak self] in
            guard let self = self, !self.destroyed else { return }
            // 先取出 context，如果存在则释放 passRetained 时增加的引用
            if let context = self.callbacks.removeValue(forKey: n) {
                Unmanaged.passUnretained(context).release()
            }
            webview_unbind(self.wv, n)
        }
        return self
    }

    /// Destroys the webview and closes the window.
    /// Once a Webview has been destroyed it cannot be used.
    /// Returns: The current instance of Webview for chaining.
    @discardableResult
    public func destroy() -> Webview {
        if !destroyed {
            // 先收集所有 key，避免在遍历中修改字典
            let keys = Array(callbacks.keys)
            for key in keys {
                // 释放 passRetained 增加的引用
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

    /// Terminates the main loop and closes the window.
    /// This function is thread safe.
    /// Returns: The current instance of Webview for chaining.
    @discardableResult
    public func terminate() -> Webview {
        if !destroyed {
            webview_terminate(wv)
        }
        return self
    }

    // MARK: - Async Evaluation

    private var continuations: [String: CheckedContinuation<String, Error>] = [:]
    private var isReturnHelperBound: Bool = false

    /// Error thrown during evaluating JavaScript
    public enum EvalError: Error {
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
            
            // 使用 continuation 前确保持有该引用，由于 dispatch 和 binding 是多线程行为
            // 但 swift 层面有 `DispatchQueue.main` 或并发队列保护，这里我们将它转到 task 内部
            Task {
                if let continuation = self?.continuations.removeValue(forKey: id) {
                    if isError {
                        continuation.resume(throwing: EvalError.executionError(resultStr))
                    } else {
                        continuation.resume(returning: resultStr)
                    }
                }
            }
            
            return "{}"
        }
    }

    /// Evaluates JavaScript code asynchronously and returns its result as a JSON string.
    /// - Parameter js: The JavaScript code to evaluate.
    /// - Returns: The JSON stringified result of the evaluation.
    public func evaluateJavaScript(_ js: String) async throws -> String {
        guard !destroyed else {
            throw EvalError.destroyed
        }
        
        bindReturnHelperIfNeeded()

        let id = UUID().uuidString
        
        // We wrap the user's JS in an async IIFE.
        // It executes the code, checks if it's a promise, awaits if so,
        // and stringifies the result before sending it back via our bound helper.
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
            self.dispatch { [weak self] in
                guard let self = self else { return }
                self.continuations[id] = continuation
                self.eval(wrappedJS)
            }
        }
    }
}
