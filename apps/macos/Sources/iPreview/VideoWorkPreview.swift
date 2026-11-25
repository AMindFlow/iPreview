import SwiftUI
import iPreviewCore

@Observable
final class VideoWorkPreviewSession {
    enum Collectible: Hashable {
        case disc, album(Int)
    }

    struct Album {
        let title: String
        let cover: Media
        let photos: [Media]
    }

    let work: IndexedVideoWork
    let albums: [Album]
    var selection = Collectible.disc
    var browsing = false

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

    var initialAlbum: Int {
        if case .album(let index) = selection { return index }
        return 0
    }
}

struct VideoWorkPreview: View {
    let session: VideoWorkPreviewSession
    let revision: Int
    let close: () -> Void

    @ViewState private var video = VideoPlayback()

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
                .accessibilityLabel(session.browsing ? "返回作品总览" : "退出作品预览")
                .help(session.browsing ? "返回作品总览（Esc）" : "退出作品预览（Esc）")
                Text(session.work.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
            if session.browsing {
                VideoWorkWorkspace(work: session.work, video: video, albums: session.albums,
                                   initialAlbum: session.initialAlbum, autoplay: session.selection == .disc,
                                   revision: revision)
            } else {
                VideoWorkOverview(session: session, revision: revision)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .onExitCommand(perform: back)
        .onDisappear { video.stop() }
        .accessibilityIdentifier("video-work-preview")
    }

    private func back() {
        if session.browsing {
            video.stop()
            session.browsing = false
        } else {
            close()
        }
    }
}

private struct VideoWorkOverview: View {
    let session: VideoWorkPreviewSession
    let revision: Int
    @FocusState private var focused: VideoWorkPreviewSession.Collectible?

    var body: some View {
        ScrollViewReader { reader in
            HStack(spacing: 24) {
                collectible(.disc, title: "影碟") {
                    DiscCase(video: session.work.video, revision: revision)
                }
                Divider()
                    .frame(height: 154)
                    .accessibilityHidden(true)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(session.albums.indices, id: \.self) { index in
                            let album = session.albums[index]
                            collectible(.album(index), title: album.title) {
                                AlbumCase(cover: album.cover, revision: revision)
                            }
                            .id(VideoWorkPreviewSession.Collectible.album(index))
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                }
                .frame(height: 238)
                .defaultScrollAnchor(.leading)
            }
            .frame(maxWidth: 980, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("video-work-overview")
            .task(id: session.selection) {
                if case .album = session.selection { reader.scrollTo(session.selection) }
                await Task.yield()
                if !Task.isCancelled { focused = session.selection }
            }
            .onChange(of: focused) { _, selection in
                guard let selection else { return }
                session.selection = selection
                if case .album = selection { reader.scrollTo(selection) }
            }
        }
    }

    private func collectible<Cover: View>(_ selection: VideoWorkPreviewSession.Collectible, title: String,
                                          @ViewBuilder cover: () -> Cover) -> some View {
        Button {
            open(selection)
        } label: {
            VStack(spacing: 13) {
                cover()
                    .accessibilityHidden(true)
                Text(title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            }
            .padding(9)
            .background(session.selection == selection ? Color.accentColor.opacity(0.12) : .clear,
                        in: .rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(session.selection == selection ? Color.accentColor.opacity(0.78) : .clear,
                                  lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focused, equals: selection)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], phases: [.down, .repeat]) { press in
            let previous = press.key == .leftArrow || press.key == .upArrow
            let order: [VideoWorkPreviewSession.Collectible] = [.disc] + session.albums.indices.map { .album($0) }
            let current = order.firstIndex(of: selection)!
            let next = min(max(current + (previous ? -1 : 1), 0), order.count - 1)
            session.selection = order[next]
            return .handled
        }
        .onKeyPress(.space) {
            open(selection)
            return .handled
        }
        .accessibilityAddTraits(session.selection == selection ? .isSelected : [])
    }

    private func open(_ selection: VideoWorkPreviewSession.Collectible) {
        session.selection = selection
        session.browsing = true
    }
}

private struct DiscCase: View {
    let video: Media
    let revision: Int

    var body: some View {
        let edge = RoundedRectangle(cornerRadius: 13)
        ZStack(alignment: .leading) {
            Circle()
                .fill(AngularGradient(colors: [
                    Color(white: 0.68), .cyan.opacity(0.38), Color(white: 0.91),
                    .purple.opacity(0.42), Color(white: 0.54), .mint.opacity(0.52), Color(white: 0.68)
                ], center: .center, angle: .degrees(-24)))
                .overlay { Circle().strokeBorder(.white.opacity(0.62), lineWidth: 1.2) }
                .overlay { Circle().strokeBorder(.white.opacity(0.24), lineWidth: 1).padding(6) }
                .overlay {
                    Circle()
                        .fill(.thinMaterial)
                        .frame(width: 35, height: 35)
                        .overlay { Circle().strokeBorder(.white.opacity(0.5), lineWidth: 2) }
                        .overlay { Circle().fill(.black.opacity(0.36)).frame(width: 15) }
                }
                .frame(width: 140, height: 140)
                .shadow(color: .black.opacity(0.19), radius: 8, x: 3, y: 5)
                .offset(x: 73, y: 3)
            MediaThumbnail(media: video, revision: revision)
                .frame(width: 129, height: 139)
                .clipShape(.rect(cornerRadius: 6))
                .overlay(alignment: .bottomLeading) {
                    Image(systemName: "opticaldisc")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.black.opacity(0.48), in: Circle())
                        .padding(6)
                }
                .padding(.vertical, 9)
                .padding(.trailing, 9)
                .padding(.leading, 16)
                .previewGlass(in: edge)
                .overlay { edge.strokeBorder(.white.opacity(0.47), lineWidth: 1) }
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.linearGradient(colors: [.white.opacity(0.48), .primary.opacity(0.16)],
                                              startPoint: .leading, endPoint: .trailing))
                        .frame(width: 5)
                        .padding(.vertical, 10)
                        .padding(.leading, 5)
                }
                .shadow(color: .black.opacity(0.23), radius: 9, x: 0, y: 6)
        }
        .frame(width: 224, height: 176, alignment: .leading)
    }
}

private struct AlbumCase: View {
    let cover: Media
    let revision: Int

    var body: some View {
        let edge = RoundedRectangle(cornerRadius: 11)
        ZStack(alignment: .topLeading) {
            ForEach((1...3).reversed(), id: \.self) { page in
                edge.fill(.thickMaterial)
                    .overlay { edge.strokeBorder(.primary.opacity(0.17), lineWidth: 1) }
                    .frame(width: 125, height: 151)
                    .offset(x: CGFloat(page) * 3, y: CGFloat(page) * 4)
            }
            MediaThumbnail(media: cover, revision: revision)
                .frame(width: 106, height: 132)
                .clipShape(.rect(cornerRadius: 5))
                .padding(.vertical, 9)
                .padding(.trailing, 7)
                .padding(.leading, 15)
                .previewGlass(in: edge)
                .overlay { edge.strokeBorder(.white.opacity(0.45), lineWidth: 1) }
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.linearGradient(colors: [.white.opacity(0.47), .primary.opacity(0.2)],
                                              startPoint: .leading, endPoint: .trailing))
                        .frame(width: 5)
                        .padding(.vertical, 7)
                        .padding(.leading, 4)
                }
                .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 5)
        }
        .frame(width: 143, height: 176)
    }
}
