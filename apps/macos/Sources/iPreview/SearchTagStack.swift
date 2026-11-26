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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var anchorSize = CGSize.zero
    @ViewState private var anchorHovered = false
    @ViewState private var listHovered = false
    @ViewState private var hoveredTag: Int64?
    @ViewState private var unfolded = false
    @FocusState private var anchorFocused: Bool
    @FocusState private var focusedTag: Int64?

    private let listWidth: CGFloat = 155
    private let rowHeight: CGFloat = 27
    private let rowSpacing: CGFloat = 5
    private let inset: CGFloat = 7
    private let gap: CGFloat = 5

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
                    .opacity(presentation.isExpanded ? 0 : 1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused($anchorFocused)
            .onGeometryChange(for: CGSize.self, of: { $0.size }) { anchorSize = $0 }
            .onHover { anchorHovered = $0 }
            .accessibilityLabel("已筛选标签")
            .accessibilityValue(tags.map(\.name).joined(separator: "、"))
            .help("查看或移除筛选标签")
            .overlay(alignment: .topTrailing) {
                if presentation.isExpanded {
                    tagList(depth: depth)
                        .padding(.top, anchorSize.height)
                        .transition(.identity)
                        .task {
                            guard !reduceMotion else { return }
                            try? await Task.sleep(for: .milliseconds(16))
                            guard !Task.isCancelled else { return }
                            withAnimation(.easeOut(duration: 0.20)) { unfolded = true }
                        }
                }
            }
            .onKeyPress(.escape) {
                guard presentation.isExpanded else { return .ignored }
                dismiss()
                return .handled
            }
            .onChange(of: presentation.isExpanded) { _, expanded in
                if !expanded { unfolded = false }
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

    private func tagList(depth: Int) -> some View {
        let open = reduceMotion || unfolded
        let edge = RoundedRectangle(cornerRadius: 12)
        let rows = VStack(spacing: rowSpacing) {
            ForEach(Array(tags.reversed().enumerated()), id: \.element.id) { index, tag in
                tagRow(tag, index: index, depth: depth, open: open)
            }
        }
        .padding(inset)
        return Group {
            if tags.count > 4 {
                ScrollView { rows }
                    .frame(height: 4 * rowHeight + 3 * rowSpacing + 2 * inset)
            } else {
                rows
            }
        }
        .frame(width: listWidth)
        .background {
            edge.fill(.regularMaterial)
                .overlay { edge.strokeBorder(.primary.opacity(0.18)) }
                .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
                .opacity(open ? 1 : 0)
                .allowsHitTesting(false)
        }
        .padding(.top, gap)
        .contentShape(Rectangle())
        .onHover { listHovered = $0 }
    }

    private func tagRow(_ tag: SourceAlbumTag, index: Int, depth: Int, open: Bool) -> some View {
        let layer = CGFloat(min(index, depth))
        let cardWidth = anchorSize.width - CGFloat(depth) * 5
        let cardHeight = anchorSize.height - CGFloat(depth) * 4
        let startX = (layer - CGFloat(depth)) * 5 + inset
        let startY = cardHeight / 2 + layer * 4
        let endY = anchorSize.height + gap + inset + rowHeight / 2 + CGFloat(index) * (rowHeight + rowSpacing)
        return label(tag)
            .frame(maxWidth: .infinity)
            .frame(height: rowHeight)
            .padding(.horizontal, 19)
            .background { card(.controlBackgroundColor) }
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
            .scaleEffect(x: open ? 1 : min(1, cardWidth / (listWidth - 2 * inset)),
                         y: open ? 1 : min(1, cardHeight / rowHeight), anchor: .trailing)
            .offset(x: open ? 0 : startX, y: open ? 0 : startY - endY)
            .opacity(open || index <= depth ? 1 : 0)
            .zIndex(-Double(index))
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
