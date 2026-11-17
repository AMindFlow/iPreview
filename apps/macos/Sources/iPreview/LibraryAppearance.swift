import AppKit
import SwiftUI
import iPreviewCore

extension iPreviewCore.Layout {
    var sidebarSymbol: String {
        switch self {
        case .flat: "folder"
        case .creator: "person.crop.circle"
        case .multiCreator: "person.2"
        }
    }
}

extension LibraryPage {
    var indexedDirectory: LibraryPage? {
        switch self {
        case .creator, .folder: self
        default: nil
        }
    }

    func renamedDirectory(in edit: SourceNameEdit, to newPath: String) -> LibraryPage? {
        guard sourceID == edit.source.id else { return nil }
        switch self {
        case .creator(let id, let path) where path == edit.path:
            return .creator(id, newPath)
        case .folder(let id, let path) where path == edit.path || path.hasPrefix(edit.path + "/"):
            return .folder(id, newPath + path.dropFirst(edit.path.count))
        default:
            return nil
        }
    }
}

struct RenameClickBoundary: NSViewRepresentable {
    let onOutsideClick: () -> Void

    func makeNSView(context: Context) -> BoundaryView {
        BoundaryView()
    }

    func updateNSView(_ view: BoundaryView, context: Context) {
        view.onOutsideClick = onOutsideClick
    }

    static func dismantleNSView(_ view: BoundaryView, coordinator: ()) {
        view.removeMonitor()
    }

    final class BoundaryView: NSView {
        var onOutsideClick: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp, .otherMouseUp]) { [weak self] event in
                if let self, let onOutsideClick, event.window == window,
                   !bounds.contains(convert(event.locationInWindow, from: nil)) {
                    // Let the clicked control finish handling its mouse event before publishing the rename.
                    DispatchQueue.main.async { onOutsideClick() }
                }
                return event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

extension View {
    @ViewBuilder
    func libraryGlassButton() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }
}

struct LibraryTitleEdit {
    enum Target {
        case album(VirtualAlbum)
        case directory(SourceNameEdit)
    }

    let id = UUID()
    let page: LibraryPage
    let target: Target

    var name: String {
        switch target {
        case .album(let album): album.name
        case .directory(let edit): edit.name
        }
    }

    var placeholder: String {
        switch target {
        case .album: "合集名称"
        case .directory: "文件夹名称"
        }
    }

    var controlID: String {
        switch target {
        case .album: "virtual-album"
        case .directory: "source-directory"
        }
    }
}

struct LibraryTitleBarControls<Controls: View>: NSViewRepresentable {
    let sidebarWidth: CGFloat?
    let controls: Controls

    func makeNSView(context: Context) -> AttachmentView {
        AttachmentView(sidebarWidth: sidebarWidth, controls: controls)
    }

    func updateNSView(_ view: AttachmentView, context: Context) {
        view.host.rootView = controls
        view.sidebarWidth = sidebarWidth
        view.updateWidth()
    }

    static func dismantleNSView(_ view: AttachmentView, coordinator: ()) {
        view.uninstall()
    }

    final class AttachmentView: NSView {
        let host: NSHostingView<Controls>
        var sidebarWidth: CGFloat?
        private let accessory = TitleBarAccessory()
        private weak var installedWindow: NSWindow?

        init(sidebarWidth: CGFloat?, controls: Controls) {
            self.sidebarWidth = sidebarWidth
            host = NSHostingView(rootView: controls)
            super.init(frame: .zero)
            host.sizingOptions = []
            host.safeAreaRegions = []
            host.frame = NSRect(x: 0, y: 0, width: 64, height: 26)
            accessory.view = host
            accessory.layoutAttribute = .left
            accessory.onLayout = { [weak self] in self?.updateWidth() }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            uninstall()
            super.viewWillMove(toWindow: newWindow)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.addTitlebarAccessoryViewController(accessory)
            installedWindow = window
            updateWidth()
        }

        func updateWidth() {
            guard installedWindow != nil else { return }
            let leading = host.convert(host.bounds, to: nil).minX
            let width = max(64, (sidebarWidth ?? 0) - leading - 8)
            if abs(host.frame.width - width) > 0.5 {
                host.setFrameSize(NSSize(width: width, height: host.frame.height))
            }
        }

        func uninstall() {
            if let window = installedWindow,
               let index = window.titlebarAccessoryViewControllers.firstIndex(of: accessory) {
                window.removeTitlebarAccessoryViewController(at: index)
            }
            installedWindow = nil
        }
    }
}

private final class TitleBarAccessory: NSTitlebarAccessoryViewController {
    var onLayout: (() -> Void)?

    override func viewDidLayout() {
        super.viewDidLayout()
        onLayout?()
    }
}
