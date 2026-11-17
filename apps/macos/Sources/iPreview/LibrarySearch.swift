import AppKit
import SwiftUI
import iPreviewCore

struct LibrarySearchFilters: View {
    @Binding var mode: MatchMode
    @Binding var directories: Bool
    @Binding var files: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Picker("搜索模式", selection: $mode) {
                ForEach(MatchMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Toggle("目录名", systemImage: "folder", isOn: $directories)
                .toggleStyle(.switch)
            Toggle("文件名", systemImage: "doc", isOn: $files)
                .toggleStyle(.switch)
        }
        .controlSize(.small)
        .frame(width: 200)
        .padding(15)
    }
}

struct GlobalSearchPanel: View {
    let index: SearchIndex
    let revision: Int
    let isPreviewing: Bool
    @Binding var mode: MatchMode
    @Binding var directories: Bool
    @Binding var files: Bool
    let dismiss: () -> Void
    let open: (GlobalSearchResult) -> Void
    let preview: (Media, [Media]) -> Void

    @ViewState private var query = ""
    @ViewState private var selection: GlobalSearchResult?
    @ViewState private var matches: (request: Request, results: [GlobalSearchResult])?
    @ViewState private var filtersShown = false
    @FocusState private var focus: Focus?

    private enum Focus: Hashable { case query, results }

    private struct Request: Equatable, Sendable {
        let query: String
        let mode: MatchMode
        let directories: Bool
        let files: Bool
        let revision: Int
    }

    private var request: Request {
        Request(query: query.trimmingCharacters(in: .whitespacesAndNewlines),
                mode: mode, directories: directories, files: files, revision: revision)
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
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)
                .accessibilityHidden(true)
            surface
                .frame(maxWidth: 585)
                .padding(25)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("global-search-panel")
        .task { focus = .query }
        .onChange(of: isPreviewing) { _, previewing in
            if !previewing { focus = .results }
        }
        .task(id: request) {
            selection = nil
            guard !request.query.isEmpty else {
                matches = nil
                return
            }
            let result = await Task.detached(priority: .userInitiated) {
                index.globalSearch(request.query, mode: request.mode, directories: request.directories, files: request.files)
            }.value
            if !Task.isCancelled { matches = (request, result) }
        }
    }

    @ViewBuilder
    private var surface: some View {
        if #available(macOS 26, *) {
            panel.glassEffect(.regular, in: .rect(cornerRadius: 25))
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
            Text("↑ ↓ 选择    ↵ 前往    空格预览    Esc 关闭")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
        }
        .contentShape(.rect(cornerRadius: 25))
    }

    private var queryField: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("搜索所有来源", text: $query)
                .font(.title2)
                .textFieldStyle(.plain)
                .focused($focus, equals: .query)
                .accessibilityIdentifier("global-search-query")
                .onSubmit(confirmResult)
                .onKeyPress(keys: [.upArrow, .downArrow, .escape], phases: .down, action: handleKey)
            if !query.isEmpty {
                Button {
                    query = ""
                    focus = .query
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除全局搜索")
            }
            Button {
                filtersShown.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3").frame(width: 22, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("全局搜索筛选")
            .help("搜索模式和范围")
            .popover(isPresented: $filtersShown, arrowEdge: .bottom) {
                LibrarySearchFilters(mode: $mode, directories: $directories, files: $files)
            }
        }
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
            .focused($focus, equals: .results)
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
            focus = .results
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
                    Text(result.path)
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

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        if focus == .query,
           let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.hasMarkedText() {
            return .ignored
        }
        switch press.key {
        case .escape:
            if press.phase == .down { dismiss() }
        case .upArrow, .downArrow:
            guard !results.isEmpty else { return .ignored }
            if focus == .query {
                selection = press.key == .upArrow ? results.last : results.first
                focus = .results
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
            if press.phase == .down { focus = .query }
        default:
            return .ignored
        }
        return .handled
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

    var symbol: String {
        switch self {
        case .directory: "folder"
        case .file(let item): item.kind == .video ? "film" : "photo"
        }
    }
}
