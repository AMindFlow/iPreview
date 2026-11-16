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

    private var itemStatus: NSKeyValueObservation?
    private var playStatus: NSKeyValueObservation?
    private var timeObserver: Any?
    private var failureObserver: NSObjectProtocol?
    private var session: UUID?

    func start(_ media: Media) {
        stop()
        let id = UUID()
        session = id
        do {
            let item = AVPlayerItem(url: try media.readableURL())
            player.replaceCurrentItem(with: item)
            itemStatus = item.observe(\.status, options: [.initial, .new]) { [weak self] current, _ in
                let status = current.status
                let duration = current.duration.seconds
                let error = current.error?.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self, self.session == id else { return }
                    if status == .failed {
                        self.showFailure(error)
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
                    guard self?.session == id else { return }
                    self?.showFailure(error)
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
        } catch {
            showFailure(error.localizedDescription)
        }
    }

    func toggle() {
        guard message == nil else { return }
        if isPlaying {
            player.pause()
        } else {
            if duration > 0 && elapsed >= duration - 0.1 { seek(0) }
            player.play()
        }
    }

    func seek(_ seconds: Double) {
        guard message == nil, seconds.isFinite, duration > 0 else { return }
        elapsed = min(max(seconds, 0), duration)
        player.seek(to: CMTime(seconds: elapsed, preferredTimescale: 600))
    }

    func stop() {
        session = nil
        itemStatus = nil
        playStatus = nil
        if let observer = timeObserver { player.removeTimeObserver(observer) }
        if let observer = failureObserver { NotificationCenter.default.removeObserver(observer) }
        timeObserver = nil
        failureObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        elapsed = 0
        duration = 0
        isPlaying = false
        message = nil
    }

    private func showFailure(_ detail: String?) {
        player.pause()
        message = detail.map { "无法播放此视频：\($0)" } ?? "当前系统无法解码此视频。"
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
