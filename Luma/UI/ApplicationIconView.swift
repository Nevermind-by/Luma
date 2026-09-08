import AppKit
import SwiftUI

struct ApplicationIconView: View {
    let applicationURL: URL
    var size: CGFloat = 50

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.20, style: .continuous))
            .accessibilityLabel("Application icon")
    }

    private var icon: NSImage {
        let image = NSWorkspace.shared.icon(forFile: applicationURL.path)
        guard image.isValid, image.size.width > 0, image.size.height > 0 else {
            return fallbackIcon
        }
        return image
    }

    private var fallbackIcon: NSImage {
        let image = NSImage(size: NSSize(width: 128, height: 128))
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 128, height: 128), xRadius: 24, yRadius: 24).fill()

        let symbol = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
        symbol?.draw(in: NSRect(x: 32, y: 32, width: 64, height: 64), from: .zero, operation: .sourceOver, fraction: 0.55)
        return image
    }
}
