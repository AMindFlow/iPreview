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
        let sourceSize: CGSize
        let grabOffset: CGPoint
        let avatar: AnyView
        let mode: MediaBrowseMode
        let owner: UUID
    }

    private struct Slot {
        let frame: CGRect
        let owner: UUID
    }

    private(set) var drag: Drag?
    private(set) var destination: Int?
    private(set) var pointer: CGPoint?
    @ObservationIgnored private var slots: [MediaBrowseMode: [Int64: Slot]] = [:]
    @ObservationIgnored private var viewport: CGRect = .null
    @ObservationIgnored private var cancelledOwner: UUID?

    func record(_ frame: CGRect?, for item: Media, mode: MediaBrowseMode, owner: UUID) {
        if let frame {
            slots[mode, default: [:]][item.id] = Slot(frame: frame, owner: owner)
        } else if slots[mode]?[item.id]?.owner == owner {
            slots[mode]?[item.id] = nil
        }
    }

    func recordViewport(_ frame: CGRect) {
        if viewport.size != frame.size { cancel() }
        viewport = frame
    }

    func pointInBrowser(_ point: CGPoint, from item: Media, mode: MediaBrowseMode, owner: UUID) -> CGPoint? {
        guard let slot = slots[mode]?[item.id], slot.owner == owner else { return nil }
        let frame = slot.frame
        let x = frame.maxX - AlbumOrderHandle.trailingInset(mode) - AlbumOrderHandle.size.width
        let y = mode == .list
            ? frame.midY - AlbumOrderHandle.size.height / 2
            : frame.maxY - AlbumOrderHandle.bottomInset(mode) - AlbumOrderHandle.size.height
        return CGPoint(x: x + point.x, y: y + point.y)
    }

    func begin(_ item: Media, album: VirtualAlbum, mode: MediaBrowseMode, owner: UUID,
               grabbedAt point: CGPoint, avatar: AnyView) -> Bool {
        guard drag == nil, cancelledOwner != owner, let slot = slots[mode]?[item.id], slot.owner == owner,
              let index = album.mediaIDs.firstIndex(of: item.id) else { return false }
        let indices = Dictionary(uniqueKeysWithValues: album.mediaIDs.enumerated().map { ($1, $0) })
        let frame = slot.frame
        let offset = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
        drag = Drag(album: album, item: item, indices: indices, sourceIndex: index,
                    sourceSize: frame.size, grabOffset: offset, avatar: avatar, mode: mode, owner: owner)
        return true
    }

    func update(_ point: CGPoint, owner: UUID) {
        guard let drag, drag.owner == owner else { return }
        guard viewport.contains(point) else {
            pointer = nil
            destination = nil
            return
        }
        pointer = point
        let center = CGPoint(x: point.x - drag.grabOffset.x + drag.sourceSize.width / 2,
                             y: point.y - drag.grabOffset.y + drag.sourceSize.height / 2)
        destination = slots[drag.mode, default: [:]]
            .compactMap { id, slot -> (index: Int, score: CGFloat)? in
                let frame = slot.frame
                guard let index = drag.indices[id], frame.intersects(viewport) else { return nil }
                let x = (center.x - frame.midX) / max(1, frame.width / 2)
                let y = (center.y - frame.midY) / max(1, frame.height / 2)
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
        let modeSlots = slots[drag.mode, default: [:]]
        guard let source = modeSlots[id]?.frame,
              let target = modeSlots[drag.album.mediaIDs[movedIndex]]?.frame else { return .zero }
        return CGSize(width: target.minX - source.minX, height: target.minY - source.minY)
    }

    @discardableResult
    func cancel() -> Bool {
        guard let drag else { return false }
        clear()
        cancelledOwner = drag.owner
        return true
    }

    func endGesture(for owner: UUID) {
        if cancelledOwner == owner { cancelledOwner = nil }
        if drag?.owner == owner { clear() }
    }

    private func clear() {
        drag = nil
        destination = nil
        pointer = nil
    }
}

extension View {
    func albumOrderOverlay(_ order: AlbumOrderDrag) -> some View {
        overlay(alignment: .topLeading) {
            if let drag = order.drag, let point = order.pointer, order.destination != nil {
                drag.avatar
                    .frame(width: drag.sourceSize.width, height: drag.sourceSize.height)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.13)))
                    .shadow(color: .black.opacity(0.24), radius: 9, y: 4)
                    .offset(x: point.x - drag.grabOffset.x, y: point.y - drag.grabOffset.y)
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

struct AlbumOrderItem<Content: View, Avatar: View>: View {
    let order: AlbumOrderDrag
    let album: VirtualAlbum
    let item: Media
    let mode: MediaBrowseMode
    let enabled: Bool
    let content: Content
    let avatar: Avatar
    let start: () -> Void
    let commit: (VirtualAlbum, Int) -> Void

    @ViewState private var owner = UUID()
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
            order.record($0, for: item, mode: mode, owner: owner)
        }
        .onDisappear {
            order.record(nil, for: item, mode: mode, owner: owner)
            order.endGesture(for: owner)
        }
    }

    private func updateDrag(_ location: CGPoint, _ origin: CGPoint) {
        guard let point = order.pointInBrowser(location, from: item, mode: mode, owner: owner),
              let grabbedAt = order.pointInBrowser(origin, from: item, mode: mode, owner: owner) else { return }
        if order.drag == nil,
           order.begin(item, album: album, mode: mode, owner: owner, grabbedAt: grabbedAt, avatar: AnyView(avatar)) {
            start()
        }
        order.update(point, owner: owner)
    }

    private func finishDrag(_ location: CGPoint?) {
        defer { order.endGesture(for: owner) }
        guard order.drag?.owner == owner, let location,
              let point = order.pointInBrowser(location, from: item, mode: mode, owner: owner) else { return }
        order.update(point, owner: owner)
        if let drag = order.drag, let target = order.destination, drag.sourceIndex != target {
            commit(drag.album, target)
        }
    }
}

private struct AlbumOrderHandle: NSViewRepresentable {
    static let size = CGSize(width: 23, height: 22)
    static func trailingInset(_ mode: MediaBrowseMode) -> CGFloat { mode == .list ? 2 : 5 }
    static func bottomInset(_ mode: MediaBrowseMode) -> CGFloat { mode == .list ? 0 : 18 }

    let update: (CGPoint, CGPoint) -> Void
    let finish: (CGPoint?) -> Void

    func makeNSView(context: Context) -> Surface { Surface() }

    func updateNSView(_ view: Surface, context: Context) {
        view.updateDrag = update
        view.finishDrag = finish
    }

    // Claim mouse-down just on the grip so the surrounding scroll view cannot take the drag.
    final class Surface: NSView {
        var updateDrag: ((CGPoint, CGPoint) -> Void)?
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
            updateDrag?(convert(point, from: nil), convert(anchor, from: nil))
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
