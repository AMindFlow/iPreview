import SwiftUI
import iPreviewCore

struct VideoWorkWorkspace: View {
    let work: IndexedVideoWork
    let video: VideoPlayback
    let albums: [VideoWorkPreviewSession.Album]
    let initialAlbum: Int
    let autoplay: Bool
    let revision: Int

    var body: some View {
        GeometryReader { geometry in
            let layout = geometry.size.width < 810
                ? AnyLayout(VStackLayout(spacing: 14))
                : AnyLayout(HStackLayout(spacing: 14))
            layout {
                VideoWorkPlayer(media: work.video, video: video, autoplay: autoplay, revision: revision)
                VideoWorkPhotos(albums: albums, initialAlbum: initialAlbum, revision: revision)
            }
        }
        .accessibilityIdentifier("video-work-workspace")
    }
}

private struct VideoWorkPlayer: View {
    let media: Media
    let video: VideoPlayback
    let autoplay: Bool
    let revision: Int

    @ViewState private var started = false
    @ViewState private var scrubPosition: Double?
    @ViewState private var scrubbing = false

    var body: some View {
        VStack(spacing: 10) {
            Text(media.name)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            ZStack {
                Color.mediaSurface
                if !started {
                    MediaThumbnail(media: media, revision: revision)
                } else if let message = video.message {
                    PreviewError(message: message)
                } else {
                    VideoPlaybackCanvas(video: video)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(.rect(cornerRadius: 11))
            controls
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .previewGlass(in: RoundedRectangle(cornerRadius: 16))
        .onAppear { if autoplay && !started { play() } }
        .accessibilityIdentifier("video-work-player")
    }

    private var controls: some View {
        let elapsed = videoTimeLabel(scrubPosition ?? video.elapsed)
        let duration = videoTimeLabel(video.duration)
        return HStack(spacing: 10) {
            Button(action: play) {
                Image(systemName: video.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(video.isPlaying ? "暂停视频" : "播放视频")
            .help(video.isPlaying ? "暂停视频" : "播放视频")
            .disabled(video.message != nil)
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
                if !editing, let scrubPosition {
                    video.seek(scrubPosition)
                    self.scrubPosition = nil
                }
            })
            .labelsHidden()
            .controlSize(.small)
            .accessibilityLabel("视频进度")
            .disabled(video.duration <= 0 || video.message != nil)
            Text(duration)
                .monospacedDigit()
                .accessibilityLabel("总时长 \(duration)")
        }
        .font(.caption)
    }

    private func play() {
        if started {
            video.toggle()
        } else {
            started = true
            video.start(media)
        }
    }
}

private struct VideoWorkPhotos: View {
    let albums: [VideoWorkPreviewSession.Album]
    let revision: Int

    @ViewState private var selectedAlbum: Int
    @ViewState private var selectedPhoto: Int64?
    @ViewState private var sort = MediaSort()
    @FocusState private var photoFocused: Bool

    init(albums: [VideoWorkPreviewSession.Album], initialAlbum: Int, revision: Int) {
        self.albums = albums
        self.revision = revision
        _selectedAlbum = ViewState(initialValue: initialAlbum)
    }

    var body: some View {
        SortedMedia(request: MediaSortRequest(items: albums[selectedAlbum].photos, sort: sort,
                                             revision: revision)) { photos in
            let position = photos.firstIndex { $0.id == selectedPhoto } ?? 0
            let photo = photos[position]
            VStack(spacing: 10) {
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
                    Spacer(minLength: 0)
                    MediaSortMenu(sort: Binding(get: { sort }, set: { value in
                        selectedPhoto = photo.id
                        sort = value
                    }))
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
                .focused($photoFocused)
                .onTapGesture { photoFocused = true }
                .onKeyPress(keys: [.leftArrow, .rightArrow], phases: [.down, .repeat]) { press in
                    let step = press.key == .leftArrow ? -1 : 1
                    let index = min(max(position + step, 0), photos.count - 1)
                    selectedPhoto = photos[index].id
                    return .handled
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("照片画布")
                .accessibilityIdentifier("video-work-photo")
                HStack(spacing: 8) {
                    navigationButton("上一张", symbol: "chevron.left", index: position - 1, photos: photos)
                    Text(photo.name)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(position + 1) / \(photos.count)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    navigationButton("下一张", symbol: "chevron.right", index: position + 1, photos: photos)
                }
                .font(.caption)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .previewGlass(in: RoundedRectangle(cornerRadius: 16))
        .task {
            await Task.yield()
            if !Task.isCancelled { photoFocused = true }
        }
        .accessibilityIdentifier("video-work-photos")
    }

    private func navigationButton(_ label: String, symbol: String, index: Int, photos: [Media]) -> some View {
        Button {
            selectedPhoto = photos[index].id
        } label: {
            Image(systemName: symbol)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!photos.indices.contains(index))
        .accessibilityLabel(label)
        .help(label)
    }
}
