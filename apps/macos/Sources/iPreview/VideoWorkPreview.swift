import SwiftUI
import iPreviewCore

@Observable
final class VideoWorkPreviewSession {
    enum Collectible: Hashable {
        case tape, photos
    }

    struct Album {
        let title: String
        let photos: [Media]
    }

    let work: IndexedVideoWork
    let albums: [Album]
    private(set) var selection = Collectible.tape
    private(set) var selectedAlbum = 0
    private var photoPositions: [Int]
    var workspaceID: UUID?
    var browsing: Bool { workspaceID != nil }
    var album: Album { albums[selectedAlbum] }
    var photoPosition: Int { photoPositions[selectedAlbum] }
    var currentPhoto: Media { album.photos[photoPosition] }

    init(work: IndexedVideoWork) {
        self.work = work
        var albums: [Album] = []
        if !work.samples.isEmpty {
            albums.append(Album(title: "官方样张", photos: work.samples))
        }
        albums += work.photoSets.map {
            Album(title: $0.title, photos: $0.photos)
        }
        self.albums = albums
        photoPositions = Array(repeating: 0, count: albums.count)
    }

    func select(_ collectible: Collectible) {
        selection = collectible
    }

    func selectAlbum(_ index: Int) {
        selectedAlbum = index
        select(.photos)
    }

    func stepPhoto(_ direction: Int) {
        let count = album.photos.count
        photoPositions[selectedAlbum] = (photoPosition + direction + count) % count
        select(.photos)
    }
}

struct VideoWorkPreview: View {
    let session: VideoWorkPreviewSession
    let revision: Int
    let close: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var video = VideoPlayback()
    @ViewState private var overviewVisible = true

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Button(action: back) {
                    Image(systemName: session.browsing ? "chevron.left" : "xmark")
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .previewGlass(in: Circle(), interactive: true)
                .accessibilityLabel(session.browsing ? "返回作品总览" : "退出沉浸模式")
                .help(session.browsing ? "返回作品总览（Esc）" : "退出沉浸模式（Esc）")
                Text(session.work.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
            ZStack {
                if let workspaceID = session.workspaceID {
                    VideoWorkWorkspace(work: session.work, video: video, albums: session.albums,
                                       initialAlbum: session.selectedAlbum, initialPhotoID: session.currentPhoto.id,
                                       revision: revision, back: back)
                        .id(workspaceID)
                        .transition(.opacity)
                }
                if overviewVisible {
                    VideoWorkOverview(session: session, revision: revision, open: open)
                        .allowsHitTesting(!session.browsing)
                        .accessibilityHidden(session.browsing)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .onExitCommand(perform: back)
        .onDisappear { video.stop() }
        .accessibilityIdentifier("video-work-preview")
    }

    private func open() {
        guard !session.browsing else { return }
        let workspaceID = UUID()
        video.start(session.work.video)
        if reduceMotion {
            overviewVisible = false
            session.workspaceID = workspaceID
        } else {
            withAnimation(.easeInOut(duration: 0.38), completionCriteria: .logicallyComplete) {
                session.workspaceID = workspaceID
            } completion: {
                if session.workspaceID == workspaceID { overviewVisible = false }
            }
        }
    }

    private func back() {
        if session.browsing {
            video.stop()
            overviewVisible = true
            session.workspaceID = nil
        } else {
            close()
        }
    }
}

struct VideoWorkColumns<Left: View, Right: View>: View {
    @ViewBuilder let left: () -> Left
    @ViewBuilder let right: () -> Right

    var body: some View {
        GeometryReader { geometry in
            let half = geometry.size.width / 2
            HStack(spacing: 0) {
                left().frame(width: half, height: geometry.size.height)
                right().frame(width: half, height: geometry.size.height)
            }
        }
    }
}

private struct VideoWorkOverview: View {
    let session: VideoWorkPreviewSession
    let revision: Int
    let open: () -> Void

    @FocusState private var focused: VideoWorkPreviewSession.Collectible?

    var body: some View {
        VideoWorkColumns {
            GeometryReader { geometry in
                let half = geometry.size
                let height = tapeHeight(in: half)
                VStack(spacing: 15) {
                    Button {
                        session.select(.tape)
                        open()
                    } label: {
                        TapeCase(video: session.work.video, revision: revision, height: height,
                                 opening: session.browsing)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable()
                    .focusEffectDisabled()
                    .focused($focused, equals: .tape)
                    .onKeyPress(.rightArrow) {
                        focused = .photos
                        return .handled
                    }
                    .onKeyPress(.space) {
                        open()
                        return .handled
                    }
                    .accessibilityLabel("录像带")
                    .accessibilityHint("打开沉浸浏览并播放")
                    caption("录像带", selected: focused == .tape)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(x: inward(half.width, artworkWidth: height * 9 / 16))
            }
        } right: {
            GeometryReader { geometry in
                let half = geometry.size
                let width = pileWidth(in: half)
                VStack(spacing: 15) {
                    VideoWorkPhotoPile(session: session, revision: revision, width: width,
                                       open: {
                                           session.select(.photos)
                                           open()
                                       }, takeFocus: { focused = .photos })
                        .focused($focused, equals: .photos)
                        .onKeyPress(.upArrow) {
                            focused = .tape
                            return .handled
                        }
                    albumSelector(width: width)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(x: -inward(half.width, artworkWidth: width))
            }
        }
        .accessibilityIdentifier("video-work-overview")
        .task(id: session.browsing) {
            guard !session.browsing else { return }
            await Task.yield()
            if !Task.isCancelled { focused = session.selection }
        }
        .onChange(of: focused) { _, selection in
            if let selection, !session.browsing { session.select(selection) }
        }
    }

    @ViewBuilder
    private func albumSelector(width: CGFloat) -> some View {
        if session.albums.count == 1 {
            caption(session.album.title, selected: focused == .photos)
        } else {
            Menu {
                ForEach(session.albums.indices, id: \.self) { index in
                    Button {
                        session.selectAlbum(index)
                        focused = .photos
                    } label: {
                        if index == session.selectedAlbum {
                            Label(session.albums[index].title, systemImage: "checkmark")
                        } else {
                            Text(session.albums[index].title)
                        }
                    }
                }
            } label: {
                Text(session.album.title).lineLimit(1)
            }
            .fixedSize()
            .frame(maxWidth: max(1, width))
            .accessibilityLabel("图册")
            .accessibilityValue(session.album.title)
            .opacity(session.browsing ? 0 : 1)
        }
    }

    private func caption(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.callout.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .background(selected ? Color.accentColor.opacity(0.18) : .clear, in: Capsule())
            .opacity(session.browsing ? 0 : 1)
            .accessibilityHidden(true)
    }

    private func tapeHeight(in half: CGSize) -> CGFloat {
        let aspect: CGFloat = 9 / 16
        return min(sqrt(half.width * half.height * 0.4 / aspect), max(1, half.height - 60),
                   max(1, half.width - 54) / aspect)
    }

    private func pileWidth(in half: CGSize) -> CGFloat {
        let aspect: CGFloat = 1.23
        return min(sqrt(half.width * half.height * 0.39 / aspect), max(1, half.height - 68) / aspect,
                   max(1, half.width - 54))
    }

    private func inward(_ halfWidth: CGFloat, artworkWidth: CGFloat) -> CGFloat {
        min(halfWidth * 0.075, max(0, (halfWidth - artworkWidth) / 2 - 24))
    }
}
