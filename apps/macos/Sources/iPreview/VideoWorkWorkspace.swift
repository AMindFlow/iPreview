import AppKit
import Carbon.HIToolbox
import SwiftUI
import iPreviewCore

struct VideoWorkWorkspace: View {
    let work: IndexedVideoWork
    let video: VideoPlayback
    let albums: [VideoWorkPreviewSession.Album]
    let revision: Int
    let back: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var pane = Pane.video
    @ViewState private var locked = false
    @ViewState private var selectedAlbum: Int
    @ViewState private var selectedPhoto: Int64?
    @ViewState private var sort = MediaSort()
    @ViewState private var scrubPosition: Double?
    @ViewState private var scrubbing = false
    @FocusState private var focus: Control?

    private enum Pane { case video, photos }
    private enum Control: Hashable { case video, timeline, photos, albums, sort }

    private var canSeek: Bool { video.duration > 0 && video.message == nil }

    init(work: IndexedVideoWork, video: VideoPlayback, albums: [VideoWorkPreviewSession.Album],
         initialAlbum: Int, revision: Int, back: @escaping () -> Void) {
        self.work = work
        self.video = video
        self.albums = albums
        self.revision = revision
        self.back = back
        _selectedAlbum = ViewState(initialValue: initialAlbum)
    }

    var body: some View {
        SortedMedia(request: MediaSortRequest(items: albums[selectedAlbum].photos, sort: sort, revision: revision)) { photos in
            let position = photos.firstIndex { $0.id == selectedPhoto } ?? 0
            VideoWorkColumns {
                videoPane
                    .modifier(WorkPaneFrame(active: pane == .video, reduceMotion: reduceMotion))
                    .padding(.horizontal, 7)
            } right: {
                photoPane(photos, position: position)
                    .modifier(WorkPaneFrame(active: pane == .photos, reduceMotion: reduceMotion))
                    .padding(.horizontal, 7)
            }
            .background {
                VideoWorkEvents { event in
                    handle(event, photos: photos, position: position)
                } onClick: { left in
                    pane = left ? .video : .photos
                }
                .allowsHitTesting(false)
            }
        }
        .task {
            await Task.yield()
            if !Task.isCancelled { focus = .video }
        }
        .onChange(of: video.message) { _, message in
            if message != nil { locked = false }
        }
        .accessibilityIdentifier("video-work-workspace")
    }

    private var videoPane: some View {
        VStack(spacing: 8) {
            Text(work.video.name)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            ZStack {
                Color.mediaSurface
                if let message = video.message {
                    PreviewError(message: message)
                } else {
                    VideoPlaybackCanvas(video: video)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(.rect(cornerRadius: 11))
            .contentShape(Rectangle())
            .focusable()
            .focusEffectDisabled()
            .focused($focus, equals: .video)
            .onTapGesture { focus = .video }

            videoTimeline
            videoButtons
        }
        .accessibilityIdentifier("video-work-player")
    }

    private var videoTimeline: some View {
        let elapsed = videoTimeLabel(scrubPosition ?? video.elapsed)
        let duration = videoTimeLabel(video.duration)
        return HStack(spacing: 8) {
            Text(elapsed)
                .monospacedDigit()
                .accessibilityLabel("播放位置 \(elapsed)")
            Slider(value: Binding(
                get: { min(scrubPosition ?? video.elapsed, max(video.duration, 1)) },
                set: { seconds in
                    if scrubbing {
                        scrubPosition = seconds
                    } else {
                        video.seek(seconds)
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
            .disabled(!canSeek)
            .focusable(canSeek, interactions: .edit)
            .focused($focus, equals: .timeline)
            Text(duration)
                .monospacedDigit()
                .accessibilityLabel("总时长 \(duration)")
        }
        .font(.caption)
    }

    private var videoButtons: some View {
        HStack(spacing: 17) {
            iconButton("后退 15 秒", symbol: "gobackward.15", disabled: video.duration <= 0) {
                video.seek(video.elapsed - 15)
            }
            iconButton(video.isPlaying ? "暂停视频" : "播放视频", symbol: video.isPlaying ? "pause.fill" : "play.fill",
                       disabled: video.message != nil, action: video.toggle)
            iconButton("前进 15 秒", symbol: "goforward.15", disabled: video.duration <= 0) {
                video.seek(video.elapsed + 15)
            }
            iconButton(locked ? "解除视频锁定" : "锁定视频", symbol: locked ? "lock.fill" : "lock.open",
                       disabled: video.message != nil) {
                locked.toggle()
            }
            .accessibilityValue(locked ? "已锁定" : "未锁定")
        }
    }

    private func photoPane(_ photos: [Media], position: Int) -> some View {
        let photo = photos[position]
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Picker("图片组", selection: Binding(get: { selectedAlbum }, set: { index in
                    if selectedAlbum != index {
                        selectedPhoto = nil
                        selectedAlbum = index
                    }
                })) {
                    ForEach(albums.indices, id: \.self) { index in
                        Text(albums[index].title).tag(index)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityLabel("图片组")
                .focusable()
                .focused($focus, equals: .albums)
                Spacer(minLength: 0)
                MediaSortMenu(sort: Binding(get: { sort }, set: { value in
                    selectedPhoto = photo.id
                    sort = value
                }))
                .focusable()
                .focused($focus, equals: .sort)
            }
            ZStack {
                Color.mediaSurface
                PhotoCanvas(media: photo)
                    .id(photo.id)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(.rect(cornerRadius: 11))
            .contentShape(Rectangle())
            .focusable()
            .focusEffectDisabled()
            .focused($focus, equals: .photos)
            .onTapGesture { focus = .photos }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("照片画布")
            .accessibilityIdentifier("video-work-photo")
            HStack(spacing: 8) {
                iconButton("上一张", symbol: "chevron.left", disabled: position == 0) {
                    movePhoto(-1, in: photos, position: position)
                }
                Text(photo.name)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(position + 1) / \(photos.count)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                iconButton("下一张", symbol: "chevron.right", disabled: position + 1 == photos.count) {
                    movePhoto(1, in: photos, position: position)
                }
            }
            .font(.caption)
        }
        .accessibilityIdentifier("video-work-photos")
    }

    private func iconButton(_ label: String, symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 25, height: 25)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
        .help(label)
    }

    private func movePhoto(_ step: Int, in photos: [Media], position: Int) {
        let next = min(max(position + step, 0), photos.count - 1)
        selectedPhoto = photos[next].id
    }

    private func handle(_ event: NSEvent, photos: [Media], position: Int) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let key = Int(event.keyCode)
        if key == kVK_Tab, modifiers.isEmpty || modifiers == .shift {
            if !event.isARepeat {
                pane = pane == .video ? .photos : .video
                focus = pane == .video ? .video : .photos
            }
            return true
        }
        guard modifiers.isEmpty else { return false }
        if key == kVK_Escape {
            if !event.isARepeat { back() }
            return true
        }
        if pane == .photos {
            switch key {
            case kVK_LeftArrow, kVK_RightArrow:
                movePhoto(key == kVK_LeftArrow ? -1 : 1, in: photos, position: position)
            case kVK_UpArrow: focus = .albums
            case kVK_DownArrow: focus = .sort
            default: return false
            }
        } else {
            switch key {
            case kVK_Space:
                if !event.isARepeat { video.toggle() }
            case kVK_Return, kVK_ANSI_KeypadEnter:
                if !event.isARepeat && video.message == nil { locked.toggle() }
            case kVK_DownArrow:
                guard focus == .video, canSeek else { return false }
                focus = .timeline
            case kVK_UpArrow:
                guard focus == .timeline else { return false }
                focus = .video
            case kVK_LeftArrow, kVK_RightArrow:
                guard locked || focus == .timeline else { return false }
                let step = locked ? 15.0 : 0.25
                video.seek(video.elapsed + (key == kVK_LeftArrow ? -step : step))
            default: return false
            }
        }
        return true
    }
}

private struct WorkPaneFrame: ViewModifier {
    let active: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        let border = RoundedRectangle(cornerRadius: 16)
        content
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .previewGlass(in: border)
            .overlay {
                if active {
                    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { time in
                        let turn = reduceMotion ? 0 : time.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) * 90
                        let light = AngularGradient(colors: [.mint, .cyan, .indigo, .pink, .green, .mint],
                                                    center: .center, angle: .degrees(turn))
                        border.strokeBorder(light, lineWidth: 2.3)
                            .shadow(color: .cyan.opacity(0.44), radius: 5)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
    }
}
