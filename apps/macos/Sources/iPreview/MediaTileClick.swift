import AppKit
import SwiftUI

struct MediaTileClick: NSViewRepresentable {
    let onClick: (Int) -> Void

    func makeNSView(context: Context) -> ClickSurface {
        ClickSurface()
    }

    func updateNSView(_ view: ClickSurface, context: Context) {
        view.onClick = onClick
    }

    final class ClickSurface: NSView {
        var onClick: ((Int) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            // Leave right-click, Control-click and hover handling with the SwiftUI card.
            guard let event = NSApp.currentEvent, event.type == .leftMouseDown,
                  !event.modifierFlags.contains(.control) else { return nil }
            return super.hitTest(point)
        }

        override func mouseDown(with event: NSEvent) {
            // Keep this surface as the target through mouse-up, when we commit the click.
        }

        override func mouseUp(with event: NSEvent) {
            guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
            onClick?(event.clickCount)
        }
    }
}
