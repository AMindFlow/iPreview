import QuartzCore
import SwiftUI
import iPreviewCore

struct TapeCase: View {
    let cover: CGImage?
    let height: CGFloat
    let opening: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var width: CGFloat { height * 9 / 16 }
    private var dark: Bool { colorScheme == .dark }
    private var iceLavender: Color { Color(red: 0.82, green: 0.86, blue: 1.0) }
    private var warmWhite: Color { Color(red: 1.0, green: 0.96, blue: 0.91) }

    var body: some View {
        let box = CGSize(width: width, height: height)
        let frontQuad = Quad(
            tl: CGPoint(x: width * 0.155, y: height * 0.045),
            tr: CGPoint(x: width * 0.970, y: height * 0.082),
            br: CGPoint(x: width * 0.970, y: height * 0.930),
            bl: CGPoint(x: width * 0.155, y: height * 0.969)
        )
        let spineQuad = Quad(
            tl: CGPoint(x: width * 0.065, y: height * 0.060),
            tr: frontQuad.tl, br: frontQuad.bl,
            bl: CGPoint(x: width * 0.065, y: height * 0.946)
        )
        let frontSize = CGSize(width: width * 0.815, height: height * 0.924)
        let spineSize = CGSize(width: width * 0.105, height: height * 0.910)

        ZStack(alignment: .topLeading) {
            groundShadow(spineQuad: spineQuad, frontQuad: frontQuad)
            outerShell(box: box, spineQuad: spineQuad, frontQuad: frontQuad)
            innerTray(size: frontSize)
                .projectionEffect(quadProjection(from: frontSize, to: frontQuad))
            leftSpine(size: spineSize)
                .projectionEffect(quadProjection(from: spineSize, to: spineQuad))
            frontLid(size: frontSize)
                .rotation3DEffect(.degrees(opening ? -67 : 0), axis: (x: 0, y: 1, z: 0),
                                  anchor: .leading, perspective: 0.42)
                .projectionEffect(quadProjection(from: frontSize, to: frontQuad))
        }
        .frame(width: width, height: height)
        .scaleEffect(opening ? 1.13 : 1)
        .opacity(opening ? 0 : 1)
        .accessibilityHidden(true)
    }

    private func groundShadow(spineQuad: Quad, frontQuad: Quad) -> some View {
        let bl = frontQuad.bl, br = frontQuad.br, sl = spineQuad.bl
        let drop = max(4, height * 0.026)
        return ZStack {
            Path { p in
                p.move(to: CGPoint(x: sl.x - width * 0.015, y: sl.y + drop * 0.18))
                p.addQuadCurve(to: CGPoint(x: bl.x, y: bl.y + drop * 0.42),
                               control: CGPoint(x: (sl.x + bl.x) * 0.5, y: bl.y + drop * 0.34))
                p.addLine(to: CGPoint(x: br.x + width * 0.015, y: br.y + drop * 0.32))
                p.addLine(to: CGPoint(x: br.x, y: br.y - drop * 0.08))
                p.addLine(to: CGPoint(x: bl.x, y: bl.y - drop * 0.08))
                p.addLine(to: CGPoint(x: sl.x, y: sl.y - drop * 0.08))
                p.closeSubpath()
            }
            .fill(LinearGradient(colors: [.black.opacity(dark ? 0.38 : 0.18), .black.opacity(dark ? 0.12 : 0.04)],
                                 startPoint: .leading, endPoint: .trailing))
            .blur(radius: max(4, width * 0.04))

            // Small restrained pool of bottom reflection near the weight-bearing corner
            Ellipse()
                .fill(RadialGradient(
                    colors: [warmWhite.opacity(dark ? 0.11 : 0.14), iceLavender.opacity(dark ? 0.05 : 0.07), .clear],
                    center: .center, startRadius: 0, endRadius: width * 0.24
                ))
                .frame(width: width * 0.42, height: max(5, drop * 1.1))
                .position(x: bl.x + width * 0.24, y: bl.y + drop * 0.38)
                .blur(radius: max(2.5, width * 0.025))
        }
        .allowsHitTesting(false)
    }

    private func outerShell(box: CGSize, spineQuad: Quad, frontQuad: Quad) -> some View {
        let shell = continuousShellPath(box: box, spineQuad: spineQuad, frontQuad: frontQuad)
        let rimGradient = LinearGradient(
            stops: [
                .init(color: warmWhite.opacity(dark ? 0.64 : 0.86), location: 0.00),
                .init(color: iceLavender.opacity(dark ? 0.16 : 0.26), location: 0.22),
                .init(color: .white.opacity(dark ? 0.06 : 0.12), location: 0.55),
                .init(color: warmWhite.opacity(dark ? 0.48 : 0.72), location: 1.00)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        return ZStack {
            shell.stroke(Color.black.opacity(dark ? 0.50 : 0.24), lineWidth: 1.1)
            shell.stroke(rimGradient, lineWidth: 0.75)
        }
        .allowsHitTesting(false)
    }

    private func innerTray(size: CGSize) -> some View {
        let bezel = max(3, size.width * 0.032)
        let radius = max(5, size.width * 0.068)
        let tray = RoundedRectangle(cornerRadius: max(3, radius - bezel * 0.4), style: .continuous)
        let innerW = max(1, size.width - bezel * 2), innerH = max(1, size.height - bezel * 2)
        let bg = dark ? [Color(white: 0.09, opacity: 0.84), Color(white: 0.05, opacity: 0.90)]
                      : [Color(white: 0.16, opacity: 0.14), Color(white: 0.10, opacity: 0.20)]

        return ZStack {
            tray.fill(LinearGradient(colors: bg, startPoint: .topLeading, endPoint: .bottomTrailing))
                .opacity(opening ? 1 : (dark ? 0.65 : 0.20))
            VStack(spacing: innerH * 0.48) {
                Capsule().fill(.white.opacity(dark ? 0.09 : 0.18))
                    .frame(width: innerW * 0.62, height: max(3, innerH * 0.025))
                RoundedRectangle(cornerRadius: max(4, radius * 0.5), style: .continuous)
                    .fill(.black.opacity(dark ? 0.24 : 0.10))
                    .overlay {
                        HStack(spacing: innerW * 0.14) {
                            Circle().strokeBorder(.white.opacity(dark ? 0.24 : 0.34), lineWidth: 1)
                            Circle().strokeBorder(.white.opacity(dark ? 0.24 : 0.34), lineWidth: 1)
                        }
                        .padding(max(4, innerW * 0.05))
                    }
                    .frame(width: innerW * 0.58, height: innerH * 0.17)
            }
            .opacity(opening ? 0.68 : 0)
            tray.strokeBorder(.black.opacity(dark ? 0.44 : 0.18), lineWidth: 0.75)
        }
        .frame(width: innerW, height: innerH)
        .frame(width: size.width, height: size.height)
    }

    private func leftSpine(size: CGSize) -> some View {
        let r = max(3.5, size.width * 0.30)
        let outer = UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: r,
                                           bottomTrailingRadius: r * 0.38, topTrailingRadius: r * 0.38, style: .continuous)
        let insetH = max(1.8, size.width * 0.14), insetV = max(3.2, size.height * 0.020)
        let insert = RoundedRectangle(cornerRadius: max(2, r * 0.50), style: .continuous)
        let innerW = max(1, size.width - insetH * 1.9), innerH = max(1, size.height - insetV * 2)

        return ZStack {
            Group {
                if let cover {
                    Image(decorative: cover, scale: 1).resizable().scaledToFill()
                        .frame(width: innerW, height: innerH, alignment: .leading).clipped()
                } else {
                    Color.black.opacity(dark ? 0.28 : 0.12)
                }
            }
            .frame(width: innerW, height: innerH)
            .clipShape(insert)
            .overlay {
                insert.fill(LinearGradient(colors: [.black.opacity(0.32), .black.opacity(0.06),
                                                    .white.opacity(0.06), .black.opacity(0.22)],
                                           startPoint: .leading, endPoint: .trailing))
            }

            // High-contrast narrow glass edge on outer spine with localized corner refraction
            outer.strokeBorder(.black.opacity(dark ? 0.46 : 0.20), lineWidth: 0.9)
            outer.strokeBorder(LinearGradient(
                stops: [
                    .init(color: warmWhite.opacity(dark ? 0.66 : 0.88), location: 0.00),
                    .init(color: iceLavender.opacity(dark ? 0.16 : 0.28), location: 0.18),
                    .init(color: .white.opacity(dark ? 0.06 : 0.12), location: 0.52),
                    .init(color: iceLavender.opacity(dark ? 0.18 : 0.30), location: 0.84),
                    .init(color: warmWhite.opacity(dark ? 0.58 : 0.82), location: 1.00)
                ],
                startPoint: .top, endPoint: .bottom
            ), lineWidth: 0.75)

            // Hinge ridge: crisp peaks at top/bottom corners, subtle thin glass line in the middle
            Rectangle()
                .fill(LinearGradient(
                    stops: [
                        .init(color: warmWhite.opacity(dark ? 0.78 : 0.94), location: 0.00),
                        .init(color: iceLavender.opacity(dark ? 0.24 : 0.38), location: 0.14),
                        .init(color: .white.opacity(dark ? 0.12 : 0.22), location: 0.50),
                        .init(color: iceLavender.opacity(dark ? 0.24 : 0.38), location: 0.86),
                        .init(color: warmWhite.opacity(dark ? 0.72 : 0.90), location: 1.00)
                    ],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: 0.95)
                .padding(.vertical, r * 0.5)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: size.width, height: size.height)
    }

    private func frontLid(size: CGSize) -> some View {
        let radius = max(5.5, size.width * 0.068)
        let bezel = max(2.8, size.width * 0.026)
        let outer = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let innerBevel = RoundedRectangle(cornerRadius: max(3.5, radius - bezel * 0.42), style: .continuous)
        let insert = RoundedRectangle(cornerRadius: max(2.5, radius - bezel * 0.82), style: .continuous)
        let innerW = max(1, size.width - bezel * 2), innerH = max(1, size.height - bezel * 2)

        return ZStack {
            Group {
                if let cover {
                    Image(decorative: cover, scale: 1).resizable().scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(colors: dark ? [Color(white: 0.13), Color(white: 0.09)]
                                                    : [Color(white: 0.87), Color(white: 0.79)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "film").font(.title2).foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(width: innerW, height: innerH)
            .clipShape(insert)
            .overlay { insert.strokeBorder(.black.opacity(dark ? 0.62 : 0.28), lineWidth: 0.8) }

            // Narrow inner refractive edge: crisp at top & weight-bearing bottom, recessed along sides
            innerBevel.strokeBorder(.black.opacity(dark ? 0.42 : 0.18), lineWidth: 0.75)
                .padding(bezel * 0.42)
            innerBevel.strokeBorder(LinearGradient(
                stops: [
                    .init(color: iceLavender.opacity(dark ? 0.56 : 0.78), location: 0.00),
                    .init(color: .white.opacity(dark ? 0.10 : 0.18), location: 0.22),
                    .init(color: .white.opacity(dark ? 0.08 : 0.14), location: 0.78),
                    .init(color: warmWhite.opacity(dark ? 0.52 : 0.74), location: 1.00)
                ],
                startPoint: .top, endPoint: .bottom
            ), lineWidth: 0.75)
                .padding(bezel * 0.42)

            // Outer glass rim: dark refractive base + localized high-contrast warm-white / ice-lavender corners
            outer.strokeBorder(.black.opacity(dark ? 0.48 : 0.22), lineWidth: 1.1)
            outer.strokeBorder(LinearGradient(
                stops: [
                    .init(color: warmWhite.opacity(dark ? 0.72 : 0.90), location: 0.00),
                    .init(color: iceLavender.opacity(dark ? 0.20 : 0.34), location: 0.20),
                    .init(color: .white.opacity(dark ? 0.08 : 0.16), location: 0.52),
                    .init(color: iceLavender.opacity(dark ? 0.22 : 0.36), location: 0.84),
                    .init(color: warmWhite.opacity(dark ? 0.66 : 0.86), location: 1.00)
                ],
                startPoint: .top, endPoint: .bottom
            ), lineWidth: 0.85)

            // Tight corner glints (warm-white & pale blue-violet)
            cornerGlint(shape: outer, center: .topLeading, color: warmWhite, radius: radius * 1.9, width: 1.25)
            cornerGlint(shape: outer, center: .topTrailing, color: iceLavender, radius: radius * 1.6, width: 1.05)
            cornerGlint(shape: outer, center: .bottomLeading, color: warmWhite, radius: radius * 1.8, width: 1.2)
            cornerGlint(shape: outer, center: .bottomTrailing, color: iceLavender, radius: radius * 1.5, width: 1.0)

            // Top edge & load-bearing bottom edge narrow refractive double highlight
            edgeGlint(width: innerW * 0.72, colors: [.clear, iceLavender.opacity(dark ? 0.52 : 0.76),
                                                     warmWhite.opacity(dark ? 0.62 : 0.84), .clear])
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, bezel * 0.34)
            edgeGlint(width: innerW * 0.78, colors: [.clear, warmWhite.opacity(dark ? 0.68 : 0.88),
                                                     iceLavender.opacity(dark ? 0.46 : 0.66), .clear])
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, bezel * 0.32)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(outer)
    }

    private func cornerGlint(shape: RoundedRectangle, center: UnitPoint, color: Color,
                             radius: CGFloat, width: CGFloat) -> some View {
        shape.strokeBorder(
            RadialGradient(colors: [color.opacity(dark ? 0.88 : 0.98), .clear],
                           center: center, startRadius: 0, endRadius: radius),
            lineWidth: width
        )
    }

    private func edgeGlint(width: CGFloat, colors: [Color]) -> some View {
        Capsule()
            .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
            .frame(width: width, height: 0.9)
    }

    private func continuousShellPath(box: CGSize, spineQuad: Quad, frontQuad: Quad) -> Path {
        let rx = max(2.5, box.width * 0.025), ry = max(3.5, box.height * 0.024)
        let spineSpan = max(1, frontQuad.tl.x - spineQuad.tl.x)
        let topHinge = CGPoint(x: frontQuad.tl.x + box.width * 0.048, y: frontQuad.tl.y + box.height * 0.002)
        let botHinge = CGPoint(x: frontQuad.bl.x + box.width * 0.048, y: frontQuad.bl.y - box.height * 0.002)
        return Path { p in
            p.move(to: CGPoint(x: spineQuad.tl.x, y: spineQuad.tl.y + ry))
            p.addCurve(to: CGPoint(x: spineQuad.tl.x + rx, y: spineQuad.tl.y - ry * 0.12),
                       control1: CGPoint(x: spineQuad.tl.x, y: spineQuad.tl.y + ry * 0.22),
                       control2: CGPoint(x: spineQuad.tl.x + rx * 0.35, y: spineQuad.tl.y - ry * 0.04))
            p.addCurve(to: topHinge,
                       control1: CGPoint(x: frontQuad.tl.x - spineSpan * 0.38, y: frontQuad.tl.y + box.height * 0.002),
                       control2: CGPoint(x: frontQuad.tl.x + box.width * 0.012, y: frontQuad.tl.y))
            p.addLine(to: CGPoint(x: frontQuad.tr.x - rx * 1.4, y: frontQuad.tr.y - box.height * 0.001))
            p.addQuadCurve(to: CGPoint(x: frontQuad.tr.x, y: frontQuad.tr.y + ry * 1.1), control: frontQuad.tr)
            p.addLine(to: CGPoint(x: frontQuad.br.x, y: frontQuad.br.y - ry * 1.1))
            p.addQuadCurve(to: CGPoint(x: frontQuad.br.x - rx * 1.4, y: frontQuad.br.y + box.height * 0.001),
                           control: frontQuad.br)
            p.addLine(to: botHinge)
            p.addCurve(to: CGPoint(x: spineQuad.bl.x + rx, y: spineQuad.bl.y + ry * 0.12),
                       control1: CGPoint(x: frontQuad.bl.x + box.width * 0.012, y: frontQuad.bl.y),
                       control2: CGPoint(x: frontQuad.bl.x - spineSpan * 0.38, y: frontQuad.bl.y - box.height * 0.002))
            p.addCurve(to: CGPoint(x: spineQuad.bl.x, y: spineQuad.bl.y - ry),
                       control1: CGPoint(x: spineQuad.bl.x + rx * 0.35, y: spineQuad.bl.y + ry * 0.04),
                       control2: CGPoint(x: spineQuad.bl.x, y: spineQuad.bl.y - ry * 0.22))
            p.closeSubpath()
        }
    }
}

private struct Quad {
    let tl, tr, br, bl: CGPoint
}

private func quadProjection(from size: CGSize, to q: Quad) -> ProjectionTransform {
    let w = max(1, size.width), h = max(1, size.height)
    let dx1 = q.tr.x - q.br.x, dy1 = q.tr.y - q.br.y
    let dx2 = q.bl.x - q.br.x, dy2 = q.bl.y - q.br.y
    let sx = q.tl.x - q.tr.x + q.br.x - q.bl.x, sy = q.tl.y - q.tr.y + q.br.y - q.bl.y
    let denom = dx1 * dy2 - dy1 * dx2
    let g = abs(denom) < 1e-6 ? 0 : (sx * dy2 - sy * dx2) / denom
    let k = abs(denom) < 1e-6 ? 0 : (dx1 * sy - dy1 * sx) / denom
    let a = q.tr.x - q.tl.x + g * q.tr.x, b = q.bl.x - q.tl.x + k * q.bl.x
    let d = q.tr.y - q.tl.y + g * q.tr.y, e = q.bl.y - q.tl.y + k * q.bl.y
    return ProjectionTransform(CATransform3D(
        m11: a / w, m12: d / w, m13: 0, m14: g / w,
        m21: b / h, m22: e / h, m23: 0, m24: k / h,
        m31: 0, m32: 0, m33: 1, m34: 0,
        m41: q.tl.x, m42: q.tl.y, m43: 0, m44: 1
    ))
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
