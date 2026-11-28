import AppKit
import SwiftUI

@main
struct IPreviewApp: App {
    @AppStorage("libraryTheme") private var theme = LibraryTheme.system

    var body: some Scene {
        Window("iPreview", id: "library") {
            LibraryView(theme: $theme)
                .frame(minWidth: 760, minHeight: 500)
                .onChange(of: theme, initial: true) { _, theme in
                    NSApp.appearance = theme.appearance
                }
        }
        .defaultSize(width: 1120, height: 740)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            LibraryBrowseCommands()
            LibraryImportCommands()
            LibrarySearchCommands()
            MediaPreviewCommands()
        }
    }
}

private struct LibraryImportActionKey: FocusedValueKey {
    typealias Value = @MainActor () -> Void
}

private struct LibraryMetadataActionKey: FocusedValueKey {
    typealias Value = @MainActor () -> Void
}

private struct PreviewPlayActionKey: FocusedValueKey {
    typealias Value = @MainActor () -> Void
}

extension FocusedValues {
    var libraryImportAction: (@MainActor () -> Void)? {
        get { self[LibraryImportActionKey.self] }
        set { self[LibraryImportActionKey.self] = newValue }
    }

    var libraryMetadataAction: (@MainActor () -> Void)? {
        get { self[LibraryMetadataActionKey.self] }
        set { self[LibraryMetadataActionKey.self] = newValue }
    }

    var previewPlayAction: (@MainActor () -> Void)? {
        get { self[PreviewPlayActionKey.self] }
        set { self[PreviewPlayActionKey.self] = newValue }
    }
}

private struct MediaPreviewCommands: Commands {
    @FocusedValue(\.libraryMetadataAction) private var showMetadata
    @FocusedValue(\.previewPlayAction) private var startPlayback

    var body: some Commands {
        CommandGroup(replacing: .printItem) {
            Button("媒体元信息") { showMetadata?() }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(showMetadata == nil)
            Button("开始播放") { startPlayback?() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(startPlayback == nil)
        }
    }
}

private struct LibraryImportCommands: Commands {
    @FocusedValue(\.libraryImportAction) private var importFolder

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("导入文件夹…") { importFolder?() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(importFolder == nil)
        }
    }
}

extension Color {
    static let ipreviewAccent = Color.accentColor
    static let libraryInk = Color(nsColor: .labelColor)
    static let mediaSurface = Color(nsColor: .quaternaryLabelColor).opacity(0.32)
}

// Use the state property wrapper on the Command Line Tools SDK as well as Xcode.
typealias ViewState<Value> = SwiftUI.State<Value>
