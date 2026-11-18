import AppKit
import SwiftUI

@main
struct IPreviewApp: App {
    var body: some Scene {
        Window("iPreview", id: "library") {
            LibraryView()
                .frame(minWidth: 760, minHeight: 500)
        }
        .defaultSize(width: 1120, height: 740)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            LibraryBrowseCommands()
            LibraryImportCommands()
            LibrarySearchCommands()
        }
    }
}

private struct LibraryImportActionKey: FocusedValueKey {
    typealias Value = @MainActor () -> Void
}

extension FocusedValues {
    var libraryImportAction: (@MainActor () -> Void)? {
        get { self[LibraryImportActionKey.self] }
        set { self[LibraryImportActionKey.self] = newValue }
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
