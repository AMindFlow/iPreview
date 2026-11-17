import AppKit
import SwiftUI
import iPreviewCore

private let albumOrderSpace = "album-order"

@MainActor @Observable
final class AlbumOrderDrag {
    struct Drag {
        let album: VirtualAlbum
        let item: Media
        let indices: [Int64: Int]
        let sourceIndex: Int
    }

    private(set) var drag: Drag?
    private(set) var destination: Int?
    private(set) var pointer: CGPoint?
    @ObservationIgnored private var frames: [Int64: CGRect] = [:]
    @ObservationIgnored private var viewport: CGRect = .null
    @ObservationIgnored private var cancelledID: Int64?

    func record(_ frame: CGRect?, for item: Media) {
        frames[item.id] = frame
    }

    func recordViewport(_ frame: CGRect) {
        if viewport.size != frame.size { cancel() }
        viewport = frame
    }

    func pointInBrowser(_ point: CGPoint, from item: Media, mode: MediaBrowseMode) -> CGPoint? {
        guard let frame = frames[item.id] else { return nil }
        let x = frame.maxX - AlbumOrderHandle.trailingInset(mode) - AlbumOrderHandle.size.width
        let y = mode == .list
            ? frame.midY - AlbumOrderHandle.size.height / 2
            : frame.maxY - AlbumOrderHandle.bottomInset(mode) - AlbumOrderHandle.size.height
        return CGPoint(x: x + point.x, y: y + point.y)
    }

    func update(_ point: CGPoint, item: Media, album: VirtualAlbum) {
        guard cancelledID != item.id else { return }
        if drag == nil, let index = album.mediaIDs.firstIndex(of: item.id) {
            let indices = Dictionary(uniqueKeysWithValues: album.mediaIDs.enumerated().map { ($1, $0) })
            drag = Drag(album: album, item: item, indices: indices, sourceIndex: index)
        }
        guard let drag, drag.item.id == item.id else { return }
        guard viewport.contains(point) else {
            pointer = nil
            destination = nil
            return
        }
        pointer = point
        destination = frames
            .compactMap { id, frame -> (index: Int, score: CGFloat)? in
                guard let index = drag.indices[id], frame.intersects(viewport) else { return nil }
                let x = (point.x - frame.midX) / max(1, frame.width / 2)
                let y = (point.y - frame.midY) / max(1, frame.height / 2)
                return (index, x * x + y * y)
            }
            .min { $0.score == $1.score ? $0.index < $1.index : $0.score < $1.score }?.index
    }

    func displacement(for id: Int64) -> CGSize {
        guard let drag, let destination, let index = drag.indices[id] else { return .zero }
        let movedIndex: Int
        if index == drag.sourceIndex {
            movedIndex = destination
        } else if drag.sourceIndex < index, index <= destination {
            movedIndex = index - 1
        } else if destination <= index, index < drag.sourceIndex {
            movedIndex = index + 1
        } else {
            return .zero
        }
        guard let source = frames[id], let target = frames[drag.album.mediaIDs[movedIndex]] else { return .zero }
        return CGSize(width: target.minX - source.minX, height: target.minY - source.minY)
    }

    @discardableResult
    func cancel() -> Bool {
        guard let drag else { return false }
        clear()
        cancelledID = drag.item.id
        return true
    }

    func endGesture(for id: Int64) {
        if cancelledID == id { cancelledID = nil }
        if drag?.item.id == id { clear() }
    }

    private func clear() {
        drag = nil
        destination = nil
        pointer = nil
    }
}

extension View {
    func albumOrderOverlay(_ order: AlbumOrderDrag, revision: Int) -> some View {
        overlay(alignment: .topLeading) {
            if let drag = order.drag, let point = order.pointer, let destination = order.destination {
                VStack(alignment: .leading, spacing: 5) {
                    MediaThumbnail(media: drag.item, revision: revision)
                        .frame(height: 65)
                        .clipShape(.rect(cornerRadius: 7))
                    Text(drag.item.name).font(.caption).lineLimit(1)
                    Text("位置 \(destination + 1)").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(width: 115, alignment: .leading)
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.12)))
                .shadow(color: .black.opacity(0.24), radius: 9, y: 4)
                .offset(x: point.x + 13, y: point.y + 10)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .coordinateSpace(name: albumOrderSpace)
    }

    func albumOrderViewport(_ order: AlbumOrderDrag, album: VirtualAlbum?) -> some View {
        onGeometryChange(for: CGRect.self) { geometry in
            album == nil ? .null : geometry.frame(in: .named(albumOrderSpace))
        } action: { frame in
            if album != nil { order.recordViewport(frame) }
        }
    }
}

struct AlbumOrderItem<Content: View>: View {
    let order: AlbumOrderDrag
    let album: VirtualAlbum
    let item: Media
    let mode: MediaBrowseMode
    let enabled: Bool
    let content: Content
    let start: () -> Void
    let commit: (VirtualAlbum, Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let placeholder = order.drag?.item.id == item.id && order.destination != nil
        let alignment: Alignment = mode == .list ? .trailing : .bottomTrailing

        ZStack {
            content
                .opacity(placeholder ? 0.22 : 1)
                .overlay {
                    if placeholder {
                        RoundedRectangle(cornerRadius: mode == .list ? 6 : 12)
                            .fill(Color.accentColor.opacity(0.10))
                            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .allowsHitTesting(false)
                    }
                }
                .offset(order.displacement(for: item.id))
        }
        .overlay(alignment: alignment) {
            if enabled {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: AlbumOrderHandle.size.width, height: AlbumOrderHandle.size.height)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.15)))
                    .overlay {
                        AlbumOrderHandle(update: updateDrag, finish: finishDrag)
                    }
                    .accessibilityHidden(true)
                    .help("拖动排序")
                    .padding(.trailing, AlbumOrderHandle.trailingInset(mode))
                    .padding(.bottom, AlbumOrderHandle.bottomInset(mode))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: order.destination)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(albumOrderSpace)) } action: {
            order.record($0, for: item)
        }
        .onDisappear {
            order.record(nil, for: item)
            order.endGesture(for: item.id)
        }
    }

    private func updateDrag(_ location: CGPoint) {
        guard let point = order.pointInBrowser(location, from: item, mode: mode) else { return }
        let wasActive = order.drag != nil
        order.update(point, item: item, album: album)
        if !wasActive, order.drag != nil { start() }
    }

    private func finishDrag(_ location: CGPoint?) {
        defer { order.endGesture(for: item.id) }
        guard order.drag?.item.id == item.id, let location else { return }
        updateDrag(location)
        if let drag = order.drag, let target = order.destination, drag.sourceIndex != target {
            commit(drag.album, target)
        }
    }
}

private struct AlbumOrderHandle: NSViewRepresentable {
    static let size = CGSize(width: 23, height: 22)
    static func trailingInset(_ mode: MediaBrowseMode) -> CGFloat { mode == .list ? 2 : 5 }
    static func bottomInset(_ mode: MediaBrowseMode) -> CGFloat { mode == .list ? 0 : 18 }

    let update: (CGPoint) -> Void
    let finish: (CGPoint?) -> Void

    func makeNSView(context: Context) -> Surface { Surface() }

    func updateNSView(_ view: Surface, context: Context) {
        view.updateDrag = update
        view.finishDrag = finish
    }

    // Claim mouse-down just on the grip so the surrounding scroll view cannot take the drag.
    final class Surface: NSView {
        var updateDrag: ((CGPoint) -> Void)?
        var finishDrag: ((CGPoint?) -> Void)?
        private var anchor: CGPoint?
        private var dragging = false

        override var isFlipped: Bool { true }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, event.type == .leftMouseDown,
                  !event.modifierFlags.contains(.control) else { return nil }
            return super.hitTest(point)
        }

        override func mouseDown(with event: NSEvent) {
            anchor = event.locationInWindow
        }

        override func mouseDragged(with event: NSEvent) {
            guard let anchor else { return }
            let point = event.locationInWindow
            if !dragging {
                guard hypot(point.x - anchor.x, point.y - anchor.y) >= 4 else { return }
                dragging = true
                NSCursor.closedHand.set()
            }
            updateDrag?(convert(point, from: nil))
        }

        override func mouseUp(with event: NSEvent) {
            let point = window?.isKeyWindow == true ? convert(event.locationInWindow, from: nil) : nil
            endDrag(at: point)
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil { endDrag(at: nil) }
            super.viewWillMove(toWindow: newWindow)
        }

        private func endDrag(at point: CGPoint?) {
            anchor = nil
            guard dragging else { return }
            dragging = false
            NSCursor.openHand.set()
            finishDrag?(point)
        }
    }
}
