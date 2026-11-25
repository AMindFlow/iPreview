import AppKit
import SwiftUI
import iPreviewCore

struct VideoWorkPhotoPile: View {
    let session: VideoWorkPreviewSession
    let revision: Int
    let width: CGFloat
    let open: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var drag: CGFloat = 0
    @ViewState private var release: CGFloat = 0
    @ViewState private var outgoing: Media?

    private let angles = [0.0, -3.2, 2.6, -4.8, 3.8]
    private let xOffsets: [CGFloat] = [0, -6, 7, -9, 8]
    private let yOffsets: [CGFloat] = [0, 4, 7, 11, 14]

    var body: some View {
        let photos = session.album.photos
        let start = session.photoPosition
        let direction = drag > 0 ? -1 : 1
        let cards = (0..<min(photos.count, angles.count)).map { depth in
            photos[(start + depth * direction + photos.count) % photos.count]
        }
        Button(action: open) {
            ZStack {
                ForEach(Array(cards.enumerated()), id: \.element.id) { depth, photo in
                    printCard(photo, depth: depth)
                        .zIndex(Double(cards.count - depth))
                }
                if let outgoing {
                    VideoWorkPhotoPrint(media: outgoing, revision: revision, width: width)
                        .rotationEffect(.degrees(Double(release / width) * 15))
                        .offset(x: release)
                        .opacity(1 - min(1, abs(release) / (width * 0.9)))
                        .zIndex(Double(cards.count + 1))
                }
            }
            .frame(width: width, height: width * 1.23)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focusEffectDisabled()
        .background {
            if !session.browsing && photos.count > 1 {
                PhotoPileWheel(onMove: move, onEnd: finish)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: session.selectedAlbum) { _, _ in reset() }
        .onChange(of: session.browsing) { _, browsing in
            if browsing { reset() }
        }
        .onKeyPress(.leftArrow) {
            flip(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            flip(1)
            return .handled
        }
        .onKeyPress(.space) {
            open()
            return .handled
        }
        .accessibilityLabel(session.album.title)
        .accessibilityValue("\(start + 1) / \(photos.count)，\(session.currentPhoto.name)")
        .accessibilityHint("左右方向键翻图，按空格进入沉浸浏览")
        .accessibilityIdentifier("video-work-photo-pile")
    }

    private func printCard(_ photo: Media, depth: Int) -> some View {
        let drift = session.browsing || reduceMotion ? 0 : drag
        let approach = depth == 1 ? min(1, abs(drift) / (width * 0.34)) : 0
        let offset = 1 - approach
        let front = depth == 0
        let coverScale: CGFloat = session.browsing ? (front ? 1.50 : 0.71) : 1
        return VideoWorkPhotoPrint(media: photo, revision: revision, width: width)
            .scaleEffect((1 - CGFloat(depth) * 0.022 * offset) * coverScale)
            .rotationEffect(.degrees(angles[depth] * Double(offset) + (front ? Double(drift / width) * 15 : 0)))
            .offset(x: front ? drift : xOffsets[depth] * offset, y: yOffsets[depth] * offset)
            .opacity(session.browsing ? 0 : 1)
            .accessibilityHidden(true)
    }

    private func move(_ distance: CGFloat) {
        guard outgoing == nil else { return }
        drag = min(width * 0.55, max(-width * 0.55, distance))
    }

    private func finish(_ cancelled: Bool) {
        if !cancelled && abs(drag) >= min(72, width * 0.24) {
            flip(drag < 0 ? 1 : -1)
        } else {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { drag = 0 }
        }
    }

    private func flip(_ direction: Int) {
        guard session.album.photos.count > 1, outgoing == nil else { return }
        if reduceMotion {
            drag = 0
            session.stepPhoto(direction)
            return
        }
        let photo = session.currentPhoto
        outgoing = photo
        release = drag
        withAnimation(.easeOut(duration: 0.22), completionCriteria: .logicallyComplete) {
            session.stepPhoto(direction)
            release = -CGFloat(direction) * width * 0.92
            drag = 0
        } completion: {
            if outgoing?.id == photo.id { reset() }
        }
    }

    private func reset() {
        outgoing = nil
        release = 0
        drag = 0
    }
}

private struct PhotoPileWheel: NSViewRepresentable {
    let onMove: (CGFloat) -> Void
    let onEnd: (Bool) -> Void

    func makeNSView(context: Context) -> WheelView { WheelView() }

    func updateNSView(_ view: WheelView, context: Context) {
        view.onMove = onMove
        view.onEnd = onEnd
    }

    static func dismantleNSView(_ view: WheelView, coordinator: ()) { view.stop() }

    final class WheelView: NSView {
        var onMove: ((CGFloat) -> Void)?
        var onEnd: ((Bool) -> Void)?
        private var monitor: Any?
        private var active = false
        private var horizontal: Bool?
        private var distance: CGFloat = 0

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                return scroll(event)
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            resetGesture()
        }

        private func scroll(_ event: NSEvent) -> NSEvent? {
            guard let window, event.window === window, window.isKeyWindow, event.hasPreciseScrollingDeltas,
                  event.momentumPhase.isEmpty, !event.phase.isEmpty else { return event }
            let inside = visibleRect.contains(convert(event.locationInWindow, from: nil))
            if event.phase.contains(.began) {
                if horizontal == true { onEnd?(true) }
                resetGesture()
                active = inside
            }
            guard active else { return event }
            if !inside || event.phase.contains(.cancelled) || event.phase.contains(.ended) {
                let handled = horizontal == true
                resetGesture()
                if handled { onEnd?(!inside || event.phase.contains(.cancelled)) }
                return handled && inside ? nil : event
            }
            let x = event.scrollingDeltaX
            let y = event.scrollingDeltaY
            if horizontal == nil && (x != 0 || y != 0) { horizontal = abs(x) > abs(y) }
            guard horizontal == true else { return event }
            distance += event.isDirectionInvertedFromDevice ? x : -x
            onMove?(distance)
            return nil
        }

        private func resetGesture() {
            active = false
            horizontal = nil
            distance = 0
        }
    }
}
