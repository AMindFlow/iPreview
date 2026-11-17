import SwiftUI
import iPreviewCore

struct ImportSheet: View {
    let inspection: SourceInspection
    let confirm: (ImportCandidate) -> Void
    @Environment(\.dismiss) private var dismiss
    @ViewState private var layout: iPreviewCore.Layout?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("导入「\(inspection.root.lastPathComponent)」")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(inspection.root.path)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if inspection.candidates.count > 1 {
                Picker("目录结构", selection: $layout) {
                    ForEach(inspection.candidates) { candidate in
                        Text(summary(candidate)).tag(Optional(candidate.layout))
                    }
                }
                .pickerStyle(.radioGroup)
            } else if let candidate = inspection.candidates.first {
                Label(summary(candidate), systemImage: "folder")
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("导入") {
                    if let candidate = inspection.candidates.first(where: { $0.layout == layout }) {
                        confirm(candidate)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(layout == nil)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            if inspection.candidates.count == 1 { layout = inspection.candidates.first?.layout }
        }
    }

    private func summary(_ candidate: ImportCandidate) -> String {
        "\(candidate.layout.title) · \(candidate.albumCount) 个专辑，\(candidate.entries.count) 项"
    }
}

struct AlbumEdit: Identifiable {
    let id = UUID()
    var album: VirtualAlbum?
    var firstMediaID: Int64?

    var idToRename: Int64? { album?.id }
}

struct AlbumSheet: View {
    let edit: AlbumEdit
    let confirm: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @ViewState private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(edit.album == nil ? "新建虚拟专辑" : "重命名专辑")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            TextField("专辑名称", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .accessibilityIdentifier("album-name")
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(edit.album == nil ? "创建" : "保存") {
                    confirm(name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
        .onAppear {
            name = edit.album?.name ?? ""
            focused = true
        }
    }
}

struct SourceNameEdit: Identifiable {
    let id = UUID()
    let source: Source
    let path: String
    let mediaID: Int64?
    let folder: LibraryPage?

    init(media: Media) {
        source = media.source
        path = media.relativePath
        mediaID = media.id
        folder = nil
    }

    init(folder: LibraryFolder) {
        source = folder.cover.source
        mediaID = nil
        self.folder = folder.page
        switch folder.page {
        case .creator(_, let path), .folder(_, let path):
            self.path = path
        default:
            preconditionFailure("A folder card must represent an indexed directory")
        }
    }

    var sourcePath: String { source.url.appendingPathComponent(path).path }
    var name: String {
        let leaf = (path as NSString).lastPathComponent
        return mediaID == nil ? leaf : (leaf as NSString).deletingPathExtension
    }
    var fileExtension: String? { mediaID == nil ? nil : (path as NSString).pathExtension }
}

struct SourceNameSheet: View {
    let edit: SourceNameEdit
    let save: (String) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @ViewState private var name: String
    @ViewState private var selection: TextSelection?
    @ViewState private var isSaving = false
    @ViewState private var error: String?

    init(edit: SourceNameEdit, save: @escaping (String) async throws -> Void) {
        self.edit = edit
        self.save = save
        _name = ViewState(initialValue: edit.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(edit.mediaID == nil ? "重命名源文件夹" : "重命名源文件")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(edit.sourcePath)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
            HStack(spacing: 5) {
                TextField("名称", text: $name, selection: $selection)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .accessibilityIdentifier("source-item-name")
                    .onSubmit(submit)
                if let fileExtension = edit.fileExtension {
                    Text("." + fileExtension)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("文件扩展名 \(fileExtension)")
                }
            }
            .disabled(isSaving)
            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)
                Button("重命名", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
        .interactiveDismissDisabled(isSaving)
        .task {
            focused = true
            await Task.yield()
            selection = TextSelection(range: name.startIndex..<name.endIndex)
        }
    }

    private func submit() {
        guard !isSaving, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSaving = true
        error = nil
        Task {
            defer { isSaving = false }
            do {
                try await save(name)
                dismiss()
            } catch {
                self.error = error.localizedDescription
                focused = true
            }
        }
    }
}
