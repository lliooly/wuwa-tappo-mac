import AppKit

// All rectangles use the original 200px pet coordinate space, y upwards.
final class PetDecorations {
    static let scale: CGFloat = 1.2
    static let origin = NSPoint(x: 32, y: 8)
    static let size = NSSize(width: 286 * scale, height: 327 * scale)
    static let petRect = NSRect(x: 0, y: 11, width: 200, height: 200)
    static let chestRects = [NSRect(x: 174, y: 35, width: 62, height: 44),
                             NSRect(x: 184, y: 83, width: 62, height: 44)]
    static let bubbleRects = zip([-8.0, -19, -16, 2, 30], [143.0, 108, 72, 40, 16]).map {
        NSRect(x: $0.0, y: 211 - $0.1 - 32, width: 32, height: 32)
    }
    private let images: [String: NSImage]
    var invalidate: (() -> Void)?
    var onChest: ((Int, NSEvent) -> Void)?
    private(set) var open = false
    private var openAmount: Double = 0
    private var fanStart = ProcessInfo.processInfo.systemUptime
    private var fanFrom: Double = 0
    private var ticker: Timer?
    private var pressed: Int?
    private var pressedAt: Double = 0
    private var chestPress: (index: Int, start: Double)?
    private var floats: [(index: Int, start: Double, x: Double, y: Double)] = []
    private var sequence = 0
    private struct Spring {
        var x = 1.0, y = 1.0, vx = 0.0, vy = 0.0
        var targetX = 1.0, targetY = 1.0
        var releaseAt: Double?, returnAt: Double?
        var moving: Bool { abs(x-targetX) + abs(y-targetY) + abs(vx) + abs(vy) > 0.005 || releaseAt != nil || returnAt != nil }
        mutating func step(_ dt: Double, now: Double) {
            if let time = releaseAt, now >= time {
                targetX = 1.48; targetY = 1.2; vx += 2.4; vy += 3.3
                releaseAt = nil; returnAt = now + 0.115
            }
            if let time = returnAt, now >= time { targetX = 1; targetY = 1; returnAt = nil }
            vx += ((targetX-x) * 245 - vx * 13.2) * dt
            vy += ((targetY-y) * 285 - vy * 14) * dt
            x += vx * dt; y += vy * dt
        }
    }
    private var springs = Array(repeating: Spring(), count: 5)
    private var lastTick = ProcessInfo.processInfo.systemUptime
    var activeFloatingCount: Int { floats.count }

    init(images: [String: NSImage]) { self.images = images }
    deinit { ticker?.invalidate() }
    private var now: Double { ProcessInfo.processInfo.systemUptime }

    func setOpen(_ value: Bool, animated: Bool = true) {
        fanFrom = openAmount
        fanStart = now
        open = value
        if !animated {
            openAmount = value ? 1 : 0
            fanFrom = openAmount
            fanStart = now - 0.72
        }
        else { animate() }
        invalidate?()
    }

    func toggle() { setOpen(!open) }

    private func animate() {
        guard ticker == nil else { return }
        lastTick = now
        ticker = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(ticker!, forMode: .common)
    }

    private func tick() {
        let time = now
        let dt = min(0.028, time - lastTick)
        lastTick = time
        for index in springs.indices { springs[index].step(dt, now: time) }
        let elapsed = now - fanStart
        let t = min(1, elapsed / 0.72)
        openAmount = fanFrom + ((open ? 1 : 0) - fanFrom) * t
        floats.removeAll { now - $0.start >= 1 }
        if let chest = chestPress, now - chest.start >= 0.48 { chestPress = nil }
        invalidate?()
        if t >= 1 && floats.isEmpty && chestPress == nil && pressed == nil && !springs.contains(where: { $0.moving }) {
            ticker?.invalidate(); ticker = nil
        }
    }

    private func fanFraction(_ index: Int) -> CGFloat {
        let progress = open ? openAmount : 1 - openAmount
        let stagger = Double(open ? index : 4 - index) * 0.045
        let t = max(0, min(1, (progress * 0.72 - stagger) / 0.52))
        // Cubic-bezier(.34,1.45,.48,1), solved for x; original fan timing.
        var lo = 0.0, hi = 1.0
        for _ in 0..<16 {
            let u = (lo + hi) / 2
            let x = 3 * (1-u) * (1-u) * u * 0.34 + 3 * (1-u) * u * u * 0.48 + u*u*u
            if x < t { lo = u } else { hi = u }
        }
        let u = (lo + hi) / 2
        let y = 3 * (1-u) * (1-u) * u * 1.45 + 3 * (1-u) * u * u + u*u*u
        return CGFloat(open ? y : 1-y)
    }

    func draw() {
        for (index, rect) in Self.chestRects.enumerated() {
            NSGraphicsContext.saveGraphicsState()
            if let press = chestPress, press.index == index {
                let t = min(1, (now - press.start) / 0.48)
                let amount = sin(t * .pi * 2) * (1-t)
                let c = NSAffineTransform()
                c.translateX(by: rect.midX, yBy: rect.midY)
                c.scaleX(by: 1 + amount * 0.14, yBy: 1 - amount * 0.16)
                c.translateX(by: -rect.midX, yBy: -rect.midY)
                c.concat()
            }
            images["chestBubble"]?.draw(in: rect)
            // CSS top:11,left:14,width:28,height:21. Bottom-left conversion.
            let icon = NSRect(x: rect.minX + 14, y: rect.maxY - 11 - 21, width: 28, height: 21)
            images["chestBody"]?.draw(in: icon)
            images["chestLid"]?.draw(in: icon)
            NSGraphicsContext.restoreGraphicsState()
        }
        if openAmount > 0 {
            for (index, target) in Self.bubbleRects.enumerated() {
                let f = fanFraction(index)
                guard f > 0 else { continue }
                let rect = NSRect(x: 6 + (target.minX - 6) * f, y: 14 + (target.minY - 14) * f,
                                  width: 32, height: 32)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.cgContext.setAlpha(min(1, f))
                let transform = NSAffineTransform()
                transform.translateX(by: rect.midX, yBy: rect.midY)
                let grow = 0.15 + 0.85 * f
                let spring = springs[index]
                transform.scaleX(by: grow * max(0.72, min(1.72, spring.x)), yBy: grow * max(0.62, min(1.55, spring.y)))
                transform.translateX(by: -rect.midX, yBy: -rect.midY)
                transform.concat()
                NSColor(calibratedRed: 253/255, green: 249/255, blue: 237/255, alpha: 0.5).setFill()
                NSBezierPath(ovalIn: rect).fill()
                images["bubbleBack"]?.draw(in: rect)
                images["emote\(index)"]?.draw(in: rect.insetBy(dx: 1, dy: 1))
                images["bubbleFront"]?.draw(in: rect)
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }

    func drawFloating() {
        for item in floats {
            let t = min(1, now - item.start)
            let eased = 1 - pow(1-t, 1.7)
            let size = 80 * (1 + eased * 0.08)
            let rect = NSRect(x: 100 + item.x - size/2,
                y: 111 - item.y - size * 0.7 + eased * 102, width: size, height: size)
            images["emote\(item.index)"]?.draw(in: rect, from: .zero, operation: .sourceOver,
                fraction: CGFloat(t < 0.7 ? 1 : (1-t) / 0.3))
        }
    }

    func bubble(at point: NSPoint) -> Int? {
        guard open, openAmount > 0.9 else { return nil }
        return Self.bubbleRects.firstIndex { rect in
            let dx = (point.x - rect.midX) / 16, dy = (point.y - rect.midY) / 16
            return dx*dx + dy*dy <= 1
        }
    }

    func contains(_ point: NSPoint) -> Bool {
        bubble(at: point) != nil || Self.chestRects.contains { $0.contains(point) }
    }

    func mouseDown(at point: NSPoint, event: NSEvent) -> Bool {
        if let index = bubble(at: point) {
            springs[index].releaseAt = nil; springs[index].returnAt = nil
            springs[index].targetX = 0.86; springs[index].targetY = 0.72; springs[index].vy -= 0.8
            pressed = index; pressedAt = now; animate(); invalidate?(); return true
        }
        if let index = Self.chestRects.firstIndex(where: { $0.contains(point) }) {
            chestPress = (index, now); animate(); onChest?(index, event); return true
        }
        return false
    }

    func mouseUp(at point: NSPoint) {
        guard let index = pressed else { return }
        pressed = nil
        springs[index].releaseAt = max(now, pressedAt + 0.08)
        if bubble(at: point) == index { selectEmote(index) }
        invalidate?()
    }

    func selectEmote(_ index: Int) {
        guard (0..<5).contains(index) else { return }
        let offsets = [(-30.0, 10.0), (4, -6), (28, 12), (-14, 2), (36, 6), (-38, 16), (16, -10), (-6, 8)]
        let offset = offsets[sequence % offsets.count]; sequence += 1
        floats.append((index, now, (offset.0 + Double.random(in: -5...5)).rounded(),
                       (offset.1 + Double.random(in: -4...4) - 50).rounded()))
        animate(); invalidate?()
    }

    func dispose() { ticker?.invalidate(); ticker = nil; pressed = nil; floats.removeAll() }
}
