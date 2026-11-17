import SwiftUI
import iPreviewCore

struct AlbumMediaPicker: View {
    let album: VirtualAlbum
    let model: LibraryModel
    private let creators: [(id: LibraryPage, title: String, source: Source)]
    private let mediaByCreator: [LibraryPage: [Media]]
    private let existing: Set<Int64>

    @Environment(\.dismiss) private var dismiss
    @ViewState private var creator: LibraryPage?
    @ViewState private var folder: LibraryPage?
    @ViewState private var checkedFolder: LibraryPage?
    @ViewState private var readableCandidates: [Media] = []
    @ViewState private var staged: [Media] = []
    @ViewState private var saving = false
    @ViewState private var error: String?

    init(album: VirtualAlbum, model: LibraryModel) {
        self.album = album
        self.model = model
        existing = Set(album.mediaIDs)
        let available = model.snapshot.media.filter(\.isAvailable)
        mediaByCreator = Dictionary(grouping: available, by: Self.creatorPage)
        var seen: Set<LibraryPage> = []
        creators = available.compactMap { item in
            let key = Self.creatorPage(for: item)
            guard seen.insert(key).inserted else { return nil }
            return (key, item.creator, item.source)
        }
    }

    private static func creatorPage(for item: Media) -> LibraryPage {
        item.source.layout == .multiCreator ? .creator(item.source.id, item.creator) : .source(item.source.id)
    }

    var body: some View {
        let creatorMedia = creator.flatMap { mediaByCreator[$0] } ?? []
        let byFolder = Dictionary(grouping: creatorMedia) { item in
            LibraryPage.folder(item.source.id, ContentScope.folderKey(item))
        }
        let folders = byFolder.map { (id: $0.key, title: $0.value[0].album) }.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        let requestedFolder = folder
        let indexed = (requestedFolder.flatMap { byFolder[$0] } ?? []).filter { !existing.contains($0.id) }
        let candidates = checkedFolder == requestedFolder ? readableCandidates : []
        let stagedIDs = Set(staged.map(\.id))
        let remaining = candidates.filter { !stagedIDs.contains($0.id) }

        VStack(alignment: .leading, spacing: 14) {
            Text("添加到「\(album.name)」")
                .font(.title2.weight(.semibold))
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: 10) {
                pane("来源与创作者") {
                    List(selection: $creator) {
                        ForEach(creators, id: \.id) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                if item.source.layout == .multiCreator {
                                    Text(item.source.name).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .help(item.source.path)
                            .accessibilityHint(item.source.path)
                            .tag(item.id)
                        }
                    }
                    .listStyle(.bordered)
                    .accessibilityLabel("来源与创作者")
                }
                .frame(width: 132)

                pane("专辑") {
                    List(selection: $folder) {
                        ForEach(folders, id: \.id) { item in
                            Text(item.title)
                                .tag(item.id)
                        }
                    }
                    .listStyle(.bordered)
                    .accessibilityLabel("来源专辑")
                }
                .frame(width: 132)

                pane("媒体") {
                    if candidates.isEmpty {
                        Text(emptyMessage)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], spacing: 8) {
                                ForEach(candidates) { item in
                                    let selected = stagedIDs.contains(item.id)
                                    Button {
                                        if selected { staged.removeAll { $0.id == item.id } }
                                        else { staged.append(item) }
                                    } label: {
                                        tile(item, selected: selected)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(item.name)
                                    .accessibilityAddTraits(selected ? .isSelected : [])
                                }
                            }
                            .padding(2)
                        }
                    }
                    Button("全选当前专辑") { staged.append(contentsOf: remaining) }
                        .disabled(remaining.isEmpty)
                }
                .frame(maxWidth: .infinity)

                pane("待添加 · \(staged.count) 项") {
                    List {
                        ForEach(staged) { item in
                            HStack(spacing: 6) {
                                MediaThumbnail(media: item).frame(width: 30, height: 26)
                                Text(item.name).lineLimit(1).help(item.name)
                                Spacer(minLength: 2)
                                Button {
                                    staged.removeAll { $0.id == item.id }
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("移除\(item.name)")
                            }
                        }
                    }
                    .listStyle(.bordered)
                    .accessibilityLabel("待添加媒体")
                }
                .frame(width: 166)
            }
            .disabled(saving)
            HStack {
                if let error { Text(error).foregroundStyle(.red).accessibilityAddTraits(.updatesFrequently) }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(saving)
                Button(saving ? "正在添加…" : "确认添加", action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(staged.isEmpty || saving)
            }
        }
        .padding(22)
        .frame(width: 740, height: 463)
        .onChange(of: creator) { folder = nil }
        .task(id: requestedFolder) {
            guard !Task.isCancelled, folder == requestedFolder else { return }
            checkedFolder = nil
            readableCandidates = []
            guard let requestedFolder else { return }

            let readable = await Self.checkReadability(indexed)
            guard !Task.isCancelled, folder == requestedFolder else { return }
            readableCandidates = readable
            checkedFolder = requestedFolder
        }
        .interactiveDismissDisabled(saving)
    }

    private var emptyMessage: String {
        if creators.isEmpty { return "没有可用来源" }
        if creator == nil { return "先选择来源或创作者" }
        if folder == nil { return "请选择一个专辑" }
        if checkedFolder != folder { return "正在检查媒体…" }
        return "此专辑没有可添加的媒体"
    }

    private func pane(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.callout.weight(.semibold)).accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func tile(_ item: Media, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            MediaThumbnail(media: item)
                .aspectRatio(1.4, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 6))
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white, Color.ipreviewAccent)
                            .padding(4)
                            .accessibilityHidden(true)
                    }
                }
            Label(item.name, systemImage: item.kind == .video ? "film" : "photo")
                .font(.caption2)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .help(item.name)
    }

    private static func checkReadability(_ items: [Media]) async -> [Media] {
        let inspection = Task.detached(priority: .userInitiated) {
            var readable: [Media] = []
            for item in items {
                if Task.isCancelled { break }
                if (try? item.readableURL()) != nil { readable.append(item) }
            }
            return readable
        }
        return await withTaskCancellationHandler {
            await inspection.value
        } onCancel: {
            inspection.cancel()
        }
    }

    private func confirm() {
        guard !saving else { return }
        saving = true
        error = nil
        let chosen = staged
        Task {
            defer { saving = false }
            let readable = await Self.checkReadability(chosen)
            if readable.count != chosen.count {
                let readableIDs = Set(readable.map(\.id))
                let unavailableIDs = Set(chosen.lazy.map(\.id).filter { !readableIDs.contains($0) })
                readableCandidates.removeAll { unavailableIDs.contains($0.id) }
                error = "有选中的媒体已不可用。请从待添加列表移除后重试。"
                return
            }
            if await model.add(mediaIDs: readable.map(\.id), to: album.id) {
                dismiss()
            } else {
                error = model.error ?? "无法添加媒体，请重试。"
                model.error = nil
            }
        }
    }
}
