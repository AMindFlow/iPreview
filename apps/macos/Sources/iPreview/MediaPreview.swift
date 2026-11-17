import SwiftUI
import iPreviewCore

struct PreviewRequest {
    let items: [Media]
    let selection: Int64
    let layout: BrowseLayout
}

struct PreviewOriginKey: PreferenceKey {
    static let defaultValue: [Int64: Anchor<CGRect>] = [:]

    static func reduce(value: inout [Int64: Anchor<CGRect>], nextValue: () -> [Int64: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

struct MediaPreview: View {
    let request: PreviewRequest
    let sourceFrame: (Int64) -> CGRect?
    let close: (Int64) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var expanded = false
    @ViewState private var closingSelection: Int64?
    @ViewState private var index: Int
    @ViewState private var video = VideoPlayback()
    @ViewState private var scrubPosition: Double?
    @ViewState private var scrubbing = false
    @FocusState private var focus: Focus?

    private enum Focus: Hashable { case canvas, timeline }
    private static let previewKeys: Set<KeyEquivalent> = [
        .escape, .space, .tab, .leftArrow, .rightArrow, .upArrow, .downArrow,
    ]

    private var media: Media { request.items[index] }

    init(request: PreviewRequest, sourceFrame: @escaping (Int64) -> CGRect?, close: @escaping (Int64) -> Void) {
        self.request = request
        self.sourceFrame = sourceFrame
        self.close = close
        _index = ViewState(initialValue: request.items.firstIndex(where: { $0.id == request.selection })!)
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let window = CGRect(origin: .zero, size: size)
            let destination = window.insetBy(dx: size.width * 0.12, dy: size.height * 0.14)
            let thumbnail = sourceFrame(closingSelection ?? request.selection)?.intersection(window)
            let origin = thumbnail.flatMap { $0.width >= 8 && $0.height >= 8 ? $0 : nil }
            let fallback = destination.insetBy(dx: size.width * 0.10, dy: size.height * 0.10)
            let frame = expanded || reduceMotion ? destination : origin ?? fallback
            ZStack {
                Color(red: 0.050, green: 0.058, blue: 0.074)
                    .opacity(expanded ? 1 : 0)
                    .onTapGesture { focus = .canvas }
                neighbors(in: size)
                    .opacity(expanded ? 1 : 0)
                stage
                    .id(media.id)
                    .frame(width: frame.width, height: frame.height)
                    .clipShape(.rect(cornerRadius: expanded ? 12 : min(12, frame.height * 0.12)))
                    .position(x: frame.midX, y: frame.midY)
                    .opacity(expanded || (!reduceMotion && origin != nil) ? 1 : 0)
                    .accessibilityLabel(media.name)
                    .onTapGesture { focus = .canvas }
                navigation
                    .opacity(expanded ? 1 : 0)
            }
            .focusable()
            .focusEffectDisabled()
            .focused($focus, equals: .canvas)
            .onKeyPress(keys: Self.previewKeys, phases: [.down, .repeat], action: handleKey)
            .overlay(alignment: .top) { topControls.opacity(expanded ? 1 : 0) }
            .overlay(alignment: .bottom) {
                if media.kind == .video, video.message == nil {
                    playerControls
                        .frame(width: min(size.width * 0.65, 620))
                        .padding(.bottom, 22)
                        .opacity(expanded ? 1 : 0)
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
        .task {
            await Task.yield()
            guard closingSelection == nil else { return }
            focus = .canvas
            withAnimation(transitionAnimation) { expanded = true }
        }
        .task(id: media.id) {
            guard closingSelection == nil else { return }
            scrubPosition = nil
            scrubbing = false
            if media.kind == .video {
                video.start(media)
            } else {
                video.stop()
            }
        }
        .onChange(of: video.message) { _, message in
            if message != nil { focus = .canvas }
        }
        .onDisappear { video.stop() }
        .allowsHitTesting(closingSelection == nil)
        .accessibilityIdentifier("media-preview")
    }

    private var transitionAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .easeInOut(duration: 0.24)
    }

    private func dismiss(returningTo selection: Int64) {
        guard closingSelection == nil else { return }
        closingSelection = selection
        video.player.pause()
        withAnimation(transitionAnimation, completionCriteria: .logicallyComplete) {
            expanded = false
        } completion: {
            close(selection)
        }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        if closingSelection != nil { return .handled }
        switch press.key {
        case .escape:
            if press.phase == .down { dismiss(returningTo: request.selection) }
        case .space:
            guard focus == .canvas else { return .ignored }
            if press.phase == .down { dismiss(returningTo: media.id) }
        case .tab:
            guard media.kind == .video, video.message == nil, video.duration > 0 else { return .ignored }
            if press.phase == .down { focus = focus == .timeline ? .canvas : .timeline }
        default:
            if focus == .timeline {
                let backward = press.key == .leftArrow || press.key == .downArrow
                video.seek(video.elapsed + (backward ? -0.25 : 0.25))
            } else if let destination = neighbor(toward: press.key) {
                index = destination
            }
        }
        return .handled
    }

    private var topControls: some View {
        HStack {
            Button {
                dismiss(returningTo: request.selection)
            } label: {
                Image(systemName: "xmark")
                    .font(.callout.weight(.semibold))
                    .frame(width: 35, height: 35)
                    .previewGlass(in: Circle(), interactive: true)
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
                .previewGlass(in: Capsule())
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
        ZStack {
            HStack {
                navigationButton(toward: .leftArrow, icon: "chevron.left", label: "左侧媒体")
                Spacer()
                navigationButton(toward: .rightArrow, icon: "chevron.right", label: "右侧媒体")
            }
            .padding(.horizontal, 16)
            VStack {
                navigationButton(toward: .upArrow, icon: "chevron.up", label: "上方媒体")
                Spacer()
                navigationButton(toward: .downArrow, icon: "chevron.down", label: "下方媒体")
            }
            .padding(.top, 42)
            .padding(.bottom, media.kind == .video && video.message == nil ? 76 : 20)
        }
    }

    @ViewBuilder
    private func navigationButton(toward key: KeyEquivalent, icon: String, label: String) -> some View {
        if let destination = neighbor(toward: key) {
            Button {
                index = destination
                focus = .canvas
            } label: {
                Image(systemName: icon)
                    .font(.body.weight(.medium))
                    .frame(width: 34, height: 34)
                    .previewGlass(in: Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .help(label)
        }
    }

    private func neighbor(toward key: KeyEquivalent) -> Int? {
        request.layout.neighbor(of: index, toward: key, count: request.items.count)
    }

    @ViewBuilder
    private func neighbors(in size: CGSize) -> some View {
        ZStack {
            neighborThumbnail(toward: .leftArrow, width: size.width * 0.27, height: size.height * 0.54)
                .offset(x: -size.width * 0.43)
            neighborThumbnail(toward: .rightArrow, width: size.width * 0.27, height: size.height * 0.54)
                .offset(x: size.width * 0.43)
            neighborThumbnail(toward: .upArrow, width: size.width * 0.54, height: size.height * 0.22)
                .offset(y: -size.height * 0.43)
            neighborThumbnail(toward: .downArrow, width: size.width * 0.54, height: size.height * 0.22)
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
    private func neighborThumbnail(toward key: KeyEquivalent, width: CGFloat, height: CGFloat) -> some View {
        if let position = neighbor(toward: key) {
            MediaThumbnail(media: request.items[position])
                .frame(width: width, height: height)
                .clipShape(.rect(cornerRadius: 12))
        }
    }

    private var playerControls: some View {
        HStack(spacing: 12) {
            Button {
                video.toggle()
                focus = .canvas
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
                if !editing {
                    focus = .timeline
                    if let scrubPosition {
                        video.seek(scrubPosition)
                        self.scrubPosition = nil
                    }
                }
            })
            .labelsHidden()
            .controlSize(.small)
            .accessibilityLabel("视频进度")
            .disabled(video.duration <= 0)
            .focusable(video.duration > 0, interactions: .edit)
            .focused($focus, equals: .timeline)
            .onKeyPress(keys: Self.previewKeys, phases: [.down, .repeat], action: handleKey)

            Text(time(video.duration))
                .monospacedDigit()
                .accessibilityLabel("总时长 \(time(video.duration))")
        }
        .font(.caption)
        .padding(.horizontal, 15)
        .frame(height: 42)
        .previewGlass(in: Capsule(), interactive: true)
    }

    private func time(_ seconds: Double) -> String {
        let rounded = Int(seconds)
        return String(format: "%d:%02d", rounded / 60, rounded % 60)
    }
}

private extension View {
    @ViewBuilder
    func previewGlass(in shape: some Shape, interactive: Bool = false) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular.interactive(interactive), in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }
}
