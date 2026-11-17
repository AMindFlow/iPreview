import SwiftUI
import iPreviewCore

struct PreviewRequest {
    let items: [Media]
    let selection: Int64
    let layout: BrowseLayout
}

struct PreviewOrigin {
    let bounds: Anchor<CGRect>
    let cornerRadius: CGFloat
    let image: CGImage?
}

struct PreviewThumbnail {
    let bounds: CGRect
    let visibleBounds: CGRect
    let cornerRadius: CGFloat
    let image: CGImage?

    var aspectRatio: CGFloat? {
        image.map { CGFloat($0.width) / CGFloat($0.height) }
    }
}

struct PreviewOrigins {
    var items: [Int64: PreviewOrigin] = [:]
    var viewport: Anchor<CGRect>?

    func thumbnail(for id: Int64, in geometry: GeometryProxy) -> PreviewThumbnail? {
        guard let item = items[id] else { return nil }
        let bounds = geometry[item.bounds]
        let window = geometry.frame(in: .local)
        let visibleArea = viewport.map { geometry[$0].intersection(window) } ?? window
        let visibleBounds = bounds.intersection(visibleArea)
        guard visibleBounds.width >= 8 && visibleBounds.height >= 8 else { return nil }
        return PreviewThumbnail(bounds: bounds, visibleBounds: visibleBounds, cornerRadius: item.cornerRadius,
                                image: item.image)
    }
}

struct PreviewOriginKey: PreferenceKey {
    static var defaultValue: PreviewOrigins { PreviewOrigins() }

    static func reduce(value: inout PreviewOrigins, nextValue: () -> PreviewOrigins) {
        let next = nextValue()
        value.items.merge(next.items, uniquingKeysWith: { _, latest in latest })
        if let viewport = next.viewport { value.viewport = viewport }
    }
}

extension View {
    func previewScrollViewport() -> some View {
        transformAnchorPreference(key: PreviewOriginKey.self, value: .bounds) { origins, viewport in
            origins.viewport = viewport
        }
    }
}

struct MediaPreview: View {
    let request: PreviewRequest
    let thumbnail: (Int64) -> PreviewThumbnail?
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

    init(request: PreviewRequest, thumbnail: @escaping (Int64) -> PreviewThumbnail?, close: @escaping (Int64) -> Void) {
        self.request = request
        self.thumbnail = thumbnail
        self.close = close
        _index = ViewState(initialValue: request.items.firstIndex(where: { $0.id == request.selection })!)
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let window = CGRect(origin: .zero, size: size)
            let destination = window.insetBy(dx: size.width * 0.12, dy: size.height * 0.14)
            let source = reduceMotion ? nil : thumbnail(closingSelection ?? request.selection)
            let displayedThumbnail = thumbnail(media.id)
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { focus = .canvas }
                    .accessibilityHidden(true)
                Rectangle()
                    .fill(.regularMaterial)
                    .opacity(expanded ? 1 : 0)
                    .allowsHitTesting(false)
                neighbors(in: size)
                    .opacity(expanded ? 1 : 0)
                PreviewStage(progress: expanded || reduceMotion ? 1 : 0, source: source, destination: destination,
                             aspectRatio: displayedThumbnail?.aspectRatio) {
                    stage(poster: displayedThumbnail?.image)
                        .id(media.id)
                }
                .opacity(expanded || source != nil ? 1 : 0)
                .accessibilityLabel(media.name)
                .onTapGesture { focus = .canvas }
                navigation
                    .opacity(expanded ? 1 : 0)
                    .disabled(closingSelection != nil)
            }
            .frame(width: size.width, height: size.height)
            .focusable()
            .focusEffectDisabled()
            .focused($focus, equals: .canvas)
            .onKeyPress(keys: Self.previewKeys, phases: [.down, .repeat], action: handleKey)
            .overlay(alignment: .top) {
                topControls
                    .opacity(expanded ? 1 : 0)
                    .disabled(closingSelection != nil)
            }
            .overlay(alignment: .bottom) {
                if media.kind == .video, video.message == nil {
                    playerControls
                        .frame(width: min(size.width * 0.65, 620))
                        .padding(.bottom, 22)
                        .opacity(expanded ? 1 : 0)
                        .disabled(closingSelection != nil)
                }
            }
        }
        .foregroundStyle(.primary)
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
            guard media.kind == .video, video.message == nil, video.duration > 0 else { return .handled }
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
    private func stage(poster: CGImage?) -> some View {
        if media.kind == .video {
            if let message = video.message {
                PreviewError(message: message)
            } else {
                VideoCanvas(player: video.player)
                    .background {
                        if let poster {
                            Image(decorative: poster, scale: 1)
                                .resizable()
                                .scaledToFit()
                        } else {
                            Color.black
                        }
                    }
            }
        } else {
            PhotoCanvas(media: media, poster: poster)
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

private struct PreviewStage<Content: View>: View, Animatable {
    nonisolated var progress: CGFloat
    let source: PreviewThumbnail?
    let destination: CGRect
    let aspectRatio: CGFloat?
    @ViewBuilder let content: () -> Content

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let fitted = mediaBounds(in: destination, fill: false)
        let fallback = fitted.insetBy(dx: fitted.width * 0.10, dy: fitted.height * 0.10)
        let clip = interpolate(from: source?.visibleBounds ?? fallback, to: fitted)
        let media = interpolate(from: mediaBounds(in: source?.bounds ?? fallback, fill: true), to: fitted)
        let radius = interpolate(from: source?.cornerRadius ?? 12, to: 12)

        content()
            .frame(width: media.width, height: media.height)
            .position(x: media.midX - clip.minX, y: media.midY - clip.minY)
            .frame(width: clip.width, height: clip.height)
            .clipShape(.rect(cornerRadius: radius))
            .position(x: clip.midX, y: clip.midY)
    }

    private func mediaBounds(in bounds: CGRect, fill: Bool) -> CGRect {
        guard let aspectRatio else { return bounds }
        let widthLimitedHeight = bounds.width / aspectRatio
        let height = fill ? max(bounds.height, widthLimitedHeight) : min(bounds.height, widthLimitedHeight)
        return bounds.insetBy(dx: (bounds.width - height * aspectRatio) / 2,
                              dy: (bounds.height - height) / 2)
    }

    private func interpolate(from start: CGRect, to end: CGRect) -> CGRect {
        CGRect(x: interpolate(from: start.minX, to: end.minX),
               y: interpolate(from: start.minY, to: end.minY),
               width: interpolate(from: start.width, to: end.width),
               height: interpolate(from: start.height, to: end.height))
    }

    private func interpolate(from start: CGFloat, to end: CGFloat) -> CGFloat {
        start + (end - start) * progress
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
