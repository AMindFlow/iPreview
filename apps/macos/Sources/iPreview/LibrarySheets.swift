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
