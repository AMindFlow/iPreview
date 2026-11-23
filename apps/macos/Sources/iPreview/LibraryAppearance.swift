import AppKit
import SwiftUI
import iPreviewCore

enum LibraryTheme: String, CaseIterable {
    case system, light, dark

    var next: Self {
        switch self {
        case .system: .light
        case .light: .dark
        case .dark: .system
        }
    }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var symbol: String {
        switch self {
        case .system: "display"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

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

enum LibraryTitleBarLayout {
    static let buttonSize: CGFloat = 26
    static let buttonSpacing: CGFloat = 4
    static let groupSpacing: CGFloat = 12
    static let minimumWidth = buttonSize * 3 + buttonSpacing + groupSpacing
}

struct LibraryTitleBarControls<Controls: View>: NSViewRepresentable {
    let sidebarWidth: CGFloat?
    let controls: Controls

    func makeNSView(context: Context) -> AttachmentView {
        AttachmentView(sidebarWidth: sidebarWidth, controls: controls)
    }

    func updateNSView(_ view: AttachmentView, context: Context) {
        let visibilityChanged = (view.sidebarWidth == nil) != (sidebarWidth == nil)
        view.host.rootView = controls
        view.sidebarWidth = sidebarWidth
        view.updateWidth(animated: visibilityChanged && context.transaction.animation != nil)
    }

    static func dismantleNSView(_ view: AttachmentView, coordinator: ()) {
        view.uninstall()
    }

    final class AttachmentView: NSView {
        let host: NSHostingView<Controls>
        var sidebarWidth: CGFloat?
        private let accessory = TitleBarAccessory()
        private weak var installedWindow: NSWindow?
        private var targetWidth: CGFloat?

        init(sidebarWidth: CGFloat?, controls: Controls) {
            self.sidebarWidth = sidebarWidth
            host = NSHostingView(rootView: controls)
            super.init(frame: .zero)
            host.sizingOptions = []
            host.safeAreaRegions = []
            host.frame = NSRect(x: 0, y: 0, width: LibraryTitleBarLayout.minimumWidth,
                                height: LibraryTitleBarLayout.buttonSize)
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

        func updateWidth(animated: Bool = false) {
            guard installedWindow != nil else { return }
            let leading = host.convert(host.bounds, to: nil).minX
            let width = max(LibraryTitleBarLayout.minimumWidth, (sidebarWidth ?? 0) - leading - 8)
            if let targetWidth, abs(targetWidth - width) <= 0.5 { return }
            targetWidth = width
            if animated {
                NSAnimationContext.runAnimationGroup { animation in
                    animation.duration = 0.24
                    host.animator().setFrameSize(NSSize(width: width, height: host.frame.height))
                }
            } else {
                host.setFrameSize(NSSize(width: width, height: host.frame.height))
            }
        }

        func uninstall() {
            if let window = installedWindow,
               let index = window.titlebarAccessoryViewControllers.firstIndex(of: accessory) {
                window.removeTitlebarAccessoryViewController(at: index)
            }
            installedWindow = nil
            targetWidth = nil
        }
    }
}

struct LibraryThemeButton: View {
    @Binding var theme: LibraryTheme
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false
    @State private var showingMenu = false

    var body: some View {
        let size = LibraryTitleBarLayout.buttonSize
        Button {
            if NSEvent.modifierFlags.contains(.option) {
                showingMenu = true
            } else {
                theme = theme.next
            }
        } label: {
            Group {
                if hovering && isEnabled {
                    LibraryThemeSwitchGlyph()
                } else {
                    Image(systemName: theme.symbol)
                        .font(.system(size: 14, weight: .medium))
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(LibraryIconButtonStyle())
        .onHover { hovering in
            self.hovering = hovering
            if isEnabled && hovering && NSEvent.modifierFlags.contains(.option) { showingMenu = true }
        }
        .onModifierKeysChanged(mask: .option) { _, keys in
            if isEnabled && hovering && keys.contains(.option) { showingMenu = true }
        }
        .accessibilityLabel("主题：\(theme.title)")
        .accessibilityIdentifier("library-theme")
        .accessibilityAction(named: Text("选择主题")) { showingMenu = true }
        .help("点击依次切换跟随系统、浅色、深色。按住 Option 显示主题菜单。")
        .popover(isPresented: $showingMenu, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(LibraryTheme.allCases, id: \.self) { option in
                    Button {
                        theme = option
                        showingMenu = false
                    } label: {
                        HStack {
                            Label(option.title, systemImage: option.symbol)
                            Spacer()
                            Image(systemName: "checkmark")
                                .opacity(theme == option ? 1 : 0)
                                .accessibilityHidden(true)
                        }
                        .frame(minWidth: 114)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(theme == option ? .isSelected : [])
                }
            }
            .padding(8)
        }
    }
}

private struct LibraryThemeSwitchGlyph: View {
    var body: some View {
        Canvas { context, size in
            let side = size.width
            let center = side / 2
            let gap: CGFloat = 1.3
            let font = Font.system(size: 14, weight: .medium)

            var sun = context
            sun.clip(to: Path { path in
                path.addLines([.zero, CGPoint(x: side - gap, y: 0), CGPoint(x: 0, y: side - gap)])
                path.closeSubpath()
            })
            sun.draw(Text(Image(systemName: "sun.max")).font(font), at: CGPoint(x: center - 1, y: center - 1))

            var moon = context
            moon.clip(to: Path { path in
                path.addLines([CGPoint(x: side, y: side), CGPoint(x: side, y: gap), CGPoint(x: gap, y: side)])
                path.closeSubpath()
            })
            moon.draw(Text(Image(systemName: "moon")).font(font), at: CGPoint(x: center + 1, y: center + 1))

            context.stroke(Path { path in
                path.move(to: CGPoint(x: 1.5, y: side - 1.5))
                path.addLine(to: CGPoint(x: side - 1.5, y: 1.5))
            }, with: .foreground, style: StrokeStyle(lineWidth: 1, lineCap: .round))
        }
        .frame(width: 18, height: 18)
    }
}

struct LibraryIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isHovered && isEnabled ? .primary : .secondary)
            .background {
                RoundedRectangle(cornerRadius: 5)
                    .fill(.primary.opacity(configuration.isPressed ? 0.14 : 0.08))
                    .opacity(isEnabled && (isHovered || configuration.isPressed) ? 1 : 0)
                    .frame(minWidth: 26, minHeight: 26)
            }
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct EmptyAlbumAddButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 15)
        let isPressed = isEnabled && configuration.isPressed
        let highlighted = isEnabled && (isHovered || isPressed)
        let highlight = contrast == .increased ? Color.primary : Color.ipreviewAccent

        configuration.label
            .frame(width: 74, height: 70)
            .background(isPressed ? Color.primary.opacity(0.14) : Color.mediaSurface.opacity(0.48), in: shape)
            .overlay {
                shape.strokeBorder(highlight, lineWidth: isPressed ? 2 : 1.5)
                    .opacity(highlighted ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: highlighted)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isPressed)
    }
}

struct LibraryBrowseModePicker: View {
    @Binding var selection: MediaBrowseMode

    var body: some View {
        Group {
            if #available(macOS 26, *) {
                buttons.glassEffect(.regular, in: .capsule)
            } else {
                buttons
                    .background(.regularMaterial, in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(.quaternary)
                            .allowsHitTesting(false)
                    }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("浏览视图")
    }

    private var buttons: some View {
        HStack(spacing: 3) {
            ForEach(MediaBrowseMode.allCases) { mode in
                Button { selection = mode } label: {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(LibraryBrowseModeButtonStyle(selected: mode == selection))
                .accessibilityLabel(mode.title)
                .accessibilityIdentifier(mode.symbol)
                .accessibilityAddTraits(mode == selection ? .isSelected : [])
                .help("\(mode.title)（⌘\(String(mode.shortcut.character))）")
            }
        }
        .padding(4)
    }
}

private struct LibraryBrowseModeButtonStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background {
                Circle()
                    .fill(.primary.opacity(selected ? 0.14 : 0.07))
                    .opacity(selected || isHovered || configuration.isPressed ? 1 : 0)
            }
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Circle())
            .onHover { isHovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: selected)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
    }
}

private final class TitleBarAccessory: NSTitlebarAccessoryViewController {
    var onLayout: (() -> Void)?

    override func viewDidLayout() {
        super.viewDidLayout()
        onLayout?()
    }
}
