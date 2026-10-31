import AppKit
import WebKit

private final class SettingsWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

// The panel is bundled, offline content. Only close and drag cross into native code.
final class SettingsPanel: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let window: NSWindow
    let webView: WKWebView
    var onTestComplete: ((Bool, String) -> Void)?
    private let resources: URL
    private var previewPath: String?

    init(resources: URL) {
        self.resources = resources
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
        window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        webView.navigationDelegate = self
        config.userContentController.add(self, name: "panel")
        webView.setValue(false, forKey: "drawsBackground")
        window.title = "Wuwa Tappo · 背包与设置"
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.level = .floating
        window.collectionBehavior = [.fullScreenAuxiliary]
    }

    func show(previewPath: String? = nil) {
        self.previewPath = previewPath
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame.insetBy(dx: 24, dy: 24)
            let scale = min(1, min(visible.width / 1100, visible.height / 760))
            window.setContentSize(NSSize(width: 1100 * scale, height: 760 * scale))
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if webView.url == nil {
            webView.loadFileURL(resources.appendingPathComponent("panel/index.html"), allowingReadAccessTo: resources)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let body = message.body as? [String: String] else { return }
        switch body["type"] {
        case "close": window.orderOut(nil)
        case "drag":
            if let event = NSApp.currentEvent, event.type == .leftMouseDown { window.performDrag(with: event) }
        default: break
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, url.isFileURL,
              url.standardizedFileURL.path.hasPrefix(resources.standardizedFileURL.path + "/") else {
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard previewPath != nil else { return }
        webView.callAsyncJavaScript("""
          await document.fonts.ready;
          await Promise.all([...document.images].filter(img => img.getAttribute('src')).map(img => img.decode()));
          return await window.panelTest.run();
          """, arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error): self.onTestComplete?(false, "Panel test: \(error)")
            case .success(let value):
                NSLog("Panel test: %@", String(describing: value))
                if CommandLine.arguments.contains("--login-preview") {
                    self.webView.evaluateJavaScript("window.panelTest.showLogin()")
                }
                // Let WebKit finish the post-test preview render before capturing.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.capture() }
            }
        }
    }

    private func capture() {
        webView.takeSnapshot(with: nil) { [weak self] image, error in
            guard let self = self, let path = self.previewPath else { return }
            guard let image = image, let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
                self.onTestComplete?(false, "Panel snapshot failed: \(String(describing: error))"); return
            }
            do {
                try png.write(to: URL(fileURLWithPath: path))
                self.onTestComplete?(true, "Panel navigation, filters, preview and snapshot: \(path)")
            } catch { self.onTestComplete?(false, error.localizedDescription) }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onTestComplete?(false, error.localizedDescription)
    }
}
