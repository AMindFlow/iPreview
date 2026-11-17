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

    @ViewState private var editing = false
    @ViewState private var draft = ""
    @ViewState private var selection: TextSelection?

    var body: some View {
        if editing {
            TextField("专辑名称", text: $draft, selection: $selection)
                .textFieldStyle(.roundedBorder)
                .focused(focus, equals: .albumTitle)
                .frame(minWidth: 105, idealWidth: 210, maxWidth: 320)
                .accessibilityIdentifier("virtual-album-name")
                .task {
                    await Task.yield()
                    focus.wrappedValue = .albumTitle
                }
                .onSubmit {
                    let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    editing = false
                    finished()
                    if name != album.name { Task { await rename(name) } }
                }
                .onKeyPress(.escape) {
                    editing = false
                    finished()
                    return .handled
                }
                .onChange(of: disabled) {
                    if disabled { editing = false }
                }
        } else {
            Button {
                focus.wrappedValue = nil
                draft = album.name
                selection = TextSelection(range: draft.startIndex..<draft.endIndex)
                editing = true
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
