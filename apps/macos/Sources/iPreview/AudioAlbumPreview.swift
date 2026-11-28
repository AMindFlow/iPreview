import SwiftUI
import iPreviewCore

struct AudioAlbumPreview: View {
    let session: PreviewSession
    let album: AudioAlbum
    let close: (Int64) -> Void

    @ViewState private var playback = VideoPlayback()
    @ViewState private var artwork: CGImage?
    @ViewState private var timelineKeyboardFocus = false
    @FocusState private var focus: Focus?

    private enum Focus: Hashable { case deck, timeline }

    private var track: Media { session.media }
    private var trackIndex: Int { album.tracks.firstIndex { $0.id == track.id }! }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let stacked = width < 730
            let contentHeight = max(0, height - 115)
            let jacketWidth = min(stacked ? 108 : 180, width * 0.19)
            let listWidth = min(318, max(185, width * 0.28))
            VStack(spacing: 13) {
                if stacked {
                    VStack(spacing: 12) {
                        HStack(spacing: 20) {
                            jacket(width: jacketWidth)
                            deck(size: min(width * 0.55, contentHeight * 0.48))
                        }
                        trackList
                    }
                    .frame(height: contentHeight)
                } else {
                    HStack(spacing: 22) {
                        jacket(width: jacketWidth)
                        deck(size: min(height * 0.69, width - jacketWidth - listWidth - 96))
                        trackList.frame(width: listWidth)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: contentHeight)
                }
                transport.frame(maxWidth: 620)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.regularMaterial)
        .focusable()
        .focusEffectDisabled()
        .focused($focus, equals: .deck)
        .onTapGesture { focus = .deck }
        .onKeyPress(keys: [.escape, .space, .leftArrow, .rightArrow, .tab]) { press in
            if press.key == .escape {
                session.dismiss()
                return .handled
            }
            guard focus == .deck else { return .ignored }
            switch press.key {
            case .space: togglePlayback()
            case .leftArrow: moveTrack(by: -1)
            case .rightArrow: moveTrack(by: 1)
            case .tab:
                guard playback.duration > 0, !press.modifiers.contains(.shift) else { return .ignored }
                timelineKeyboardFocus = true
                focus = .timeline
            default: return .ignored
            }
            return .handled
        }
        .focusedSceneValue(\.previewPlayAction, startOrResume)
        .task {
            await Task.yield()
            focus = .deck
        }
        .task(id: track.id) {
            guard session.closingSelection == nil else { return }
            playback.start(track)
        }
        .task(id: album) {
            let load = Task.detached(priority: .userInitiated) { await album.cover(limit: 1000) }
            let image = await withTaskCancellationHandler { await load.value } onCancel: { load.cancel() }
            if !Task.isCancelled { artwork = image }
        }
        .onChange(of: session.closingSelection) { _, selection in
            guard let selection else { return }
            playback.stop()
            close(selection)
        }
        .onChange(of: focus) { _, next in
            if next != .timeline { timelineKeyboardFocus = false }
        }
        .onDisappear { playback.stop() }
        .accessibilityIdentifier("audio-album-preview")
    }

    private func jacket(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AudioAlbumArtwork(image: artwork)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 8))
            Text(album.name)
                .font(.headline)
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(width: width)
    }

    private func deck(size: CGFloat) -> some View {
        Image(systemName: "opticaldisc")
            .font(.system(size: max(0, size * 0.65), weight: .ultraLight))
            .foregroundStyle(.secondary)
            .frame(width: max(0, size), height: max(0, size))
            .accessibilityHidden(true)
    }

    private var trackList: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("曲目")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(album.tracks.enumerated()), id: \.element.id) { offset, media in
                            let selected = media.id == track.id
                            Button {
                                selectTrack(media)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "waveform")
                                        .opacity(selected ? 1 : 0)
                                        .font(.caption)
                                        .frame(width: 18)
                                    Text(media.name)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 7)
                                .frame(minHeight: 31)
                                .background(selected ? Color.accentColor.opacity(0.14) : .clear,
                                            in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(media.name)
                            .accessibilityValue("第 \(offset + 1) 首")
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .help(media.name)
                            .id(media.id)
                        }
                    }
                }
                .onChange(of: track.id, initial: true) { _, id in scroll.scrollTo(id, anchor: .center) }
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var transport: some View {
        VStack(spacing: 7) {
            if let message = playback.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .accessibilityIdentifier("audio-playback-error")
            }
            VideoTimeline(video: playback, focus: $focus, control: .timeline, spacing: 10,
                          showsKeyboardFocus: $timelineKeyboardFocus, seekLabel: "音频进度",
                          keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
                timelineKeyboardFocus = true
                let backwards = press.key == .leftArrow || press.key == .downArrow
                playback.seek(playback.elapsed + (backwards ? -0.25 : 0.25))
                return .handled
            }
            .id(track.id)
            HStack(spacing: 12) {
                transportButton("上一首", icon: "backward.end.fill") { moveTrack(by: -1) }
                    .disabled(trackIndex == 0)
                transportButton(playback.isPlaying ? "暂停" : "播放", icon: playback.isPlaying ? "pause.fill" : "play.fill",
                                action: togglePlayback)
                transportButton("停止", icon: "stop.fill") {
                    playback.stop()
                    focus = .deck
                }
                .disabled(playback.player.currentItem == nil && playback.message == nil && playback.elapsed == 0)
                transportButton("下一首", icon: "forward.end.fill") { moveTrack(by: 1) }
                    .disabled(trackIndex == album.tracks.count - 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .previewGlass(in: RoundedRectangle(cornerRadius: 22), interactive: true)
    }

    private func transportButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .frame(width: 30, height: 25)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    private func moveTrack(by offset: Int) {
        let next = trackIndex + offset
        guard album.tracks.indices.contains(next) else { return }
        selectTrack(album.tracks[next])
    }

    private func selectTrack(_ media: Media) {
        guard session.closingSelection == nil else { return }
        if media.id == track.id {
            startOrResume()
        } else {
            playback.stop()
            session.selectAudioTrack(media)
        }
        focus = .deck
    }

    private func togglePlayback() {
        if playback.isPlaying {
            playback.toggle()
        } else {
            startOrResume()
        }
        focus = .deck
    }

    private func startOrResume() {
        guard session.closingSelection == nil, !playback.isPlaying else { return }
        if playback.player.currentItem == nil {
            playback.start(track)
        } else {
            playback.toggle()
        }
    }
}

struct AudioAlbumArtwork: View {
    let image: CGImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.mediaSurface
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: min(32, geometry.size.height * 0.3), weight: .light))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityHidden(true)
    }
}

struct AudioAlbumCardArtwork: View {
    let album: AudioAlbum
    let revision: Int

    private struct Request: Equatable {
        let album: AudioAlbum
        let revision: Int
    }

    @ViewState private var image: CGImage?

    var body: some View {
        AudioAlbumArtwork(image: image)
            .task(id: Request(album: album, revision: revision)) {
                let load = Task.detached(priority: .utility) { await album.cover(limit: 520) }
                let resolved = await withTaskCancellationHandler { await load.value } onCancel: { load.cancel() }
                if !Task.isCancelled { image = resolved }
            }
    }
}
