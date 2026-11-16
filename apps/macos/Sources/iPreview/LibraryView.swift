import AppKit
import SwiftUI
import iPreviewCore

struct LibraryView: View {
    @ViewState private var model = LibraryModel()
    @ViewState private var page = LibraryPage.library
    @ViewState private var selected: Int64?
    @ViewState private var query = ""
    @ViewState private var mode = MatchMode.fuzzy
    @ViewState private var searchDirectories = true
    @ViewState private var searchFiles = true
    @ViewState private var matches: [Media] = []
    @ViewState private var filtersShown = false
    @ViewState private var editAlbum: AlbumEdit?
    @ViewState private var preview: PreviewRequest?
    @FocusState private var focus: Focus?

    private enum Focus: Hashable { case gallery, search }
    private var searching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        @Bindable var model = model
        let scope = ContentScope(page: page, snapshot: model.snapshot, matches: searching ? matches : nil)

        ZStack {
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 188)
                Rectangle()
                    .fill(Color.libraryInk.opacity(0.07))
                    .frame(width: 1)
                VStack(alignment: .leading, spacing: 0) {
                    header(scope)
                    content(scope)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.libraryCanvas)
            }
            .allowsHitTesting(preview == nil)
            .accessibilityHidden(preview != nil)

            if let preview {
                MediaPreview(request: preview) {
                    self.preview = nil
                    focusGallery()
                }
                .id(preview.selection)
                .transition(.opacity)
            }
        }
        .background(Color.libraryCanvas)
        .task { await model.start() }
        .task(id: SearchRequest(query: query, mode: mode, directories: searchDirectories, files: searchFiles, revision: model.revision)) {
            let index = model.searchIndex
            let request = SearchRequest(query: query, mode: mode, directories: searchDirectories, files: searchFiles, revision: model.revision)
            let result = await Task.detached(priority: .userInitiated) {
                index.search(request.query, mode: request.mode, directories: request.directories, files: request.files)
            }.value
            if !Task.isCancelled { matches = result }
        }
        .sheet(item: $model.inspection) { inspection in
            ImportSheet(inspection: inspection) { candidate in
                Task {
                    await model.register(inspection, candidate: candidate)
                    if let imported = model.snapshot.sources.first(where: { $0.path == inspection.root.path }) {
                        navigate(.source(imported.id))
                    }
                }
            }
        }
        .sheet(item: $editAlbum) { edit in
            AlbumSheet(edit: edit) { name in
                Task {
                    if let albumID = edit.idToRename {
                        await model.rename(albumID: albumID, to: name)
                    } else if let id = await model.createAlbum(named: name, with: edit.firstMediaID) {
                        navigate(.virtual(id))
                    }
                }
            }
        }
        .alert("无法完成操作", isPresented: Binding(
            get: { model.error != nil },
            set: { if !$0 { model.error = nil } }
        )) {
            Button("好") { model.error = nil }
        } message: {
            Text(model.error ?? "")
        }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                sidebarRow("媒体库", icon: "photo.on.rectangle.angled", active: page == .library && !searching) {
                    navigate(.library)
                }
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Label("来源", systemImage: "folder")
                        Spacer()
                        Button(action: chooseFolder) {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                        .disabled(model.isWorking)
                        .accessibilityLabel("导入文件夹")
                        .help("导入文件夹")
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 32)
                    .foregroundStyle(.secondary)

                    ForEach(model.snapshot.sources) { source in
                        sidebarRow(source.name, icon: source.isAvailable ? "externaldrive" : "externaldrive.badge.xmark",
                                   active: page.sourceID == source.id && !searching) {
                            navigate(.source(source.id))
                        }
                        .help(source.path)
                        .contextMenu {
                            Button("重新扫描") { Task { await model.rescan(source) } }
                                .disabled(model.isWorking)
                        }
                    }
                }
                .padding(.top, 11)

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Label("虚拟专辑", systemImage: "square.stack")
                        Spacer()
                        Button {
                            editAlbum = AlbumEdit()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                        .disabled(model.isWorking)
                        .accessibilityLabel("新建虚拟专辑")
                        .help("新建虚拟专辑")
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 32)
                    .foregroundStyle(.secondary)

                    ForEach(model.snapshot.albums) { album in
                        sidebarRow(album.name, icon: "rectangle.stack", active: page == .virtual(album.id) && !searching) {
                            navigate(.virtual(album.id))
                        }
                        .contextMenu {
                            Button("重命名专辑") { editAlbum = AlbumEdit(album: album) }
                                .disabled(model.isWorking)
                        }
                    }
                }
                .padding(.top, 11)
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.top, 49)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .background {
            Color.libraryCanvas
                .overlay(Color.ipreviewAccent.opacity(0.035))
        }
        .background(.regularMaterial)
        .accessibilityLabel("媒体库导航")
    }

    private func sidebarRow(_ name: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .frame(width: 17)
                    .foregroundStyle(active ? Color.ipreviewAccent : Color.libraryInk.opacity(0.68))
                Text(name)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .fontWeight(active ? .semibold : .medium)
            .foregroundStyle(Color.libraryInk)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(active ? Color.ipreviewAccent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func header(_ scope: ContentScope) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                if !searching, case .folder(let sourceID, _) = page {
                    Button { navigate(.source(sourceID)) } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("返回来源")
                    .help("返回来源")
                }
                Text(scope.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.libraryInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityAddTraits(.isHeader)
                if let source = scope.source, !source.isAvailable {
                    Label("离线", systemImage: "externaldrive.badge.xmark")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                searchField
                    .frame(idealWidth: 265, maxWidth: 310)
                Button(action: chooseFolder) {
                    Label("导入", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .keyboardShortcut("o", modifiers: .command)
                .disabled(model.isWorking)
                .help("导入本地媒体目录")
            }

            if searching || scope.source != nil || scope.virtualAlbum != nil || selected != nil {
                HStack(spacing: 10) {
                    Text(scope.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 6)
                    if let source = scope.source {
                        Button {
                            Task { await model.rescan(source) }
                        } label: {
                            Label("重新扫描", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .disabled(model.isWorking)
                    }
                    if let album = scope.virtualAlbum {
                        Button {
                            editAlbum = AlbumEdit(album: album)
                        } label: {
                            Label("重命名", systemImage: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .disabled(model.isWorking)
                    }
                    if let media = scope.items.first(where: { $0.id == selected }) {
                        Menu {
                            mediaActions(media, in: scope.virtualAlbum)
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(width: 25)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .accessibilityLabel("所选媒体的操作")
                        .disabled(model.isWorking)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 43)
        .padding(.bottom, 21)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("搜索媒体", text: $query)
                .textFieldStyle(.plain)
                .focused($focus, equals: .search)
                .accessibilityIdentifier("library-search")
                .onSubmit { focusGallery() }
            if !query.isEmpty {
                Button {
                    query = ""
                    focus = .search
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("清除搜索")
            }
            Button {
                filtersShown.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("搜索筛选")
            .help("搜索模式和范围")
            .popover(isPresented: $filtersShown, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 13) {
                    Picker("搜索模式", selection: $mode) {
                        ForEach(MatchMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Toggle("目录名", systemImage: "folder", isOn: $searchDirectories)
                        .toggleStyle(.switch)
                    Toggle("文件名", systemImage: "doc", isOn: $searchFiles)
                        .toggleStyle(.switch)
                }
                .controlSize(.small)
                .frame(width: 200)
                .padding(15)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(focus == .search ? Color.ipreviewAccent : Color.libraryInk.opacity(0.10))
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func content(_ scope: ContentScope) -> some View {
        if !scope.folders.isEmpty {
            folderGallery(scope.folders)
        } else if !scope.items.isEmpty {
            mediaGallery(scope.items, in: scope.virtualAlbum)
        } else if model.isWorking {
            ProgressView()
                .accessibilityLabel("正在读取媒体库")
        } else if searching {
            ContentUnavailableView("没有匹配媒体", systemImage: "magnifyingglass", description: Text("调整关键词或搜索范围。"))
        } else if scope.virtualAlbum != nil {
            ContentUnavailableView("专辑为空", systemImage: "rectangle.stack",
                                   description: Text("在媒体库选中媒体，再用「加入虚拟专辑」添加。"))
        } else if scope.source != nil {
            ContentUnavailableView("没有可显示的媒体", systemImage: "photo.on.rectangle")
        } else {
            ContentUnavailableView {
                Label("媒体库为空", systemImage: "photo.on.rectangle")
            } description: {
                Text("导入包含图片或视频的文件夹。")
            } actions: {
                Button("导入文件夹", action: chooseFolder)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
            }
        }
    }

    private func folderGallery(_ folders: [FolderAlbum]) -> some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVGrid(columns: columns(for: geometry.size.width), alignment: .leading, spacing: 18) {
                    ForEach(folders) { folder in
                        Button {
                            navigate(.folder(folder.cover.source.id, folder.id))
                            focusGallery()
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                MediaThumbnail(media: folder.cover)
                                    .aspectRatio(1.47, contentMode: .fit)
                                    .clipShape(.rect(cornerRadius: 12))
                                Text(folder.name)
                                    .font(.callout.weight(.semibold))
                                    .lineLimit(1)
                                Text("\(folder.creator) · \(folder.count) 项")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .foregroundStyle(Color.libraryInk)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    private func mediaGallery(_ items: [Media], in album: VirtualAlbum?) -> some View {
        GeometryReader { geometry in
            let columns = columns(for: geometry.size.width)
            ScrollViewReader { reader in
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        ForEach(items) { item in
                            MediaTile(media: item, selected: selected == item.id, showPath: searching)
                                .onTapGesture(count: 2) { open(item, among: items, columns: columns.count) }
                                .onTapGesture {
                                    selected = item.id
                                    focus = .gallery
                                }
                                .contextMenu { mediaActions(item, in: album) }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(item.name)
                                .accessibilityValue(item.isAvailable ? item.directories.joined(separator: "，") : "不可用")
                                .accessibilityAddTraits(selected == item.id ? [.isButton, .isSelected] : .isButton)
                                .accessibilityAction { open(item, among: items, columns: columns.count) }
                                .id(item.id)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
                .focusable()
                .focusEffectDisabled()
                .focused($focus, equals: .gallery)
                .onKeyPress(keys: [.space, .leftArrow, .rightArrow, .upArrow, .downArrow], phases: [.down, .repeat]) { press in
                    let index = items.firstIndex(where: { $0.id == selected }) ?? 0
                    if press.key == .space {
                        if press.phase == .down { open(items[index], among: items, columns: columns.count) }
                    } else {
                        let next = moveIndex(index, key: press.key, columns: columns.count, count: items.count)
                        selected = items[next].id
                        reader.scrollTo(items[next].id, anchor: .center)
                    }
                    return .handled
                }
                .onChange(of: items.map(\.id), initial: true) { _, ids in
                    if let selected, ids.contains(selected) { return }
                    selected = ids.first
                }
            }
        }
    }

    @ViewBuilder
    private func mediaActions(_ media: Media, in album: VirtualAlbum?) -> some View {
        if let album {
            let position = album.mediaIDs.firstIndex(of: media.id)
            Button("上移") { Task { await model.move(mediaID: media.id, in: album.id, by: -1) } }
                .disabled(position == album.mediaIDs.indices.first)
            Button("下移") { Task { await model.move(mediaID: media.id, in: album.id, by: 1) } }
                .disabled(position == album.mediaIDs.indices.last)
            Divider()
            Button("从专辑移除", role: .destructive) {
                Task { await model.remove(mediaID: media.id, from: album.id) }
            }
        } else {
            Menu("加入虚拟专辑") {
                ForEach(model.snapshot.albums) { album in
                    Button(album.name) { Task { await model.add(mediaID: media.id, to: album.id) } }
                        .disabled(album.mediaIDs.contains(media.id))
                }
                if !model.snapshot.albums.isEmpty { Divider() }
                Button("新建专辑并添加…") { editAlbum = AlbumEdit(firstMediaID: media.id) }
            }
        }
    }

    private func columns(for width: CGFloat) -> [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 148), spacing: 15), count: max(1, Int((width - 33) / 230)))
    }

    private func chooseFolder() {
        guard !model.isWorking else { return }
        let picker = NSOpenPanel()
        picker.title = "导入媒体目录"
        picker.prompt = "扫描"
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.canCreateDirectories = false
        picker.allowsMultipleSelection = false
        if let window = NSApp.keyWindow {
            picker.beginSheetModal(for: window) { answer in
                if answer == .OK, let url = picker.url {
                    Task { await model.inspect(url) }
                }
            }
        } else {
            picker.begin { answer in
                if answer == .OK, let url = picker.url {
                    Task { await model.inspect(url) }
                }
            }
        }
    }

    private func navigate(_ page: LibraryPage) {
        self.page = page
        query = ""
        selected = nil
    }

    private func open(_ item: Media, among items: [Media], columns: Int) {
        selected = item.id
        preview = PreviewRequest(items: items, selection: item.id, columns: columns)
    }

    private func focusGallery() {
        Task { @MainActor in
            await Task.yield()
            focus = .gallery
        }
    }
}

private struct SearchRequest: Equatable {
    let query: String
    let mode: MatchMode
    let directories: Bool
    let files: Bool
    let revision: Int
}

private enum LibraryPage: Hashable {
    case library
    case source(Int64)
    case folder(Int64, String)
    case virtual(Int64)

    var sourceID: Int64? {
        switch self {
        case .source(let id), .folder(let id, _): id
        case .library, .virtual: nil
        }
    }
}

private struct FolderAlbum: Identifiable {
    let id: String
    let cover: Media
    let count: Int

    var name: String { cover.album }
    var creator: String { cover.creator }
}

private struct ContentScope {
    let title: String
    let items: [Media]
    let folders: [FolderAlbum]
    let source: Source?
    let virtualAlbum: VirtualAlbum?

    var subtitle: String {
        if let source { return "\(source.layout.title) · \(folders.isEmpty ? "\(items.count) 项" : "\(folders.count) 个专辑")" }
        return "\(items.count) 项"
    }

    init(page: LibraryPage, snapshot: LibrarySnapshot, matches: [Media]?) {
        if let matches {
            title = "搜索结果"
            items = matches
            folders = []
            source = nil
            virtualAlbum = nil
            return
        }

        let active = snapshot.media.filter(\.existsInSource)
        source = page.sourceID.flatMap { id in snapshot.sources.first { $0.id == id } }
        switch page {
        case .library:
            title = "媒体库"
            items = active
            folders = []
            virtualAlbum = nil
        case .source(let id):
            title = source?.name ?? "来源"
            let sourceItems = active.filter { $0.source.id == id }
            if source?.layout == .flat {
                items = sourceItems
                folders = []
            } else {
                let groups = Dictionary(grouping: sourceItems, by: Self.folderKey)
                var seen: Set<String> = []
                folders = sourceItems.compactMap {
                    let key = Self.folderKey($0)
                    guard seen.insert(key).inserted else { return nil }
                    let members = groups[key]!
                    return FolderAlbum(id: key, cover: members[0], count: members.count)
                }
                items = []
            }
            virtualAlbum = nil
        case .folder(let id, let key):
            items = active.filter { $0.source.id == id && Self.folderKey($0) == key }
            title = items.first?.album ?? key
            folders = []
            virtualAlbum = nil
        case .virtual(let id):
            let album = snapshot.albums.first { $0.id == id }
            let byID = Dictionary(uniqueKeysWithValues: snapshot.media.map { ($0.id, $0) })
            title = album?.name ?? "虚拟专辑"
            items = album?.mediaIDs.compactMap { byID[$0] } ?? []
            folders = []
            virtualAlbum = album
        }
    }

    private static func folderKey(_ media: Media) -> String {
        media.components.dropLast().joined(separator: "/")
    }
}

private struct MediaTile: View {
    let media: Media
    let selected: Bool
    let showPath: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            MediaThumbnail(media: media)
                .aspectRatio(1.47, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(selected ? Color.ipreviewAccent : .clear, lineWidth: 2)
                }
                .overlay(alignment: .bottomLeading) {
                    if media.kind == .video {
                        Image(systemName: "play.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 27, height: 27)
                            .background(.black.opacity(0.55), in: Circle())
                            .padding(8)
                    }
                }
            Text(media.name)
                .font(.caption.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.ipreviewAccent : Color.libraryInk.opacity(0.72))
                .lineLimit(1)
            if showPath {
                Text(media.directories.joined(separator: " / "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .contentShape(Rectangle())
        .help(media.directories.joined(separator: " / ") + " / " + media.name)
    }
}
