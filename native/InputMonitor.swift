import AppKit
import CoreGraphics

final class InputMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var modifiers = Set<Int>()
    var onKey: ((Int, Bool) -> Void)?
    var onRawKey: ((Int, Bool, UInt64, Bool) -> Void)?
    var onMouse: ((Bool) -> Void)?
    var onMouseEvent: ((String, Bool, CGPoint) -> Void)?
    var onReset: (() -> Void)?
    var onStatus: ((String) -> Void)?
    private(set) var keyEvents = 0
    private(set) var mouseEvents = 0
    var running: Bool { tap != nil }

    @discardableResult func start() -> Bool {
        if tap != nil { return true }
        guard CGPreflightListenEventAccess() else {
            onStatus?("未授权输入监控")
            return false
        }
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, pointer in
                guard let pointer = pointer else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<InputMonitor>.fromOpaque(pointer).takeUnretainedValue()
                monitor.receive(type, event)
                return Unmanaged.passUnretained(event)
            }, userInfo: pointer) else {
            onStatus?("监听启动失败，请重新授权后重试")
            return false
        }
        tap = port
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        onStatus?("正在监听键鼠")
        return true
    }

    private func receive(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            modifiers.removeAll()
            onReset?()
            if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        switch type {
        case .keyDown, .keyUp:
            keyEvents += 1
            let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
            onKey?(code, type == .keyDown)
            onRawKey?(code, type == .keyDown, event.flags.rawValue, event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        case .flagsChanged:
            let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let down = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(code))
            if down != modifiers.contains(code) {
                if down { modifiers.insert(code) } else { modifiers.remove(code) }
                keyEvents += 1
                onKey?(code, down)
                onRawKey?(code, down, event.flags.rawValue, false)
            }
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            mouseEvents += 1
            onMouse?(true)
            onMouseEvent?(type == .leftMouseDown ? "left" : type == .rightMouseDown ? "right" : "middle", true, event.location)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            mouseEvents += 1
            onMouse?(false)
            onMouseEvent?(type == .leftMouseUp ? "left" : type == .rightMouseUp ? "right" : "middle", false, event.location)
        default: break
        }
    }

    func stop() {
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        tap = nil
        modifiers.removeAll()
        onReset?()
    }
}
