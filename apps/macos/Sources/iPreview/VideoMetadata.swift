import AVFoundation
import Foundation

struct VideoMetadata {
    let resolution: String?
    let duration: Double?
    let title: String?
    let author: String?

    enum ReadError: LocalizedError {
        case unreadable

        var errorDescription: String? { "无法识别视频元信息。" }
    }

    static func read(from url: URL) async throws -> Self {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ReadError.unreadable
        }

        let (duration, metadata) = try await asset.load(.duration, .commonMetadata)
        let descriptions = try await track.load(.formatDescriptions)
        let resolution = descriptions.first.flatMap { description -> String? in
            let size = CMVideoFormatDescriptionGetDimensions(description)
            guard size.width > 0, size.height > 0 else { return nil }
            return "\(size.width) × \(size.height)"
        }

        let title = try await text(from: metadata, matching: [.commonKeyTitle])
        let author = try await text(from: metadata, matching: [.commonKeyAuthor, .commonKeyCreator, .commonKeyArtist])
        return Self(resolution: resolution, duration: duration.seconds.isFinite && duration.seconds > 0
                    ? duration.seconds : nil, title: title, author: author)
    }

    private static func text(from metadata: [AVMetadataItem], matching keys: [AVMetadataKey]) async throws -> String? {
        for key in keys {
            for item in metadata where item.commonKey == key {
                let value = try await item.load(.stringValue)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let value, !value.isEmpty { return value }
            }
        }
        return nil
    }
}
