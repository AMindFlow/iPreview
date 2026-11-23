import AppKit
import SwiftUI

@MainActor
final class VLCPlayback {
    enum State: Int32 {
        case idle, opening, buffering, playing, paused, stopped, ended, failed

        var isPlaying: Bool { self == .opening || self == .buffering || self == .playing }
    }

    private static let runtime = Result { try VLCRuntime() }
    private static let releaseQueue = DispatchQueue(label: "iPreview.VLCRelease", qos: .userInitiated)

    let surface = Surface()
    private let runtime: VLCRuntime
    private let instance: OpaquePointer
    private let player: OpaquePointer
    private var started = false
    private(set) var couldNotStart = false

    init(url: URL) throws {
        let demux: String
        switch url.pathExtension.lowercased() {
        case "mp4", "mov": demux = "mp4"
        case "ts": demux = "ts"
        case "mkv", "webm": demux = "mkv"
        case "avi": demux = "avi"
        default: throw VLCPlaybackError.unsupportedFormat
        }
        let runtime = try Self.runtime.get()
        let options = ["--no-video-title-show", "--no-media-library", "--no-plugins-cache", "--no-sub-autodetect-file"]
        let allocated = options.map { strdup($0)! }
        defer { allocated.forEach { free($0) } }
        let arguments: [UnsafePointer<CChar>?] = allocated.map { UnsafePointer($0) }
        guard let instance = arguments.withUnsafeBufferPointer({
            runtime.create(Int32($0.count), $0.baseAddress)
        }) else {
            throw VLCPlaybackError.initialization
        }
        guard let media = url.withUnsafeFileSystemRepresentation({ path in
            path.flatMap { runtime.createMedia(instance, $0) }
        }) else {
            runtime.release(instance)
            throw VLCPlaybackError.initialization
        }
        defer { runtime.releaseMedia(media) }
        ":demux=\(demux)".withCString { runtime.setMediaOption(media, $0) }
        guard let player = runtime.createPlayer(media) else {
            runtime.release(instance)
            throw VLCPlaybackError.initialization
        }
        self.runtime = runtime
        self.instance = instance
        self.player = player
        surface.onAttach = { [weak self] in self?.start() }
    }

    var state: State { State(rawValue: runtime.getState(player))! }
    var duration: Double { max(0, Double(runtime.getLength(player)) / 1000) }
    var elapsed: Double { max(0, Double(runtime.getTime(player)) / 1000) }

    func play() {
        guard started else { return }
        if state == .paused {
            runtime.setPause(player, 0)
        } else {
            couldNotStart = runtime.play(player) != 0
        }
    }

    func pause() {
        if started { runtime.setPause(player, 1) }
    }

    func seek(_ time: Double) {
        runtime.setTime(player, Int64((time * 1000).rounded()))
    }

    func stop() {
        surface.onAttach = nil
        pause()
        // LibVLC may wait for AppKit while removing the video surface.
        let playerAddress = UInt(bitPattern: player)
        let instanceAddress = UInt(bitPattern: instance)
        Self.releaseQueue.async { [runtime, surface] in
            let player = OpaquePointer(bitPattern: playerAddress)!
            runtime.stop(player)
            runtime.releasePlayer(player)
            runtime.release(OpaquePointer(bitPattern: instanceAddress)!)
            DispatchQueue.main.async { withExtendedLifetime(surface) {} }
        }
    }

    private func start() {
        guard !started else { return }
        started = true
        runtime.setSurface(player, Unmanaged.passUnretained(surface).toOpaque())
        play()
    }

    final class Surface: NSView {
        var onAttach: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { onAttach?() }
        }
    }
}

struct VLCCanvas: NSViewRepresentable {
    let surface: VLCPlayback.Surface

    func makeNSView(context: Context) -> VLCPlayback.Surface { surface }

    func updateNSView(_ view: VLCPlayback.Surface, context: Context) {}
}

private enum VLCPlaybackError: Error {
    case missingRuntime, initialization, unsupportedFormat
}

// LibVLC's C entry points are immutable. The runtime stays loaded until all player releases have finished.
private final class VLCRuntime: @unchecked Sendable {
    typealias HandleAction = @convention(c) (OpaquePointer) -> Void
    typealias TimeQuery = @convention(c) (OpaquePointer) -> Int64

    private let library: UnsafeMutableRawPointer
    let create: @convention(c) (Int32, UnsafePointer<UnsafePointer<CChar>?>?) -> OpaquePointer?
    let release: HandleAction
    let createMedia: @convention(c) (OpaquePointer, UnsafePointer<CChar>) -> OpaquePointer?
    let setMediaOption: @convention(c) (OpaquePointer, UnsafePointer<CChar>) -> Void
    let releaseMedia: HandleAction
    let createPlayer: @convention(c) (OpaquePointer) -> OpaquePointer?
    let releasePlayer: HandleAction
    let setSurface: @convention(c) (OpaquePointer, UnsafeMutableRawPointer?) -> Void
    let play: @convention(c) (OpaquePointer) -> Int32
    let setPause: @convention(c) (OpaquePointer, Int32) -> Void
    let stop: HandleAction
    let getState: @convention(c) (OpaquePointer) -> Int32
    let getLength: TimeQuery
    let getTime: TimeQuery
    let setTime: @convention(c) (OpaquePointer, Int64) -> Void

    init() throws {
        guard let path = Bundle.main.privateFrameworksURL?.appendingPathComponent("LibVLC/lib/libvlc.dylib"),
              let library = dlopen(path.path, RTLD_NOW | RTLD_LOCAL) else {
            throw VLCPlaybackError.missingRuntime
        }
        func load<Function>(_ name: String) throws -> Function {
            guard let symbol = dlsym(library, name) else { throw VLCPlaybackError.missingRuntime }
            return unsafeBitCast(symbol, to: Function.self)
        }
        do {
            create = try load("libvlc_new")
            release = try load("libvlc_release")
            createMedia = try load("libvlc_media_new_path")
            setMediaOption = try load("libvlc_media_add_option")
            releaseMedia = try load("libvlc_media_release")
            createPlayer = try load("libvlc_media_player_new_from_media")
            releasePlayer = try load("libvlc_media_player_release")
            setSurface = try load("libvlc_media_player_set_nsobject")
            play = try load("libvlc_media_player_play")
            setPause = try load("libvlc_media_player_set_pause")
            stop = try load("libvlc_media_player_stop")
            getState = try load("libvlc_media_player_get_state")
            getLength = try load("libvlc_media_player_get_length")
            getTime = try load("libvlc_media_player_get_time")
            setTime = try load("libvlc_media_player_set_time")
        } catch {
            dlclose(library)
            throw error
        }
        self.library = library
    }

    deinit { dlclose(library) }
}
