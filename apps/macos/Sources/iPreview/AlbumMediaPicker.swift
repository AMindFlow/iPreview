import SwiftUI
import iPreviewCore

struct AlbumMediaPicker: View {
    let album: VirtualAlbum
    let model: LibraryModel
    private let creators: [(id: LibraryPage, title: String, path: String)]
    private let mediaByCreator: [LibraryPage: [Media]]
    private let existing: Set<Int64>

    @Environment(\.dismiss) private var dismiss
    @ViewState private var creator: LibraryPage?
    @ViewState private var folder: LibraryPage?
    @ViewState private var checkedFolder: LibraryPage?
    @ViewState private var sort = MediaSort()
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
        let options = available.compactMap { item -> (id: LibraryPage, title: String, path: String)? in
            let key = Self.creatorPage(for: item)
            guard seen.insert(key).inserted else { return nil }
            let title = item.source.layout == .multiCreator
                ? "\(item.creator) · \(item.source.name)"
                : item.creator
            return (key, title, item.source.path)
        }
        let duplicates = Dictionary(grouping: options, by: \.title).filter { $0.value.count > 1 }
        creators = options.map { option in
            let title = duplicates[option.title] == nil ? option.title : "\(option.title) · \(option.path)"
            return (option.id, title, option.path)
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

        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Text("添加到「\(album.name)」")
                    .font(.system(size: 21, weight: .semibold))
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                    .help(album.name)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 17)
                    .frame(height: 49)

                Divider().padding(.horizontal, 16)

                SortedMedia(request: MediaSortRequest(items: candidates, sort: sort)) { ordered in
                    filters(folders, remaining: ordered.filter { !stagedIDs.contains($0.id) })
                    candidatePane(ordered, stagedIDs: stagedIDs)
                }
            }
            .disabled(saving)

            Divider()

            VStack(spacing: 0) {
                stagedStrip.disabled(saving)
                footer
            }
            .background(.thinMaterial)
        }
        .foregroundStyle(Color.libraryInk)
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
        if creators.isEmpty { return "没有可用媒体源" }
        if creator == nil { return "先选择媒体源或创作者" }
        if folder == nil { return "请选择一个专辑" }
        if checkedFolder != folder { return "正在检查媒体…" }
        return "此专辑没有可添加的媒体"
    }

    private func filters(_ folders: [(id: LibraryPage, title: String)], remaining: [Media]) -> some View {
        HStack(spacing: 18) {
            HStack(spacing: 7) {
                Text("媒体源与创作者")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityHidden(true)
                Picker("媒体源与创作者", selection: $creator) {
                    Text("请选择").tag(nil as LibraryPage?)
                    ForEach(creators, id: \.id) { item in
                        Text(item.title)
                            .help(item.path)
                            .tag(Optional(item.id))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .help(creators.first { $0.id == creator }?.path ?? "")
                .frame(width: 150)
                .disabled(creators.isEmpty)
            }

            HStack(spacing: 7) {
                Text("源专辑")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityHidden(true)
                Picker("源专辑", selection: $folder) {
                    Text("请选择").tag(nil as LibraryPage?)
                    ForEach(folders, id: \.id) { item in
                        Text(item.title).tag(Optional(item.id))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 165)
                .disabled(folders.isEmpty)
            }

            Spacer(minLength: 0)

            MediaSortMenu(sort: $sort)
                .disabled(readableCandidates.isEmpty)
            Button("全选当前专辑") { staged.append(contentsOf: remaining) }
                .controlSize(.small)
                .disabled(remaining.isEmpty)
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .frame(height: 39)
    }

    private func candidatePane(_ candidates: [Media], stagedIDs: Set<Int64>) -> some View {
        Group {
            if candidates.isEmpty {
                Text(emptyMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 4), spacing: 9) {
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
                            .accessibilityValue(item.kind.title)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var stagedStrip: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("待添加 · \(staged.count) 项")
                .font(.callout.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 16)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 9) {
                    ForEach(staged) { item in
                        stagedTile(item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 3)
            }
            .frame(height: 67)
            .accessibilityLabel("待添加媒体")
        }
        .padding(.top, 7)
    }

    private func stagedTile(_ item: Media) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            MediaThumbnail(media: item)
                .frame(width: 82, height: 44)
                .clipShape(.rect(cornerRadius: 6))
                .overlay(alignment: .topTrailing) {
                    Button {
                        staged.removeAll { $0.id == item.id }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Color.libraryInk)
                            .frame(width: 20, height: 20)
                            .background(.white, in: Circle())
                            .overlay { Circle().strokeBorder(Color.libraryInk.opacity(0.12)) }
                    }
                    .buttonStyle(.plain)
                    .padding(2)
                    .accessibilityLabel("移除\(item.name)")
                }
            Text(item.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(item.directories.joined(separator: " / ") + " / " + item.name)
        }
        .frame(width: 82, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .accessibilityAddTraits(.updatesFrequently)
            }

            Spacer(minLength: 4)

            Button("取消") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(saving)
            Button(saving ? "正在添加…" : "确认添加", action: confirm)
                .buttonStyle(.borderedProminent)
                .tint(.ipreviewAccent)
                .keyboardShortcut(.defaultAction)
                .disabled(staged.isEmpty || saving)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .frame(minHeight: 40)
    }

    private func tile(_ item: Media, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            MediaThumbnail(media: item)
                .aspectRatio(1.66, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(selected ? Color.ipreviewAccent : .clear, lineWidth: 2)
                }
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white, Color.ipreviewAccent)
                            .padding(5)
                            .accessibilityHidden(true)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if item.kind == .video {
                        Image(systemName: "play.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(.black.opacity(0.58), in: Circle())
                            .padding(5)
                            .accessibilityHidden(true)
                    }
                }
            Text(item.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
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
                error = "有选中的媒体已不可用。请从待添加栏移除后重试。"
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
