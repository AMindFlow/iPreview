import SwiftUI
import iPreviewCore

struct SearchTagStack: View {
    let tags: [SourceAlbumTag]
    let remove: (SourceAlbumTag) -> Void

    @ViewState private var anchorHovered = false
    @ViewState private var listHovered = false
    @ViewState private var hoveredTag: Int64?
    @ViewState private var hoverExpanded = false
    @ViewState private var pinned = false
    @FocusState private var anchorFocused: Bool
    @FocusState private var focusedTag: Int64?

    var body: some View {
        if let first = tags.first {
            Button { pinned.toggle() } label: {
                label(first)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(.quaternary, in: Capsule())
                    .background(alignment: .trailing) {
                        if tags.count > 1 {
                            Capsule()
                                .fill(.quaternary)
                                .offset(x: 4, y: 2)
                        }
                    }
                    .padding(.trailing, tags.count > 1 ? 4 : 0)
            }
            .buttonStyle(.plain)
            .focused($anchorFocused)
            .onHover { anchorHovered = $0 }
            .accessibilityLabel("已筛选标签")
            .accessibilityValue(tags.map(\.name).joined(separator: "、"))
            .help("查看或移除筛选标签")
            .overlay(alignment: .topTrailing) {
                if expanded {
                    tagList
                        .padding(.top, 26)
                }
            }
            .task(id: anchorHovered || listHovered) {
                if anchorHovered || listHovered {
                    hoverExpanded = true
                } else {
                    try? await Task.sleep(for: .milliseconds(160))
                    if !Task.isCancelled { hoverExpanded = false }
                }
            }
        }
    }

    private var expanded: Bool { pinned || hoverExpanded || anchorFocused || focusedTag != nil }

    private var tagList: some View {
        ScrollView {
            VStack(alignment: .trailing, spacing: 5) {
                ForEach(tags) { tag in
                    label(tag)
                        .padding(.vertical, 5)
                        .padding(.leading, 8)
                        .padding(.trailing, 22)
                        .background(.quaternary, in: Capsule())
                        .overlay(alignment: .topTrailing) {
                            Button {
                                remove(tag)
                                if tags.count == 1 { pinned = false }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20, height: 20)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .focused($focusedTag, equals: tag.id)
                            .opacity(hoveredTag == tag.id || focusedTag == tag.id ? 1 : 0)
                            .accessibilityLabel("移除筛选标签 \(tag.name)")
                        }
                        .onHover { inside in
                            if inside { hoveredTag = tag.id }
                            else if hoveredTag == tag.id { hoveredTag = nil }
                        }
                        .accessibilityAction(named: Text("移除筛选标签")) { remove(tag) }
                }
            }
            .padding(7)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: 155, height: min(150, CGFloat(tags.count) * 29 + 12))
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        .contentShape(.rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary).allowsHitTesting(false) }
        .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
        .onHover { listHovered = $0 }
    }

    private func label(_ tag: SourceAlbumTag) -> some View {
        Label(tag.name, systemImage: "tag.fill")
            .font(.caption)
            .lineLimit(1)
            .frame(maxWidth: 112)
    }
}
