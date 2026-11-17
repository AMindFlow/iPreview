import SwiftUI
import iPreviewCore

enum MediaBrowseMode: String, CaseIterable, Identifiable {
    case icons, list, gallery

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
    var symbol: String {
        switch self {
        case .icons: "square.grid.2x2"
        case .list: "list.bullet"
        case .gallery: "rectangle.on.rectangle"
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
    let showPath: Bool
    let checked: Bool?
    @ViewState private var facts: Facts?

    private struct Facts: Sendable {
        let modified: Date?
        let size: Int?
    }

    var body: some View {
        MediaListColumns {
            HStack(spacing: 8) {
                if let checked {
                    MediaSelectionMark(isChecked: checked)
                        .frame(width: 17)
                }
                MediaThumbnail(media: media, revision: revision)
                    .frame(width: 25, height: 20)
                    .clipShape(.rect(cornerRadius: 3))
                VStack(alignment: .leading, spacing: 1) {
                    Text(media.name)
                        .fontWeight(selected ? .semibold : .regular)
                    if showPath {
                        Text(media.directories.joined(separator: " / "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .truncationMode(.middle)
                    }
                }
            }
        } modified: {
            Text(facts?.modified?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                .foregroundStyle(.secondary)
        } size: {
            Text(facts?.size?.formatted(.byteCount(style: .file)) ?? "—")
                .foregroundStyle(.secondary)
        } kind: {
            Text(kind)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 12))
        .lineLimit(1)
        .frame(height: showPath ? 37 : 29)
        .background(selected ? Color.ipreviewAccent.opacity(0.16) : shaded ? Color.libraryInk.opacity(0.045) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .task(id: revision) {
            facts = nil
            if media.isAvailable {
                let result = await Task.detached(priority: .utility) {
                    let url = try? media.readableURL()
                    let values = try? url?.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                    return Facts(modified: values?.contentModificationDate, size: values?.fileSize)
                }.value
                if !Task.isCancelled { facts = result }
            }
        }
    }

    private var kind: String {
        let suffix = URL(fileURLWithPath: media.name).pathExtension.uppercased()
        let format = suffix == "JPG" ? "JPEG" : suffix
        return "\(format) \(media.kind == .video ? "视频" : "图像")"
    }
}

struct MediaSelectionMark: View {
    let isChecked: Bool

    var body: some View {
        Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(isChecked ? .white : Color.libraryInk.opacity(0.65), Color.ipreviewAccent)
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
