import CoreGraphics
import SwiftUI

public struct RecordDeck: View {
    public let artwork: CGImage?
    public let isPlaying: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pausedAngle = 0.0
    @State private var spinStart: Date?

    public init(artwork: CGImage? = nil, isPlaying: Bool = false) {
        self.artwork = artwork
        self.isPlaying = isPlaying
    }

    private var isDark: Bool { colorScheme == .dark }
    private var shouldSpin: Bool { isPlaying && !reduceMotion }

    public var body: some View {
        GeometryReader { proxy in
            let scale = max(0.001, min(proxy.size.width / 440, proxy.size.height / 360))
            let p = Palette(isDark: isDark)
            ZStack {
                Canvas { ctx, size in
                    ctx.scaleBy(x: size.width / 440, y: size.height / 360)
                    drawStaticDeck(in: &ctx, p: p, isDark: isDark)
                }
                ZStack {
                    TimelineView(.animation(paused: !shouldSpin)) { timeline in
                        let angle = shouldSpin ? (pausedAngle + max(0, timeline.date.timeIntervalSince(spinStart ?? timeline.date)) * 45).truncatingRemainder(dividingBy: 360) : pausedAngle
                        labelView(p: p).rotationEffect(.degrees(angle))
                    }
                    .position(x: 178, y: 180)
                    Circle()
                        .fill(RadialGradient(colors: [p.spindleHi, p.arm[1], p.arm[2]], center: .init(x: 0.35, y: 0.35), startRadius: 0.5, endRadius: 7.5))
                        .overlay(Circle().stroke(.black.opacity(isDark ? 0.5 : 0.24), lineWidth: 0.6))
                        .overlay(Circle().inset(by: 2.8).stroke(.white.opacity(isDark ? 0.25 : 0.45), lineWidth: 0.5))
                        .frame(width: 13, height: 13).shadow(color: .black.opacity(isDark ? 0.65 : 0.35), radius: 2.2, x: 1, y: 1.6)
                        .position(x: 178, y: 180)
                    TonearmOverlay(isPlaying: isPlaying, isDark: isDark, reduceMotion: reduceMotion, p: p)
                }
                .frame(width: 440, height: 360).scaleEffect(scale)
            }
            .frame(width: 440 * scale, height: 360 * scale)
            .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.5)
        }
        .frame(idealWidth: 440, idealHeight: 360).aspectRatio(440.0 / 360.0, contentMode: .fit)
        .allowsHitTesting(false).accessibilityHidden(true)
        .onChange(of: shouldSpin, initial: true) { _, active in if active { spinStart = spinStart ?? Date() } else { freezeSpin() } }
        .onDisappear { freezeSpin() }
    }

    @ViewBuilder
    private func labelView(p: Palette) -> some View {
        Group {
            if let artwork, artwork.width > 0, artwork.height > 0 {
                Image(decorative: artwork, scale: 1).resizable().scaledToFill()
            } else {
                Circle().fill(RadialGradient(colors: [p.label[0], p.label[1]], center: .init(x: 0.4, y: 0.4), startRadius: 4, endRadius: 52))
                    .overlay(Circle().stroke((isDark ? Color.white : .black).opacity(0.09), lineWidth: 0.85).padding(9))
                    .overlay(Circle().stroke(p.label[2], lineWidth: 1.5).padding(19))
                    .overlay(Circle().stroke((isDark ? Color.white : .black).opacity(0.09), lineWidth: 0.75).padding(34))
            }
        }
        .frame(width: 104, height: 104).clipShape(Circle())
        .overlay(Circle().inset(by: 0.75).stroke(.black.opacity(isDark ? 0.35 : 0.14), lineWidth: 1.5))
        .overlay(Circle().stroke((isDark ? Color.white : .black).opacity(isDark ? 0.11 : 0.18), lineWidth: 0.9))
    }

    private func freezeSpin() {
        guard let start = spinStart else { return }
        pausedAngle = (pausedAngle + max(0, Date().timeIntervalSince(start)) * 45).truncatingRemainder(dividingBy: 360)
        spinStart = nil
    }
}

private struct Palette: Sendable {
    let plinth, platter, arm, label, head: [Color]
    let plinthSpec, plinthBorder, plinthShadow, lip, spindleHi, stylus, well: Color
    let brush, groove, specMain, specSub: Double

    init(isDark: Bool) {
        let c = { (r: Double, g: Double, b: Double) in Color(red: r, green: g, blue: b) }
        plinth = isDark ? [c(0.18, 0.184, 0.196), c(0.155, 0.159, 0.17), c(0.132, 0.135, 0.145)] : [c(0.918, 0.902, 0.875), c(0.878, 0.861, 0.831), c(0.836, 0.818, 0.786)]
        platter = isDark ? [c(0.255, 0.262, 0.278), c(0.175, 0.18, 0.192), c(0.095, 0.098, 0.106)] : [c(0.955, 0.945, 0.925), c(0.79, 0.772, 0.742), c(0.56, 0.542, 0.512)]
        arm = isDark ? [c(0.74, 0.76, 0.79), c(0.44, 0.46, 0.49), c(0.21, 0.22, 0.24)] : [c(0.94, 0.93, 0.9), c(0.74, 0.72, 0.68), c(0.44, 0.42, 0.39)]
        label = isDark ? [c(0.176, 0.18, 0.192), c(0.145, 0.149, 0.16), c(0.8, 0.64, 0.5).opacity(0.42)] : [c(0.905, 0.892, 0.868), c(0.855, 0.84, 0.812), c(0.36, 0.52, 0.48).opacity(0.45)]
        head = isDark ? [c(0.19, 0.195, 0.21), c(0.11, 0.115, 0.125)] : [c(0.56, 0.54, 0.5), c(0.35, 0.33, 0.3)]
        plinthSpec = .white.opacity(isDark ? 0.085 : 0.72)
        plinthBorder = isDark ? .black.opacity(0.55) : c(0.68, 0.66, 0.62).opacity(0.75)
        plinthShadow = .black.opacity(isDark ? 0.46 : 0.17)
        lip = .black.opacity(isDark ? 0.65 : 0.35)
        spindleHi = isDark ? c(0.8, 0.82, 0.85) : c(0.97, 0.96, 0.94)
        stylus = isDark ? c(0.84, 0.64, 0.44) : c(0.82, 0.58, 0.34)
        well = isDark ? c(0.098, 0.102, 0.11) : c(0.64, 0.62, 0.58)
        (brush, groove, specMain, specSub) = isDark ? (0.018, 0.042, 0.145, 0.085) : (0.04, 0.055, 0.185, 0.11)
    }
}

private func drawStaticDeck(in ctx: inout GraphicsContext, p: Palette, isDark: Bool) {
    let plinthRect = CGRect(x: 8, y: 8, width: 424, height: 344)
    let plinthPath = Path(roundedRect: plinthRect, cornerRadius: 24, style: .continuous)
    ctx.drawLayer { $0.addFilter(.shadow(color: p.plinthShadow, radius: 7, x: 0, y: 4)); $0.fill(plinthPath, with: .color(p.plinth[1])) }
    ctx.fill(plinthPath, with: .linearGradient(Gradient(colors: p.plinth), startPoint: plinthRect.origin, endPoint: .init(x: 432, y: 352)))
    ctx.drawLayer { brush in
        brush.clip(to: plinthPath)
        for i in 0..<138 {
            let y = 9.5 + Double(i) * 2.5
            brush.stroke(Path { $0.move(to: .init(x: 8, y: y)); $0.addLine(to: .init(x: 432, y: y)) }, with: .color((i.isMultiple(of: 2) ? Color.white : .black).opacity(p.brush * (i.isMultiple(of: 2) ? 1 : 0.7))), lineWidth: 0.75)
        }
        brush.stroke(Path(roundedRect: plinthRect.insetBy(dx: 0.8, dy: 0.8), cornerRadius: 23.2, style: .continuous), with: .linearGradient(Gradient(colors: [p.plinthSpec, p.plinthSpec.opacity(0.18), .clear]), startPoint: .init(x: 220, y: 8), endPoint: .init(x: 220, y: 352)), lineWidth: 1.25)
    }
    ctx.stroke(plinthPath, with: .color(p.plinthBorder), lineWidth: 1)

    let center = CGPoint(x: 178, y: 180)
    let platterRect = CGRect(x: 20, y: 22, width: 316, height: 316)
    ctx.drawLayer { $0.addFilter(.shadow(color: .black.opacity(isDark ? 0.55 : 0.24), radius: 7, x: 1.5, y: 3.5)); $0.fill(Path(ellipseIn: platterRect), with: .color(p.platter[2])) }
    ctx.fill(Path(ellipseIn: platterRect), with: .linearGradient(Gradient(stops: [.init(color: p.platter[0], location: 0), .init(color: p.platter[1], location: 0.45), .init(color: p.platter[2], location: 0.82), .init(color: p.platter[1], location: 1)]), startPoint: platterRect.origin, endPoint: .init(x: 336, y: 338)))
    ctx.stroke(Path(ellipseIn: platterRect.insetBy(dx: 3.5, dy: 3.5)), with: .linearGradient(Gradient(colors: [p.platter[2], p.platter[0]]), startPoint: platterRect.origin, endPoint: .init(x: 336, y: 338)), lineWidth: 1.2)

    let vinylRect = CGRect(x: 28, y: 30, width: 300, height: 300)
    let vinylPath = Path(ellipseIn: vinylRect)
    ctx.stroke(Path(ellipseIn: vinylRect.insetBy(dx: -1, dy: -1)), with: .color(p.lip), lineWidth: 2)
    ctx.fill(vinylPath, with: .radialGradient(Gradient(colors: [Color(red: 0.092, green: 0.095, blue: 0.102), Color(red: 0.055, green: 0.058, blue: 0.064)]), center: center, startRadius: 52, endRadius: 150))
    ctx.drawLayer { grooves in
        grooves.clip(to: Path { $0.addEllipse(in: vinylRect); $0.addEllipse(in: CGRect(x: 126, y: 128, width: 104, height: 104)) }, style: FillStyle(eoFill: true))
        for step in 0...40 {
            let r = 67.0 + Double(step) * 1.95
            if abs(r - 92) >= 1.2 && abs(r - 120) >= 1.2 {
                grooves.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(p.groove * [1.15, 0.35, 0.7, 0.35, 0.9][step % 5])), lineWidth: 0.65)
            }
        }
        grooves.stroke(Path(ellipseIn: CGRect(x: 119, y: 121, width: 118, height: 118)), with: .color(.white.opacity(p.groove * 0.55)), lineWidth: 0.6)
        grooves.fill(vinylPath, with: .conicGradient(Gradient(stops: [.init(color: .clear, location: 0), .init(color: .white.opacity(p.specSub), location: 0.14), .init(color: .clear, location: 0.28), .init(color: .clear, location: 0.5), .init(color: .white.opacity(p.specMain), location: 0.635), .init(color: .clear, location: 0.77), .init(color: .clear, location: 1)]), center: center))
    }
    ctx.stroke(Path(ellipseIn: vinylRect.insetBy(dx: 0.75, dy: 0.75)), with: .linearGradient(Gradient(colors: [.white.opacity(isDark ? 0.14 : 0.22), .clear, .white.opacity(isDark ? 0.08 : 0.12)]), startPoint: vinylRect.origin, endPoint: .init(x: 328, y: 330)), lineWidth: 1)

    let baseRect = CGRect(x: 344, y: 42, width: 60, height: 60)
    ctx.drawLayer { $0.addFilter(.shadow(color: .black.opacity(isDark ? 0.45 : 0.2), radius: 4, x: 1, y: 2.5)); $0.fill(Path(ellipseIn: baseRect), with: .color(p.arm[1])) }
    ctx.fill(Path(ellipseIn: baseRect), with: .linearGradient(Gradient(colors: p.arm), startPoint: baseRect.origin, endPoint: .init(x: 404, y: 102)))
    ctx.stroke(Path(ellipseIn: baseRect), with: .color(.black.opacity(isDark ? 0.55 : 0.22)), lineWidth: 0.85)
    ctx.fill(Path(ellipseIn: baseRect.insetBy(dx: 5.5, dy: 5.5)), with: .color(p.well))
    ctx.fill(Path(ellipseIn: baseRect.insetBy(dx: 13, dy: 13)), with: .linearGradient(Gradient(colors: p.arm), startPoint: .init(x: 357, y: 55), endPoint: .init(x: 391, y: 89)))
    ctx.fill(Path(ellipseIn: CGRect(x: 378, y: 201, width: 14, height: 14)), with: .linearGradient(Gradient(colors: p.arm), startPoint: .init(x: 378, y: 201), endPoint: .init(x: 392, y: 215)))
    ctx.fill(Path(roundedRect: CGRect(x: 380.5, y: 205, width: 9, height: 6), cornerRadius: 2.2), with: .color(p.head[1]))
}

private struct TonearmOverlay: View {
    let isPlaying, isDark, reduceMotion: Bool, p: Palette
    var body: some View {
        let tube = Path { $0.move(to: .init(x: 374, y: 80)); $0.addCurve(to: .init(x: 380, y: 166), control1: .init(x: 375, y: 110), control2: .init(x: 380, y: 138)); $0.addCurve(to: .init(x: 364, y: 246), control1: .init(x: 380, y: 196), control2: .init(x: 372, y: 226)) }
        ZStack {
            ZStack {
                Path { $0.move(to: .init(x: 374, y: 64)); $0.addLine(to: .init(x: 374, y: 52)) }.stroke(p.arm[2], style: .init(lineWidth: 3.2, lineCap: .round))
                RoundedRectangle(cornerRadius: 3.2, style: .continuous).fill(LinearGradient(colors: p.arm, startPoint: .leading, endPoint: .trailing))
                    .overlay(RoundedRectangle(cornerRadius: 3.2, style: .continuous).stroke(.black.opacity(isDark ? 0.45 : 0.22), lineWidth: 0.7)).frame(width: 15, height: 19).position(x: 374, y: 45.5)
                tube.stroke(p.arm[2], style: .init(lineWidth: 5.8, lineCap: .round, lineJoin: .round))
                tube.stroke(LinearGradient(colors: p.arm, startPoint: .init(x: 0.81, y: 0.2), endPoint: .init(x: 0.89, y: 0.7)), style: .init(lineWidth: 4.6, lineCap: .round, lineJoin: .round))
                tube.stroke(.white.opacity(isDark ? 0.24 : 0.45), style: .init(lineWidth: 1.15, lineCap: .round, lineJoin: .round))
                ZStack {
                    Path { $0.move(to: .init(x: 368.5, y: 258)); $0.addLine(to: .init(x: 377, y: 260.5)) }.stroke(p.arm[1], style: .init(lineWidth: 1.7, lineCap: .round))
                    Path { $0.move(to: .init(x: 364, y: 270)); $0.addLine(to: .init(x: 364, y: 277)) }.stroke(p.stylus, style: .init(lineWidth: 1.6, lineCap: .round))
                    if isPlaying { Circle().fill(RadialGradient(colors: [p.stylus.opacity(0.42), .clear], center: .center, startRadius: 0, endRadius: 5)).frame(width: 10, height: 10).position(x: 364, y: 277) }
                    RoundedRectangle(cornerRadius: 2.2, style: .continuous).fill(LinearGradient(colors: p.head, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(RoundedRectangle(cornerRadius: 2.2, style: .continuous).stroke(.white.opacity(isDark ? 0.14 : 0.35), lineWidth: 0.75))
                        .overlay(HStack(spacing: 2.2) { Capsule().fill(.white.opacity(isDark ? 0.16 : 0.26)).frame(width: 0.9, height: 7); Capsule().fill(.white.opacity(isDark ? 0.16 : 0.26)).frame(width: 0.9, height: 7) }.offset(y: -2))
                        .frame(width: 11, height: 27).position(x: 364, y: 257.5)
                }
                .rotationEffect(.degrees(24), anchor: UnitPoint(x: 364.0 / 440.0, y: 246.0 / 360.0))
            }
            .shadow(color: .black.opacity(isDark ? 0.58 : 0.26), radius: 4.5, x: 2.5, y: isPlaying ? 4 : 6)
            .rotationEffect(.degrees(isPlaying ? 26 : -4), anchor: UnitPoint(x: 0.85, y: 0.2))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: isPlaying)
            Circle().fill(LinearGradient(colors: p.arm, startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().inset(by: 0.5).stroke(.white.opacity(isDark ? 0.22 : 0.55), lineWidth: 0.8))
                .frame(width: 24, height: 24).shadow(color: .black.opacity(isDark ? 0.5 : 0.22), radius: 2.5, x: 0.5, y: 1.5).position(x: 374, y: 72)
        }
        .frame(width: 440, height: 360)
    }
}
