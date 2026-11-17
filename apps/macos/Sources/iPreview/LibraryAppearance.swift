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

    @ViewBuilder
    func libraryGlassSurface() -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: .rect(cornerRadius: 13))
        } else {
            background(.regularMaterial, in: .rect(cornerRadius: 13))
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
        case .album: "专辑名称"
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
