import AppKit
import SwiftUI
import iPreviewCore

struct LibrarySearchActions {
    let show: (@MainActor (LibrarySearchDomain) -> Void)?
}

private struct LibrarySearchActionsKey: FocusedValueKey {
    typealias Value = LibrarySearchActions
}

extension FocusedValues {
    var librarySearchActions: LibrarySearchActions? {
        get { self[LibrarySearchActionsKey.self] }
        set { self[LibrarySearchActionsKey.self] = newValue }
    }
}

struct LibrarySearchCommands: Commands {
    @FocusedValue(\.librarySearchActions) private var actions

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Button("搜索当前范围") { actions?.show?(.current) }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(actions?.show == nil)
            Button("全局搜索") { actions?.show?(.global) }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(actions?.show == nil)
        }
    }
}

enum LibrarySearchDomain: Sendable {
    case current, global

    var title: String { self == .current ? "当前范围" : "全局" }
    var prompt: String { self == .current ? "搜索当前范围" : "搜索所有媒体源" }
}

struct LibrarySearchPanel: View {
    let index: SearchIndex
    let revision: Int
    let page: LibraryPage
    let albumMembers: Set<Int64>
    let domain: LibrarySearchDomain
    let isPreviewing: Bool
    let closingPreviewSelection: Int64?
    let focus: FocusState<LibraryView.Focus?>.Binding
    let switchDomain: () -> Void
    let dismiss: () -> Void
    let open: (GlobalSearchResult) -> Void
    let preview: (Media, [Media]) -> Void

    @ViewState private var query = ""
    @ViewState private var mode = MatchMode.fuzzy
    @ViewState private var selection: GlobalSearchResult?
    @ViewState private var matches: (request: Request, results: [GlobalSearchResult])?
    @ViewState private var scope = Scope.all

    private enum Scope: Sendable { case all, files, directories }

    private struct Request: Equatable, Sendable {
        let query: String
        let mode: MatchMode
        let scope: Scope
        let domain: LibrarySearchDomain
        let page: LibraryPage
        let albumMembers: Set<Int64>
        let revision: Int
    }

    private var request: Request {
        Request(query: query.trimmingCharacters(in: .whitespacesAndNewlines), mode: mode, scope: scope,
                domain: domain, page: page, albumMembers: albumMembers, revision: revision)
    }

    private var results: [GlobalSearchResult] {
        guard let matches, matches.request == request else { return [] }
        return matches.results
    }

    private var highlighted: GlobalSearchResult? {
        guard let first = results.first else { return nil }
        return selection ?? first
    }

    var body: some View {
        let request = request
        ZStack {
            Color.black.opacity(0.18)
                .onTapGesture(perform: dismiss)
                .accessibilityHidden(true)
            surface
                .frame(maxWidth: 585)
                .padding(25)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("library-search-panel")
        .task {
            await Task.yield()
            if !Task.isCancelled { focus.wrappedValue = .searchQuery }
        }
        .onChange(of: isPreviewing) { _, previewing in
            if !previewing { focus.wrappedValue = .searchResults }
        }
        .onChange(of: closingPreviewSelection) { _, mediaID in
            if let mediaID, let result = results.first(where: {
                if case .file(let item) = $0 { return item.id == mediaID }
                return false
            }) {
                selection = result
            }
        }
        .task(id: request) {
            selection = nil
            guard !request.query.isEmpty else {
                matches = nil
                return
            }
            let result = await Task.detached(priority: .userInitiated) {
                index.globalSearch(request.query, mode: request.mode,
                                   directories: request.scope != .files, files: request.scope != .directories) { result in
                    request.domain == .global || request.page.containsSearchResult(result, virtualMembers: request.albumMembers)
                }
            }.value
            if !Task.isCancelled { matches = (request, result) }
        }
    }

    @ViewBuilder
    private var surface: some View {
        if #available(macOS 26, *) {
            panel
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.63), in: .rect(cornerRadius: 25))
                .glassEffect(.regular, in: .rect(cornerRadius: 25))
        } else {
            panel.background(.regularMaterial, in: .rect(cornerRadius: 25))
                .overlay {
                    RoundedRectangle(cornerRadius: 25)
                        .strokeBorder(.quaternary)
                        .allowsHitTesting(false)
                }
                .shadow(color: .black.opacity(0.2), radius: 22, y: 10)
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            queryField
                .padding(.horizontal, 19)
                .padding(.vertical, 16)
            Divider().padding(.horizontal, 14)
            if !request.query.isEmpty {
                if !results.isEmpty {
                    resultsList
                    Divider().padding(.horizontal, 14)
                } else {
                    Text(matches?.request == request ? "没有匹配结果" : "正在搜索…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
            }
            shortcutHints
                .padding(.horizontal, 17)
                .padding(.vertical, 10)
        }
        .contentShape(.rect(cornerRadius: 25))
    }

    private var queryField: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(domain.prompt, text: $query)
                .font(.title2)
                .textFieldStyle(.plain)
                .focused(focus, equals: .searchQuery)
                .accessibilityIdentifier("library-search-query")
                .onSubmit(confirmResult)
                .onKeyPress(keys: [.upArrow, .downArrow, .escape], phases: .down, action: handleKey)
                .onChange(of: query) { _, value in
                    let term = GlobalSearchTerm(value)
                    if mode == .fuzzy, term.mode == .exact, !isComposingQuery {
                        mode = .exact
                        query = term.text
                    }
                }
            if mode == .exact {
                Text("精确匹配")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.13), in: Capsule())
                    .accessibilityIdentifier("library-search-match-mode")
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if !query.isEmpty {
                Button {
                    query = ""
                    focus.wrappedValue = .searchQuery
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
    }

    private var shortcutHints: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Button {
                    if !isComposingQuery { switchDomain() }
                } label: {
                    Text("⌘0 \(domain.title)")
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .foregroundStyle(Color.accentColor)
                        .background(Color.accentColor.opacity(0.15), in: .rect(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("0", modifiers: .command)
                .accessibilityLabel("搜索域：\(domain.title)")
                .help("在当前范围和全局之间切换")
                .disabled(isPreviewing)
                scopeShortcut(.files, key: "1", label: "文件")
                scopeShortcut(.directories, key: "2", label: "目录")
                Spacer()
                Text(mode == .exact ? "Esc 退出精确匹配" : "输入 @ 后按空格精确匹配")
                    .foregroundStyle(.secondary)
            }
            Text(mode == .exact ? "↑ ↓ 选择    ↵ 前往    空格预览" : "↑ ↓ 选择    ↵ 前往    空格预览    Esc 关闭")
                .padding(.leading, 4)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func scopeShortcut(_ target: Scope, key: KeyEquivalent, label: String) -> some View {
        let isActive = scope == target
        return Button {
            scope = isActive ? .all : target
            focus.wrappedValue = .searchQuery
        } label: {
            Text("⌘\(String(key.character)) \(label)")
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .background(isActive ? Color.accentColor.opacity(0.15) : .clear, in: .rect(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: .command)
        .accessibilityLabel("仅搜索\(label)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .help(isActive ? "再次按下以搜索全部" : "仅搜索\(label)")
        .disabled(isPreviewing)
    }

    private var resultsList: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(results) { result in
                        resultRow(result)
                            .id(result)
                    }
                }
                .padding(7)
            }
            .frame(height: CGFloat(min(results.count, 6)) * 44 + 14)
            .focusable()
            .focusEffectDisabled()
            .focused(focus, equals: .searchResults)
            .onKeyPress(keys: [.upArrow, .downArrow, .return, .space, .tab, .escape],
                        phases: [.down, .repeat], action: handleKey)
            .onChange(of: selection) { _, result in
                if let result { reader.scrollTo(result) }
            }
        }
    }

    private func resultRow(_ result: GlobalSearchResult) -> some View {
        let isSelected = result == highlighted
        return Button {
            selection = result
            focus.wrappedValue = .searchResults
        } label: {
            HStack(spacing: 11) {
                Image(systemName: result.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 25)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.name)
                        .font(.callout.weight(isSelected ? .semibold : .regular))
                        .lineLimit(1)
                    Text(result.details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 42)
            .background(isSelected ? Color.accentColor.opacity(0.16) : .clear, in: .rect(cornerRadius: 9))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityAction(named: Text("前往")) { open(result) }
    }

    private func confirmResult() {
        if let highlighted { open(highlighted) }
    }

    private var isComposingQuery: Bool {
        focus.wrappedValue == .searchQuery
            && (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() == true
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        if isComposingQuery { return .ignored }
        switch press.key {
        case .escape:
            if press.phase == .down {
                if mode == .exact {
                    mode = .fuzzy
                    focus.wrappedValue = .searchQuery
                } else {
                    dismiss()
                }
            }
        case .upArrow, .downArrow:
            guard !results.isEmpty else { return .ignored }
            if focus.wrappedValue == .searchQuery {
                selection = press.key == .upArrow ? results.last : results.first
                focus.wrappedValue = .searchResults
            } else if let highlighted, let offset = results.firstIndex(of: highlighted) {
                let next = offset + (press.key == .upArrow ? -1 : 1)
                if results.indices.contains(next) { selection = results[next] }
            }
        case .return:
            if press.phase == .down { confirmResult() }
        case .space:
            if press.phase == .down, case .file(let item) = highlighted {
                let files: [Media] = results.compactMap {
                    if case .file(let item) = $0 { item } else { nil }
                }
                preview(item, files)
            }
        case .tab:
            if press.phase == .down { focus.wrappedValue = .searchQuery }
        default:
            return .ignored
        }
        return .handled
    }
}

private extension LibraryPage {
    func containsSearchResult(_ result: GlobalSearchResult, virtualMembers: Set<Int64>) -> Bool {
        if self == .library { return true }
        switch result {
        case .file(let item):
            return contains(item, virtualMembers: virtualMembers)
        case .directory(let directory):
            guard directory.source.id == sourceID else { return false }
            let path = directory.relativePath
            switch self {
            case .source: return true
            case .creator(_, let creator): return path == creator || path.hasPrefix(creator + "/")
            case .folder(_, let folder): return path == folder
            case .library, .virtual: return false
            }
        }
    }
}

private extension GlobalSearchResult {
    var name: String {
        switch self {
        case .directory(let directory): directory.name
        case .file(let item): item.name
        }
    }

    var path: String {
        switch self {
        case .directory(let directory):
            return directory.relativePath.isEmpty
                ? directory.source.url.deletingLastPathComponent().path
                : directory.components.dropLast().joined(separator: " / ")
        case .file(let item):
            return item.directories.joined(separator: " / ")
        }
    }

    var details: String {
        switch category {
        case .creator: "创作者 · \(path)"
        case .album: "专辑 · \(path)"
        case .file, .directory: path
        }
    }

    var symbol: String {
        switch (self, category) {
        case (.file(let item), _): item.kind == .video ? "film" : "photo"
        case (_, .creator): "person.crop.square"
        case (_, .album): "photo.on.rectangle"
        case (.directory, _): "folder"
        }
    }
}
