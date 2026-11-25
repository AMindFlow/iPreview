import SwiftUI
import iPreviewCore

@Observable
final class VideoWorkPreviewSession {
    enum Collectible: Hashable {
        case tape, album(Int)
    }

    struct Album {
        let title: String
        let cover: Media
        let photos: [Media]
    }

    let work: IndexedVideoWork
    let albums: [Album]
    private(set) var selection = Collectible.tape
    private(set) var selectedAlbum = 0
    var workspaceID: UUID?
    var browsing: Bool { workspaceID != nil }

    init(work: IndexedVideoWork) {
        self.work = work
        var albums: [Album] = []
        if let cover = work.samples.first {
            albums.append(Album(title: "官方样张", cover: cover, photos: work.samples))
        }
        albums += work.photoSets.map {
            Album(title: $0.title, cover: $0.cover ?? $0.photos[0], photos: $0.photos)
        }
        self.albums = albums
    }

    func select(_ collectible: Collectible) {
        selection = collectible
        if case .album(let index) = collectible { selectedAlbum = index }
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
                .accessibilityLabel(session.browsing ? "返回专辑总览" : "退出专辑模式")
                .help(session.browsing ? "返回专辑总览（Esc）" : "退出专辑模式（Esc）")
                Text(session.work.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
            ZStack {
                if let workspaceID = session.workspaceID {
                    VideoWorkWorkspace(work: session.work, video: video, albums: session.albums,
                                       initialAlbum: session.selectedAlbum, revision: revision, back: back)
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
        ScrollViewReader { reader in
            VideoWorkColumns {
                GeometryReader { geometry in
                    let height = tapeHeight(in: geometry.size)
                    collectible(.tape, title: "录像带", opens: true) {
                        TapeCase(video: session.work.video, revision: revision, height: height,
                                 opening: session.browsing)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } right: {
                GeometryReader { geometry in
                    let width = bookWidth(in: geometry.size)
                    let overlap = width * 0.26 + 18
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: -overlap) {
                            ForEach(session.albums.indices, id: \.self) { index in
                                let album = session.albums[index]
                                let foreground = session.selectedAlbum == index
                                collectible(.album(index), title: album.title, opens: false,
                                            titleWidth: width * 0.74) {
                                    AlbumCase(album: album, revision: revision, width: width,
                                              foreground: foreground, opening: session.browsing)
                                }
                                .scaleEffect(session.browsing ? (foreground ? 1.54 : 0.69) : 1)
                                .opacity(session.browsing ? 0 : 1)
                                .zIndex(foreground ? 1 : 0)
                                .id(VideoWorkPreviewSession.Collectible.album(index))
                            }
                        }
                        .frame(minWidth: max(0, geometry.size.width - 24))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 30)
                    }
                    .scrollClipDisabled()
                    .defaultScrollAnchor(.leading)
                    .frame(maxHeight: .infinity)
                }
                .clipped()
            }
            .accessibilityIdentifier("video-work-overview")
            .task(id: session.browsing ? nil : session.selection) {
                guard !session.browsing else { return }
                if case .album = session.selection { reader.scrollTo(session.selection) }
                await Task.yield()
                if !Task.isCancelled { focused = session.selection }
            }
            .onChange(of: focused) { _, selection in
                guard let selection, !session.browsing else { return }
                session.select(selection)
                if case .album = selection { reader.scrollTo(selection) }
            }
        }
    }

    private func tapeHeight(in available: CGSize) -> CGFloat {
        let aspect: CGFloat = 9.0 / 16.0
        let area = available.width * available.height * 0.4
        return min(sqrt(area / aspect), max(0, available.height - 48),
                   max(0, available.width - 30) / aspect)
    }

    private func bookWidth(in available: CGSize) -> CGFloat {
        let aspect: CGFloat = 1.29
        let visibleBooks = CGFloat(min(session.albums.count, 3))
        let span = 1 + (visibleBooks - 1) * 0.74
        let shelfWidth = max(1, available.width - 24)
        let area = available.width * available.height * 0.4
        let fitted = sqrt(area / (span * aspect))
        let target = fitted * span <= shelfWidth ? fitted : area / (shelfWidth * aspect)
        return min(target, max(0, available.height - 92) / aspect, max(0, shelfWidth - 26))
    }

    private func collectible<Cover: View>(_ selection: VideoWorkPreviewSession.Collectible, title: String,
                                          opens: Bool, titleWidth: CGFloat? = nil,
                                          @ViewBuilder cover: () -> Cover) -> some View {
        let selected = session.selection == selection
        return Button {
            session.select(selection)
            if opens { open() }
        } label: {
            VStack(spacing: 12) {
                cover()
                    .accessibilityHidden(true)
                Text(title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .frame(width: titleWidth)
                    .opacity(session.browsing ? 0 : 1)
            }
            .padding(9)
            .background(selected && !session.browsing ? Color.accentColor.opacity(0.10) : .clear,
                        in: .rect(cornerRadius: 17))
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .strokeBorder(selected && !session.browsing ? Color.accentColor.opacity(0.69) : .clear,
                                  lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
        .buttonStyle(.plain)
        .focusable()
        .focusEffectDisabled()
        .focused($focused, equals: selection)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], phases: [.down, .repeat]) { press in
            let previous = press.key == .leftArrow || press.key == .upArrow
            let order: [VideoWorkPreviewSession.Collectible] = [.tape] + session.albums.indices.map { .album($0) }
            let current = order.firstIndex(of: session.selection)!
            let next = min(max(current + (previous ? -1 : 1), 0), order.count - 1)
            session.select(order[next])
            return .handled
        }
        .onKeyPress(.space) {
            open()
            return .handled
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(opens ? "打开专辑并播放" : "选择此图册，按空格打开专辑")
        .help(title)
    }
}
