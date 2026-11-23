import AppKit
import AVFoundation
import Observation
import SwiftUI
import iPreviewCore

@MainActor
@Observable
final class VideoPlayback {
    let player = AVPlayer()
    private(set) var elapsed: Double = 0
    private(set) var duration: Double = 0
    private(set) var isPlaying = false
    private(set) var message: String?
    private(set) var fallback: VLCPlayback?

    private var itemStatus: NSKeyValueObservation?
    private var playStatus: NSKeyValueObservation?
    private var timeObserver: Any?
    private var failureObserver: NSObjectProtocol?
    private var fallbackClock: Task<Void, Never>?
    private var session: UUID?

    func start(_ media: Media) {
        stop()
        do {
            startNative(try media.readableURL())
        } catch {
            showFailure(error.localizedDescription)
        }
    }

    private func startNative(_ url: URL) {
        let id = UUID()
        session = id
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        itemStatus = item.observe(\.status, options: [.initial, .new]) { [weak self] current, _ in
            let status = current.status
            let duration = current.duration.seconds
            let error = current.error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, self.session == id else { return }
                if status == .failed {
                    self.startFallback(url, nativeError: error)
                } else if duration.isFinite && duration > 0 {
                    self.duration = duration
                }
            }
        }
        playStatus = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] current, _ in
            let playing = current.timeControlStatus != .paused
            Task { @MainActor [weak self] in
                guard self?.session == id else { return }
                self?.isPlaying = playing
            }
        }
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] note in
            let error = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError)?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, self.session == id else { return }
                self.startFallback(url, nativeError: error)
            }
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 8), queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, self.session == id else { return }
                if time.seconds.isFinite { self.elapsed = max(0, time.seconds) }
                if let seconds = self.player.currentItem?.duration.seconds, seconds.isFinite {
                    self.duration = max(0, seconds)
                }
            }
        }
        player.play()
    }

    private func startFallback(_ url: URL, nativeError: String?) {
        stopNative()
        elapsed = 0
        duration = 0
        isPlaying = false
        do {
            let fallback = try VLCPlayback(url: url)
            self.fallback = fallback
            fallbackClock = Task { @MainActor [weak self] in
                var displayedPicture = false
                var reachedEnd = false
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(125))
                    guard !Task.isCancelled, let self else { return }
                    let state = fallback.state
                    let position = fallback.elapsed
                    displayedPicture = displayedPicture || fallback.hasDisplayedPicture
                    let terminal = state == .ended || state == .stopped
                    // LibVLC reports end before publishing its final counters.
                    let settledEnd = terminal && reachedEnd
                    reachedEnd = terminal
                    // A selected track may have a late first frame. Fail early only when
                    // playback has advanced without a selected video track.
                    let missingVideo = !displayedPicture && (
                        settledEnd ||
                        (state == .playing && position >= 1 && !fallback.hasSelectedVideoTrack)
                    )
                    if fallback.couldNotStart || state == .failed || missingVideo {
                        self.stopFallback()
                        self.showFailure(nativeError)
                        return
                    }
                    let length = fallback.duration
                    if length > 0 { self.duration = length }
                    self.elapsed = state == .ended ? self.duration : position
                    self.isPlaying = state.isPlaying
                }
            }
        } catch {
            showFailure(nativeError)
        }
    }

    func toggle() {
        guard message == nil else { return }
        if isPlaying {
            pause()
        } else if let fallback {
            if fallback.state == .ended {
                let url = fallback.url
                stopFallback()
                startFallback(url, nativeError: nil)
            } else {
                fallback.play()
            }
        } else {
            if duration > 0 && elapsed >= duration - 0.1 { seek(0) }
            player.play()
        }
    }

    func prepareToClose() {
        session = nil
        pause()
    }

    private func pause() {
        if let fallback { fallback.pause() } else { player.pause() }
    }

    func seek(_ seconds: Double) {
        guard message == nil, seconds.isFinite, duration > 0 else { return }
        elapsed = min(max(seconds, 0), duration)
        if let fallback {
            fallback.seek(elapsed)
        } else {
            player.seek(to: CMTime(seconds: elapsed, preferredTimescale: 600))
        }
    }

    func stop() {
        stopNative()
        stopFallback()
        elapsed = 0
        duration = 0
        isPlaying = false
        message = nil
    }

    private func stopNative() {
        session = nil
        itemStatus = nil
        playStatus = nil
        if let observer = timeObserver { player.removeTimeObserver(observer) }
        if let observer = failureObserver { NotificationCenter.default.removeObserver(observer) }
        timeObserver = nil
        failureObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func stopFallback() {
        fallbackClock?.cancel()
        fallbackClock = nil
        fallback?.stop()
        fallback = nil
    }

    private func showFailure(_ detail: String?) {
        isPlaying = false
        message = detail.map { "无法播放此视频：\($0)" } ?? "当前播放器无法解码此视频。"
    }
}

struct VideoCanvas: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerSurface {
        let view = PlayerSurface()
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: PlayerSurface, context: Context) {
        let layer = view.layer as! AVPlayerLayer
        layer.player = player
    }

    final class PlayerSurface: NSView {
        override func makeBackingLayer() -> CALayer {
            let layer = AVPlayerLayer()
            layer.videoGravity = .resizeAspect
            return layer
        }
    }
}
