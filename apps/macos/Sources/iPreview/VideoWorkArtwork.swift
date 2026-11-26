import SwiftUI
import iPreviewCore

struct TapeCase: View {
    let cover: CGImage?
    let height: CGFloat
    let opening: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var width: CGFloat { height * 9 / 16 }
    private var dark: Bool { colorScheme == .dark }
    private var radius: CGFloat { max(5, width * 0.06) }

    var body: some View {
        let dx: CGFloat = max(4, width * 0.105)
        let dy: CGFloat = max(3, height * 0.030)
        ZStack(alignment: .topLeading) {
            thicknessPlanes(dx: dx, dy: dy)
            baseShell
            transparentLid
                .rotation3DEffect(
                    .degrees(opening ? -67 : 0),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: .leading,
                    perspective: 0.42
                )
        }
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(0.24), radius: 13, x: -4, y: 10)
        .scaleEffect(opening ? 1.13 : 1)
        .opacity(opening ? 0 : 1)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func thicknessPlanes(dx: CGFloat, dy: CGFloat) -> some View {
        let r = radius
        let c = r * 0.293
        let tintedGlass = Color(red: 0.48, green: 0.57, blue: 0.77)
        let spineTint = Color(red: 0.21, green: 0.28, blue: 0.46)
        let topFill = LinearGradient(colors: [.white.opacity(0.75), tintedGlass.opacity(0.22), .white.opacity(0.65)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)
        let leftFill = LinearGradient(colors: [tintedGlass.opacity(0.6), spineTint.opacity(dark ? 0.86 : 0.7),
                                               .white.opacity(0.45)],
                                      startPoint: .leading, endPoint: .trailing)
        let edge = Color.white.opacity(dark ? 0.5 : 0.82)

        Path { p in
            p.addLines([
                CGPoint(x: c, y: c), CGPoint(x: r, y: 0), CGPoint(x: width - r, y: 0),
                CGPoint(x: width - c, y: c), CGPoint(x: width - c - dx, y: c - dy),
                CGPoint(x: width - r - dx, y: -dy), CGPoint(x: r - dx, y: -dy), CGPoint(x: c - dx, y: c - dy)
            ])
            p.closeSubpath()
        }
        .fill(topFill)
        .overlay(Path { p in
            p.addLines([
                CGPoint(x: c - dx, y: c - dy), CGPoint(x: r - dx, y: -dy),
                CGPoint(x: width - r - dx, y: -dy), CGPoint(x: width - c - dx, y: c - dy)
            ])
        }.stroke(edge, lineWidth: 1.1))

        Path { p in
            p.addLines([
                CGPoint(x: c, y: c), CGPoint(x: c - dx, y: c - dy), CGPoint(x: -dx, y: r - dy),
                CGPoint(x: -dx, y: height - r - dy), CGPoint(x: c - dx, y: height - c - dy),
                CGPoint(x: c, y: height - c), CGPoint(x: 0, y: height - r), CGPoint(x: 0, y: r)
            ])
            p.closeSubpath()
        }
        .fill(leftFill)
        .overlay(Path { p in
            p.addLines([
                CGPoint(x: c - dx, y: c - dy), CGPoint(x: -dx, y: r - dy),
                CGPoint(x: -dx, y: height - r - dy), CGPoint(x: c - dx, y: height - c - dy)
            ])
        }.stroke(edge.opacity(0.76), lineWidth: 1))
    }

    private var baseShell: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let bezel = max(4, width * 0.06)
        let print = RoundedRectangle(cornerRadius: max(3, radius - bezel / 2), style: .continuous)
        let paperWidth = max(1, width - 2 * bezel)
        let paperHeight = max(1, height - 2 * bezel)

        return ZStack {
            Color.clear.previewGlass(in: shape)
            shape.fill(.linearGradient(colors: [.white.opacity(0.27), .clear, .white.opacity(0.20)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            ZStack {
                Color.mediaSurface
                if let cover {
                    Image(decorative: cover, scale: 1)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "film")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: paperWidth, height: paperHeight)
            .clipShape(print)
            .overlay { print.strokeBorder(.black.opacity(0.40), lineWidth: 1) }
        }
        .frame(width: width, height: height)
        .clipShape(shape)
    }

    private var transparentLid: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let rim = LinearGradient(
            colors: [
                Color.white.opacity(0.84),
                Color(red: 0.69, green: 0.78, blue: 1).opacity(0.35),
                Color.white.opacity(0.54)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        return ZStack(alignment: .leading) {
            shape.strokeBorder(rim, lineWidth: 1.5)
            shape.inset(by: 3).strokeBorder(Color.white.opacity(0.33), lineWidth: 0.75)
            Rectangle()
                .fill(Color.white.opacity(dark ? 0.14 : 0.32))
                .frame(width: 1)
                .padding(.vertical, radius)
                .padding(.leading, max(3, width * 0.04))
        }
        .frame(width: width, height: height)
        .contentShape(shape)
    }
}

struct VideoWorkPhotoPrint: View {
    let media: Media
    let revision: Int
    let width: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        let height = width * 1.23
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        let topPaper = dark
            ? Color(red: 0.945, green: 0.938, blue: 0.920)
            : Color(red: 0.978, green: 0.973, blue: 0.958)
        let bottomPaper = dark
            ? Color(red: 0.895, green: 0.888, blue: 0.868)
            : Color(red: 0.942, green: 0.936, blue: 0.918)

        ZStack(alignment: .top) {
            shape.fill(LinearGradient(colors: [topPaper, bottomPaper], startPoint: .top, endPoint: .bottom))
            MediaThumbnail(media: media, revision: revision)
                .frame(width: max(1, width - 12), height: max(1, height - 18))
                .clipped()
                .overlay(Rectangle().strokeBorder(Color.black.opacity(dark ? 0.22 : 0.10), lineWidth: 0.5))
                .padding(.top, 6)
            Rectangle().fill(Color.white.opacity(dark ? 0.45 : 0.85)).frame(height: 0.75)
            shape.strokeBorder(Color.black.opacity(dark ? 0.34 : 0.14), lineWidth: 0.5)
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .shadow(color: .black.opacity(0.29), radius: 3.5, x: 1, y: 3)
        .accessibilityHidden(true)
    }
}
