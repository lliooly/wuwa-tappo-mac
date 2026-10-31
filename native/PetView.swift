import AppKit

struct PetResources: Decodable {
    let files: [String: String]
    let offsetX: Double
    let offsetY: Double
}

final class PetView: NSView {
    private let images: [String: NSImage]
    private let resources: PetResources
    let decorations: PetDecorations
    var body = 1 { didSet { needsDisplay = true } }
    var head = 1 { didSet { needsDisplay = true } }
    var clickCount = 0 { didSet { needsDisplay = true } }
    var onMenu: ((NSEvent) -> Void)?
    var onChest: ((Int, NSEvent) -> Void)? {
        didSet { decorations.onChest = onChest }
    }
    private let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()
    override var isOpaque: Bool { false }

    init(resourceURL: URL) throws {
        resources = try JSONDecoder().decode(PetResources.self,
            from: Data(contentsOf: resourceURL.appendingPathComponent("appearance.json")))
        var loaded: [String: NSImage] = [:]
        for key in ["body1", "body2", "body3", "head1", "head2", "accessory", "toolbar",
                    "chestBubble", "chestBody", "chestLid", "bubbleBack", "bubbleFront",
                    "emote0", "emote1", "emote2", "emote3", "emote4"] {
            guard let path = resources.files[key],
                  let image = NSImage(contentsOf: resourceURL.appendingPathComponent(path)), image.isValid else {
                throw NSError(domain: "WuwaTappo", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "缺少或无法读取素材：\(key)"])
            }
            loaded[key] = image
        }
        images = loaded
        decorations = PetDecorations(images: loaded)
        super.init(frame: NSRect(origin: .zero, size: PetDecorations.size))
        decorations.invalidate = { [weak self] in self?.needsDisplay = true }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.translateBy(x: PetDecorations.origin.x * PetDecorations.scale,
                                                        y: PetDecorations.origin.y * PetDecorations.scale)
        NSGraphicsContext.current?.cgContext.scaleBy(x: PetDecorations.scale, y: PetDecorations.scale)
        let scale: CGFloat = 1
        drawInfoBar(scale: scale)
        let petRect = NSRect(x: 0, y: 11 * scale, width: 200 * scale, height: 200 * scale)
        images["head\(head)"]?.draw(in: petRect)
        images["body\(body)"]?.draw(in: petRect)
        let accessory = petRect.offsetBy(dx: resources.offsetX * scale, dy: -resources.offsetY * scale)
        images["accessory"]?.draw(in: accessory)
        decorations.draw()
        decorations.drawFloating()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawInfoBar(scale: CGFloat) {
        // Original flex layout: 180px container, 61px fixed toolbar,
        // 136px text item shrinks to 121px, with a -2px right margin.
        let textRect = NSRect(x: 20 * scale, y: 0, width: 121 * scale, height: 32 * scale)
        let toolbarRect = NSRect(x: 139 * scale, y: 0, width: 61 * scale, height: 32 * scale)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
        shadow.shadowOffset = NSSize(width: 0, height: -2 * scale)
        shadow.shadowBlurRadius = 2 * scale
        shadow.set()
        NSGraphicsContext.current?.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
        let background = NSBezierPath(roundedRect: textRect, xRadius: 16 * scale, yRadius: 16 * scale)
        background.appendRect(NSRect(x: textRect.midX, y: 0, width: textRect.width / 2, height: textRect.height))
        NSColor(calibratedRed: 253/255, green: 249/255, blue: 237/255, alpha: 1).setFill()
        background.fill()
        images["toolbar"]?.draw(in: toolbarRect)
        NSGraphicsContext.current?.cgContext.endTransparencyLayer()
        NSGraphicsContext.restoreGraphicsState()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byClipping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18 * scale, weight: .bold),
            .foregroundColor: NSColor(calibratedRed: 142/255, green: 94/255, blue: 67/255, alpha: 1),
            .paragraphStyle: paragraph
        ]
        let text = numberFormatter.string(from: NSNumber(value: clickCount)) ?? "0"
        let height = (text as NSString).size(withAttributes: attributes).height
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: textRect).addClip()
        (text as NSString).draw(in: NSRect(x: textRect.minX + 18 * scale,
            y: (textRect.height - height) / 2, width: textRect.width - 18 * scale, height: height),
            withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        let point = logicalPoint(convert(event.locationInWindow, from: nil))
        let scale: CGFloat = 1
        if decorations.mouseDown(at: point, event: event) { return }
        if NSRect(x: 162 * scale, y: 0, width: 38 * scale, height: 32 * scale).contains(point) {
            onMenu?(event)
        } else if NSRect(x: 139, y: 0, width: 23, height: 32).contains(point) {
            decorations.toggle()
        } else {
            let before = window?.frame.origin
            window?.performDrag(with: event)
            if let before = before, let after = window?.frame.origin,
               hypot(after.x - before.x, after.y - before.y) < 3 { decorations.toggle() }
        }
    }

    override func mouseUp(with event: NSEvent) {
        decorations.mouseUp(at: logicalPoint(convert(event.locationInWindow, from: nil)))
    }

    func logicalPoint(_ point: NSPoint) -> NSPoint {
        NSPoint(x: point.x / PetDecorations.scale - PetDecorations.origin.x,
                y: point.y / PetDecorations.scale - PetDecorations.origin.y)
    }

    func isInteractive(_ point: NSPoint) -> Bool {
        let p = logicalPoint(point)
        return PetDecorations.petRect.contains(p) || NSRect(x: 20, y: 0, width: 180, height: 32).contains(p)
            || decorations.contains(p)
    }
}
