import SwiftUI
import iPreviewCore

enum MediaBrowseMode: String, CaseIterable, Identifiable {
    case list, gallery, icons

    var id: Self { self }

    func layout(gridColumns: Int) -> BrowseLayout {
        switch self {
        case .icons: .grid(columns: gridColumns)
        case .list: .list
        case .gallery: .gallery
        }
    }

    var title: String {
        switch self {
        case .icons: "图标"
        case .list: "列表"
        case .gallery: "画廊"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .list: "1"
        case .gallery: "2"
        case .icons: "3"
        }
    }

    var symbol: String {
        switch self {
        case .icons: "square.grid.2x2"
        case .list: "list.bullet"
        case .gallery: "rectangle.on.rectangle"
        }
    }
}

private struct LibraryBrowseModeKey: FocusedValueKey {
    typealias Value = Binding<MediaBrowseMode>
}

private struct LibraryImmersiveActionKey: FocusedValueKey {
    typealias Value = @MainActor () -> Void
}

extension FocusedValues {
    var libraryBrowseMode: Binding<MediaBrowseMode>? {
        get { self[LibraryBrowseModeKey.self] }
        set { self[LibraryBrowseModeKey.self] = newValue }
    }

    var libraryImmersiveAction: (@MainActor () -> Void)? {
        get { self[LibraryImmersiveActionKey.self] }
        set { self[LibraryImmersiveActionKey.self] = newValue }
    }
}

struct LibraryBrowseCommands: Commands {
    @FocusedValue(\.libraryBrowseMode) private var mode
    @FocusedValue(\.libraryImmersiveAction) private var openImmersive

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            ForEach(MediaBrowseMode.allCases) { destination in
                Button(destination.title) { mode?.wrappedValue = destination }
                    .keyboardShortcut(destination.shortcut, modifiers: .command)
                    .disabled(mode == nil)
            }
            Divider()
            Button("沉浸模式") { openImmersive?() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(openImmersive == nil)
        }
    }
}

struct MediaListColumns<Name: View, Modified: View, Size: View, Kind: View>: View {
    @ViewBuilder let name: () -> Name
    @ViewBuilder let modified: () -> Modified
    @ViewBuilder let size: () -> Size
    @ViewBuilder let kind: () -> Kind

    var body: some View {
        HStack(spacing: 12) {
            name().frame(maxWidth: .infinity, alignment: .leading)
            modified().frame(width: 139, alignment: .leading)
            size().frame(width: 68, alignment: .trailing)
            kind().frame(width: 74, alignment: .leading)
        }
        .padding(.horizontal, 10)
    }
}

struct MediaListRow: View {
    let media: Media
    let revision: Int
    let selected: Bool
    let shaded: Bool
    let checked: Bool
    @Environment(\.appearsActive) private var appearsActive
    @ViewState private var facts: MediaFileFacts?

    var body: some View {
        MediaListColumns {
            HStack(spacing: 8) {
                MediaThumbnail(media: media, revision: revision, previewCornerRadius: 3)
                    .frame(width: 25, height: 20)
                    .clipShape(.rect(cornerRadius: 3))
                Text(media.name)
            }
        } modified: {
            Text(facts?.modified?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                .foregroundStyle(detailColor)
        } size: {
            Text(facts?.size?.formatted(.byteCount(style: .file)) ?? "—")
                .foregroundStyle(detailColor)
        } kind: {
            Text(kind)
                .foregroundStyle(detailColor)
        }
        .foregroundStyle(selected ? selectedTextColor : .primary)
        .font(.system(size: 12))
        .lineLimit(1)
        .frame(height: 29)
        .background(selected ? selectedBackground
                    : shaded ? Color.libraryInk.opacity(0.045) : .clear, in: .rect(cornerRadius: 6))
        .overlay(alignment: .bottomTrailing) {
            if checked {
                MediaSelectionMark()
                    .padding(.trailing, 5)
                    .padding(.bottom, 4)
            }
        }
        .contentShape(Rectangle())
        .task(id: revision) {
            facts = nil
            if media.isAvailable {
                let result = await Task.detached(priority: .utility) { MediaFileFacts(media) }.value
                if !Task.isCancelled { facts = result }
            }
        }
    }

    private var selectedBackground: Color {
        Color(nsColor: appearsActive ? .selectedContentBackgroundColor : .unemphasizedSelectedContentBackgroundColor)
    }

    private var selectedTextColor: Color {
        Color(nsColor: appearsActive ? .alternateSelectedControlTextColor : .unemphasizedSelectedTextColor)
    }

    private var detailColor: Color {
        selected ? selectedTextColor.opacity(0.9) : .secondary
    }

    private var kind: String {
        let suffix = URL(fileURLWithPath: media.name).pathExtension.uppercased()
        let format = suffix == "JPG" ? "JPEG" : suffix
        return "\(format) \(media.kind == .video ? "视频" : "图像")"
    }
}

struct MediaSelectionMark: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white, Color.ipreviewAccent)
            .background(.white, in: Circle())
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct InlineGalleryImage: View {
    let media: Media
    let revision: Int
    @ViewState private var image: CGImage?
    @ViewState private var loaded = false

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                } else if loaded {
                    Label(media.isAvailable ? "无法显示媒体" : "媒体不可用",
                          systemImage: media.kind == .video ? "film" : "photo")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color.libraryInk.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel(media.name)
        .task(id: revision) {
            image = nil
            loaded = false
            let decoded = await Task.detached(priority: .utility) {
                await MediaImages.thumbnail(for: media, limit: 1600)
            }.value
            guard !Task.isCancelled else { return }
            image = decoded
            loaded = true
        }
    }
}
