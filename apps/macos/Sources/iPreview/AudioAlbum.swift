import AVFoundation
import Foundation
import ImageIO
import iPreviewCore

struct AudioAlbum: Hashable, Sendable {
    let name: String
    let tracks: [Media]
    let images: [Media]

    init(track: Media, ordered: [Media], indexed: [Media]) {
        let folder = track.parentRelativePath
        name = folder.split(separator: "/").last.map(String.init) ?? track.source.name

        let members = indexed.filter {
            $0.source.id == track.source.id && $0.parentRelativePath == folder &&
                ($0.existsInSource || $0.id == track.id)
        }.sorted { compareNaturally($0.name, $1.name) == .orderedAscending }
        images = members.filter { $0.kind == .image }

        let indexedTracks = members.filter { $0.kind == .audio }
        let trackIDs = Set(indexedTracks.map(\.id))
        let shown = ordered.filter { trackIDs.contains($0.id) }
        tracks = shown.count == indexedTracks.count ? shown : indexedTracks
    }

    func cover(limit: Int) async -> CGImage? {
        for image in images {
            guard !Task.isCancelled else { return nil }
            if let url = try? image.readableURL(), let cover = MediaImages.image(at: url, limit: limit) {
                return cover
            }
        }
        for track in tracks.sorted(by: { compareNaturally($0.name, $1.name) == .orderedAscending }) {
            guard !Task.isCancelled else { return nil }
            if let cover = await AudioArtwork.embedded(in: track, limit: limit) {
                return cover
            }
        }
        return nil
    }
}

enum AudioArtwork {
    static func embedded(in media: Media, limit: Int) async -> CGImage? {
        guard let url = try? media.readableURL() else { return nil }
        let asset = AVURLAsset(url: url)
        if let metadata = try? await asset.load(.commonMetadata) {
            for item in AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork) {
                guard !Task.isCancelled else { return nil }
                if let bytes = try? await item.load(.dataValue), let image = MediaImages.image(data: bytes, limit: limit) {
                    return image
                }
            }
        }
        guard url.pathExtension.lowercased() == "flac" else { return nil }
        return try? flacArtwork(at: url, limit: limit)
    }

    private static func flacArtwork(at url: URL, limit: Int) throws -> CGImage? {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        guard try file.read(upToCount: 4) == Data("fLaC".utf8) else { return nil }

        while !Task.isCancelled, let header = try file.read(upToCount: 4), header.count == 4 {
            let length = header.dropFirst().reduce(0) { ($0 << 8) | Int($1) }
            if header[0] & 0x7f == 6, length > 0 {
                guard let block = try file.read(upToCount: length), block.count == length else { return nil }
                if let bytes = pictureBytes(in: block), let image = MediaImages.image(data: bytes, limit: limit) {
                    return image
                }
            } else {
                try file.seek(toOffset: file.offset() + UInt64(length))
            }
            if header[0] & 0x80 != 0 { return nil }
        }
        return nil
    }

    private static func pictureBytes(in block: Data) -> Data? {
        var cursor = 4 // Picture type.
        func readLength() -> Int? {
            guard cursor <= block.count - 4 else { return nil }
            defer { cursor += 4 }
            return block[cursor..<(cursor + 4)].reduce(0) { ($0 << 8) | Int($1) }
        }

        guard let mimeLength = readLength(), mimeLength <= block.count - cursor else { return nil }
        cursor += mimeLength
        guard let descriptionLength = readLength(), descriptionLength <= block.count - cursor else { return nil }
        cursor += descriptionLength + 16 // Width, height, depth and indexed colors.
        guard let imageLength = readLength(), imageLength <= block.count - cursor else { return nil }
        return block.subdata(in: cursor..<(cursor + imageLength))
    }
}

extension MediaKind {
    var icon: String {
        switch self {
        case .image: "photo"
        case .video: "film"
        case .audio: "music.note"
        }
    }

    var title: String {
        switch self {
        case .image: "图像"
        case .video: "视频"
        case .audio: "音频"
        }
    }
}
