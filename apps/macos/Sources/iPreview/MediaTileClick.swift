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
        private var mouseMonitor: Any?
        private var windowObserver: (any NSObjectProtocol)?

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
            if adjusting, let window { captureAdjustmentPress(in: window) }
        }

        override func mouseDragged(with event: NSEvent) {
            updateDrag(at: event.locationInWindow)
        }

        private func updateDrag(at point: CGPoint) {
            guard adjusting, var press else { return }
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
            guard let initialPress = press else { return }
            // Some input producers deliver the last position together with the release.
            if !initialPress.dragging, adjusting, moved(event.locationInWindow, from: initialPress.anchor) {
                updateDrag(at: event.locationInWindow)
            }
            guard let press = takePress() else { return }
            let point = convert(event.locationInWindow, from: nil)
            if press.dragging {
                finishDrag(at: window?.windowNumber == event.windowNumber ? point : nil)
                return
            }
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
            if takePress()?.dragging == true { finishDrag(at: nil) }
        }

        private func captureAdjustmentPress(in window: NSWindow) {
            // Keep the adjustment press together when a ScrollView also tracks mouse drags.
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self, weak window] event in
                guard let self, let window, self.window === window, self.press != nil else { return event }
                guard event.windowNumber == window.windowNumber else {
                    if event.type == .leftMouseUp { self.cancelPress() }
                    return event
                }
                if event.type == .leftMouseDragged {
                    self.mouseDragged(with: event)
                } else {
                    self.mouseUp(with: event)
                }
                return nil
            }
            windowObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancelPress() }
            }
        }

        private func takePress() -> Press? {
            let previous = press
            press = nil
            if let mouseMonitor {
                self.mouseMonitor = nil
                NSEvent.removeMonitor(mouseMonitor)
            }
            if let windowObserver {
                self.windowObserver = nil
                NotificationCenter.default.removeObserver(windowObserver)
            }
            return previous
        }

        private func finishDrag(at point: CGPoint?) {
            NSCursor.arrow.set()
            reorder?.finish(point)
        }

        private func moved(_ point: CGPoint, from anchor: CGPoint) -> Bool {
            hypot(point.x - anchor.x, point.y - anchor.y) >= Self.dragDistance
        }
    }
}
