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

struct VirtualAlbumTitle: View {
    let album: VirtualAlbum
    let disabled: Bool
    let focus: FocusState<LibraryView.Focus?>.Binding
    let rename: (String) async -> Void
    let finished: () -> Void

    @ViewState private var draft: String?
    @ViewState private var selection: TextSelection?

    var body: some View {
        if let draft = Binding($draft) {
            TextField("专辑名称", text: draft, selection: $selection)
                .textFieldStyle(.roundedBorder)
                .focused(focus, equals: .albumTitle)
                .frame(minWidth: 105, idealWidth: 210, maxWidth: 320)
                .accessibilityIdentifier("virtual-album-name")
                .task {
                    await Task.yield()
                    focus.wrappedValue = .albumTitle
                }
                .onSubmit {
                    let name = draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    self.draft = nil
                    finished()
                    if name != album.name { Task { await rename(name) } }
                }
                .onKeyPress(.escape) {
                    self.draft = nil
                    finished()
                    return .handled
                }
                .onChange(of: disabled) {
                    if disabled { self.draft = nil }
                }
        } else {
            Button {
                focus.wrappedValue = nil
                draft = album.name
                selection = TextSelection(range: album.name.startIndex..<album.name.endIndex)
            } label: {
                Text(album.name)
                    .accessibilityAddTraits(.isHeader)
            }
            .buttonStyle(.plain)
            .disabled(disabled)
            .accessibilityIdentifier("virtual-album-title")
            .accessibilityHint("重命名虚拟专辑")
            .help("点击标题重命名专辑")
        }
    }
}
