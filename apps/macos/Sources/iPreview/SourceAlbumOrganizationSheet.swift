import SwiftUI
import iPreviewCore

enum AlbumOrganizationTarget: Identifiable {
    case album(name: String, key: SourceAlbumKey, media: [Media])
    case tags

    var id: SourceAlbumKey? {
        if case .album(_, let key, _) = self { return key }
        return nil
    }
}

struct SourceAlbumOrganizationSheet: View {
    let target: AlbumOrganizationTarget
    let model: LibraryModel

    @Environment(\.dismiss) private var dismiss
    @ViewState private var organization: SourceAlbumOrganization?
    @ViewState private var working = false
    @ViewState private var error: String?
    @ViewState private var tagDraft = ""
    @ViewState private var renamingTag: SourceAlbumTag?
    @ViewState private var deletingTag: SourceAlbumTag?
    @ViewState private var coverDraft: [Int64]?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch target {
            case .album(let name, let key, let media):
                Text(name).font(.title2.bold())
                if let organization {
                    albumControls(key: key, organization: organization)
                    Divider()
                    coverControls(key: key, media: media, organization: organization)
                } else if error == nil {
                    ProgressView().accessibilityLabel("正在读取专辑组织")
                }
            case .tags:
                Text("管理标签").font(.title2.bold())
                globalTags
            }
            if let error {
                Text(error).foregroundStyle(.red)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(working)
            }
        }
        .padding(20)
        .frame(width: 490)
        .task {
            do {
                if case .album(_, let key, _) = target {
                    organization = try await model.organization(for: key)
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
        .alert("删除标签", isPresented: Binding(
            get: { deletingTag != nil }, set: { if !$0 { deletingTag = nil } }
        ), presenting: deletingTag) { tag in
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { apply { try await $0.deleteTag(tag.id) } }
        } message: { tag in
            Text("将从全库移除「\(tag.name)」及其专辑关联。")
        }
    }

    private func albumControls(key: SourceAlbumKey, organization: SourceAlbumOrganization) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("收藏", isOn: Binding(get: { organization.favorite },
                                         set: { value in apply { try await $0.setFavorite(value, for: key) } }))
            Picker("评分", selection: Binding(get: { organization.ratingHalf },
                                              set: { value in apply { try await $0.setRatingHalf(value, for: key) } })) {
                Text("未评分").tag(nil as Int?)
                ForEach(0...10, id: \.self) { value in
                    Text("\(Double(value) / 2, format: .number) 星").tag(Optional(value))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("标签").font(.headline)
                if !organization.tags.isEmpty {
                    ScrollView {
                        VStack(spacing: 5) {
                            ForEach(organization.tags) { tag in
                                HStack {
                                    Text(tag.name).lineLimit(1)
                                    Spacer()
                                    Button {
                                        apply { try await $0.removeTag(tag.id, from: key) }
                                    } label: {
                                        Image(systemName: "xmark.circle")
                                    }
                                    .accessibilityLabel("移除标签 \(tag.name)")
                                    .buttonStyle(.borderless)
                                }
                                .frame(height: 20)
                            }
                        }
                    }
                    .frame(height: CGFloat(min(organization.tags.count, 4) * 25 - 5))
                }
                HStack {
                    TextField("标签名称", text: $tagDraft).onSubmit { addTag(key) }
                    Button("添加") { addTag(key) }
                        .disabled(tagDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Menu("已有标签") {
                        let attached = Set(organization.tags.map(\.id))
                        ForEach(model.sourceAlbumIndex.tags.filter { !attached.contains($0.id) }) { tag in
                            Button(tag.name) { apply { try await $0.addTag(tag.id, to: key) } }
                        }
                    }
                }
            }
        }
        .disabled(working)
    }

    private var globalTags: some View {
        VStack(alignment: .leading, spacing: 9) {
            if model.sourceAlbumIndex.tags.isEmpty {
                Text("没有标签").foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 7) {
                    ForEach(model.sourceAlbumIndex.tags) { tag in
                        HStack {
                            if renamingTag?.id == tag.id {
                                TextField("标签名称", text: $tagDraft).onSubmit { saveTagName(tag) }
                                Button("取消") { renamingTag = nil }
                                Button("保存") { saveTagName(tag) }
                                    .disabled(tagDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            } else {
                                Text(tag.name)
                                Spacer()
                                Button("重命名") {
                                    tagDraft = tag.name
                                    renamingTag = tag
                                }
                                Button(role: .destructive) { deletingTag = tag } label: {
                                    Image(systemName: "trash")
                                }
                                .accessibilityLabel("从全库删除标签 \(tag.name)")
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .disabled(working)
    }

    private func coverControls(key: SourceAlbumKey, media: [Media], organization: SourceAlbumOrganization) -> some View {
        let images = media.filter { $0.isAvailable && $0.kind == .image }
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("封面").font(.headline)
                Spacer()
                if coverDraft == nil {
                    let count = organization.configuredCoverIDs.count
                    Text(count == 0 ? "自动" : count == 1 ? "手选" : "\(count) 张拼图")
                        .foregroundStyle(.secondary)
                    Button("选择图片") { coverDraft = [] }.disabled(images.isEmpty)
                    if count != 0 {
                        Button("恢复自动") { apply { try await $0.replaceCover([], for: key) } }
                    }
                } else {
                    Button("取消") { coverDraft = nil }
                    Button("设为封面") {
                        guard let selected = coverDraft, !selected.isEmpty else { return }
                        apply({ try await $0.replaceCover(selected, for: key) }) { coverDraft = nil }
                    }
                    .disabled(coverDraft?.isEmpty != false)
                }
            }
            if let coverDraft {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 9) {
                        ForEach(images) { item in
                            coverChoice(item, selection: coverDraft)
                        }
                    }
                }
                .frame(height: 202)
            } else {
                let byID = Dictionary(uniqueKeysWithValues: images.map { ($0.id, $0) })
                AlbumCoverArtwork(media: organization.effectiveCoverIDs.compactMap { byID[$0] }, revision: model.revision)
                    .frame(width: 180, height: 122)
                    .clipShape(.rect(cornerRadius: 8))
            }
        }
        .disabled(working)
    }

    private func coverChoice(_ item: Media, selection: [Int64]) -> some View {
        let position = selection.firstIndex(of: item.id)
        return Button {
            if let position {
                coverDraft?.remove(at: position)
            } else {
                coverDraft?.append(item.id)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                MediaThumbnail(media: item, revision: model.revision)
                    .frame(height: 74)
                    .clipShape(.rect(cornerRadius: 6))
                    .overlay(alignment: .topTrailing) {
                        if let position {
                            Text("\(position + 1)")
                                .font(.caption.bold())
                                .padding(5)
                                .background(.regularMaterial, in: Circle())
                                .padding(4)
                        }
                    }
                Text(item.name).font(.caption).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(position == nil ? [] : .isSelected)
        .disabled(position == nil && selection.count >= 4)
    }

    private func addTag(_ key: SourceAlbumKey) {
        let name = tagDraft
        apply({ _ = try await $0.addTag(named: name, to: key) }) { tagDraft = "" }
    }

    private func saveTagName(_ tag: SourceAlbumTag) {
        let name = tagDraft
        apply({ try await $0.renameTag(tag.id, to: name) }) { renamingTag = nil }
    }

    private func apply(_ action: @escaping (Catalog) async throws -> Void, success: @escaping () -> Void = {}) {
        guard !working else { return }
        working = true
        error = nil
        Task {
            defer { working = false }
            do {
                try await model.organize(action)
                if case .album(_, let key, _) = target {
                    organization = try await model.organization(for: key)
                }
                success()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

struct AlbumCoverArtwork: View {
    let media: [Media]
    let revision: Int

    var body: some View {
        if media.isEmpty {
            ZStack {
                Color.mediaSurface
                Image(systemName: "photo").font(.title2).foregroundStyle(.tertiary)
            }
            .accessibilityHidden(true)
        } else if media.count == 1 {
            MediaThumbnail(media: media[0], revision: revision)
        } else {
            VStack(spacing: 2) {
                row(media.prefix(2))
                if media.count > 2 { row(media.dropFirst(2)) }
            }
        }
    }

    private func row(_ items: ArraySlice<Media>) -> some View {
        HStack(spacing: 2) {
            ForEach(items) { MediaThumbnail(media: $0, revision: revision) }
        }
    }
}
