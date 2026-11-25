import SwiftUI
import iPreviewCore

enum SearchTagStackPresentation {
    case closed, hovered, pinned, focused, dismissed

    var isExpanded: Bool { self == .hovered || self == .pinned || self == .focused }
}

struct SearchTagStack: View {
    let tags: [SourceAlbumTag]
    @Binding var presentation: SearchTagStackPresentation
    let dismiss: () -> Void
    let remove: (SourceAlbumTag) -> Void

    @ViewState private var anchorHovered = false
    @ViewState private var listHovered = false
    @ViewState private var hoveredTag: Int64?
    @FocusState private var anchorFocused: Bool
    @FocusState private var focusedTag: Int64?

    private var pointerWithin: Bool { anchorHovered || listHovered }
    private var keyboardWithin: Bool { anchorFocused || focusedTag != nil }

    var body: some View {
        if let front = tags.last {
            let depth = min(tags.count - 1, 2)
            Button {
                if presentation == .pinned { dismiss() }
                else { presentation = .pinned }
            } label: {
                label(front)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background {
                        ZStack {
                            ForEach((0..<depth).reversed(), id: \.self) { index in
                                card(.windowBackgroundColor)
                                    .offset(x: CGFloat(index + 1) * 5, y: CGFloat(index + 1) * 4)
                            }
                            card(.controlBackgroundColor)
                        }
                    }
                    .padding(.trailing, CGFloat(depth) * 5)
                    .padding(.bottom, CGFloat(depth) * 4)
            }
            .buttonStyle(.plain)
            .focused($anchorFocused)
            .onHover { anchorHovered = $0 }
            .accessibilityLabel("已筛选标签")
            .accessibilityValue(tags.map(\.name).joined(separator: "、"))
            .help("查看或移除筛选标签")
            .overlay(alignment: .topTrailing) {
                if presentation.isExpanded {
                    tagList
                        .padding(.top, 26 + CGFloat(depth) * 4)
                }
            }
            .onKeyPress(.escape) {
                guard presentation.isExpanded else { return .ignored }
                dismiss()
                return .handled
            }
            .onChange(of: presentation) { _, value in
                guard value == .dismissed else { return }
                if !pointerWithin { presentation = .closed }
                listHovered = false
                hoveredTag = nil
            }
            .onChange(of: keyboardWithin) { _, focused in
                if focused && presentation != .pinned {
                    presentation = .focused
                } else if !focused && presentation == .focused {
                    presentation = pointerWithin ? .hovered : .closed
                }
            }
            .task(id: pointerWithin) {
                if pointerWithin {
                    if presentation == .closed { presentation = .hovered }
                } else {
                    try? await Task.sleep(for: .milliseconds(160))
                    if !Task.isCancelled && (presentation == .hovered || presentation == .dismissed) {
                        presentation = .closed
                    }
                }
            }
        }
    }

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

    private func card(_ fill: NSColor) -> some View {
        let edge = RoundedRectangle(cornerRadius: 7)
        return edge.fill(Color(nsColor: fill))
            .overlay { edge.strokeBorder(Color.primary.opacity(0.32)) }
            .accessibilityHidden(true)
    }

    private func label(_ tag: SourceAlbumTag) -> some View {
        Label(tag.name, systemImage: "tag.fill")
            .font(.caption)
            .lineLimit(1)
            .frame(maxWidth: 112)
    }
}
