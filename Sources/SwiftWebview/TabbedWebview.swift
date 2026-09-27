import Foundation
import cWebview

/// One UI event loop and native window. Invoke page operations through dispatch.
@available(macOS 10.15, *)
public final class TabbedWebview: @unchecked Sendable {
    private let root = Webview(false)
    private var native: UnsafeMutableRawPointer?
    public private(set) var pages: [String: Webview] = [:]
    public private(set) var selectedPage: String?
    public private(set) var interactivePage: String?
    public var onEvent: (@Sendable (String, String, String) -> Void)?
    public var onPageCreated: (@Sendable (String, Webview, String?) -> Void)?

    public init() {
        root.setTitle("Logorythia Browser").setSize(1024, 720, .None)
        native = webview_tabs_create(root.wv, { event, page, value, context in
            guard let context, let event, let page, let value else { return nil }
            let owner = Unmanaged<TabbedWebview>.fromOpaque(context).takeUnretainedValue()
            let name = String(cString: event), id = String(cString: page), text = String(cString: value)
            if name == "popup" {
                let childID = UUID().uuidString
                guard let child = owner.createPage(childID, opener: id) else { return nil }
                owner.onEvent?("page_created", childID, id)
                if owner.interactivePage == id {
                    owner.setInteractive(childID)
                    owner.select(childID, show: true)
                }
                return child.wv
            }
            if name == "selected" { owner.selectedPage = id }
            owner.onEvent?(name, id, text)
            return nil
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    deinit {
        // Restore native delegates and detach widgets before releasing page engines.
        webview_tabs_destroy(native)
        for page in pages.values { page.destroy() }
        root.destroy()
    }

    public func dispatch(_ work: @escaping @Sendable () -> Void) { root.dispatch(work) }
    public func run() { root.run() }
    public func terminate() { root.terminate() }

    @discardableResult
    public func createPage(_ id: String, opener: String? = nil) -> Webview? {
        guard pages[id] == nil, native != nil else { return nil }
        let page = Webview(false, parentWindow: webview_get_window(root.wv))
        pages[id] = page
        webview_tabs_attach(native, page.wv, id)
        webview_tabs_interactive(native, id, 0)
        onPageCreated?(id, page, opener)
        return page
    }

    public func closePage(_ id: String) {
        guard let page = pages.removeValue(forKey: id) else { return }
        webview_tabs_remove(native, id)
        page.destroy()
        if interactivePage == id { interactivePage = nil }
        if selectedPage == id { selectedPage = pages.keys.sorted().first }
        if pages.isEmpty { webview_tabs_visible(native, 0) }
    }

    public func select(_ id: String, show: Bool) {
        guard pages[id] != nil else { return }
        selectedPage = id
        webview_tabs_select(native, id, show ? 1 : 0)
    }

    public func setInteractive(_ id: String?) {
        for pageID in pages.keys { webview_tabs_interactive(native, pageID, pageID == id ? 1 : 0) }
        interactivePage = id
    }

    public func setTitle(_ title: String, pageID: String) { webview_tabs_title(native, pageID, title) }
    public func setVisible(_ visible: Bool) { webview_tabs_visible(native, visible ? 1 : 0) }
}
