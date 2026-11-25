import AppKit
import SwiftUI

struct VideoWorkEvents: NSViewRepresentable {
    let handleKey: (NSEvent) -> Bool
    var onClick: ((Bool) -> Void)? = nil

    func makeNSView(context: Context) -> EventsView { EventsView() }

    func updateNSView(_ view: EventsView, context: Context) {
        view.handleKey = handleKey
        view.onClick = onClick
    }

    static func dismantleNSView(_ view: EventsView, coordinator: ()) {
        view.stop()
    }

    final class EventsView: NSView {
        var handleKey: ((NSEvent) -> Bool)?
        var onClick: ((Bool) -> Void)?
        private var monitor: Any?
        private var menusTracking = 0

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            NotificationCenter.default.addObserver(self, selector: #selector(menuOpened),
                                                   name: NSMenu.didBeginTrackingNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(menuClosed),
                                                   name: NSMenu.didEndTrackingNotification, object: nil)
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
                guard let self, let window = self.window, event.window === window,
                      self.menusTracking == 0 else { return event }
                if event.type == .leftMouseDown {
                    let location = self.convert(event.locationInWindow, from: nil)
                    if self.bounds.contains(location) {
                        self.onClick?(location.x < self.bounds.midX)
                    }
                    // Select the pane without consuming the native control's click.
                    return event
                }
                return self.handleKey?(event) == true ? nil : event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            NotificationCenter.default.removeObserver(self)
            menusTracking = 0
        }

        @objc private func menuOpened(_ notification: Notification) { menusTracking += 1 }
        @objc private func menuClosed(_ notification: Notification) { menusTracking = max(0, menusTracking - 1) }
    }
}
