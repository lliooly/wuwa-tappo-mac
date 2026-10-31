import Foundation
import JavaScriptCore

final class AnimationEngine {
    let context: JSContext
    private var timers: [Int: DispatchWorkItem] = [:]
    private var sequence = 0
    private(set) var body = 1
    private(set) var head = 1
    var onChange: ((Int, Int) -> Void)?
    private(set) var failure: String?

    init(resourceURL: URL) throws {
        guard let context = JSContext() else { throw CocoaError(.executableNotLoadable) }
        self.context = context
        context.exceptionHandler = { [weak self] _, exception in
            self?.failure = exception?.toString() ?? "JavaScript 异常"
            NSLog("Animation: %@", self?.failure ?? "")
        }
        let render: @convention(block) (Int, Int) -> Void = { [weak self] body, head in
            guard let self = self else { return }
            self.body = body
            self.head = head
            self.onChange?(body, head)
        }
        let schedule: @convention(block) (JSValue, Double) -> Int = { [weak self] callback, delay in
            guard let self = self else { return 0 }
            self.sequence += 1
            let id = self.sequence
            let work = DispatchWorkItem { [weak self] in
                self?.timers.removeValue(forKey: id)
                callback.call(withArguments: [])
            }
            self.timers[id] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay / 1000, execute: work)
            return id
        }
        let cancel: @convention(block) (Int) -> Void = { [weak self] id in
            self?.timers.removeValue(forKey: id)?.cancel()
        }
        context.setObject(render, forKeyedSubscript: "nativeRender" as NSString)
        context.setObject(schedule, forKeyedSubscript: "nativeSetTimer" as NSString)
        context.setObject(cancel, forKeyedSubscript: "nativeClearTimer" as NSString)
        context.evaluateScript("function setTimeout(cb, ms) { return nativeSetTimer(cb, ms); } function clearTimeout(id) { nativeClearTimer(id); }")
        context.evaluateScript(try String(contentsOf: resourceURL.appendingPathComponent("pet-animation.js"), encoding: .utf8))
        context.evaluateScript("var pet = new PetAnimation({onChange: s => nativeRender(s.body, s.head)});")
        if failure != nil { throw CocoaError(.executableNotLoadable) }
    }

    func start() { context.evaluateScript("pet.start()") }
    func reset() { context.evaluateScript("pet.resetInput()") }
    @discardableResult func key(_ code: Int, down: Bool) -> Bool {
        let result = context.evaluateScript("pet.\(down ? "keyDown" : "keyUp")('\(code)')")
        return !down && (result?.toBool() ?? false)
    }
    func mouse(down: Bool) {
        context.evaluateScript("pet.mouseButton('\(down ? "press" : "release")')")
    }
    func dispose() {
        context.evaluateScript("pet.dispose()")
        timers.values.forEach { $0.cancel() }
        timers.removeAll()
    }
}
