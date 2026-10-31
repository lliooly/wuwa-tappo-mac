import AppKit
import WebKit
import ServiceManagement
import Network

private final class OriginalWindow: NSWindow {
    var interactive = true
    override var canBecomeKey: Bool { interactive }
    override var canBecomeMain: Bool { interactive }
}

private final class OriginalPetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class OriginalWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class OriginalAssetScheme: NSObject, WKURLSchemeHandler {
    let root: URL
    init(root: URL) { self.root = root }
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, url.host == "app" else { task.didFailWithError(CocoaError(.fileReadNoPermission)); return }
        let path = url.path.removingPercentEncoding ?? url.path
        let file = root.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).standardizedFileURL.resolvingSymlinksInPath()
        guard file.path.hasPrefix(root.standardizedFileURL.path + "/"), let data = try? Data(contentsOf: file) else {
            task.didFailWithError(CocoaError(.fileNoSuchFile)); return
        }
        let types = ["html": "text/html", "js": "application/javascript", "css": "text/css", "json": "application/json",
                     "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "svg": "image/svg+xml",
                     "woff2": "font/woff2", "ico": "image/x-icon"]
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": types[file.pathExtension] ?? "application/octet-stream", "Access-Control-Allow-Origin": "*"
        ])!
        task.didReceive(response); task.didReceive(data); task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

final class OriginalFrontend: NSObject, WKScriptMessageHandlerWithReply, WKScriptMessageHandler, WKNavigationDelegate {
    let resources: URL
    var windows: [String: NSWindow] = [:]
    var views: [String: WKWebView] = [:]
    var lastSnapshot: [String: Any]?
    var unknownCommands = Set<String>()
    var runtimeErrors: [String] = []
    var onExit: (() -> Void)?
    var onRequestInputAccess: (() -> Void)?
    private var ready = Set<String>()
    private var pointerTimer: Timer?
    private var mainHitRects: [[String: Any]] = []
    private var panelOpen = false
    private var resizeMonitor: Any?
    private var mouseDownMonitor: Any?
    private var lastMouseDown: NSEvent?
    private var shortcutCapture = false
    private var panelMousePress = false
    private var status: NSStatusItem?
    private var menuLabels: [String: String] = [:]
    private var nativeMenuState: [String: Any] = [:]
    private var inputStatus: String?
    private var source: OriginalAssetScheme
    private let base = URL(string: "wuwa://app/")!
    private var flags: [String: Any] = [:]
    private let clickStore = OriginalClickStore()
    private lazy var sessionStore = OriginalSessionStore()
    private let networkMonitor = NWPathMonitor()
    private var onlineReportTimer: Timer?
    private var networkRules: WKContentRuleList?
    private let online = !CommandLine.arguments.contains("--offline") && !CommandLine.arguments.contains("--original-preview") && !CommandLine.arguments.contains("--original-audit")

    init(resources: URL) {
        self.resources = resources.appendingPathComponent("original")
        self.source = OriginalAssetScheme(root: resources.appendingPathComponent("original"))
        super.init()
        if let shortcuts = UserDefaults.standard.dictionary(forKey: "originalShortcuts") { flags["shortcuts"] = shortcuts }
    }

    func start() {
        let filters = online ? [
            "^https?://mp-cn-sdklog\\.kurogames\\.com/",
            "^https?://ali-sh-datareceiver\\.kurogame\\.xyz/",
            "^https?://sdkdataapi\\.kurogame\\.com/maidian",
            "^https?://api-mc-wuwatappo\\.kurogames-global\\.com/zimple-api/frontend/report/"
        ] : ["^https?://", "^wss?://"]
        let rules = filters.map { ["trigger": ["url-filter": $0], "action": ["type": "block"]] }
        let json = String(data: try! JSONSerialization.data(withJSONObject: rules), encoding: .utf8)!
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "wuwa-\(online ? "online" : "offline")-v1", encodedContentRuleList: json) { [weak self] list, error in
            guard let self = self, let list = list else {
                NSLog("Network isolation rules unavailable; application startup stopped")
                NSApp.terminate(nil)
                return
            }
            self.networkRules = list
            self.startRuntime()
        }
    }

    private func startRuntime() {
        if online {
            networkMonitor.pathUpdateHandler = { [weak self] path in
                DispatchQueue.main.async { self?.emit("cat-native-network-status-changed", ["internetAccess": path.status == .satisfied]) }
            }
            networkMonitor.start(queue: DispatchQueue(label: "wuwa.network-status"))
        }
        // WK IPC arrives after the DOM mousedown handler returns. Keep the actual
        // originating event rather than relying on NSApp.currentEvent at reply time.
        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.lastMouseDown = event
            return event
        }
        _ = create(label: "main", route: "/")
        windows["main"]?.orderFrontRegardless()
        buildApplicationMenu()
        buildMenu()
        pointerTimer = Timer.scheduledTimer(withTimeInterval: 1/30, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let point = self.screenPoint(NSEvent.mouseLocation)
            self.emit("mouse-move", ["x": point.x, "y": point.y], target: "main")
            if let window = self.windows["main"] {
                let p = window.convertPoint(fromScreen: NSEvent.mouseLocation)
                let local = NSPoint(x: p.x, y: window.frame.height - p.y)
                let hit = self.mainHitRects.contains { rect in
                    let x = rect["left"] as? Double ?? rect["x"] as? Double ?? 0
                    let y = rect["top"] as? Double ?? rect["y"] as? Double ?? 0
                    return NSRect(x: x, y: y, width: rect["width"] as? Double ?? 0, height: rect["height"] as? Double ?? 0).contains(local)
                }
                if NSEvent.pressedMouseButtons == 0 { window.ignoresMouseEvents = !hit }
            }
        }
    }

    @discardableResult func create(label: String, route: String) -> NSWindow {
        if let existing = windows[label] { return existing }
        let config = WKWebViewConfiguration()
        if let rules = networkRules { config.userContentController.add(rules) }
        config.setURLSchemeHandler(source, forURLScheme: "wuwa")
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "originalInvoke")
        config.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "originalSession")
        config.userContentController.add(self, name: "originalLog")
        let initialSession = online ? sessionStore.snapshot() : [:]
        let sessionJSON = String(data: try! JSONSerialization.data(withJSONObject: initialSession), encoding: .utf8)!
        let bootstrap = "window.__MACOS_ONLINE__=\(online ? "true" : "false");window.__MACOS_INITIAL_SESSION__=\(sessionJSON);"
        config.userContentController.addUserScript(WKUserScript(source: bootstrap, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        if let session = try? String(contentsOf: resources.appendingPathComponent("session-adapter.js"), encoding: .utf8) {
            config.userContentController.addUserScript(WKUserScript(source: session, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        if let adapter = try? String(contentsOf: resources.appendingPathComponent("tauri-adapter.js"), encoding: .utf8) {
            config.userContentController.addUserScript(WKUserScript(source: adapter, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        if let audit = try? String(contentsOf: resources.appendingPathComponent("audit.js"), encoding: .utf8) {
            config.userContentController.addUserScript(WKUserScript(source: audit, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        let view = OriginalWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = self
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = label == "main" ? screen.size : (label == "login" ? NSSize(width: 500, height: 378) : NSSize(width: 1100, height: 756))
        let rect = NSRect(origin: label == "main" ? screen.origin : .zero, size: size)
        let window: NSWindow
        if label == "main" {
            let panel = OriginalPetPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isFloatingPanel = true; panel.becomesKeyOnlyIfNeeded = true
            window = panel
        } else {
            let auxiliary = OriginalWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
            auxiliary.interactive = label != "toast"
            window = auxiliary
        }
        window.title = "Wuwa Tappo · \(label)"
        window.hidesOnDeactivate = false
        window.acceptsMouseMovedEvents = true
        window.backgroundColor = .clear; window.isOpaque = false
        window.hasShadow = label != "main"; window.isReleasedWhenClosed = false
        window.level = label == "main" ? .floating : NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        window.collectionBehavior = label == "main" ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.fullScreenAuxiliary]
        window.ignoresMouseEvents = label == "main" || label == "toast"
        window.contentView = view
        windows[label] = window; views[label] = view
        if label != "main" { window.center() }
        let url = URL(string: "index.html?window=\(label)#\(route)", relativeTo: base)!
        view.load(URLRequest(url: url))
        return window
    }

    func showPanel(tab: String = "bag") {
        panelOpen = true
        let window = create(label: "panel", route: "/panel?tab=\(tab)")
        let visible = NSScreen.main?.visibleFrame ?? window.frame
        let scale = min(1, min((visible.width - 48)/1100, (visible.height - 48)/756))
        window.setContentSize(NSSize(width: 1100 * scale, height: 756 * scale))
        if let view = views["panel"] { view.setMagnification(scale, centeredAt: .zero) }
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        emit("panel-open-tab", tab, target: "panel")
        if let snapshot = lastSnapshot { emit("cat-panel-state", snapshot, target: "panel") }
    }

    func openPanelFromMain(tab: String = "bag", attempt: Int = 0) {
        if panelOpen { showPanel(tab: tab); return }
        views["main"]?.evaluateJavaScript("(()=>{const button=document.querySelector('.settings-btn');if(!button)return false;button.click();return true})()") { [weak self] value, error in
            guard let self = self else { return }
            if value as? Bool == true {
                DispatchQueue.main.asyncAfter(deadline: .now()+0.2) { self.emit("panel-open-tab", tab, target: "panel") }
            } else if attempt < 30 {
                DispatchQueue.main.asyncAfter(deadline: .now()+0.1) { self.openPanelFromMain(tab: tab, attempt: attempt+1) }
            }
        }
    }

    func emit(_ event: String, _ payload: Any = NSNull(), target: String? = nil) {
        for (label, view) in views where target == nil || target == label {
            view.callAsyncJavaScript("window.__ORIGINAL_RECEIVE__(event, payload)", arguments: ["event": event, "payload": payload],
                                     in: nil, in: .page, completionHandler: nil)
        }
    }

    private func screenPoint(_ point: NSPoint) -> NSPoint {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return NSPoint(x: point.x, y: top - point.y)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        if message.name == "originalSession" {
            guard online, message.frameInfo.isMainFrame, let body = message.body as? [String: Any],
                  let name = body["name"] as? String, let value = body["value"] as? String,
                  let days = body["days"] as? Double else { replyHandler(nil, "Invalid session request"); return }
            do {
                try sessionStore.set(name: name, value: value, days: days)
                let snapshot = sessionStore.snapshot()
                for view in views.values where view !== message.webView {
                    view.callAsyncJavaScript("window.__MACOS_SESSION__.receive(snapshot)", arguments: ["snapshot": snapshot], in: nil, in: .page, completionHandler: nil)
                }
                replyHandler(NSNull(), nil)
            } catch { replyHandler(nil, error.localizedDescription) }
            return
        }
        guard let body = message.body as? [String: Any], let label = body["label"] as? String,
              let command = body["command"] as? String else { replyHandler(nil, "Invalid platform request"); return }
        let args = body["args"] as? [String: Any] ?? [:]
        do { replyHandler(try invoke(command, args, label), nil) }
        catch { replyHandler(nil, error.localizedDescription) }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let entry = message.body as? [String: Any] else { return }
        let text = redactOriginalLog("[\(entry["label"] ?? "")] \(entry["kind"] ?? ""): \(entry["value"] ?? "")")
        if ["error", "rejection"].contains(entry["kind"] as? String ?? "") { runtimeErrors.append(text) }
        NSLog("Original %@", text)
    }

    private func invoke(_ command: String, _ args: [String: Any], _ caller: String) throws -> Any {
        let label = args["label"] as? String ?? caller
        let window = windows[label] ?? windows[caller]!
        let null = NSNull()
        if command == "plugin:event|emit" || command == "plugin:event|emit_to" {
            let event = args["event"] as? String ?? ""
            let payload = args["payload"] ?? null
            if event == "cat-panel-state" { lastSnapshot = payload as? [String: Any] }
            let target = (args["target"] as? [String: Any])?["label"] as? String
            emit(event, payload, target: target)
            if event == "cat-panel-action", let action = payload as? [String: Any], action["type"] as? String == "ready" {
                if let snapshot = lastSnapshot { emit("cat-panel-state", snapshot, target: "panel") }
            }
            return null
        }
        switch command {
        case "plugin:app|version": return Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "0.2.0"
        case "plugin:app|name": return "Wuwa Tappo macOS"
        case "plugin:app|identifier": return Bundle.main.bundleIdentifier ?? "io.lliooly.wuwa-tappo.mac"
        case "plugin:app|tauri_version": return "macOS AppKit adapter"
        case "plugin:window|get_all_windows": return Array(windows.keys)
        case "plugin:webview|get_all_webviews": return windows.keys.map { ["label": $0, "windowLabel": $0] }
        case "plugin:window|scale_factor": return 1.0 // Native adapter coordinates are logical points throughout.
        case "plugin:window|outer_size", "plugin:window|inner_size": return ["width": window.frame.width, "height": window.frame.height]
        case "plugin:window|outer_position", "plugin:window|inner_position":
            let point = screenPoint(NSPoint(x: window.frame.minX, y: window.frame.maxY)); return ["x": point.x, "y": point.y]
        case "plugin:window|current_monitor":
            return window.screen.map { monitor($0) as Any } ?? null
        case "plugin:window|primary_monitor":
            // NSScreen.main follows the key window; the first screen owns the
            // menu bar and remains the primary display when focus changes.
            return NSScreen.screens.first.map { monitor($0) as Any } ?? null
        case "plugin:window|monitor_from_point":
            guard let x = args["x"] as? Double, let y = args["y"] as? Double,
                  x.isFinite, y.isFinite else { throw CocoaError(.coderInvalidValue) }
            let point = NSPoint(x: x, y: y)
            // Match the frontend's top-left coordinates directly so the top
            // edge is included and the bottom edge excluded, as in Tauri.
            return NSScreen.screens.first(where: { screen in
                let origin = screenPoint(NSPoint(x: screen.frame.minX, y: screen.frame.maxY))
                return NSRect(origin: origin, size: screen.frame.size).contains(point)
            }).map { monitor($0) as Any } ?? null
        case "plugin:window|available_monitors": return NSScreen.screens.map(monitor)
        case "plugin:window|cursor_position": let point = screenPoint(NSEvent.mouseLocation); return ["x": point.x, "y": point.y]
        case "plugin:window|is_visible": return window.isVisible
        case "plugin:window|is_focused": return window.isKeyWindow
        case "plugin:window|is_fullscreen": return false
        case "plugin:window|is_always_on_top": return true
        case "plugin:window|theme": return "light"
        case "plugin:window|title": return window.title
        case "plugin:window|set_title": window.title = args["value"] as? String ?? window.title; return null
        case "plugin:window|show", "plugin:webview|webview_show": window.orderFrontRegardless(); return null
        case "plugin:window|hide", "plugin:webview|webview_hide": window.orderOut(nil); return null
        case "plugin:window|close", "plugin:window|destroy", "plugin:webview|webview_close": window.orderOut(nil); return null
        case "plugin:window|set_focus", "plugin:webview|set_webview_focus": window.makeKeyAndOrderFront(nil); return null
        case "plugin:window|center": window.center(); return null
        case "plugin:window|start_dragging":
            if let event = lastMouseDown, event.window === window, NSEvent.pressedMouseButtons & 1 != 0 {
                window.performDrag(with: event)
            }
            return null
        case "plugin:window|start_resize_dragging":
            guard let direction = args["value"] as? String,
                  ["North", "South", "East", "West", "NorthWest", "NorthEast", "SouthWest", "SouthEast"].contains(direction) else {
                throw CocoaError(.coderInvalidValue)
            }
            beginResize(window, direction: direction); return null
        case "plugin:window|set_size":
            let value = args["value"] as? [String: Any] ?? [:]
            let size = value["data"] as? [String: Any] ?? value
            if let w = size["width"] as? Double, let h = size["height"] as? Double, label != "main" {
                window.setContentSize(NSSize(width: w, height: h))
            }; return null
        case "plugin:window|set_position":
            let value = args["value"] as? [String: Any] ?? [:]
            let point = value["data"] as? [String: Any] ?? value
            if let x = point["x"] as? Double, let y = point["y"] as? Double, label != "main" {
                let top = NSScreen.screens.first?.frame.maxY ?? 0
                window.setFrameOrigin(NSPoint(x: x, y: top - y - window.frame.height))
            }; return null
        case "plugin:window|set_focusable", "plugin:window|set_always_on_top", "plugin:window|set_decorations",
             "plugin:window|set_skip_taskbar", "plugin:window|set_shadow", "plugin:window|set_ignore_cursor_events",
             "plugin:window|set_min_size", "plugin:window|set_max_size", "plugin:window|set_resizable": return null
        case "open_panel_window":
            let payload = args["payload"] as? [String: Any] ?? [:]
            showPanel(tab: payload["tab"] as? String ?? "bag"); return null
        case "close_panel_window": windows["panel"]?.orderOut(nil); panelOpen = false; emit("cat-panel-window-closed"); return null
        case "raise_panel_window_above_pets": windows["panel"]?.orderFrontRegardless(); return null
        case "set_panel_window_collapsed":
            let collapsed = (args["payload"] as? [String: Any])?["collapsed"] as? Bool ?? false
            if let panel = windows["panel"], let visible = panel.screen?.visibleFrame {
                let width: CGFloat = collapsed ? 958 : 1100
                let scale = min(1, min((visible.width-48)/width, (visible.height-48)/756))
                panel.setContentSize(NSSize(width: width*scale, height: 756*scale))
                views["panel"]?.setMagnification(scale, centeredAt: .zero)
            }; return null
        case "open_about_window":
            create(label: "about", route: "/about").makeKeyAndOrderFront(nil)
            emit("about-open", target: "about"); return null
        case "open_oss_notice_window":
            create(label: "oss-notice", route: "/oss-notice").makeKeyAndOrderFront(nil)
            emit("oss-notice-open", target: "oss-notice"); return null
        case "close_about_window": windows["about"]?.orderOut(nil); return null
        case "close_oss_notice_window": windows["oss-notice"]?.orderOut(nil); return null
        case "open_login_window":
            create(label: "login", route: "/login").makeKeyAndOrderFront(nil)
            emit("login-modal-open", ["intent": args["intent"] as? String ?? "login"], target: "login")
            return null
        case "resize_login_window_to_content":
            guard let payload = args["payload"] as? [String: Any],
                  let width = payload["width"] as? Double, let height = payload["height"] as? Double,
                  width.isFinite, height.isFinite, width > 0, height > 0,
                  let login = windows["login"] else { throw CocoaError(.coderInvalidValue) }
            let visible = (login.screen ?? NSScreen.main)?.visibleFrame ?? login.frame
            let size = NSSize(width: min(width, visible.width), height: min(height, visible.height))
            let center = NSPoint(x: login.frame.midX, y: login.frame.midY)
            login.setContentSize(size)
            login.setFrameOrigin(NSPoint(x: max(visible.minX, min(center.x - size.width/2, visible.maxX - size.width)),
                                         y: max(visible.minY, min(center.y - size.height/2, visible.maxY - size.height))))
            return null
        case "close_login_window": windows["login"]?.orderOut(nil); return null
        case "load_key_press_count", "load_cumulative_click_count", "save_key_press_count", "save_cumulative_click_count":
            return try clickStore.invoke(command, args: args)
        case "is_force_update_locked", "is_internal_testing_build", "is_devtools_hotkeys_build", "has_maintenance_notice", "is_elevated_autostart_enabled": return false
        case "get_track_os_info": return ["os": "macOS", "osVersion": ProcessInfo.processInfo.operatingSystemVersionString]
        case "get_app_shortcuts": return flags["shortcuts"] ?? ["togglePet": ["key": 120, "modifiers": 0], "gameMode": ["key": 119, "modifiers": 0], "switchScreen": ["key": 121, "modifiers": 0]]
        case "set_app_shortcuts":
            guard let config = args["config"] as? [String: Any] else { throw CocoaError(.coderInvalidValue) }
            let bindings = config.values.compactMap { $0 as? [String: Int] }.filter { ($0["key"] ?? 0) > 0 }
            let unique = Set(bindings.map { "\($0["modifiers"] ?? 0):\($0["key"] ?? 0)" })
            if unique.count != bindings.count { throw NSError(domain: "Shortcut", code: 1, userInfo: [NSLocalizedDescriptionKey: "duplicate"]) }
            flags["shortcuts"] = config; UserDefaults.standard.set(config, forKey: "originalShortcuts")
            emit("app-shortcuts-changed", config); return null
        case "get_main_desktop_safe_area":
            let screen = windows["main"]?.screen ?? NSScreen.main!
            let fullscreen = foregroundFullscreen(on: screen)
            return ["insets": safeInsets(screen), "autoHideEdge": null, "foregroundFullscreen": fullscreen, "foregroundApplicationFullscreen": fullscreen]
        case "get_main_taskbar_insets": return safeInsets(windows["main"]?.screen ?? NSScreen.main!)
        case "get_boot_diagnostics": return ["system": ["platform": "macOS"], "runtime": ["webview_version": "System WebKit"]]
        case "set_main_hit_region":
            let payload = args["payload"] as? [String: Any] ?? [:]
            if payload["updateNativeInput"] as? Bool == true {
                mainHitRects = payload["inputRegions"] as? [[String: Any]] ?? []
            }
            return null
        case "sync_native_menu":
            menuLabels = args["labels"] as? [String: String] ?? menuLabels
            nativeMenuState = args
            buildMenu(); return null
        case "set_native_input_cursor", "set_overlay_cursor":
            switch args["kind"] as? String {
            case "grab": NSCursor.openHand.set()
            case "grabbing": NSCursor.closedHand.set()
            case "pointer": NSCursor.pointingHand.set()
            default: NSCursor.arrow.set()
            }; return null
        case "set_shortcut_capture": shortcutCapture = args["active"] as? Bool ?? false; return null
        case "set_main_skip_taskbar":
            NSApp.setActivationPolicy(args["skip"] as? Bool == true ? .accessory : .regular); return null
        case "set_main_window_fullscreen_shell":
            if let main = windows["main"], let screen = main.screen ?? NSScreen.main { main.setFrame(screen.frame, display: true) }
            return null
        case "set_main_window_monitor_bounds":
            let payload = args["payload"] as? [String: Any] ?? [:]
            if let x = payload["x"] as? Double, let y = payload["y"] as? Double,
               let w = payload["width"] as? Double, let h = payload["height"] as? Double {
                let top = NSScreen.screens.first?.frame.maxY ?? 0
                windows["main"]?.setFrame(NSRect(x: x, y: top-y-h, width: w, height: h), display: true)
            }; return null
        case "popup_main_dock_context_menu":
            if let window = windows["main"], let view = views["main"] {
                let point = view.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
                status?.menu?.popUp(positioning: nil, at: point, in: view)
            }
            return null
        case "sync_aux_windows_to_main_monitor":
            if let frame = windows["main"]?.screen?.visibleFrame {
                for (label, other) in windows where label != "main" {
                    other.setFrameOrigin(NSPoint(x: frame.midX-other.frame.width/2, y: frame.midY-other.frame.height/2))
                }
            }; return null
        case "write_app_log":
            let line = redactOriginalLog("\(ISO8601DateFormatter().string(from: Date())) [\(args["level"] ?? "info")] \(args["message"] ?? "")\n")
            let directory = try logDirectory()
            let file = directory.appendingPathComponent("app.log")
            if !FileManager.default.fileExists(atPath: file.path) { _ = FileManager.default.createFile(atPath: file.path, contents: nil) }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd(); try handle.write(contentsOf: Data(line.utf8)); return null
        case "plugin:path|resolve_directory":
            guard args["directory"] as? Int == 17 else { throw CocoaError(.fileReadNoPermission) }
            return try logDirectory().path
        case "plugin:opener|open_path":
            let logs = try logDirectory()
            guard let path = args["path"] as? String, isLogPath(path, directory: logs) else { throw CocoaError(.fileReadNoPermission) }
            NSWorkspace.shared.open(URL(fileURLWithPath: path)); return null
        case "plugin:opener|reveal_item_in_dir":
            let logs = try logDirectory()
            guard let paths = args["paths"] as? [String], !paths.isEmpty,
                  paths.allSatisfy({ isLogPath($0, directory: logs) }) else { throw CocoaError(.fileReadNoPermission) }
            NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(fileURLWithPath: $0) }); return null
        case "plugin:opener|open_url":
            guard let value = args["url"] as? String, let url = externalURL(value) else { throw CocoaError(.fileReadNoPermission) }
            guard NSWorkspace.shared.open(url) else { throw CocoaError(.fileReadUnknown) }
            return null
        case "plugin:process|restart":
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-n", Bundle.main.bundlePath, "--args", "--original-ui"]
            try process.run(); onExit?(); return null
        case "set_main_swallow_mouse", "set_main_force_cursor_ignore", "set_main_window_content_bounds",
             "apply_main_window_position", "sync_main_window_to_current_monitor",
             "finish_main_window_monitor_switch": return null
        case "plugin:autostart|is_enabled": return SMAppService.mainApp.status == .enabled
        case "plugin:autostart|enable":
            try SMAppService.mainApp.register()
            guard SMAppService.mainApp.status == .enabled else {
                let reason = SMAppService.mainApp.status == .requiresApproval ? "请在系统设置的登录项中允许 Wuwa Tappo，然后重试。" : "开机启动尚未启用。"
                throw NSError(domain: "Autostart", code: 1, userInfo: [NSLocalizedDescriptionKey: reason])
            }
            return null
        case "plugin:autostart|disable": try SMAppService.mainApp.unregister(); return null
        case "check_app_update": return ["enabled": false, "kind": "disabled"]
        case "show_toast_overlay":
            let toast = create(label: "toast", route: "/toast")
            toast.ignoresMouseEvents = true
            toast.orderFrontRegardless(); return null
        case "exit_app": onExit?(); return null
        default:
            if unknownCommands.insert(command).inserted { NSLog("Original unsupported command: %@ %@", command, String(describing: args)) }
            throw NSError(domain: "OriginalAdapter", code: 1, userInfo: [NSLocalizedDescriptionKey: "macOS adapter not implemented: \(command)"])
        }
    }

    private func monitor(_ screen: NSScreen) -> [String: Any] {
        let point = screenPoint(NSPoint(x: screen.frame.minX, y: screen.frame.maxY))
        let workPoint = screenPoint(NSPoint(x: screen.visibleFrame.minX, y: screen.visibleFrame.maxY))
        return ["name": screen.localizedName, "position": ["x": point.x, "y": point.y],
                "size": ["width": screen.frame.width, "height": screen.frame.height], "scaleFactor": 1.0,
                "workArea": ["position": ["x": workPoint.x, "y": workPoint.y], "size": ["width": screen.visibleFrame.width, "height": screen.visibleFrame.height]]]
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let label = views.first(where: { $0.value === webView })?.key { ready.insert(label); NSLog("Original loaded: %@", label) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = action.request.url
        if url?.scheme == "wuwa" { decisionHandler(.allow); return }
        if online, action.targetFrame?.isMainFrame == false, url?.scheme == "https",
           let host = url?.host, ["kurogame.com", "kurogames.com", "kurogames-global.com"].contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            decisionHandler(.allow); return
        }
        if action.navigationType == .linkActivated, let url = url, externalURL(url.absoluteString) != nil {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    func key(_ code: Int, down: Bool, flags rawFlags: UInt64 = 0, repeated: Bool = false) {
        emit(down ? "key-press" : "key-release", String(code), target: "main")
        if down && !repeated && !shortcutCapture {
            let bindings = flags["shortcuts"] as? [String: [String: Int]] ??
                ["togglePet": ["key": 120, "modifiers": 0], "gameMode": ["key": 119, "modifiers": 0], "switchScreen": ["key": 121, "modifiers": 0]]
            let cg = CGEventFlags(rawValue: rawFlags)
            let modifiers = (cg.contains(.maskAlternate) ? 1 : 0) | (cg.contains(.maskControl) ? 2 : 0) |
                            (cg.contains(.maskShift) ? 4 : 0) | (cg.contains(.maskCommand) ? 8 : 0)
            for (action, binding) in bindings where binding["key"] == virtualKey(code) && binding["modifiers"] == modifiers {
                emit("app-shortcut", action, target: "main")
            }
        }
    }
    func mouse(button: String, down: Bool, location: CGPoint? = nil) {
        if button == "left" {
            if down, let panel = windows["panel"], panel.isVisible {
                let point = location.map { NSPoint(x: $0.x, y: (NSScreen.screens.first?.frame.maxY ?? 0)-$0.y) } ?? NSEvent.mouseLocation
                if NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0) == panel.windowNumber {
                    // The original panel's mousedown capture already emits
                    // pet-clap. Do not count that same press through the global hook.
                    panelMousePress = true
                    return
                }
            } else if !down && panelMousePress {
                panelMousePress = false
                return
            }
        }
        emit("mouse-button", ["button": button, "action": down ? "press" : "release"], target: "main")
    }
    func resetInput() {
        panelMousePress = false
        views["main"]?.evaluateJavaScript("window.__MACOS_RESET_INPUT__?.()")
    }

    private func virtualKey(_ code: Int) -> Int {
        let keys: [Int: Int] = [0:65,1:83,2:68,3:70,4:72,5:71,6:90,7:88,8:67,9:86,11:66,12:81,13:87,14:69,15:82,16:89,17:84,
            18:49,19:50,20:51,21:52,22:54,23:53,24:187,25:57,26:55,27:189,28:56,29:48,30:221,31:79,32:85,33:219,34:73,35:80,
            36:13,37:76,38:74,39:222,40:75,41:186,42:220,43:188,44:191,45:78,46:77,47:190,48:9,49:32,50:192,51:8,53:27,
            122:112,120:113,99:114,118:115,96:116,97:117,98:118,100:119,101:120,109:121,103:122,111:123,
            105:124,107:125,113:126,106:127,64:128,79:129,80:130,90:131,
            123:37,124:39,125:40,126:38,115:36,119:35,116:33,121:34,117:46]
        return keys[code] ?? 0
    }

    private func buildMenu() {
        if status == nil { status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength); status?.button?.title = "团团" }
        let menu = NSMenu()
        for (key, fallback, action) in [("openBag", "背包", "bag"), ("openAtlas", "图鉴", "atlas"), ("openExchange", "合成", "exchange"),
                                        ("openRoom", "联机", "room"), ("trayOpenSettings", "设置", "setting"),
                                        ("hidePet", "显示／隐藏玩偶", "togglePet"), ("gameMode", "游戏模式", "gameMode"),
                                        ("quit", "退出", "quit")] {
            let item = NSMenuItem(title: menuLabels[key] ?? fallback, action: #selector(menuAction(_:)), keyEquivalent: "")
            if action == "togglePet", nativeMenuState["petDockVisible"] as? Bool == false {
                item.title = menuLabels["showPet"] ?? "显示玩偶"
            }
            if action == "gameMode" { item.state = nativeMenuState["gameMode"] as? Bool == true ? .on : .off }
            item.representedObject = action; item.target = self; menu.addItem(item)
        }
        for (title, event, values) in [(menuLabels["windowSize"] ?? "窗口大小", "tray-set-pet-scale", Array(stride(from: 50, through: 200, by: 10))),
                                        (menuLabels["windowOpacity"] ?? "透明度", "tray-set-window-opacity", Array(stride(from: 0, through: 100, by: 10)))] {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for value in values {
                let option = NSMenuItem(title: "\(value)%", action: #selector(menuSetting(_:)), keyEquivalent: "")
                option.representedObject = ["event": event, "value": value]; option.target = self; submenu.addItem(option)
                let field = event == "tray-set-pet-scale" ? "petScale" : "windowOpacity"
                option.state = (nativeMenuState[field] as? NSNumber)?.intValue == value ? .on : .off
            }
            item.submenu = submenu; menu.insertItem(item, at: max(0, menu.items.count-1))
        }
        let passthrough = NSMenuItem(title: menuLabels["windowPassthrough"] ?? "禁用拖动", action: #selector(menuSetting(_:)), keyEquivalent: "")
        passthrough.target = self; passthrough.representedObject = ["event": "tray-toggle-window-passthrough"]
        passthrough.state = nativeMenuState["windowPassthrough"] as? Bool == true ? .on : .off
        menu.insertItem(passthrough, at: max(0, menu.items.count-1))
        let restart = NSMenuItem(title: menuLabels["restart"] ?? "重启", action: #selector(menuSetting(_:)), keyEquivalent: "")
        restart.target = self; restart.representedObject = ["event": "tray-restart"]
        menu.insertItem(restart, at: max(0, menu.items.count-1))
        menu.insertItem(.separator(), at: 0)
        let permission = NSMenuItem(title: inputStatus ?? (CGPreflightListenEventAccess() ? "输入监控已授权" : "授权输入监控…"), action: #selector(requestInputAccess), keyEquivalent: "")
        permission.target = self; menu.insertItem(permission, at: 0)
        status?.menu = menu
    }

    private func buildApplicationMenu() {
        let bar = NSMenu()
        let application = NSMenuItem(); application.submenu = NSMenu(title: "Wuwa Tappo")
        let about = NSMenuItem(title: "关于 Wuwa Tappo", action: #selector(openAbout), keyEquivalent: "")
        about.target = self; application.submenu?.addItem(about)
        let settings = NSMenuItem(title: "设置…", action: #selector(menuAction(_:)), keyEquivalent: ",")
        settings.target = self; settings.representedObject = "setting"; application.submenu?.addItem(settings)
        application.submenu?.addItem(.separator())
        let quit = NSMenuItem(title: "退出 Wuwa Tappo", action: #selector(menuAction(_:)), keyEquivalent: "q")
        quit.target = self; quit.representedObject = "quit"; application.submenu?.addItem(quit)
        bar.addItem(application)
        let edit = NSMenuItem(); edit.submenu = NSMenu(title: "编辑")
        for (title, selector, key) in [("撤销", "undo:", "z"), ("重做", "redo:", "Z"), ("剪切", "cut:", "x"),
                                       ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            let item = NSMenuItem(title: title, action: Selector(selector), keyEquivalent: key)
            if key == "Z" { item.keyEquivalentModifierMask = [.command, .shift] }
            edit.submenu?.addItem(item)
        }
        bar.addItem(edit); NSApp.mainMenu = bar
    }

    @objc private func openAbout() { _ = try? invoke("open_about_window", [:], "main") }

    @objc private func menuAction(_ item: NSMenuItem) {
        guard let action = item.representedObject as? String else { return }
        if action == "quit" {
            NSApp.terminate(nil)
            return
        }
        if action == "togglePet" || action == "gameMode" {
            emit(action == "togglePet" ? "tray-toggle-pet-visibility" : "tray-toggle-game-mode", target: "main")
            return
        }
        openPanelFromMain(tab: action)
    }

    func requestQuit(onFailure: ((Error) -> Void)? = nil) {
        guard let view = views["main"] else { onFailure?(CocoaError(.coderInvalidValue)); return }
        view.callAsyncJavaScript("const m=await import('wuwa://app/assets/quitApp-DE3M1AoN.js');await m.quitApp();", arguments: [:], in: nil, in: .page) { result in
            if case .failure(let error) = result { onFailure?(error) }
        }
    }

    func testSnapshot(path: String) {
        if CommandLine.arguments.contains("--original-audit"),
           let data = try? JSONSerialization.data(withJSONObject: ["status": "running", "startedAt": ISO8601DateFormatter().string(from: Date())]) {
            try? data.write(to: URL(fileURLWithPath: path + ".audit.json"))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self = self else { return }
            self.views["main"]?.evaluateJavaScript("document.querySelector('.settings-btn')?.click()")
            self.views["main"]?.callAsyncJavaScript("return {text:document.body.innerText,calls:window.__ORIGINAL_DIAGNOSTICS__.calls,errors:window.__ORIGINAL_DIAGNOSTICS__.errors};", arguments: [:], in: nil, in: .page) { result in
                if case .failure(let error) = result { NSLog("Original main inspection failed: %@", error.localizedDescription) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                if CommandLine.arguments.contains("--original-audit") {
                    self.auditPages(path: path, index: 0, results: []); return
                }
                guard let view = self.views["panel"] else { exit(1) }
                view.callAsyncJavaScript("return {text:document.body.innerText, errors:window.__ORIGINAL_DIAGNOSTICS__.errors, calls:window.__ORIGINAL_DIAGNOSTICS__.calls};",
                    arguments: [:], in: nil, in: .page) { result in
                    NSLog("Original panel inspection: %@", String(describing: result))
                    let details: [String: Any] = ["inspection": String(describing: result), "unknown": self.unknownCommands.sorted(),
                        "errors": self.runtimeErrors, "snapshot": self.lastSnapshot ?? [:]]
                    if let data = try? JSONSerialization.data(withJSONObject: details, options: [.prettyPrinted, .sortedKeys]) {
                        try? data.write(to: URL(fileURLWithPath: path + ".json"))
                    }
                    view.takeSnapshot(with: nil) { image, error in
                        guard let image = image, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                              let png = bitmap.representation(using: .png, properties: [:]) else {
                            NSLog("Original snapshot failed: %@", String(describing: error)); exit(1)
                        }
                        do { try png.write(to: URL(fileURLWithPath: path)); print("ORIGINAL SNAPSHOT: \(path)"); fflush(stdout); exit(0) }
                        catch { exit(1) }
                    }
                }
            }
        }
    }

    private func auditPages(path: String, index: Int, results: [[String: Any]]) {
        let keys = ["bag", "atlas", "exchange", "room", "setting"]
        if index >= keys.count {
            Task { @MainActor in
                do {
                    var nativeChecks = try await self.auditNativeIntegration()
                    let business: Any = try await withCheckedThrowingContinuation { continuation in
                        self.views["panel"]!.callAsyncJavaScript("return await window.__ORIGINAL_AUDIT_BUSINESS__()", arguments: [:], in: nil, in: .page) { continuation.resume(with: $0) }
                    }
                    nativeChecks["appearance"] = business
                    let emote: Any = try await withCheckedThrowingContinuation { continuation in
                        self.views["main"]!.callAsyncJavaScript("return await window.__ORIGINAL_AUDIT_EMOTE__()", arguments: [:], in: nil, in: .page) { continuation.resume(with: $0) }
                    }
                    nativeChecks["emoteAnimation"] = emote
                    self.auditMainAndFinish(path: path, results: results, nativeChecks: nativeChecks)
                } catch { self.failAudit(path, "Native integration: \(String(describing: error))") }
            }
            return
        }
        guard let view = views["panel"] else { exit(1) }
        // A fresh validation profile shows the startup About notice. Do not
        // sample animations in the panel while that opaque window occludes it.
        windows["about"]?.orderOut(nil)
        windows["panel"]?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        view.callAsyncJavaScript("return await window.__ORIGINAL_AUDIT_PAGE__(key)", arguments: ["key": keys[index]], in: nil, in: .page) { result in
            switch result {
            case .failure(let error): self.failAudit(path, "Page \(keys[index]): \(String(describing: error))")
            case .success(let value):
                guard let page = value as? [String: Any] else { exit(1) }
                NSLog("Original page rendered: %@, cards=%@", keys[index], String(describing: page["cardCount"]))
                view.takeSnapshot(with: nil) { image, error in
                    guard let image = image, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                          let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
                    do {
                        try png.write(to: URL(fileURLWithPath: path + "." + keys[index] + ".png"))
                        self.auditPages(path: path, index: index+1, results: results + [page])
                    } catch { exit(1) }
                }
            }
        }
    }

    private func auditMainAndFinish(path: String, results: [[String: Any]], nativeChecks: [String: Any]) {
            views["main"]?.callAsyncJavaScript("return await window.__ORIGINAL_AUDIT_MAIN__()", arguments: [:], in: nil, in: .page) { result in
                switch result {
                case .failure(let error): self.failAudit(path, "Main behavior: \(String(describing: error))")
                case .success(let behavior):
                    self.auditLoginChoice(path: path) { choice in
                    let passed = self.runtimeErrors.isEmpty && self.unknownCommands.isEmpty
                    let report: [String: Any] = ["status": passed ? "passed" : "failed", "finishedAt": ISO8601DateFormatter().string(from: Date()), "pages": results, "mainBehavior": behavior, "errors": self.runtimeErrors,
                        "nativeChecks": nativeChecks, "presetChoice": choice, "unknownCommands": self.unknownCommands.sorted(), "snapshot": self.lastSnapshot ?? [:]]
                    do {
                        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                        try data.write(to: URL(fileURLWithPath: path + ".audit.json"))
                        print("ORIGINAL AUDIT: \(results.count) pages + original main behavior, unknown commands=\(self.unknownCommands.sorted())")
                        fflush(stdout); exit(passed ? 0 : 1)
                    } catch { NSLog("Audit report failed %@", error.localizedDescription); exit(1) }
                    }
                }
            }
    }

    private func failAudit(_ path: String, _ detail: String) -> Never {
        NSLog("Original audit failed: %@", detail)
        let report: [String: Any] = ["status": "failed", "finishedAt": ISO8601DateFormatter().string(from: Date()),
                                     "failure": detail, "errors": runtimeErrors, "unknownCommands": unknownCommands.sorted(),
                                     "windows": windows.mapValues { ["visible": $0.isVisible, "key": $0.isKeyWindow,
                                         "unoccluded": $0.occlusionState.contains(.visible)] }]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path + ".audit.json"))
        }
        exit(1)
    }

    @MainActor private func auditNativeIntegration() async throws -> [String: Any] {
        guard let main = views["main"] else { throw CocoaError(.coderInvalidValue) }
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "NativeAudit", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func settle() async throws { try await Task.sleep(nanoseconds: 250_000_000) }
        func script(_ body: String, arguments: [String: Any] = [:]) async throws -> Any {
            try await withCheckedThrowingContinuation { continuation in
                main.callAsyncJavaScript(body, arguments: arguments, in: nil, in: .page) { result in
                    continuation.resume(with: result)
                }
            }
        }
        func settings() async throws -> [String: Any] {
            try await script("return window.__WUWA_ORIGINAL__.loadDesktopCatSettings()", arguments: [:]) as? [String: Any] ?? [:]
        }
        func item(_ action: String) throws -> NSMenuItem {
            guard let item = status?.menu?.items.first(where: { $0.representedObject as? String == action }) else {
                throw CocoaError(.coderInvalidValue)
            }
            return item
        }
        func option(_ event: String, _ value: Int) throws -> NSMenuItem {
            let items = (status?.menu?.items ?? []).flatMap { [$0] + ($0.submenu?.items ?? []) }
            guard let result = items.first(where: {
                let data = $0.representedObject as? [String: Any]
                return data?["event"] as? String == event && data?["value"] as? Int == value
            }) else { throw CocoaError(.coderInvalidValue) }
            return result
        }
        let before = try await settings()
        let visible = nativeMenuState["petDockVisible"] as? Bool ?? true
        let count = try await script("return window.__WUWA_ORIGINAL__.globalStore.localClickCount", arguments: [:])
        let originalShortcuts = try invoke("get_app_shortcuts", [:], "main")
        let storedShortcuts = UserDefaults.standard.object(forKey: "originalShortcuts")
        let originalCapture = shortcutCapture
        var verified: [String] = []
        var keySamples = 0
        do {
            if let primary = NSScreen.screens.first {
                let result = try invoke("plugin:window|primary_monitor", [:], "main") as? [String: Any] ?? [:]
                try require(NSDictionary(dictionary: result).isEqual(to: monitor(primary)), "Primary display follows the focused window")
            }
            if let screen = windows["main"]?.screen {
                let result = try invoke("plugin:window|current_monitor", [:], "main") as? [String: Any] ?? [:]
                try require(NSDictionary(dictionary: result).isEqual(to: monitor(screen)), "Current display differs from the main window display")
            }
            for screen in NSScreen.screens {
                let point = screenPoint(NSPoint(x: screen.frame.midX, y: screen.frame.midY))
                let result = try invoke("plugin:window|monitor_from_point", ["x": Double(point.x), "y": Double(point.y)], "main") as? [String: Any] ?? [:]
                try require(NSDictionary(dictionary: result).isEqual(to: monitor(screen)), "Display point lookup ignored its coordinates")
                let corner = screenPoint(NSPoint(x: screen.frame.minX, y: screen.frame.maxY))
                let atCorner = try invoke("plugin:window|monitor_from_point", ["x": Double(corner.x), "y": Double(corner.y)], "main") as? [String: Any] ?? [:]
                try require(NSDictionary(dictionary: atCorner).isEqual(to: monitor(screen)), "Display top-left edge was excluded")
            }
            let outsideX = (NSScreen.screens.map { $0.frame.maxX }.max() ?? 0) + 1000
            let outside = try invoke("plugin:window|monitor_from_point", ["x": Double(outsideX), "y": 0.0], "main")
            try require(outside is NSNull, "Off-screen point incorrectly resolves to the current display")
            var invalidPointRejected = false
            do { _ = try invoke("plugin:window|monitor_from_point", [:], "main") } catch { invalidPointRejected = true }
            try require(invalidPointRejected, "Missing display coordinates were accepted")
            verified.append("monitor lookup by point, primary and current display")
            if let panel = windows["panel"] {
                let centre = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
                let location = CGPoint(x: centre.x, y: (NSScreen.screens.first?.frame.maxY ?? 0)-centre.y)
                let initial = try await script("return window.__WUWA_ORIGINAL__.globalStore.localClickCount") as! Int
                mouse(button: "left", down: true, location: location)
                emit("cat-panel-action", ["type": "pet-clap"])
                mouse(button: "left", down: false, location: location)
                try await settle()
                let after = try await script("return window.__WUWA_ORIGINAL__.globalStore.localClickCount") as! Int
                try require(after == initial+1, "Panel click counted through both DOM and global input")
                verified.append("panel/global mouse deduplication")
            }
            menuAction(try item("togglePet")); try await settle()
            try require(nativeMenuState["petDockVisible"] as? Bool == !visible, "Tray visibility event did not reach original Vue state")
            try require(try item("togglePet").title == menuLabels[visible ? "showPet" : "hidePet"], "Tray visibility label did not synchronize")
            menuAction(try item("togglePet")); try await settle()
            verified.append("visibility and localized label")
            for (action, field) in [("gameMode", "gameMode"), ("dragLock", "windowPassthrough")] {
                let initial = before[field] as? Bool ?? false
                func toggle() throws {
                    if action == "gameMode" { menuAction(try item("gameMode")) }
                    else {
                        guard let row = status?.menu?.items.first(where: { ($0.representedObject as? [String: Any])?["event"] as? String == "tray-toggle-window-passthrough" }) else { throw CocoaError(.coderInvalidValue) }
                        menuSetting(row)
                    }
                }
                try toggle(); try await settle()
                let changed = try await settings()
                try require(changed[field] as? Bool == !initial && nativeMenuState[field] as? Bool == !initial, "Tray toggle failed: \(field)")
                let row = action == "gameMode" ? try item("gameMode") : status!.menu!.items.first { ($0.representedObject as? [String: Any])?["event"] as? String == "tray-toggle-window-passthrough" }!
                try require(row.state == (initial ? .off : .on), "Tray checkmark failed: \(field)")
                try toggle(); try await settle()
                verified.append(field)
            }
            for (field, event) in [("petScale", "tray-set-pet-scale"), ("windowOpacity", "tray-set-window-opacity")] {
                let initial = (before[field] as? NSNumber)?.intValue ?? 100
                let target = initial == 70 ? 80 : 70
                menuSetting(try option(event, target)); try await settle()
                let changed = try await settings()
                try require((changed[field] as? NSNumber)?.intValue == target, "Tray value did not persist: \(field)")
                try require(try option(event, target).state == .on, "Tray value checkmark failed: \(field)")
                emit(event, initial, target: "main"); try await settle()
                verified.append(field)
            }
            // Compare macOS key-code translation with the actual recovered recorder,
            // including F13–F20 rather than just testing our mapping against itself.
            let samples: [[String: Any]] = [
                ["native": 0, "code": "KeyA", "key": "a"], ["native": 18, "code": "Digit1", "key": "1"],
                ["native": 41, "code": "Semicolon", "key": ";"], ["native": 123, "code": "ArrowLeft", "key": "ArrowLeft"],
                ["native": 117, "code": "Delete", "key": "Delete"],
                ["native": 101, "code": "F9", "key": "F9"], ["native": 105, "code": "F13", "key": "F13"],
                ["native": 107, "code": "F14", "key": "F14"], ["native": 113, "code": "F15", "key": "F15"],
                ["native": 106, "code": "F16", "key": "F16"], ["native": 64, "code": "F17", "key": "F17"],
                ["native": 79, "code": "F18", "key": "F18"], ["native": 80, "code": "F19", "key": "F19"],
                ["native": 90, "code": "F20", "key": "F20"]]
            let recorded = try await script("""
                const m = await import('wuwa://app/assets/index-CuzHFfJW.js');
                return samples.map(s => m.bY(new KeyboardEvent('keydown',{code:s.code,key:s.key,ctrlKey:true})).key);
                """, arguments: ["samples": samples]) as? [Int] ?? []
            try require(recorded == samples.map { virtualKey($0["native"] as! Int) }, "Native shortcuts differ from the original key recorder")
            keySamples = samples.count
            var bindings = originalShortcuts as? [String: Any] ?? [:]
            bindings["togglePet"] = ["key": 65, "modifiers": 3]
            _ = try invoke("set_app_shortcuts", ["config": bindings], "main")
            shortcutCapture = true
            let flags: CGEventFlags = [.maskControl, .maskAlternate]
            key(0, down: true, flags: flags.rawValue); key(0, down: false, flags: flags.rawValue)
            try await settle()
            try require(nativeMenuState["petDockVisible"] as? Bool == visible, "Shortcut activated during capture")
            shortcutCapture = false
            key(0, down: true, flags: flags.rawValue); try await settle()
            try require(nativeMenuState["petDockVisible"] as? Bool == !visible, "Native modifier shortcut did not activate")
            key(0, down: true, flags: flags.rawValue, repeated: true); try await settle()
            try require(nativeMenuState["petDockVisible"] as? Bool == !visible, "Repeated key activated a shortcut twice")
            key(0, down: false, flags: flags.rawValue)
            menuAction(try item("togglePet")); try await settle()
            var duplicate = bindings
            duplicate["gameMode"] = bindings["togglePet"]
            var rejected = false
            do { _ = try invoke("set_app_shortcuts", ["config": duplicate], "main") } catch { rejected = true }
            try require(rejected, "Duplicate shortcuts were accepted")
            verified.append("native key mapping, modifier shortcut, capture, repeat, conflict")
            try require(externalURL("sdk.kurogames.com/pro/agreement/common/language_zh-Hans/terms_of_service")?.scheme == "https", "Official scheme-less legal URL rejected")
            try require(externalURL("mailto:mc_support@kurogames.com")?.scheme == "mailto", "Support email rejected")
            try require(externalURL("file:///tmp/private") == nil && externalURL("javascript:alert(1)") == nil, "Non-web URL accepted")
            verified.append("external URL resolution (no browser launched)")
        } catch {
            _ = try? await script("window.__WUWA_ORIGINAL__.persistDesktopCatSettings(settings);window.__WUWA_ORIGINAL__.globalStore.setLocalClickCount(count)", arguments: ["settings": before, "count": count])
            _ = try? invoke("set_app_shortcuts", ["config": originalShortcuts], "main")
            if let stored = storedShortcuts { UserDefaults.standard.set(stored, forKey: "originalShortcuts") } else { UserDefaults.standard.removeObject(forKey: "originalShortcuts") }
            shortcutCapture = originalCapture
            throw error
        }
        _ = try invoke("set_app_shortcuts", ["config": originalShortcuts], "main")
        if let stored = storedShortcuts { UserDefaults.standard.set(stored, forKey: "originalShortcuts") } else { UserDefaults.standard.removeObject(forKey: "originalShortcuts") }
        shortcutCapture = originalCapture
        _ = try await script("window.__WUWA_ORIGINAL__.globalStore.setLocalClickCount(count)", arguments: ["count": count])
        let restored = try await settings()
        for field in ["petScale", "windowOpacity", "windowPassthrough", "gameMode"] {
            try require(String(describing: restored[field]) == String(describing: before[field]), "Native audit failed to restore \(field)")
        }
        return ["verified": verified, "keySamples": keySamples, "restored": true, "physicalInput": false]
    }

    private func auditLoginChoice(path: String, completion: @escaping ([String: Any]) -> Void) {
        // Only inspect the requested unauthenticated choice screen; never activate either auth button.
        views["panel"]?.callAsyncJavaScript("""
            document.querySelector('.tab-btn__icon--bag').closest('button').click();
            await new Promise(resolve => setTimeout(resolve, 100));
            const slot = document.querySelector('.preset-item--add');
            if (!slot) throw Error('Missing original empty preset slot');
            slot.click();
            """, arguments: [:], in: nil, in: .page) { result in
            if case .failure(let error) = result { NSLog("Preset entry failed %@", error.localizedDescription); exit(1) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                guard let view = self.views["login"] else { NSLog("Preset did not open login choice"); exit(1) }
                view.callAsyncJavaScript("""
                    for (let n=0; n<30 && !document.querySelector('.login-select-content.content-visible'); n++)
                        await new Promise(resolve => setTimeout(resolve, 100));
                    await document.fonts.ready;
                    const card = document.querySelector('.login-dialog-card');
                    if (!card?.innerText.includes('活动需要登录参与')) throw Error('Original login choice missing');
                    const buttons = [...card.querySelectorAll('.login-dialog-button')].map(el => el.textContent.trim());
                    if (buttons.join('|') !== '通行证登录|游戏UID登录') throw Error('Original login choices missing');
                    if (window.__ORIGINAL_DIAGNOSTICS__.errors.length) throw Error(window.__ORIGINAL_DIAGNOSTICS__.errors.join(';'));
                    return {fromPreset:true, buttons, authenticationActivated:false};
                    """, arguments: [:], in: nil, in: .page) { result in
                    guard case .success(let value) = result, let choice = value as? [String: Any] else {
                        NSLog("Login choice audit failed %@", String(describing: result)); exit(1)
                    }
                    view.takeSnapshot(with: nil) { image, error in
                        guard let tiff = image?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                              let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
                        do { try png.write(to: URL(fileURLWithPath: path + ".login-choice.png")) }
                        catch { exit(1) }
                        completion(choice)
                    }
                }
            }
        }
    }

    @objc private func requestInputAccess() { onRequestInputAccess?() }
    func updateInputStatus(_ value: String) {
        if inputStatus != value { inputStatus = value; buildMenu() }
    }
    @objc private func menuSetting(_ item: NSMenuItem) {
        guard let value = item.representedObject as? [String: Any], let event = value["event"] as? String else { return }
        emit(event, value["value"] ?? NSNull(), target: "main")
    }

    private func beginResize(_ window: NSWindow, direction: String) {
        if let existing = resizeMonitor { NSEvent.removeMonitor(existing) }
        let start = NSEvent.mouseLocation, frame = window.frame
        let scale = views["panel"]?.magnification ?? 1
        let collapsed = lastSnapshot?["collapsed"] as? Bool ?? false
        // The original CSS needs 849px of content plus the 243/101px rail and
        // border. Convert those CSS minima through the fitted WebKit scale.
        let minimum = NSSize(width: min((collapsed ? 958 : 1100)*scale, window.screen?.visibleFrame.width ?? 1100),
                             height: min(756*scale, window.screen?.visibleFrame.height ?? 756))
        resizeMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self, weak window] event in
            guard let self = self, let window = window else { return event }
            if event.type == .leftMouseUp {
                if let monitor = self.resizeMonitor { NSEvent.removeMonitor(monitor) }; self.resizeMonitor = nil
                return event
            }
            let point = NSEvent.mouseLocation, dx = point.x-start.x, dy = point.y-start.y
            var next = frame
            if direction.contains("East") { next.size.width = max(minimum.width, frame.width+dx) }
            if direction.contains("West") { next.size.width = max(minimum.width, frame.width-dx); next.origin.x = frame.maxX-next.width }
            if direction.contains("North") { next.size.height = max(minimum.height, frame.height+dy) }
            if direction.contains("South") { next.size.height = max(minimum.height, frame.height-dy); next.origin.y = frame.maxY-next.height }
            window.setFrame(next, display: true)
            return event
        }
    }

    private func logDirectory() throws -> URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let directory = library.appendingPathComponent("Logs/Wuwa Tappo", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func isLogPath(_ path: String, directory: URL) -> Bool {
        let root = directory.resolvingSymlinksInPath().standardizedFileURL.path
        let candidate = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        return candidate == root || candidate.hasPrefix(root + "/")
    }

    private func externalURL(_ value: String) -> URL? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        // The archived official legal links omit their scheme. Preserve their
        // destination while letting NSWorkspace choose the user's default browser.
        let candidate = URL(string: text)?.scheme == nil ? "https://" + text : text
        guard let url = URL(string: candidate), let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme) else { return nil }
        if scheme != "mailto" && (url.host?.contains(".") != true || url.host?.contains(where: { $0.isWhitespace }) == true) { return nil }
        return url
    }

    private func safeInsets(_ screen: NSScreen) -> [String: CGFloat] {
        let frame = screen.frame, work = screen.visibleFrame
        return ["left": max(0, work.minX-frame.minX), "top": max(0, frame.maxY-work.maxY),
                "right": max(0, frame.maxX-work.maxX), "bottom": max(0, work.minY-frame.minY)]
    }

    private func foregroundFullscreen(on screen: NSScreen) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        let target = screen.frame
        let origin = screenPoint(NSPoint(x: target.minX, y: target.maxY))
        return entries.contains { entry in
            guard entry[kCGWindowOwnerPID as String] as? Int32 == app.processIdentifier,
                  entry[kCGWindowLayer as String] as? Int == 0,
                  let dictionary = entry[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else { return false }
            return abs(rect.minX-origin.x) <= 4 && abs(rect.minY-origin.y) <= 4 && rect.width >= target.width-4 && rect.height >= target.height-4
        }
    }

    /// Opt-in local report contains readiness/state counts, never credentials.
    func startOnlineReport(path: String) {
        guard online else { return }
        onlineReportTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                var report: [String: Any] = ["status": "running", "time": ISO8601DateFormatter().string(from: Date()),
                                             "unimplementedCommands": Array(self.unknownCommands).sorted()]
                for label in ["main", "login"] {
                    guard let view = self.views[label] else { continue }
                    do {
                        let result: Any = try await withCheckedThrowingContinuation { continuation in
                            view.callAsyncJavaScript("""
                        const api = await import('wuwa://app/assets/index-CuzHFfJW.js');
                        const store = window.__WUWA_ORIGINAL__?.globalStore;
                        const sdk = typeof KrSDK !== 'undefined' ? KrSDK : null;
                        return {network: api.V.value.status, loggedIn: !!store?.isLoggedIn,
                          hasSession: !!window.__MACOS_SESSION__.get('infoToken'),
                          sdkLoaded: !!sdk, sdkReady: sdk?.core?.getInitStatus?.() === true,
                          loginChoices: [...document.querySelectorAll('.login-dialog-button')].map(el=>el.textContent.trim()),
                          hasUidForm: !!document.querySelector('.uid-cont'),
                          errorCount: window.__ORIGINAL_DIAGNOSTICS__?.errors.length || 0};
                        """, arguments: [:], in: nil, in: .page) { continuation.resume(with: $0) }
                        }
                        report[label] = result
                    } catch { report[label] = ["status": "loading"] }
                }
                if let snapshot = self.lastSnapshot {
                    report["panel"] = ["loggedIn": snapshot["isLoggedIn"] ?? false,
                                        "bagItems": (snapshot["bagList"] as? [Any])?.count ?? 0,
                                        "atlasItems": (snapshot["atlasList"] as? [Any])?.count ?? 0,
                                        "roomMode": snapshot["roomMode"] ?? "idle",
                                        "roomMembers": (snapshot["roomMembers"] as? [Any])?.count ?? 0]
                }
                if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
                }
            }
        }
    }

    func stop() {
        networkMonitor.cancel()
        onlineReportTimer?.invalidate()
        pointerTimer?.invalidate()
        if let resizeMonitor = resizeMonitor { NSEvent.removeMonitor(resizeMonitor) }
        if let mouseDownMonitor = mouseDownMonitor { NSEvent.removeMonitor(mouseDownMonitor) }
        lastMouseDown = nil
        windows.values.forEach { $0.orderOut(nil) }
    }
}
