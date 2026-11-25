import AppKit
import SwiftUI
import iPreviewCore

@Observable
final class PreviewSession {
    let originalItems: [Media]
    private(set) var items: [Media]
    var sort = MediaSort()
    let selection: Int64
    let layout: BrowseLayout
    var index: Int
    private(set) var closingSelection: Int64?

    var media: Media { items[index] }

    init(items: [Media], selection: Int64, layout: BrowseLayout) {
        originalItems = items
        self.items = items
        self.selection = selection
        self.layout = layout
        index = items.firstIndex { $0.id == selection }!
    }

    func applyOrder(_ ordered: [Media]) {
        let currentID = media.id
        items = ordered
        index = ordered.firstIndex { $0.id == currentID }!
    }

    func dismiss() {
        if closingSelection == nil { closingSelection = media.id }
    }
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
    let session: PreviewSession
    let thumbnail: (Int64) -> PreviewThumbnail?
    let prepareToClose: (Int64, Bool) -> Void
    let close: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var expanded = false
    @ViewState private var closingThumbnail: PreviewThumbnail?
    @ViewState private var video = VideoPlayback()
    @ViewState private var videoLocked = false
    @ViewState private var scrubPosition: Double?
    @ViewState private var scrubbing = false
    @FocusState private var focus: Focus?

    private enum Focus: Hashable { case canvas, timeline }
    private static let keypadEnter = KeyEquivalent("\u{3}")
    private static let previewKeys: Set<KeyEquivalent> = [
        .escape, .space, .return, keypadEnter, .tab, .leftArrow, .rightArrow, .upArrow, .downArrow,
    ]

    private var media: Media { session.media }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let sideInset: CGFloat = 30
            let topInset: CGFloat = 30
            let bottomInset: CGFloat = media.kind == .video ? 86 : 30
            let destination = CGRect(x: sideInset, y: topInset, width: max(0, size.width - 2 * sideInset),
                                     height: max(0, size.height - topInset - bottomInset))
            let origin = session.closingSelection == nil ? thumbnail(session.selection) : closingThumbnail
            let source = reduceMotion ? nil : origin
            let displayedThumbnail = thumbnail(media.id)
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { focus = .canvas }
                    .accessibilityHidden(true)
                Rectangle()
                    .fill(.regularMaterial)
                    .ignoresSafeArea(.container, edges: .top)
                    .opacity(expanded ? 1 : 0)
                    .allowsHitTesting(false)
                neighbors(in: size)
                    .opacity(expanded ? 1 : 0)
                PreviewStage(progress: expanded || reduceMotion ? 1 : 0, source: source, destination: destination,
                             aspectRatio: displayedThumbnail?.aspectRatio) {
                    stage(poster: displayedThumbnail?.image)
                }
                .opacity(expanded || source != nil ? 1 : 0)
                .accessibilityLabel(media.name)
                .onTapGesture { focus = .canvas }
                if !videoLocked {
                    navigation
                        .opacity(expanded ? 1 : 0)
                        .disabled(session.closingSelection != nil)
                }
            }
            .frame(width: size.width, height: size.height)
            .focusable()
            .focusEffectDisabled()
            .focused($focus, equals: .canvas)
            .onKeyPress(keys: Self.previewKeys, phases: [.down, .repeat], action: handleKey)
            .overlay(alignment: .bottom) {
                if media.kind == .video, video.message == nil {
                    playerControls
                        .frame(width: min(size.width * 0.74, 680))
                        .padding(.bottom, 16)
                        .opacity(expanded ? 1 : 0)
                        .disabled(session.closingSelection != nil)
                }
            }
        }
        .foregroundStyle(.primary)
        .task {
            await Task.yield()
            guard session.closingSelection == nil else { return }
            focus = .canvas
            withAnimation(transitionAnimation) { expanded = true }
        }
        .task(id: media.id) {
            guard session.closingSelection == nil else { return }
            videoLocked = false
            scrubPosition = nil
            scrubbing = false
            if media.kind == .video {
                video.start(media)
            } else {
                video.stop()
            }
        }
        .onChange(of: video.message) { _, message in
            if message != nil {
                videoLocked = false
                focus = .canvas
            }
        }
        .onChange(of: session.closingSelection) { _, selection in
            if let selection { dismiss(returningTo: selection) }
        }
        .onDisappear { video.stop() }
        .accessibilityIdentifier("media-preview")
    }

    private var transitionAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .easeInOut(duration: 0.24)
    }

    private func dismiss(returningTo selection: Int64) {
        video.prepareToClose()
        closingThumbnail = thumbnail(selection)
        prepareToClose(selection, closingThumbnail != nil)
        withAnimation(transitionAnimation, completionCriteria: .logicallyComplete) {
            expanded = false
        } completion: {
            close()
        }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        if session.closingSelection != nil { return .handled }
        switch press.key {
        case .escape:
            if press.phase == .down { session.dismiss() }
        case .return, Self.keypadEnter:
            if press.phase == .down, media.kind == .video, video.message == nil {
                toggleVideoLock()
            }
        case .space:
            if videoLocked {
                if press.phase == .down { video.toggle() }
            } else {
                guard focus == .canvas else { return .ignored }
                if press.phase == .down { session.dismiss() }
            }
        case .tab:
            guard media.kind == .video, video.message == nil, video.duration > 0 else { return .handled }
            if press.phase == .down { focus = focus == .timeline ? .canvas : .timeline }
        default:
            if videoLocked {
                if press.key == .leftArrow { video.seek(video.elapsed - 15) }
                if press.key == .rightArrow { video.seek(video.elapsed + 15) }
            } else if focus == .timeline {
                let backward = press.key == .leftArrow || press.key == .downArrow
                video.seek(video.elapsed + (backward ? -0.25 : 0.25))
            } else if let destination = neighbor(toward: press.key) {
                session.index = destination
            }
        }
        return .handled
    }

    private func toggleVideoLock() {
        videoLocked.toggle()
        focus = .canvas
    }

    @ViewBuilder
    private func stage(poster: CGImage?) -> some View {
        if media.kind == .video {
            if let message = video.message {
                PreviewError(message: message)
            } else {
                VideoPlaybackCanvas(video: video)
                    .background {
                        if let poster {
                            Image(decorative: poster, scale: 1)
                                .resizable()
                                .scaledToFit()
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
            .padding(.horizontal, 3)
            VStack {
                navigationButton(toward: .upArrow, icon: "chevron.up", label: "上方媒体")
                Spacer()
                navigationButton(toward: .downArrow, icon: "chevron.down", label: "下方媒体")
            }
            .padding(.top, 3)
            .padding(.bottom, media.kind == .video ? 57 : 3)
        }
    }

    @ViewBuilder
    private func navigationButton(toward key: KeyEquivalent, icon: String, label: String) -> some View {
        if let destination = neighbor(toward: key) {
            Button {
                session.index = destination
                focus = .canvas
            } label: {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .help(label)
        }
    }

    private func neighbor(toward key: KeyEquivalent) -> Int? {
        session.layout.neighbor(of: session.index, toward: key, count: session.items.count)
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
            MediaThumbnail(media: session.items[position])
                .frame(width: width, height: height)
                .clipShape(.rect(cornerRadius: 12))
        }
    }

    private var playerControls: some View {
        HStack(spacing: 12) {
            skipButton(seconds: -15, icon: "gobackward.15", label: "后退 15 秒")

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

            skipButton(seconds: 15, icon: "goforward.15", label: "前进 15 秒")

            Text(videoTimeLabel(scrubPosition ?? video.elapsed))
                .monospacedDigit()
                .accessibilityLabel("播放位置 \(videoTimeLabel(scrubPosition ?? video.elapsed))")

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

            Text(videoTimeLabel(video.duration))
                .monospacedDigit()
                .accessibilityLabel("总时长 \(videoTimeLabel(video.duration))")

            Button(action: toggleVideoLock) {
                Label(videoLocked ? "已锁定" : "锁定", systemImage: videoLocked ? "lock.fill" : "lock.open")
                    .foregroundStyle(videoLocked ? Color.ipreviewAccent : .primary)
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("视频锁定")
            .accessibilityValue(videoLocked ? "已锁定" : "未锁定")
            .help(videoLocked ? "解除锁定（Enter）" : "锁定当前视频（Enter）")
        }
        .font(.caption)
        .padding(.horizontal, 15)
        .frame(height: 42)
        .previewGlass(in: Capsule(), interactive: true)
    }

    private func skipButton(seconds: Double, icon: String, label: String) -> some View {
        Button {
            video.seek(video.elapsed + seconds)
            focus = .canvas
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15))
                .frame(width: 23, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(video.duration <= 0)
        .accessibilityLabel(label)
        .help(label)
    }
}

private struct PreviewTitleBar: View {
    let session: PreviewSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var feedback: CopyFeedback?

    private struct CopyFeedback: Equatable {
        let mediaID: Int64
        let token = UUID()
    }

    private var didCopy: Bool { feedback?.mediaID == session.media.id }

    var body: some View {
        @Bindable var session = session
        Group {
            if didCopy {
                Label("已复制", systemImage: "checkmark.circle.fill")
                    .transition(.opacity)
            } else {
                Text(session.media.name)
                    .transition(.opacity)
            }
        }
            .font(.callout.weight(.semibold))
            .lineLimit(1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: didCopy)
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: copyFilename)
            .accessibilityAddTraits(.isHeader)
            .accessibilityAction(named: Text("复制文件名"), copyFilename)
            .help("双击复制文件名")
            .onChange(of: session.media.id) { _, _ in feedback = nil }
            .task(id: feedback) {
                guard let feedback else { return }
                try? await Task.sleep(for: .seconds(1.2))
                if !Task.isCancelled, self.feedback == feedback { self.feedback = nil }
            }
            .padding(.horizontal, 58)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial)
            .overlay(alignment: .leading) {
                Button {
                    session.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.callout.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                        .previewGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .disabled(session.closingSelection != nil)
                .accessibilityLabel("关闭预览")
                .help("关闭预览（Esc）")
                .padding(.leading, 12)
            }
            .overlay(alignment: .trailing) {
                MediaSortMenu(sort: $session.sort)
                    .disabled(session.items.count < 2 || session.closingSelection != nil)
                    .padding(.trailing, 12)
            }
            .task(id: session.sort) {
                let request = MediaSortRequest(items: session.originalItems, sort: session.sort)
                let ordered = await request.ordered()
                if !Task.isCancelled, session.closingSelection == nil { session.applyOrder(ordered) }
            }
    }

    private func copyFilename() {
        guard session.closingSelection == nil else { return }
        let media = session.media
        let clipboard = NSPasteboard.general
        clipboard.clearContents()
        if clipboard.setString(media.name, forType: .string), media.kind == .image {
            feedback = CopyFeedback(mediaID: media.id)
        }
    }
}

struct PreviewWindowChrome: NSViewRepresentable {
    let session: PreviewSession

    func makeNSView(context: Context) -> WindowChromeView { WindowChromeView(session: session) }
    func updateNSView(_ view: WindowChromeView, context: Context) { }

    static func dismantleNSView(_ view: WindowChromeView, coordinator: ()) {
        view.uninstallTitleBar()
    }

    final class WindowChromeView: NSView {
        private let titleBar: TitleBarHost
        private var hiddenButtons: [(button: NSButton, wasHidden: Bool)] = []
        private var layoutObservation: NSKeyValueObservation?

        init(session: PreviewSession) {
            titleBar = TitleBarHost(rootView: PreviewTitleBar(session: session))
            super.init(frame: .zero)
            titleBar.sizingOptions = []
            titleBar.safeAreaRegions = []
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            uninstallTitleBar()
            super.viewWillMove(toWindow: newWindow)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, let frameView = window.contentView?.superview else { return }
            let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            for type in types {
                if let button = window.standardWindowButton(type) {
                    hiddenButtons.append((button, button.isHidden))
                    button.isHidden = true
                }
            }
            // Keep the native toolbar installed so the split view and thumbnail coordinates stay put.
            frameView.addSubview(titleBar, positioned: .above, relativeTo: nil)
            titleBar.autoresizingMask = frameView.isFlipped ? [.width, .maxYMargin] : [.width, .minYMargin]
            updateTitleBarFrame()
            layoutObservation = window.observe(\.contentLayoutRect) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.updateTitleBarFrame() }
            }
        }

        private func updateTitleBarFrame() {
            guard let window, let parent = titleBar.superview else { return }
            let bounds = parent.bounds
            let content = parent.convert(window.contentLayoutRect, from: nil)
            let toolbarHeight = parent.isFlipped ? content.minY - bounds.minY : bounds.maxY - content.maxY
            let height = max(36, toolbarHeight)
            let top = parent.isFlipped ? bounds.minY : bounds.maxY - height
            titleBar.frame = NSRect(x: bounds.minX, y: top, width: bounds.width, height: height)
        }

        func uninstallTitleBar() {
            layoutObservation = nil
            titleBar.removeFromSuperview()
            for (button, wasHidden) in hiddenButtons { button.isHidden = wasHidden }
            hiddenButtons.removeAll()
        }
    }

    private final class TitleBarHost: NSHostingView<PreviewTitleBar> {
        override var mouseDownCanMoveWindow: Bool { false }
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

extension View {
    @ViewBuilder
    func previewGlass(in shape: some Shape, interactive: Bool = false) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular.interactive(interactive), in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }
}
