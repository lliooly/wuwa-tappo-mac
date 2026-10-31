import AppKit

// Monochrome adaptation of the release icon; AppKit supplies the menu-bar tint.
enum MenuBarIcon {
    static func configure(_ item: NSStatusItem) {
        item.length = NSStatusItem.squareLength
        guard let button = item.button else { return }
        if let image = image {
            button.title = ""
            button.image = image
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
        } else {
            button.title = "团团"
        }
        button.toolTip = "Wuwa Tappo"
        button.setAccessibilityLabel("Wuwa Tappo")
    }

    private static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "menu-bar-template", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = "Wuwa Tappo"
        return image
    }()
}
