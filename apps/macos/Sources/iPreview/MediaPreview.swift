import SwiftUI
import iPreviewCore

struct PreviewRequest {
    let items: [Media]
    let selection: Int64
    let columns: Int
}

struct MediaPreview: View {
    let request: PreviewRequest
    let close: () -> Void

    @ViewState private var index: Int
    @ViewState private var video = VideoPlayback()
    @ViewState private var scrubPosition: Double?
    @ViewState private var scrubbing = false
    @FocusState private var canvasFocused: Bool

    private var media: Media { request.items[index] }

    init(request: PreviewRequest, close: @escaping () -> Void) {
        self.request = request
        self.close = close
        _index = ViewState(initialValue: request.items.firstIndex(where: { $0.id == request.selection })!)
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Color(red: 0.050, green: 0.058, blue: 0.074)
                neighbors(in: size)
                stage
                    .frame(width: size.width * 0.76, height: size.height * 0.72)
                    .clipShape(.rect(cornerRadius: 12))
                    .id(media.id)
                    .accessibilityLabel(media.name)
                navigation
                    .padding(.horizontal, 16)
            }
            .overlay(alignment: .top) { topControls }
            .overlay(alignment: .bottom) {
                if media.kind == .video, video.message == nil {
                    playerControls
                        .frame(width: min(size.width * 0.65, 620))
                        .padding(.bottom, 22)
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
        .focusable()
        .focusEffectDisabled()
        .focused($canvasFocused)
        .onKeyPress(keys: [.escape, .space, .leftArrow, .rightArrow, .upArrow, .downArrow], phases: [.down, .repeat]) { press in
            switch press.key {
            case .escape:
                if press.phase == .down { close() }
            case .space:
                if press.phase == .down, media.kind == .video { video.toggle() }
            default:
                index = moveIndex(index, key: press.key, columns: request.columns, count: request.items.count)
            }
            return .handled
        }
        .task {
            await Task.yield()
            canvasFocused = true
        }
        .task(id: media.id) {
            scrubPosition = nil
            scrubbing = false
            if media.kind == .video {
                video.start(media)
            } else {
                video.stop()
            }
        }
        .onDisappear { video.stop() }
        .accessibilityIdentifier("media-preview")
    }

    private var topControls: some View {
        HStack {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.callout.weight(.semibold))
                    .frame(width: 35, height: 35)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("关闭预览")
            .help("关闭预览（Esc）")

            Spacer()
            Text(media.name)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(.thinMaterial, in: Capsule())
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, 19)
        .padding(.top, 41)
    }

    @ViewBuilder
    private var stage: some View {
        if media.kind == .video {
            if let message = video.message {
                PreviewError(message: message)
            } else {
                VideoCanvas(player: video.player)
                    .background(.black)
            }
        } else {
            PhotoCanvas(media: media)
        }
    }

    private var navigation: some View {
        HStack {
            if index > 0 {
                navigate("chevron.left", label: "上一项", step: -1)
            }
            Spacer()
            if index < request.items.count - 1 {
                navigate("chevron.right", label: "下一项", step: 1)
            }
        }
    }

    private func navigate(_ icon: String, label: String, step: Int) -> some View {
        Button {
            index += step
            canvasFocused = true
        } label: {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .frame(width: 34, height: 34)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    @ViewBuilder
    private func neighbors(in size: CGSize) -> some View {
        let vertical = request.columns
        ZStack {
            neighbor(at: index - 1, width: size.width * 0.27, height: size.height * 0.54)
                .offset(x: -size.width * 0.43)
            neighbor(at: index + 1, width: size.width * 0.27, height: size.height * 0.54)
                .offset(x: size.width * 0.43)
            neighbor(at: index - vertical, width: size.width * 0.54, height: size.height * 0.22)
                .offset(y: -size.height * 0.43)
            neighbor(at: index + vertical, width: size.width * 0.54, height: size.height * 0.22)
                .offset(y: size.height * 0.43)
        }
        .frame(width: size.width, height: size.height)
        .opacity(0.31)
        .blur(radius: 7)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func neighbor(at position: Int, width: CGFloat, height: CGFloat) -> some View {
        if request.items.indices.contains(position) {
            MediaThumbnail(media: request.items[position])
                .frame(width: width, height: height)
                .clipShape(.rect(cornerRadius: 12))
        }
    }

    private var playerControls: some View {
        HStack(spacing: 12) {
            Button {
                video.toggle()
                canvasFocused = true
            } label: {
                Image(systemName: video.isPlaying ? "pause.fill" : "play.fill")
                    .font(.callout.weight(.semibold))
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(video.isPlaying ? "暂停视频" : "播放视频")

            Text(time(scrubPosition ?? video.elapsed))
                .monospacedDigit()
                .accessibilityLabel("播放位置 \(time(scrubPosition ?? video.elapsed))")

            Slider(value: Binding(
                get: { min(scrubPosition ?? video.elapsed, max(video.duration, 1)) },
                set: { position in
                    if scrubbing {
                        scrubPosition = position
                    } else {
                        video.seek(position)
                    }
                }
            ), in: 0...max(video.duration, 1), onEditingChanged: { editing in
                scrubbing = editing
                if !editing, let scrubPosition {
                    video.seek(scrubPosition)
                    self.scrubPosition = nil
                }
            })
            .labelsHidden()
            .controlSize(.small)
            .accessibilityLabel("视频进度")
            .disabled(video.duration <= 0)

            Text(time(video.duration))
                .monospacedDigit()
                .accessibilityLabel("总时长 \(time(video.duration))")
        }
        .font(.caption)
        .padding(.horizontal, 15)
        .frame(height: 42)
        .background(.regularMaterial, in: Capsule())
    }

    private func time(_ seconds: Double) -> String {
        let rounded = Int(seconds)
        return String(format: "%d:%02d", rounded / 60, rounded % 60)
    }
}

func moveIndex(_ index: Int, key: KeyEquivalent, columns: Int, count: Int) -> Int {
    let candidate: Int
    switch key {
    case .leftArrow: candidate = index - 1
    case .rightArrow: candidate = index + 1
    case .upArrow: candidate = index - columns
    case .downArrow: candidate = index + columns
    default: return index
    }
    return (0..<count).contains(candidate) ? candidate : index
}
