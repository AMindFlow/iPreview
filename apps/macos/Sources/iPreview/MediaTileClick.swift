import AppKit
import SwiftUI

struct MediaTileClick: NSViewRepresentable {
    struct Reorder {
        let update: (CGPoint, CGPoint) -> Void
        let finish: (CGPoint?) -> Void
    }

    var adjusting = false
    var reorder: Reorder? = nil
    let onClick: (Int) -> Void

    func makeNSView(context: Context) -> ClickSurface {
        ClickSurface()
    }

    func updateNSView(_ view: ClickSurface, context: Context) {
        if view.adjusting != adjusting || (view.reorder != nil && reorder == nil) {
            view.cancelPress()
        }
        view.adjusting = adjusting
        view.reorder = reorder
        view.onClick = onClick
    }

    final class ClickSurface: NSView {
        private struct Press {
            let anchor: CGPoint
            let timestamp: TimeInterval
            var dragging = false
        }

        private static let holdDuration: TimeInterval = 0.35
        private static let dragDistance: CGFloat = 4

        var adjusting = false
        var reorder: Reorder?
        var onClick: ((Int) -> Void)?
        private var press: Press?

        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            // Leave right-click, Control-click and hover handling with the SwiftUI card.
            guard let event = NSApp.currentEvent, event.type == .leftMouseDown,
                  !event.modifierFlags.contains(.control) else { return nil }
            return super.hitTest(point)
        }

        override func mouseDown(with event: NSEvent) {
            cancelPress()
            press = Press(anchor: event.locationInWindow, timestamp: event.timestamp)
        }

        override func mouseDragged(with event: NSEvent) {
            guard adjusting, var press else { return }
            let point = event.locationInWindow
            if !press.dragging {
                guard moved(point, from: press.anchor) else { return }
                guard reorder != nil else {
                    cancelPress()
                    return
                }
                press.dragging = true
                self.press = press
                NSCursor.closedHand.set()
            }
            reorder?.update(convert(point, from: nil), convert(press.anchor, from: nil))
        }

        override func mouseUp(with event: NSEvent) {
            guard let press else { return }
            let point = convert(event.locationInWindow, from: nil)
            if press.dragging {
                finishPress(at: window?.isKeyWindow == true ? point : nil)
                return
            }
            self.press = nil
            guard bounds.contains(point) else { return }
            if adjusting {
                guard event.timestamp - press.timestamp < Self.holdDuration,
                      !moved(event.locationInWindow, from: press.anchor) else { return }
            }
            onClick?(event.clickCount)
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil { cancelPress() }
            super.viewWillMove(toWindow: newWindow)
        }

        func cancelPress() {
            finishPress(at: nil)
        }

        private func finishPress(at point: CGPoint?) {
            let dragging = press?.dragging == true
            press = nil
            if dragging {
                NSCursor.arrow.set()
                reorder?.finish(point)
            }
        }

        private func moved(_ point: CGPoint, from anchor: CGPoint) -> Bool {
            hypot(point.x - anchor.x, point.y - anchor.y) >= Self.dragDistance
        }
    }
}
