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
    }
}

extension Color {
    static let ipreviewAccent = Color.accentColor
    static let libraryInk = Color(nsColor: .labelColor)
    static let mediaSurface = Color(nsColor: .quaternaryLabelColor).opacity(0.32)
}

// Use the state property wrapper on the Command Line Tools SDK as well as Xcode.
typealias ViewState<Value> = SwiftUI.State<Value>
