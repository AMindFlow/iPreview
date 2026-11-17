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

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                navigationPane(folders)

                Divider()

                VStack(spacing: 0) {
                    Text("添加到「\(album.name)」")
                        .font(.system(size: 21, weight: .semibold))
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                        .help(album.name)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 17)
                        .frame(height: 53)

                    Divider()

                    HStack(spacing: 0) {
                        candidatePane(candidates, stagedIDs: stagedIDs, remaining: remaining,
                                      title: folders.first(where: { $0.id == requestedFolder })?.title ?? "媒体")
                        Divider()
                        stagedPane
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .disabled(saving)

            Divider()

            footer
        }
        .foregroundStyle(Color.libraryInk)
        .background(Color.libraryCanvas)
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

    private func navigationPane(_ folders: [(id: LibraryPage, title: String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            navigationHeading("来源与创作者")
            List(selection: $creator) {
                ForEach(creators, id: \.id) { item in
                    HStack(spacing: 7) {
                        Image(systemName: item.source.layout == .multiCreator ? "person" : "externaldrive")
                            .frame(width: 15)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).lineLimit(1)
                            if item.source.layout == .multiCreator {
                                Text(item.source.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .help(item.source.path)
                    .accessibilityHint(item.source.path)
                    .tag(item.id)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .accessibilityLabel("来源与创作者")
            .frame(height: CGFloat(min(max(creators.count, 1), 4)) * 40)

            Divider().padding(.horizontal, 13)

            navigationHeading("专辑")
            List(selection: $folder) {
                ForEach(folders, id: \.id) { item in
                    Label(item.title, systemImage: "folder")
                        .lineLimit(1)
                        .tag(item.id)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .accessibilityLabel("来源专辑")
        }
        .frame(width: 157)
        .background(Color.mediaSurface.opacity(0.47))
    }

    private func navigationHeading(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 14)
            .padding(.top, 13)
            .padding(.bottom, 4)
    }

    private func candidatePane(_ candidates: [Media], stagedIDs: Set<Int64>, remaining: [Media],
                               title: String) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if !candidates.isEmpty {
                    Text("\(candidates.count) 项")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button("全选") { staged.append(contentsOf: remaining) }
                    .controlSize(.small)
                    .accessibilityLabel("全选当前专辑")
                    .help("全选当前专辑")
                    .disabled(remaining.isEmpty)
            }
            if candidates.isEmpty {
                Text(emptyMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 11) {
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
                            .accessibilityValue(item.kind == .video ? "视频" : "图片")
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    .padding(.bottom, 2)
                }
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.56))
    }

    private var stagedPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("待添加")
                    .font(.headline)
                Text(staged.count, format: .number)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.ipreviewAccent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.ipreviewAccent.opacity(0.12), in: Capsule())
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            if staged.isEmpty {
                Text("尚未选择媒体")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(staged) { item in
                        HStack(spacing: 7) {
                            MediaThumbnail(media: item)
                                .frame(width: 40, height: 29)
                                .clipShape(.rect(cornerRadius: 6))

                            Text(item.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .layoutPriority(1)
                                .help(item.directories.joined(separator: " / ") + " / " + item.name)
                            Spacer(minLength: 0)

                            Button {
                                staged.removeAll { $0.id == item.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary, Color.libraryInk.opacity(0.08))
                                    .frame(width: 22, height: 26)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("移除\(item.name)")
                        }
                        .font(.callout)
                        .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .accessibilityLabel("待添加媒体")
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 13)
        .frame(width: 190)
        .frame(maxHeight: .infinity, alignment: .topLeading)
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
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .frame(minHeight: 49)
    }

    private func tile(_ item: Media, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            MediaThumbnail(media: item)
                .aspectRatio(1.57, contentMode: .fit)
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
