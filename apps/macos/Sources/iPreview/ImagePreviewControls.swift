import AppKit
import SwiftUI
import iPreviewCore

enum ImageSlideState: Equatable {
    case stopped, playing, paused

    var action: String {
        switch self {
        case .stopped: "开始自动播放"
        case .playing: "暂停自动播放"
        case .paused: "继续自动播放"
        }
    }
}

struct ImagePreviewControls: View {
    @Binding var comic: Bool
    @Binding var coverSingle: Bool
    @Binding var slideState: ImageSlideState
    @Binding var interval: Double
    let focusCanvas: () -> Void

    @State private var editingInterval = false
    @State private var customInterval = ""

    private var customSeconds: Double? {
        guard let value = try? Double(customInterval, format: .number), (0.5...300).contains(value) else { return nil }
        return value
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                comic.toggle()
                focusCanvas()
            } label: {
                Image(systemName: comic ? "book.fill" : "book")
            }
            .help("漫画双页")
            .accessibilityLabel("漫画双页")
            .accessibilityValue(comic ? "已打开" : "已关闭")

            if comic {
                Button {
                    coverSingle.toggle()
                    focusCanvas()
                } label: {
                    Text(coverSingle ? "首页单页" : "首页双页")
                }
                .help("切换首页的单双页配对")
            }

            Divider().frame(height: 14)

            Button {
                slideState = slideState == .playing ? .paused : .playing
                focusCanvas()
            } label: {
                Image(systemName: slideState == .playing ? "pause.fill" : "play.fill")
            }
            .help(slideState.action)
            .accessibilityLabel(slideState.action)

            if slideState != .stopped {
                Button {
                    slideState = .stopped
                    focusCanvas()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .help("停止自动播放")
                .accessibilityLabel("停止自动播放")
            }

            Menu {
                ForEach([1, 2, 3, 5, 10], id: \.self) { seconds in
                    Button("\(seconds) 秒") {
                        interval = Double(seconds)
                        focusCanvas()
                    }
                }
                Button("自定义…") {
                    customInterval = interval.formatted(.number)
                    editingInterval = true
                }
            } label: {
                Text("\(interval, format: .number) 秒")
                    .monospacedDigit()
            }
            .fixedSize()
            .menuStyle(.borderlessButton)
            .help("设置每张图片的停留时间")
            .accessibilityLabel("播放间隔")
            .accessibilityValue("\(interval, format: .number) 秒")
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: 40)
        .previewGlass(in: Capsule(), interactive: true)
        .alert("播放间隔", isPresented: $editingInterval) {
            TextField("0.5 至 300 秒", text: $customInterval)
            Button("取消", role: .cancel) { focusCanvas() }
            Button("确定") {
                if let customSeconds { interval = customSeconds }
                focusCanvas()
            }
            .disabled(customSeconds == nil)
        } message: {
            Text("输入 0.5 至 300 秒。")
        }
    }
}

struct ComicPhotoSpread: View {
    let first: Media
    let second: Media?
    let forward: Bool
    let turn: Int64?
    let poster: (Int64) -> CGImage?
    let firstResolved: (Int64) -> Void
    let secondResolved: (Int64) -> Void

    var body: some View {
        HStack(spacing: 0) {
            page(first, alignment: second == nil ? .center : .trailing,
                 spine: second == nil ? .center : .trailing,
                 turn: forward || second == nil ? turn : nil, onResolved: firstResolved)
            if let second {
                page(second, alignment: .leading, spine: .leading, turn: forward ? nil : turn,
                     onResolved: secondResolved)
            }
        }
    }

    private func page(_ media: Media, alignment: Alignment, spine: UnitPoint, turn: Int64?,
                      onResolved: @escaping (Int64) -> Void) -> some View {
        PhotoCanvas(media: media, poster: poster(media.id), alignment: alignment, onResolved: onResolved)
            .accessibilityLabel(media.name)
            .keyframeAnimator(initialValue: 0.0, trigger: turn) { content, angle in
                content
                    .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), anchor: spine, perspective: 0.45)
                    .opacity(1 - abs(angle) / 90)
            } keyframes: { _ in
                if turn != nil {
                    MoveKeyframe(forward ? -75 : 75)
                    CubicKeyframe(0, duration: 0.24)
                } else {
                    MoveKeyframe(0)
                }
            }
    }
}
