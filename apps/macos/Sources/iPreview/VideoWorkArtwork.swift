import SwiftUI
import iPreviewCore

struct TapeCase: View {
    let video: Media
    let revision: Int
    let height: CGFloat
    let opening: Bool

    var body: some View {
        let width = height * 9 / 16
        let edge = RoundedRectangle(cornerRadius: 14)
        ZStack {
            edge.fill(.thinMaterial)
                .overlay { edge.strokeBorder(.primary.opacity(0.21), lineWidth: 1) }
                .offset(x: 5, y: 6)
                .shadow(color: .black.opacity(0.25), radius: 12, x: 3, y: 9)
                .scaleEffect(opening ? 1.29 : 1)
                .opacity(opening ? 0 : 1)

            ZStack {
                Color.clear
                MediaThumbnail(media: video, revision: revision)
                    .frame(width: width * 0.83, height: height * 0.37)
                    .clipShape(.rect(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.white.opacity(0.36), lineWidth: 1)
                    }
                VStack(spacing: 0) {
                    topRibs
                        .frame(width: width * 0.64)
                        .padding(.top, height * 0.10)
                    Spacer()
                    cassetteWindow
                        .frame(width: width * 0.67, height: height * 0.11)
                        .padding(.bottom, height * 0.09)
                }
            }
            .previewGlass(in: edge)
            .overlay {
                edge.strokeBorder(.linearGradient(colors: [.white.opacity(0.75), .primary.opacity(0.22)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2)
            }
            .overlay {
                VStack {
                    shellFasteners
                    Spacer()
                    shellFasteners
                }
                .padding(9)
            }
            .rotation3DEffect(.degrees(opening ? -72 : 0), axis: (x: 0, y: 1, z: 0),
                              anchor: .leading, perspective: 0.65)
            .opacity(opening ? 0 : 1)
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }

    private var topRibs: some View {
        VStack(spacing: 3) {
            ForEach(0..<4) { _ in
                Capsule().fill(.primary.opacity(0.17)).frame(height: 2)
            }
        }
    }

    private var cassetteWindow: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(.primary.opacity(0.25))
            .overlay {
                HStack {
                    spool
                    Capsule().fill(.primary.opacity(0.32)).frame(height: 4)
                    spool
                }
                .padding(4)
            }
    }

    private var spool: some View {
        Circle()
            .fill(.regularMaterial)
            .overlay { Circle().strokeBorder(.white.opacity(0.58), lineWidth: 1) }
            .overlay { Image(systemName: "gearshape").font(.system(size: 10, weight: .semibold)) }
            .aspectRatio(1, contentMode: .fit)
    }

    private var shellFasteners: some View {
        HStack {
            Circle().strokeBorder(.primary.opacity(0.32), lineWidth: 1).frame(width: 4, height: 4)
            Spacer()
            Circle().strokeBorder(.primary.opacity(0.32), lineWidth: 1).frame(width: 4, height: 4)
        }
    }
}

struct AlbumCase: View {
    let album: VideoWorkPreviewSession.Album
    let revision: Int
    let width: CGFloat
    let foreground: Bool
    let opening: Bool

    var body: some View {
        let height = width * 1.29
        let edge = RoundedRectangle(cornerRadius: 8)
        ZStack(alignment: .topLeading) {
            edge.fill(.regularMaterial)
                .overlay(alignment: .bottom) {
                    VStack(spacing: 1.4) {
                        ForEach(0..<5) { _ in
                            Capsule().fill(.primary.opacity(0.25)).frame(height: 0.9)
                        }
                    }
                    .padding(.horizontal, 5)
                    .padding(.bottom, 3)
                }
                .overlay { edge.strokeBorder(.primary.opacity(0.27), lineWidth: 1) }
                .offset(x: 8, y: 11)
                .shadow(color: .black.opacity(0.22), radius: 8, x: 4, y: 8)

            ZStack(alignment: .leading) {
                let cover = album.cover
                let first = album.photos[0]
                ZStack {
                    MediaThumbnail(media: cover, revision: revision)
                        .opacity(opening && foreground && cover.id != first.id ? 0 : 1)
                    if foreground && cover.id != first.id {
                        MediaThumbnail(media: first, revision: revision)
                            .opacity(opening ? 1 : 0)
                    }
                }
                .clipShape(.rect(cornerRadius: 4))
                .padding(.leading, 15)
                .padding([.vertical, .trailing], 7)
                Capsule()
                    .fill(.linearGradient(colors: [.white.opacity(0.55), .primary.opacity(0.25)],
                                          startPoint: .leading, endPoint: .trailing))
                    .frame(width: 7)
                    .padding(.vertical, 5)
                    .padding(.leading, 4)
            }
            .previewGlass(in: edge)
            .overlay { edge.strokeBorder(.white.opacity(0.50), lineWidth: 1) }
        }
        .frame(width: width, height: height)
        .rotation3DEffect(.degrees(opening && foreground ? 0 : -8), axis: (x: 0.24, y: 1, z: 0),
                          perspective: 0.55)
        .padding(.trailing, 8)
        .padding(.bottom, 11)
    }
}
