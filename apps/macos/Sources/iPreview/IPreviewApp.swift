import SwiftUI

@main
struct IPreviewApp: App {
    var body: some Scene {
        Window("iPreview", id: "library") {
            LibraryView()
                .preferredColorScheme(.light)
                .tint(.ipreviewAccent)
                .frame(minWidth: 760, minHeight: 500)
        }
        .defaultSize(width: 1120, height: 740)
        .windowStyle(.hiddenTitleBar)
    }
}

extension Color {
    static let ipreviewAccent = Color(red: 0.322, green: 0.455, blue: 0.875)
    static let libraryCanvas = Color(red: 0.957, green: 0.961, blue: 0.969)
    static let libraryInk = Color(red: 0.094, green: 0.125, blue: 0.176)
    static let mediaSurface = Color(red: 0.895, green: 0.917, blue: 0.950)
}

// Use the state property wrapper on the Command Line Tools SDK as well as Xcode.
typealias ViewState<Value> = SwiftUI.State<Value>
