import SwiftUI
import iPreviewCore

struct AlbumFavoriteButton: View {
    let favorite: Bool
    var size: CGFloat = 18
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: favorite ? "star.fill" : "star")
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(favorite ? Color.accentColor : .secondary)
                .frame(width: size + 9, height: size + 9)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(favorite ? "取消收藏专辑" : "收藏专辑")
        .accessibilityAddTraits(favorite ? .isSelected : [])
        .help(favorite ? "取消收藏专辑" : "收藏专辑")
    }
}

struct AlbumHeaderRating: View {
    let ratingHalf: Int?
    let setRating: (Int?) -> Void

    @ViewState private var hoverValue: Int?
    @FocusState private var focusedValue: Int?

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5) { index in
                let left = 2 * index + 1
                let displayValue = hoverValue ?? focusedValue ?? ratingHalf ?? 0
                ZStack {
                    Image(systemName: displayValue > left ? "star.fill" : displayValue == left ? "star.leadinghalf.filled" : "star")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(displayValue >= left ? Color.accentColor : .secondary)
                        .accessibilityHidden(true)
                    HStack(spacing: 0) {
                        ratingButton(left)
                        ratingButton(left + 1)
                    }
                }
                .frame(width: 21, height: 23)
            }

            Menu {
                Button("0 星") { setRating(0) }
                Button("清除评分") { setRating(nil) }
                    .disabled(ratingHalf == nil)
            } label: {
                Text(ratingTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("评分")
            .accessibilityValue(ratingTitle)
        }
        .accessibilityElement(children: .contain)
    }

    private var ratingTitle: String {
        ratingHalf.map { "\((Double($0) / 2).formatted()) 星" } ?? "未评分"
    }

    private func ratingButton(_ value: Int) -> some View {
        Button { setRating(value) } label: {
            Color.clear
                .frame(width: 10, height: 23)
                .contentShape(Rectangle())
                .overlay {
                    if focusedValue == value {
                        RoundedRectangle(cornerRadius: 3).strokeBorder(Color.accentColor, lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                }
        }
        .buttonStyle(.plain)
        .focused($focusedValue, equals: value)
        .onHover { inside in
            if inside { hoverValue = value }
            else if hoverValue == value { hoverValue = nil }
        }
        .accessibilityLabel("设为 \(Double(value) / 2, format: .number) 星")
        .help("设为 \(Double(value) / 2, format: .number) 星")
    }
}

struct AlbumHeaderTags: View {
    let tags: [SourceAlbumTag]
    let add: () -> Void
    let remove: (SourceAlbumTag) -> Void
    @State private var hovered = false
    @FocusState private var addFocused: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) {
                pills
                addButton
            }
            .fixedSize(horizontal: true, vertical: false)

            HStack(spacing: 7) {
                ScrollView(.horizontal) { HStack(spacing: 7) { pills } }
                    .scrollIndicators(.hidden)
                addButton
            }
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }

    private var pills: some View {
        ForEach(tags) { tag in
            AlbumHeaderTag(tag: tag) { remove(tag) }
        }
    }

    private var addButton: some View {
        Button(action: add) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 13, height: 13)
        }
        .buttonBorderShape(.circle)
        .controlSize(.small)
        .libraryGlassButton()
        .focused($addFocused)
        .opacity(tags.isEmpty || hovered || addFocused ? 1 : 0)
        .accessibilityLabel("添加专辑标签")
        .help("添加标签")
    }
}

private struct AlbumHeaderTag: View {
    let tag: SourceAlbumTag
    let remove: () -> Void
    @ViewState private var hovered = false
    @FocusState private var removeFocused: Bool

    var body: some View {
        Label(tag.name, systemImage: "tag")
            .font(.caption)
            .lineLimit(1)
            .frame(maxWidth: 120)
            .padding(.leading, 7)
            .padding(.trailing, 17)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
            .overlay(alignment: .topTrailing) {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focused($removeFocused)
                .opacity(hovered || removeFocused ? 1 : 0)
                .accessibilityLabel("移除标签 \(tag.name)")
            }
            .onHover { hovered = $0 }
            .accessibilityAction(named: Text("移除标签"), remove)
    }
}
