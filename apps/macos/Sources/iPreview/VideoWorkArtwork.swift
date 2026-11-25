import SwiftUI
import iPreviewCore

struct TapeCase: View {
    let video: Media
    let revision: Int
    let height: CGFloat
    let opening: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var width: CGFloat { height * 9 / 16 }
    private var dark: Bool { colorScheme == .dark }
    private var radius: CGFloat { max(5, width * 0.06) }

    var body: some View {
        let dx: CGFloat = max(4, width * 0.085)
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
        let topFill = dark
            ? Color(red: 0.18, green: 0.20, blue: 0.24).opacity(0.88)
            : Color(red: 0.74, green: 0.78, blue: 0.84).opacity(0.72)
        let leftFill = dark
            ? Color(red: 0.11, green: 0.12, blue: 0.15).opacity(0.94)
            : Color(red: 0.60, green: 0.65, blue: 0.72).opacity(0.80)
        let edge = dark ? Color.white.opacity(0.14) : Color.white.opacity(0.55)

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
        }.stroke(edge, lineWidth: 0.75))

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
        }.stroke(edge.opacity(0.65), lineWidth: 0.75))
    }

    private var baseShell: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let tray = dark
            ? Color(red: 0.08, green: 0.09, blue: 0.11).opacity(0.84)
            : Color(red: 0.16, green: 0.18, blue: 0.22).opacity(0.18)
        let groove = dark ? Color.white.opacity(0.08) : Color.black.opacity(0.10)
        let labelShape = RoundedRectangle(cornerRadius: max(2, width * 0.025), style: .continuous)
        let dot = max(2.2, width * 0.024)

        return ZStack {
            Color.clear.previewGlass(in: shape)
            shape.inset(by: max(2.5, width * 0.03)).fill(tray)
                .overlay(shape.inset(by: max(2.5, width * 0.03)).strokeBorder(groove, lineWidth: 0.75))
            MediaThumbnail(media: video, revision: revision)
                .frame(width: width * 0.80, height: height * 0.37)
                .clipShape(labelShape)
                .overlay(labelShape.strokeBorder(Color.black.opacity(dark ? 0.45 : 0.18), lineWidth: 0.75))
            reelWindow.offset(y: height * 0.265)
            VStack {
                HStack { fastener(dot); Rectangle().fill(groove).frame(height: 0.75); fastener(dot) }
                Spacer()
                HStack { fastener(dot); Rectangle().fill(groove).frame(height: 0.75); fastener(dot) }
            }
            .padding(max(5, width * 0.06))
        }
        .frame(width: width, height: height)
        .clipShape(shape)
    }

    private var reelWindow: some View {
        let winW: CGFloat = width * 0.56
        let winH: CGFloat = max(13, height * 0.082)
        let wheel: CGFloat = max(9, winH * 0.72)
        let winShape = RoundedRectangle(cornerRadius: max(3, winH * 0.28), style: .continuous)
        let well = dark
            ? Color(red: 0.04, green: 0.05, blue: 0.07).opacity(0.92)
            : Color(red: 0.15, green: 0.17, blue: 0.21).opacity(0.68)

        return ZStack {
            winShape.fill(well)
                .overlay(winShape.strokeBorder(dark ? Color.white.opacity(0.14) : Color.black.opacity(0.24), lineWidth: 0.75))
            HStack(spacing: max(6, winW * 0.24)) {
                tapeWheel(wheel)
                tapeWheel(wheel)
            }
        }
        .frame(width: winW, height: winH)
    }

    private func tapeWheel(_ size: CGFloat) -> some View {
        ZStack {
            Circle().fill(dark ? Color(red: 0.16, green: 0.18, blue: 0.22) : Color(red: 0.28, green: 0.30, blue: 0.35))
            Circle().strokeBorder(Color.white.opacity(dark ? 0.24 : 0.36), lineWidth: 0.75)
            Circle()
                .fill(dark ? Color(red: 0.62, green: 0.65, blue: 0.70) : Color(red: 0.85, green: 0.87, blue: 0.90))
                .frame(width: size * 0.44, height: size * 0.44)
        }
        .frame(width: size, height: size)
    }

    private func fastener(_ size: CGFloat) -> some View {
        Circle()
            .fill(dark ? Color.white.opacity(0.18) : Color.black.opacity(0.22))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5))
            .frame(width: size, height: size)
    }

    private var transparentLid: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let rim = LinearGradient(
            colors: [
                Color.white.opacity(dark ? 0.30 : 0.68),
                Color.white.opacity(dark ? 0.08 : 0.18),
                Color.black.opacity(dark ? 0.28 : 0.14)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        return ZStack(alignment: .leading) {
            shape.strokeBorder(rim, lineWidth: 1)
            shape.inset(by: 2.5).strokeBorder(Color.white.opacity(dark ? 0.07 : 0.22), lineWidth: 0.5)
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
