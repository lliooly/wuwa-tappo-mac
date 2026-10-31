import AppKit
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var view: PetView!
    var engine: AnimationEngine!
    var settingsPanel: SettingsPanel?
    var originalFrontend: OriginalFrontend?
    var originalExitApproved = false
    var originalTerminationPending = false
    var originalTerminationTimeout: Timer?
    let input = InputMonitor()
    let controllers = ControllerMonitor()
    var status: NSStatusItem!
    var statusRow: NSMenuItem!
    var poll: Timer?
    var pointerPoll: Timer?
    var mousePassthrough = false
    var observers: [NSObjectProtocol] = []
    var currentStatus = "未授权输入监控"
    let smoke = CommandLine.arguments.contains("--smoke-test")

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            guard let resources = Bundle.main.resourceURL else { throw CocoaError(.fileNoSuchFile) }
            let legacyTest = CommandLine.arguments.contains("--smoke-test") || CommandLine.arguments.contains("--panel-preview") ||
                CommandLine.arguments.contains("--render-preview")
            if CommandLine.arguments.contains("--original-ui") || (!CommandLine.arguments.contains("--legacy-ui") && !legacyTest) {
                originalFrontend = OriginalFrontend(resources: resources)
                originalFrontend?.onExit = { [weak self] in
                    guard let self = self else { return }
                    self.originalExitApproved = true
                    self.writeQuitReport(["status": "complete", "systemRequestedExit": self.originalTerminationPending,
                                          "savedCount": UserDefaults.standard.integer(forKey: "localClickCount")])
                    self.originalTerminationTimeout?.invalidate()
                    if self.originalTerminationPending {
                        self.originalTerminationPending = false
                        NSApp.reply(toApplicationShouldTerminate: true)
                    } else { NSApp.terminate(nil) }
                }
                originalFrontend?.onRequestInputAccess = { [weak self] in self?.requestPermission() }
                originalFrontend?.start()
                if let index = CommandLine.arguments.firstIndex(of: "--online-report"), CommandLine.arguments.indices.contains(index+1) {
                    originalFrontend?.startOnlineReport(path: CommandLine.arguments[index+1])
                }
                if CommandLine.arguments.contains("--show-login") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                        self?.originalFrontend?.create(label: "login", route: "/login").makeKeyAndOrderFront(nil)
                    }
                }
                input.onRawKey = { [weak self] code, down, flags, repeated in self?.originalFrontend?.key(code, down: down, flags: flags, repeated: repeated) }
                input.onMouseEvent = { [weak self] button, down, location in self?.originalFrontend?.mouse(button: button, down: down, location: location) }
                input.onReset = { [weak self] in self?.originalFrontend?.resetInput() }
                input.onStatus = { [weak self] value in self?.originalFrontend?.updateInputStatus(value) }
                controllers.onPress = { [weak self] in self?.originalFrontend?.emit("gamepad-button-press", target: "main") }
                if let index = CommandLine.arguments.firstIndex(of: "--original-preview"), CommandLine.arguments.indices.contains(index+1) {
                    originalFrontend?.testSnapshot(path: CommandLine.arguments[index+1])
                } else {
                    input.start(); controllers.start()
                    if CommandLine.arguments.contains("--check-input") { checkOriginalInput() }
                    if CommandLine.arguments.contains("--show-settings") { originalFrontend?.openPanelFromMain() }
                    poll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                        guard let self = self else { return }
                        if CGPreflightListenEventAccess() { self.input.start() }
                        else {
                            if self.input.running { self.input.stop() }
                            self.originalFrontend?.updateInputStatus("未授权输入监控，点击授权…")
                        }
                    }
                    let center = NSWorkspace.shared.notificationCenter
                    observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) {
                        [weak self] _ in self?.input.stop()
                    })
                    observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
                        [weak self] _ in self?.originalFrontend?.resetInput(); self?.input.start()
                    })
                }
                return
            }
            view = try PetView(resourceURL: resources)
            view.clickCount = max(0, UserDefaults.standard.integer(forKey: "localClickCount"))
            engine = try AnimationEngine(resourceURL: resources)
            engine.onChange = { [weak self] body, head in self?.view.body = body; self?.view.head = head }
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 800)
            window = NSWindow(contentRect: NSRect(origin: NSPoint(x: screen.maxX - PetDecorations.size.width - 30,
                y: screen.minY + 30), size: PetDecorations.size),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.title = "Wuwa Tappo"
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            window.contentView = view
            window.orderFrontRegardless()
            buildMenu()
            view.onMenu = { [weak self] _ in self?.showSettings() }
            view.onChest = { [weak self] _, event in
                guard let self = self else { return }
                let menu = NSMenu()
                menu.addItem(NSMenuItem(title: "宝箱需要官方账号，当前尚未接入领取", action: nil, keyEquivalent: ""))
                NSMenu.popUpContextMenu(menu, with: event, for: self.view)
            }
            input.onKey = { [weak self] code, down in
                guard let self = self else { return }
                if self.engine.key(code, down: down) { self.incrementCount() }
            }
            input.onMouse = { [weak self] down in
                guard let self = self else { return }
                self.engine.mouse(down: down)
                if down { self.incrementCount() }
            }
            input.onReset = { [weak self] in self?.engine.reset() }
            input.onStatus = { [weak self] text in self?.setStatus(text) }
            engine.start()
            if let index = CommandLine.arguments.firstIndex(of: "--panel-preview"),
               CommandLine.arguments.indices.contains(index + 1) {
                settingsPanel = SettingsPanel(resources: resources)
                settingsPanel?.onTestComplete = { [weak self] success, detail in
                    print("PANEL \(success ? "PASS" : "FAIL"): \(detail)")
                    fflush(stdout)
                    self?.engine.dispose()
                    exit(success ? 0 : 1)
                }
                settingsPanel?.show(previewPath: CommandLine.arguments[index + 1])
                DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
                    fputs("PANEL FAIL: load timeout\n", stderr); exit(1)
                }
                return
            }
            if let index = CommandLine.arguments.firstIndex(of: "--render-preview"),
               CommandLine.arguments.indices.contains(index + 1) {
                view.decorations.setOpen(true, animated: false)
                view.displayIfNeeded()
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                do {
                    guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
                    try data.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
                    engine.dispose()
                    exit(0)
                } catch { fputs("Render failed: \(error)\n", stderr); exit(1) }
            }
            if smoke { runSmokeTest(); return }
            if CommandLine.arguments.contains("--show-settings") { showSettings() }
            pointerPoll = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                let point = self.window.convertPoint(fromScreen: NSEvent.mouseLocation)
                self.window.ignoresMouseEvents = self.mousePassthrough || !self.view.isInteractive(point)
            }
            input.start()
            if CommandLine.arguments.contains("--check-input") {
                print("INPUT MONITOR: \(currentStatus)")
                fflush(stdout)
                if !input.running { engine.dispose(); exit(2) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                    guard let self = self else { return }
                    print("INPUT SAMPLE: keyboard events=\(self.input.keyEvents), mouse events=\(self.input.mouseEvents)")
                    fflush(stdout)
                    self.input.stop()
                    self.engine.dispose()
                    exit(0)
                }
            }
            poll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                if !CGPreflightListenEventAccess() {
                    if self.input.running { self.input.stop() }
                    self.setStatus("未授权输入监控")
                } else {
                    self.input.start()
                    if self.input.running {
                        self.setStatus("正在监听 · 键盘 \(self.input.keyEvents) · 鼠标 \(self.input.mouseEvents)")
                    }
                }
            }
            let center = NSWorkspace.shared.notificationCenter
            observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) {
                [weak self] _ in self?.input.stop()
            })
            observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
                [weak self] _ in self?.engine.reset(); self?.input.start()
            })
        } catch {
            if smoke { fputs("SMOKE FAIL: \(error)\n", stderr); exit(1) }
            let alert = NSAlert()
            alert.messageText = "玩偶启动失败"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func buildMenu() {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = "团团"
        let menu = NSMenu()
        statusRow = NSMenuItem(title: currentStatus, action: nil, keyEquivalent: "")
        menu.addItem(statusRow)
        for (title, action) in [("授权输入监控…", #selector(requestPermission)),
                                ("背包与设置…", #selector(showSettings)),
                                ("重试监听", #selector(retry)), ("显示玩偶", #selector(showPet)),
                                ("展开／收起表情", #selector(toggleEmotes)),
                                ("鼠标穿透", #selector(togglePassthrough)), ("退出", #selector(quit))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        status.menu = menu
    }

    func checkOriginalInput() {
        writeInputReport(["status": "starting"])
        guard input.running else {
            writeInputReport(["status": "permission unavailable"])
            print("ORIGINAL INPUT: permission unavailable"); fflush(stdout); exit(2)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self, let webView = self.originalFrontend?.views["main"] else { exit(1) }
            webView.callAsyncJavaScript("return window.__WUWA_ORIGINAL__.globalStore.localClickCount", arguments: [:], in: nil, in: .page) { result in
                guard case .success(let value) = result, let before = value as? Int else { exit(1) }
                let keys = self.input.keyEvents, mouse = self.input.mouseEvents
                self.writeInputReport(["status": "sampling", "clickCountBefore": before])
                print("ORIGINAL INPUT READY: sampling system events for 60 seconds"); fflush(stdout)
                DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                    webView.callAsyncJavaScript("return window.__WUWA_ORIGINAL__.globalStore.localClickCount", arguments: [:], in: nil, in: .page) { result in
                        guard case .success(let value) = result, let after = value as? Int else { exit(1) }
                        let report: [String: Any] = ["keyboardEvents": self.input.keyEvents-keys, "mouseEvents": self.input.mouseEvents-mouse,
                                      "clickCountBefore": before, "clickCountAfter": after, "clickCountDelta": after-before]
                        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) {
                            print("ORIGINAL INPUT SAMPLE: \(text)"); fflush(stdout)
                        }
                        self.writeInputReport(report.merging(["status": "complete"]) { _, new in new })
                        self.input.stop(); self.controllers.stop(); self.originalFrontend?.stop(); exit(0)
                    }
                }
            }
        }
    }

    func writeInputReport(_ report: [String: Any]) {
        guard let index = CommandLine.arguments.firstIndex(of: "--input-report"), CommandLine.arguments.indices.contains(index+1),
              let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) else { return }
        try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[index+1]), options: .atomic)
    }

    func writeQuitReport(_ report: [String: Any]) {
        guard let index = CommandLine.arguments.firstIndex(of: "--quit-report"), CommandLine.arguments.indices.contains(index+1),
              let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) else { return }
        try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[index+1]), options: .atomic)
    }

    func setStatus(_ text: String) { currentStatus = text; statusRow?.title = text }
    func incrementCount() {
        guard view.clickCount < Int.max else { return }
        view.clickCount += 1
        UserDefaults.standard.set(view.clickCount, forKey: "localClickCount")
    }
    @objc func requestPermission() {
        if CGRequestListenEventAccess() { input.start() }
        else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
    @objc func retry() { input.stop(); input.start() }
    @objc func showPet() { window.orderFrontRegardless() }
    @objc func showSettings() {
        if settingsPanel == nil, let resources = Bundle.main.resourceURL { settingsPanel = SettingsPanel(resources: resources) }
        settingsPanel?.show()
    }
    @objc func toggleEmotes() { view.decorations.toggle() }
    @objc func togglePassthrough(_ sender: NSMenuItem) {
        mousePassthrough.toggle()
        window.ignoresMouseEvents = mousePassthrough
        sender.state = mousePassthrough ? .on : .off
    }
    @objc func quit() { NSApp.terminate(nil) }

    func runSmokeTest() {
        // Calls the exact same adapter entry points without generating system input.
        engine.key(0, down: true)
        guard engine.body == 2 else { finishSmoke(false, "key down") ; return }
        engine.key(0, down: true)
        guard engine.body == 2 else { finishSmoke(false, "repeat") ; return }
        guard engine.key(0, down: false) else { finishSmoke(false, "effective key release count"); return }
        guard !engine.key(0, down: false) else { finishSmoke(false, "duplicate key release count"); return }
        guard engine.body == 1 else { finishSmoke(false, "key up") ; return }
        engine.mouse(down: true)
        guard engine.body == 3 else { finishSmoke(false, "mouse alternation") ; return }
        engine.mouse(down: false)
        view.decorations.setOpen(true, animated: false)
        let bubble = PetDecorations.bubbleRects[0]
        guard view.decorations.bubble(at: NSPoint(x: bubble.midX, y: bubble.midY)) == 0 else {
            finishSmoke(false, "emote hit region"); return
        }
        view.decorations.selectEmote(2)
        guard view.decorations.activeFloatingCount == 1 else { finishSmoke(false, "emote trigger"); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.10) { [weak self] in
            guard let self = self else { return }
            guard self.engine.head == 2 else { self.finishSmoke(false, "blink close"); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self.finishSmoke(self.engine.head == 1 && self.engine.failure == nil && self.view.decorations.activeFloatingCount == 0,
                                 "native window + assets + JS bridge + timers + emote lifecycle + hit regions; head=\(self.engine.head), floats=\(self.view.decorations.activeFloatingCount), JS error=\(self.engine.failure ?? "none")")
            }
        }
    }

    func finishSmoke(_ success: Bool, _ detail: String) {
        print("SMOKE \(success ? "PASS" : "FAIL"): \(detail)")
        fflush(stdout)
        engine.dispose()
        exit(success ? 0 : 1)
    }

    func applicationWillTerminate(_ notification: Notification) {
        originalTerminationTimeout?.invalidate()
        poll?.invalidate()
        pointerPoll?.invalidate()
        view?.decorations.dispose()
        input.stop()
        controllers.stop()
        engine?.dispose()
        originalFrontend?.stop()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let frontend = originalFrontend, !originalExitApproved else { return .terminateNow }
        if !originalTerminationPending {
            originalTerminationPending = true
            writeQuitReport(["status": "waiting-for-original-flush"])
            frontend.requestQuit { [weak self] error in self?.cancelOriginalTermination(error.localizedDescription) }
            originalTerminationTimeout = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
                self?.cancelOriginalTermination("等待原版保存流程超时，请重试退出。")
            }
        }
        return .terminateLater
    }

    func cancelOriginalTermination(_ reason: String) {
        guard originalTerminationPending else { return }
        originalTerminationPending = false
        writeQuitReport(["status": "cancelled", "reason": reason])
        originalTerminationTimeout?.invalidate()
        NSApp.reply(toApplicationShouldTerminate: false)
        NSLog("Original exit postponed: %@", reason)
        let alert = NSAlert()
        alert.messageText = "退出前保存尚未完成"
        alert.informativeText = reason
        alert.runModal()
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = AppDelegate()
application.delegate = delegate
// The build/run entrypoint uses SIGTERM. Route it through the same flush gate
// as Command-Q rather than terminating while a click-count write is pending.
signal(SIGTERM, SIG_IGN)
let terminationSignal = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
terminationSignal.setEventHandler { application.terminate(nil) }
terminationSignal.resume()
application.run()
