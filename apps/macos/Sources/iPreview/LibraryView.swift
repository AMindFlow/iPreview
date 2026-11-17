import AppKit
import SwiftUI
import iPreviewCore

struct LibraryView: View {
    @ViewState private var model = LibraryModel()
    @ViewState private var page = LibraryPage.library
    @ViewState private var selected: Int64?
    @ViewState private var selectedFolder: LibraryPage?
    @ViewState private var browseMode = MediaBrowseMode.icons
    @ViewState private var query = ""
    @ViewState private var mode = MatchMode.fuzzy
    @ViewState private var searchDirectories = true
    @ViewState private var searchFiles = true
    @ViewState private var matches: (request: SearchRequest, items: [Media])?
    @ViewState private var filtersShown = false
    @ViewState private var globalSearchShown = false
    @ViewState private var mediaToReveal: Int64?
    @ViewState private var creatingAlbum = false
    @ViewState private var editSourceName: SourceNameEdit?
    @ViewState private var titleEdit: LibraryTitleEdit?
    @ViewState private var titleDraft = ""
    @ViewState private var titleSelection: TextSelection?
    @ViewState private var addAlbumMedia: VirtualAlbum?
    @ViewState private var removalSelection: Set<Int64>?
    @ViewState private var albumOrder = AlbumOrderDrag()
    @ViewState private var preview: PreviewRequest?
    @FocusState private var focus: Focus?

    enum Focus: Hashable { case browser, search, globalSearchQuery, globalSearchResults, title }
    private var searching: Bool {
        page != .library && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var libraryOverlayShown: Bool { preview != nil || globalSearchShown }
    private var searchActions: LibrarySearchActions {
        let canSearch = preview == nil && titleEdit == nil && editSourceName == nil && !creatingAlbum
            && addAlbumMedia == nil && model.inspection == nil && model.error == nil
        let canSearchCurrent = canSearch && page != .library && !globalSearchShown
        return LibrarySearchActions(focusCurrent: canSearchCurrent ? focusCurrentSearch : nil,
                                    focusGlobal: canSearch ? showGlobalSearch : nil)
    }

    var body: some View {
        @Bindable var model = model
        let request = searching ? SearchRequest(query: query, mode: mode, directories: searchDirectories, files: searchFiles,
                                                revision: model.revision, page: page,
                                                albumMembers: page.virtualMembers(in: model.snapshot)) : nil
        let scope = model.contentScope(for: page, matches: request.map { request in
            if let matches, matches.request == request { matches.items } else { [] }
        })

        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 260)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                header(scope)
                content(scope)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .accessibilityHidden(libraryOverlayShown)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: chooseFolder) {
                        Label("导入", systemImage: "folder.badge.plus")
                    }
                    .keyboardShortcut("o", modifiers: .command)
                    .disabled(model.isWorking || libraryOverlayShown)
                    .help("导入本地媒体目录")
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .focusedSceneValue(\.librarySearchActions, searchActions)
        .overlay {
            if globalSearchShown {
                GlobalSearchPanel(index: model.searchIndex, revision: model.revision, isPreviewing: preview != nil,
                                  focus: $focus,
                                  dismiss: dismissGlobalSearch, open: openSearchResult) { item, results in
                    open(item, among: results, layout: .list)
                }
                .allowsHitTesting(preview == nil)
                .accessibilityHidden(preview != nil)
            }
        }
        .overlayPreferenceValue(PreviewOriginKey.self) { origins in
            if let preview {
                GeometryReader { geometry in
                    let thumbnail: (Int64) -> PreviewThumbnail? = { id in
                        guard !globalSearchShown else { return nil }
                        return origins.thumbnail(for: id, in: geometry)
                    }
                    MediaPreview(request: preview, thumbnail: thumbnail) { selection in
                        self.preview = nil
                        if !globalSearchShown {
                            self.selected = selection
                            if thumbnail(selection) == nil { self.mediaToReveal = selection }
                            focusBrowser()
                        }
                    }
                    .id(preview.selection)
                }
            }
        }
        .task { await model.start() }
        .onChange(of: searching) { removalSelection = nil }
        .task(id: request) {
            guard let request else {
                matches = nil
                return
            }
            let index = model.searchIndex
            let result = await Task.detached(priority: .userInitiated) {
                let members = Set(request.albumMembers)
                return index.search(request.query, mode: request.mode, directories: request.directories, files: request.files) {
                    request.page.contains($0, virtualMembers: members)
                }
            }.value
            if !Task.isCancelled { matches = (request, result) }
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
        .sheet(isPresented: $creatingAlbum, onDismiss: focusBrowser) {
            NewAlbumSheet { name in
                Task {
                    if let id = await model.createAlbum(named: name) {
                        navigate(.virtual(id))
                    }
                }
            }
        }
        .sheet(item: $editSourceName, onDismiss: focusBrowser) { edit in
            SourceNameSheet(edit: edit) { name in
                try await renameSourceItem(edit, to: name)
            }
        }
        .sheet(item: $addAlbumMedia) { album in
            AlbumMediaPicker(album: album, model: model)
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
                HStack(spacing: 3) {
                    sidebarRow("媒体库", icon: "photo.on.rectangle.angled", active: page == .library) {
                        navigate(.library)
                    }
                    Button(action: showGlobalSearch) {
                        Image(systemName: "magnifyingglass")
                            .frame(width: 27, height: 27)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("全局搜索")
                    .accessibilityIdentifier("show-global-search")
                    .help("搜索所有来源（⇧⌘F）")
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
                        sidebarRow(source.name, icon: source.layout.sidebarSymbol,
                                   active: page.sourceID == source.id && !searching,
                                   status: source.isAvailable ? source.layout.title : "\(source.layout.title)，离线",
                                   offline: !source.isAvailable) {
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
                            creatingAlbum = true
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
                    }
                }
                .padding(.top, 11)
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("媒体库导航")
        .accessibilityHidden(libraryOverlayShown)
    }

    private func sidebarRow(_ name: String, icon: String, active: Bool, status: String = "", offline: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .frame(width: 17)
                    .foregroundStyle(active ? Color.ipreviewAccent : Color.libraryInk.opacity(0.68))
                Text(name)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if offline {
                    Image(systemName: "bolt.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .fontWeight(active ? .semibold : .medium)
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(active ? Color.ipreviewAccent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(status)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func header(_ scope: ContentScope) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                if !searching, let parent = page.parent(in: scope.source?.layout) {
                    Button { navigate(parent.page, selecting: page) } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(parent.label)
                    .help(parent.label)
                }
                browserTitle(scope)
                if let source = scope.source, !source.isAvailable {
                    Label("离线", systemImage: "externaldrive.badge.xmark")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if page != .library {
                    searchField
                        .frame(idealWidth: 265, maxWidth: 310)
                }
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
                        virtualAlbumActions(album, hasItems: !scope.items.isEmpty)
                    }
                    if !scope.items.isEmpty {
                        Picker("浏览视图", selection: $browseMode) {
                            ForEach(MediaBrowseMode.allCases) { view in
                                Image(systemName: view.symbol)
                                    .help(view.title)
                                    .accessibilityLabel(view.title)
                                    .tag(view)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .frame(width: 114)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func browserTitle(_ scope: ContentScope) -> some View {
        Group {
            if let edit = titleEdit, page == edit.page {
                TextField(edit.placeholder, text: $titleDraft, selection: $titleSelection)
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .title)
                    .frame(minWidth: 105, idealWidth: 210, maxWidth: 320)
                    .accessibilityIdentifier(edit.controlID + "-name")
                    .background {
                        RenameClickBoundary { finishTitleEdit(edit) }
                            .allowsHitTesting(false)
                    }
                    .task {
                        await Task.yield()
                        focus = .title
                    }
                    .onSubmit {
                        finishTitleEdit(edit)
                        focusBrowser()
                    }
                    .onKeyPress(.escape) {
                        titleEdit = nil
                        focusBrowser()
                        return .handled
                    }
            } else if !model.isWorking, let album = scope.virtualAlbum, removalSelection == nil {
                editableTitle(scope.title, controlID: "virtual-album", hint: "双击标题重命名虚拟专辑") {
                    beginTitleEdit(.album(album))
                }
            } else if !model.isWorking, !searching, let source = scope.source, source.isAvailable,
                      let folder = page.indexedDirectory {
                editableTitle(scope.title, controlID: "source-directory", hint: "双击标题重命名文件夹") {
                    let member = scope.items.first(where: \.isAvailable)
                        ?? scope.folders.first(where: { $0.cover.isAvailable })?.cover
                    beginTitleEdit(.directory(SourceNameEdit(folder: folder, source: source, expectedMember: member)))
                }
            } else {
                Text(scope.title)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .font(.system(size: 28, weight: .bold))
        .lineLimit(1)
        .truncationMode(.tail)
    }

    private func editableTitle(_ title: String, controlID: String, hint: String,
                               start: @escaping () -> Void) -> some View {
        Text(title)
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: start)
            .accessibilityAddTraits([.isHeader, .isButton])
            .accessibilityAction { start() }
            .accessibilityHint(hint)
            .accessibilityIdentifier(controlID + "-title")
            .help(hint)
    }

    @ViewBuilder
    private func virtualAlbumActions(_ album: VirtualAlbum, hasItems: Bool) -> some View {
        if let removalSelection {
            Text("已选 \(removalSelection.count) 项")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("取消") {
                self.removalSelection = nil
                focusBrowser()
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            .disabled(model.isWorking)
            Button("移除引用", role: .destructive) {
                let mediaIDs = Array(removalSelection)
                Task {
                    if await model.remove(mediaIDs: mediaIDs, from: album.id) {
                        self.removalSelection = nil
                        if page == .virtual(album.id), !searching { focusBrowser() }
                    }
                }
            }
            .buttonStyle(.bordered)
            .disabled(removalSelection.isEmpty || model.isWorking)
            .help("仅从当前专辑移除所选引用")
        } else {
            if hasItems {
                Button {
                    addAlbumMedia = album
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("添加媒体")
                .help("添加媒体")
                .disabled(model.isWorking)
                Button("调整") {
                    removalSelection = []
                    focusBrowser()
                }
                .libraryGlassButton()
                .disabled(model.isWorking)
                .help("勾选媒体或按住媒体拖动排序")
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("搜索当前范围", text: $query)
                .textFieldStyle(.plain)
                .focused($focus, equals: .search)
                .accessibilityIdentifier("library-search")
                .onSubmit { focusBrowser() }
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
                LibrarySearchFilters(mode: $mode, directories: $searchDirectories, files: $searchFiles)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .libraryGlassSurface()
    }

    @ViewBuilder
    private func content(_ scope: ContentScope) -> some View {
        if !scope.folders.isEmpty {
            folderGallery(scope.folders, sourceLayout: scope.source?.layout)
        } else if !scope.items.isEmpty {
            mediaGallery(scope.items, in: scope.virtualAlbum, sourceLayout: scope.source?.layout)
        } else if model.isWorking {
            ProgressView()
                .accessibilityLabel("正在读取媒体库")
        } else if searching {
            ContentUnavailableView("没有匹配媒体", systemImage: "magnifyingglass", description: Text("调整关键词或搜索范围。"))
        } else if let album = scope.virtualAlbum {
            VStack(spacing: 14) {
                Button {
                    addAlbumMedia = album
                } label: {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 35, weight: .light))
                        .foregroundStyle(Color.libraryInk.opacity(0.64))
                        .frame(width: 74, height: 70)
                        .background(Color.mediaSurface.opacity(0.48), in: RoundedRectangle(cornerRadius: 15))
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(.white, Color.ipreviewAccent)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("添加媒体")
                .help("添加媒体")
                Text("专辑为空").font(.title3.weight(.semibold))
            }
        } else if scope.source != nil {
            ContentUnavailableView("没有可显示的媒体", systemImage: "photo.on.rectangle")
                .focusable(page.parent(in: scope.source?.layout) != nil)
                .focusEffectDisabled()
                .focused($focus, equals: .browser)
                .onKeyPress(keys: [.escape], phases: [.down, .repeat]) { press in
                    backKey(press, sourceLayout: scope.source?.layout)
                }
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

    private func folderGallery(_ folders: [LibraryFolder], sourceLayout: iPreviewCore.Layout?) -> some View {
        GeometryReader { geometry in
            let grid = columns(for: geometry.size.width)
            let layout = BrowseLayout.grid(columns: grid.count)
            ScrollViewReader { reader in
                ScrollView {
                    LazyVGrid(columns: grid, alignment: .leading, spacing: 18) {
                        ForEach(folders) { folder in
                            folderCard(folder)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
                .focusable()
                .focusEffectDisabled()
                .focused($focus, equals: .browser)
                .onKeyPress(keys: [.space, .return, .escape, .leftArrow, .rightArrow, .upArrow, .downArrow],
                            phases: [.down, .repeat]) { press in
                    if press.key == .escape { return backKey(press, sourceLayout: sourceLayout) }

                    let index = folders.firstIndex(where: { $0.page == selectedFolder }) ?? 0
                    if press.key == .space {
                        if press.phase == .down { navigate(folders[index].page) }
                    } else if press.key == .return {
                        if press.phase == .down { beginRename(SourceNameEdit(folder: folders[index])) }
                    } else if let destination = layout.neighbor(of: index, toward: press.key, count: folders.count) {
                        let folder = folders[destination].page
                        selectedFolder = folder
                        reader.scrollTo(folder, anchor: .center)
                    }
                    return .handled
                }
                .onChange(of: folders.map(\.page), initial: true) { _, visibleFolders in
                    if let selectedFolder, visibleFolders.contains(selectedFolder) {
                        reader.scrollTo(selectedFolder, anchor: .center)
                    } else {
                        selectedFolder = visibleFolders.first
                    }
                }
            }
        }
    }

    private func folderCard(_ folder: LibraryFolder) -> some View {
        let isSelected = selectedFolder == folder.page
        return Button { navigate(folder.page) } label: {
            VStack(alignment: .leading, spacing: 5) {
                MediaThumbnail(media: folder.cover, revision: model.revision)
                    .aspectRatio(1.47, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(isSelected ? Color.ipreviewAccent : .clear, lineWidth: 2)
                    }
                Text(folder.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(folder.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .foregroundStyle(Color.libraryInk)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .id(folder.page)
    }

    private func mediaGallery(_ items: [Media], in album: VirtualAlbum?, sourceLayout: iPreviewCore.Layout?) -> some View {
        GeometryReader { geometry in
            let grid = columns(for: geometry.size.width)
            let layout = browseMode.layout(gridColumns: grid.count)
            ScrollViewReader { reader in
                mediaBrowser(items, album: album, grid: grid, layout: layout)
                    .albumOrderOverlay(albumOrder)
                    .focusable()
                    .focusEffectDisabled()
                    .focused($focus, equals: .browser)
                    .onKeyPress(keys: [.space, .return, .escape, .leftArrow, .rightArrow, .upArrow, .downArrow],
                                phases: [.down, .repeat]) { press in
                        if press.key == .escape {
                            if albumOrder.cancel() { return .handled }
                            if removalSelection != nil {
                                if press.phase == .down, !model.isWorking { removalSelection = nil }
                                return .handled
                            }
                            return backKey(press, sourceLayout: sourceLayout)
                        }
                        if albumOrder.drag != nil { return .handled }

                        let index = items.firstIndex(where: { $0.id == selected }) ?? 0
                        if press.key == .space {
                            if press.phase == .down {
                                if removalSelection == nil {
                                    open(items[index], among: items, layout: layout)
                                } else {
                                    toggleRemoval(items[index].id)
                                }
                            }
                        } else if press.key == .return {
                            if press.phase == .down, removalSelection == nil, selected == items[index].id {
                                beginRename(SourceNameEdit(media: items[index]))
                            }
                        } else if let destination = layout.neighbor(of: index, toward: press.key, count: items.count) {
                            selected = items[destination].id
                            reader.scrollTo(items[destination].id, anchor: .center)
                        }
                        return .handled
                    }
                    .onChange(of: items, initial: true) { _, updated in
                        if let selected, updated.contains(where: { $0.id == selected }) { return }
                        selected = updated.first?.id
                    }
                    .task(id: mediaToReveal) {
                        guard let target = mediaToReveal, items.contains(where: { $0.id == target }) else { return }
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        reader.scrollTo(target, anchor: .center)
                        mediaToReveal = nil
                    }
                    .onChange(of: browseMode) {
                        if let selected {
                            Task { @MainActor in
                                await Task.yield()
                                reader.scrollTo(selected, anchor: .center)
                            }
                        }
                        focusBrowser()
                    }
            }
        }
    }

    @ViewBuilder
    private func mediaBrowser(_ items: [Media], album: VirtualAlbum?, grid: [GridItem], layout: BrowseLayout) -> some View {
        switch browseMode {
        case .icons:
            ScrollView {
                LazyVGrid(columns: grid, alignment: .leading, spacing: 16) {
                    ForEach(items) { item in
                        browseItem(item, among: items, album: album, layout: layout) {
                            MediaTile(media: item, revision: model.revision, selected: isMediaSelected(item.id),
                                      showPath: searching, checked: removalSelection?.contains(item.id) == true)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .previewScrollViewport()
            .albumOrderViewport(albumOrder, album: album)
        case .list:
            VStack(spacing: 0) {
                MediaListColumns {
                    Text("名称").padding(.leading, 33)
                } modified: {
                    Text("修改日期")
                } size: {
                    Text("大小")
                } kind: {
                    Text("种类")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(height: 25)
                .padding(.horizontal, 24)
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            browseItem(item, among: items, album: album, layout: layout) {
                                MediaListRow(media: item, revision: model.revision, selected: isMediaSelected(item.id),
                                             shaded: !index.isMultiple(of: 2), showPath: searching,
                                             checked: removalSelection?.contains(item.id) == true)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 6)
                }
                .previewScrollViewport()
                .albumOrderViewport(albumOrder, album: album)
            }
        case .gallery:
            VStack(spacing: 10) {
                if let item = items.first(where: { $0.id == selected }) ?? items.first {
                    InlineGalleryImage(media: item, revision: model.revision)
                        .id(item.id)
                }
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 9) {
                        ForEach(items) { item in
                            browseItem(item, among: items, album: album, layout: layout) {
                                MediaTile(media: item, revision: model.revision, selected: isMediaSelected(item.id),
                                          showPath: searching, checked: removalSelection?.contains(item.id) == true)
                                    .frame(width: 94)
                            }
                        }
                    }
                    .padding(.vertical, 5)
                }
                .frame(height: searching ? 101 : 88)
                .previewScrollViewport()
                .albumOrderViewport(albumOrder, album: album)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private func browseItem<Label: View>(_ item: Media, among items: [Media], album: VirtualAlbum?, layout: BrowseLayout,
                                        @ViewBuilder label: () -> Label) -> some View {
        let adjusting = removalSelection != nil
        let click: (Int) -> Void = { count in
            selected = item.id
            focus = .browser
            if adjusting {
                toggleRemoval(item.id)
            } else if count == 2 {
                open(item, among: items, layout: layout)
            }
        }
        let avatar = label()
        let cell = avatar
            .overlay {
                if removalSelection != nil, selected == item.id, focus == .browser {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.ipreviewAccent, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .contextMenu {
                if let album, removalSelection == nil {
                    Button("从专辑移除", role: .destructive) {
                        Task { await model.remove(mediaID: item.id, from: album.id) }
                    }
                    .disabled(model.isWorking)
                }
            }
            .help(item.directories.joined(separator: " / ") + " / " + item.name)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.name)
            .accessibilityValue(item.isAvailable ? item.directories.joined(separator: "，") : "不可用")
            .accessibilityAddTraits(isMediaSelected(item.id) ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction {
                if removalSelection != nil {
                    selected = item.id
                    toggleRemoval(item.id)
                } else {
                    open(item, among: items, layout: layout)
                }
            }
            .id(item.id)
        if let album, album.mediaIDs.count > 1 {
            let canReorder = adjusting && !model.isWorking && !searching
            AlbumOrderItem(order: albumOrder, album: album, item: item, mode: browseMode, adjusting: adjusting,
                           canReorder: canReorder, content: cell, avatar: avatar, click: click) {
                selected = item.id
                focus = .browser
            } commit: { expected, position in
                Task { await model.move(mediaID: item.id, in: expected, to: position) }
            }
            .accessibilityActions {
                if canReorder {
                    if item.id != album.mediaIDs.first {
                        Button("上移") {
                            Task { await model.move(mediaID: item.id, in: album.id, by: -1) }
                        }
                    }
                    if item.id != album.mediaIDs.last {
                        Button("下移") {
                            Task { await model.move(mediaID: item.id, in: album.id, by: 1) }
                        }
                    }
                }
            }
        } else {
            cell
                .overlay {
                    MediaTileClick(adjusting: adjusting, onClick: click)
                        .accessibilityHidden(true)
                }
        }
    }

    private func isMediaSelected(_ mediaID: Int64) -> Bool {
        removalSelection?.contains(mediaID) ?? (selected == mediaID)
    }

    private func toggleRemoval(_ mediaID: Int64) {
        guard var selection = removalSelection, !model.isWorking else { return }
        if !selection.insert(mediaID).inserted {
            selection.remove(mediaID)
        }
        removalSelection = selection
    }

    private func columns(for width: CGFloat) -> [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 148), spacing: 15), count: max(1, Int((width - 33) / 230)))
    }

    private func chooseFolder() {
        guard !model.isWorking, preview == nil, !globalSearchShown else { return }
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

    private func navigate(_ page: LibraryPage, selecting folder: LibraryPage? = nil, selectingMedia mediaID: Int64? = nil) {
        self.page = page
        removalSelection = nil
        query = ""
        selected = mediaID
        mediaToReveal = mediaID
        selectedFolder = folder
        focusBrowser()
    }

    private func focusCurrentSearch() {
        focus = .search
    }

    private func showGlobalSearch() {
        if globalSearchShown {
            focus = .globalSearchQuery
        } else {
            focus = nil
            globalSearchShown = true
        }
    }

    private func dismissGlobalSearch() {
        globalSearchShown = false
        focusBrowser()
    }

    private func openSearchResult(_ result: GlobalSearchResult) {
        globalSearchShown = false
        switch result {
        case .directory(let directory):
            navigate(.directory(directory))
        case .file(let item):
            let key = ContentScope.folderKey(item)
            let destination = key.isEmpty ? LibraryPage.source(item.source.id) : .folder(item.source.id, key)
            navigate(destination, selectingMedia: item.id)
        }
    }

    private func backKey(_ press: KeyPress, sourceLayout: iPreviewCore.Layout?) -> KeyPress.Result {
        guard preview == nil, !searching, let parent = page.parent(in: sourceLayout) else { return .ignored }
        if press.phase == .down { navigate(parent.page, selecting: page) }
        return .handled
    }

    private func beginTitleEdit(_ target: LibraryTitleEdit.Target) {
        let edit = LibraryTitleEdit(page: page, target: target)
        titleDraft = edit.name
        titleSelection = TextSelection(range: titleDraft.startIndex..<titleDraft.endIndex)
        titleEdit = edit
    }

    private func finishTitleEdit(_ edit: LibraryTitleEdit) {
        guard titleEdit?.id == edit.id else { return }
        titleEdit = nil
        let name = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != edit.name else { return }
        Task {
            switch edit.target {
            case .album(let album):
                await model.rename(albumID: album.id, to: name)
            case .directory(let source):
                do {
                    try await renameSourceItem(source, to: name)
                } catch {
                    model.error = error.localizedDescription
                }
            }
        }
    }

    private func renameSourceItem(_ edit: SourceNameEdit, to name: String) async throws {
        let path = try await model.renameSourceItem(edit, to: name)
        guard let folder = edit.folder else {
            selected = edit.mediaID
            return
        }
        if let updatedPage = page.renamedDirectory(in: edit, to: path) {
            page = updatedPage
            selectedFolder = selectedFolder?.renamedDirectory(in: edit, to: path) ?? selectedFolder
        } else if page == folder.parent(in: edit.source.layout)?.page,
                  selectedFolder == folder {
            selectedFolder = folder.renamedDirectory(in: edit, to: path)
        }
    }

    private func beginRename(_ edit: SourceNameEdit) {
        guard !model.isWorking, preview == nil else { return }
        guard edit.source.isAvailable,
              edit.mediaID == nil || model.snapshot.media.contains(where: { $0.id == edit.mediaID && $0.isAvailable }) else {
            model.error = SourceRenameError.unavailable.localizedDescription
            return
        }
        editSourceName = edit
    }

    private func open(_ item: Media, among items: [Media], layout: BrowseLayout) {
        guard !model.isWorking else { return }
        if !globalSearchShown { selected = item.id }
        preview = PreviewRequest(items: items, selection: item.id, layout: layout)
    }

    private func focusBrowser() {
        Task { @MainActor in
            await Task.yield()
            focus = .browser
        }
    }
}

private struct SearchRequest: Equatable, Sendable {
    let query: String
    let mode: MatchMode
    let directories: Bool
    let files: Bool
    let revision: Int
    let page: LibraryPage
    let albumMembers: [Int64]
}

enum LibraryPage: Hashable, Sendable {
    case library
    case source(Int64)
    case creator(Int64, String)
    case folder(Int64, String)
    case virtual(Int64)

    static func directory(_ directory: IndexedDirectory) -> Self {
        let id = directory.source.id
        let path = directory.relativePath
        if path.isEmpty { return .source(id) }
        if directory.source.layout == .multiCreator && !path.contains("/") { return .creator(id, path) }
        return .folder(id, path)
    }

    func virtualMembers(in snapshot: LibrarySnapshot) -> [Int64] {
        guard case .virtual(let id) = self else { return [] }
        return snapshot.albums.first { $0.id == id }?.mediaIDs ?? []
    }

    func contains(_ item: Media, virtualMembers: Set<Int64> = []) -> Bool {
        switch self {
        case .library: false
        case .source(let id): item.source.id == id
        case .creator(let id, let name): item.source.id == id && item.creator == name
        case .folder(let id, let key): item.source.id == id && ContentScope.folderKey(item) == key
        case .virtual: virtualMembers.contains(item.id)
        }
    }

    var sourceID: Int64? {
        switch self {
        case .source(let id), .creator(let id, _), .folder(let id, _): id
        case .library, .virtual: nil
        }
    }

    func parent(in layout: iPreviewCore.Layout?) -> (page: LibraryPage, label: String)? {
        switch self {
        case .creator(let id, _):
            return (.source(id), "返回来源")
        case .folder(let id, let key):
            if layout == .multiCreator, let creator = key.split(separator: "/").first {
                return (.creator(id, String(creator)), "返回创作者")
            }
            return (.source(id), "返回来源")
        case .library, .source, .virtual:
            return nil
        }
    }
}

struct LibraryFolder: Identifiable {
    let page: LibraryPage
    let name: String
    let cover: Media
    let caption: String

    var id: LibraryPage { page }
}

struct ContentScope {
    let title: String
    let subtitle: String
    let items: [Media]
    let folders: [LibraryFolder]
    let source: Source?
    let virtualAlbum: VirtualAlbum?

    init(page: LibraryPage, snapshot: LibrarySnapshot, matches: [Media]?) {
        if let matches {
            title = "搜索结果"
            subtitle = "\(matches.count) 项"
            items = matches
            folders = []
            source = nil
            virtualAlbum = nil
            return
        }

        let active = snapshot.media.filter(\.existsInSource)
        let source = page.sourceID.flatMap { id in snapshot.sources.first { $0.id == id } }
        self.source = source
        switch page {
        case .library:
            title = "媒体库"
            items = active
            folders = []
            virtualAlbum = nil
        case .source(let id):
            title = source?.name ?? "来源"
            let sourceItems = active.filter { page.contains($0) }
            switch source?.layout {
            case .multiCreator:
                folders = Self.groupFolders(sourceItems, by: \.creator) { name, members in
                    LibraryFolder(page: .creator(id, name), name: name, cover: members[0],
                                  caption: "\(Set(members.map(\.album)).count) 个专辑")
                }
                items = []
            case .creator:
                folders = Self.albumFolders(sourceItems)
                items = []
            case .flat, nil:
                folders = []
                items = sourceItems
            }
            virtualAlbum = nil
        case .creator(_, let creator):
            title = creator
            items = []
            folders = Self.albumFolders(active.filter { page.contains($0) })
            virtualAlbum = nil
        case .folder(_, let key):
            items = active.filter { page.contains($0) }
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

        if let source {
            let count = switch page {
            case .source where source.layout == .multiCreator: "\(folders.count) 位创作者"
            case .source where source.layout == .creator: "\(folders.count) 个专辑"
            case .creator: "\(folders.count) 个专辑"
            default: "\(items.count) 项"
            }
            subtitle = "\(source.layout.title) · \(count)"
        } else {
            subtitle = "\(items.count) 项"
        }
    }

    private static func albumFolders(_ items: [Media]) -> [LibraryFolder] {
        groupFolders(items, by: folderKey) { key, members in
            let cover = members[0]
            return LibraryFolder(page: .folder(cover.source.id, key), name: cover.album, cover: cover,
                                 caption: "\(cover.creator) · \(members.count) 项")
        }
    }

    private static func groupFolders(_ items: [Media], by key: (Media) -> String,
                                     folder: (String, [Media]) -> LibraryFolder) -> [LibraryFolder] {
        let groups = Dictionary(grouping: items, by: key)
        var seen: Set<String> = []
        return items.compactMap {
            let id = key($0)
            return seen.insert(id).inserted ? folder(id, groups[id]!) : nil
        }
    }

    static func folderKey(_ media: Media) -> String {
        media.components.dropLast().joined(separator: "/")
    }
}

private struct MediaTile: View {
    let media: Media
    let revision: Int
    let selected: Bool
    let showPath: Bool
    let checked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            MediaThumbnail(media: media, revision: revision, previewCornerRadius: 12)
                .aspectRatio(1.47, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(selected ? Color.ipreviewAccent : .clear, lineWidth: 2)
                }
                .overlay(alignment: .bottomTrailing) {
                    if checked {
                        MediaSelectionMark()
                            .padding(6)
                    }
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
    }
}
