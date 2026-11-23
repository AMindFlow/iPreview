import SwiftUI
import iPreviewCore

@Observable
final class VideoWorkPreviewSession {
    struct Group {
        let name: String
        let symbol: String
        let cover: Media
        let items: [Media]
    }

    let work: IndexedVideoWork
    let groups: [Group]
    var groupIndex = 0
    var insideGroup = false
    var selectedMediaID: Int64?

    init(work: IndexedVideoWork) {
        self.work = work
        groups = [Group(name: "影碟", symbol: "opticaldisc", cover: work.video, items: [work.video])]
            + [Group(name: "官方样张", symbol: "photo.on.rectangle", cover: work.samples[0], items: work.samples)]
            + work.photoSets.map {
                Group(name: $0.title, symbol: "book.closed", cover: $0.cover ?? $0.photos[0], items: $0.photos)
            }
    }

    var group: Group { groups[groupIndex] }

    func enterGroup(at index: Int) {
        groupIndex = index
        selectedMediaID = nil
        insideGroup = true
    }
}

struct VideoWorkPreview: View {
    let session: VideoWorkPreviewSession
    let revision: Int
    let mediaPreviewShown: Bool
    let open: (Media, [Media]) -> Void
    let close: () -> Void
    @FocusState private var focused: Bool
    @ViewState private var sort = MediaSort()

    var body: some View {
        SortedMedia(request: MediaSortRequest(items: session.insideGroup ? session.group.items : [],
                                             sort: sort, revision: revision)) { files in
            stage(files: files)
        }
    }

    private func stage(files: [Media]) -> some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                Button(action: back) {
                    Image(systemName: session.insideGroup ? "chevron.left" : "xmark")
                }
                .accessibilityLabel(session.insideGroup ? "返回作品" : "退出作品预览")
                .help(session.insideGroup ? "返回作品（Esc）" : "退出作品预览（Esc）")
                Text(session.insideGroup ? session.group.name : session.work.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if session.insideGroup { MediaSortMenu(sort: $sort) }
            }
            .padding(.horizontal, 24)
            ScrollViewReader { reader in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) {
                        if session.insideGroup {
                            ForEach(files) { item in
                                card(title: item.name, cover: item, symbol: item.kind == .video ? "play.circle" : "photo",
                                     selected: item.id == (session.selectedMediaID ?? files.first?.id)) {
                                    session.selectedMediaID = item.id
                                    open(item, files)
                                }
                                .id(item.id)
                            }
                        } else {
                            ForEach(session.groups.indices, id: \.self) { index in
                                let group = session.groups[index]
                                card(title: group.name, cover: group.cover, symbol: group.symbol,
                                     selected: index == session.groupIndex) { session.enterGroup(at: index) }
                                .id(index)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                }
                .focusable()
                .focusEffectDisabled()
                .focused($focused)
                .onKeyPress(keys: [.escape, .space, .leftArrow, .rightArrow, .upArrow, .downArrow],
                            phases: [.down, .repeat]) { press in
                    switch press.key {
                    case .escape:
                        if press.phase == .down { back() }
                    case .space:
                        if press.phase == .down { enter(files: files) }
                    default:
                        let offset = press.key == .leftArrow || press.key == .upArrow ? -1 : 1
                        move(by: offset, files: files, reader: reader)
                    }
                    return .handled
                }
                .task(id: mediaPreviewShown) {
                    guard !mediaPreviewShown else { return }
                    await Task.yield()
                    if let selected = session.selectedMediaID { reader.scrollTo(selected) }
                    focused = true
                }
                .onChange(of: session.insideGroup) {
                    if session.insideGroup {
                        if let first = files.first { reader.scrollTo(first.id) }
                    } else {
                        reader.scrollTo(session.groupIndex)
                    }
                    focused = true
                }
            }
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }

    private func card(title: String, cover: Media, symbol: String, selected: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                MediaThumbnail(media: cover, revision: revision)
                    .frame(width: 170, height: 112)
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
                    }
                Label(title, systemImage: symbol)
                    .lineLimit(1)
                    .font(.callout)
            }
            .frame(width: 170, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func back() {
        if session.insideGroup { session.insideGroup = false } else { close() }
    }

    private func enter(files: [Media]) {
        if session.insideGroup {
            guard let item = files.first(where: { $0.id == session.selectedMediaID }) ?? files.first else { return }
            session.selectedMediaID = item.id
            open(item, files)
        } else {
            session.enterGroup(at: session.groupIndex)
        }
    }

    private func move(by offset: Int, files: [Media], reader: ScrollViewProxy) {
        if session.insideGroup {
            guard !files.isEmpty else { return }
            let current = files.firstIndex { $0.id == session.selectedMediaID } ?? 0
            let next = min(max(current + offset, 0), files.count - 1)
            session.selectedMediaID = files[next].id
            reader.scrollTo(files[next].id)
        } else {
            session.groupIndex = min(max(session.groupIndex + offset, 0), session.groups.count - 1)
            reader.scrollTo(session.groupIndex)
        }
    }
}
