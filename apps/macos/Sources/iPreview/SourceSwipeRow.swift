import AppKit
import SwiftUI

struct SourceSwipeRow<Label: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isRevealed: Bool
    let enabled: Bool
    let setRevealed: (Bool) -> Void
    let rescan: () -> Void
    let delete: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        label()
            .offset(x: isRevealed ? -68 : 0)
            .overlay(alignment: .trailing) {
                if isRevealed {
                    HStack(spacing: 0) {
                        action("重新扫描", symbol: "arrow.clockwise", color: .accentColor, perform: rescan)
                        action("删除媒体源", symbol: "trash", color: .red, perform: delete)
                    }
                    .clipShape(.rect(cornerRadius: 8))
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isRevealed)
            .background {
                SourceTrackpadSwipe { open in
                    if enabled { setRevealed(open) }
                }
            }
            .contextMenu {
                Button("重新扫描", action: rescan).disabled(!enabled)
                Button("删除媒体源", role: .destructive, action: delete).disabled(!enabled)
            }
            .accessibilityAction(named: Text("重新扫描")) { if enabled { rescan() } }
            .accessibilityAction(named: Text("删除媒体源")) { if enabled { delete() } }
    }

    private func action(_ title: String, symbol: String, color: Color, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(color)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .help(title)
        .disabled(!enabled)
    }
}

private struct SourceTrackpadSwipe: NSViewRepresentable {
    let onSwipe: (Bool) -> Void

    func makeNSView(context: Context) -> SwipeView { SwipeView() }

    func updateNSView(_ view: SwipeView, context: Context) {
        view.onSwipe = onSwipe
    }

    static func dismantleNSView(_ view: SwipeView, coordinator: ()) {
        view.stopTracking()
    }

    final class SwipeView: NSView {
        var onSwipe: ((Bool) -> Void)?
        private var hover: NSTrackingArea?
        private var monitor: Any?
        private var distance: CGFloat = 0
        private var horizontal: Bool?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let hover { removeTrackingArea(hover) }
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                      owner: self, userInfo: nil)
            addTrackingArea(area)
            hover = area
        }

        override func mouseEntered(with event: NSEvent) {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                return scroll(event)
            }
        }

        override func mouseExited(with event: NSEvent) { stopTracking() }

        func stopTracking() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            resetGesture()
        }

        private func scroll(_ event: NSEvent) -> NSEvent? {
            guard event.window === window, event.hasPreciseScrollingDeltas, !event.phase.isEmpty,
                  event.momentumPhase.isEmpty else { return event }
            let point = convert(event.locationInWindow, from: nil)
            guard visibleRect.contains(point) else { return event }
            if event.phase.contains(.began) { resetGesture() }
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                let handled = horizontal == true
                resetGesture()
                return handled ? nil : event
            }
            if horizontal == nil, event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 {
                horizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            }
            guard horizontal == true else { return event }
            let delta = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
            distance += delta
            if abs(distance) >= 32 {
                onSwipe?(distance < 0)
                distance = 0
            }
            return nil
        }

        private func resetGesture() {
            distance = 0
            horizontal = nil
        }
    }
}
