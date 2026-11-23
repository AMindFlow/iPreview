import Foundation

public enum VideoWorkRecognition: Sendable {
    case unrecognized
    case ambiguous
    case recognized(VideoWork)
}

public struct VideoWork: Sendable {
    public enum Structure: String, Hashable, Sendable {
        case complete
        case compact
    }

    public struct PhotoSet: Sendable {
        public let relativePath: String
        public let cover: ScanEntry?
        public let photos: [ScanEntry]
    }

    public let root: URL
    public let structure: Structure
    public let video: ScanEntry
    public let samples: [ScanEntry]
    public let photoSets: [PhotoSet]

    private static let videoFolder = "视频"
    private static let samplesName = "官方样张"
    static let photoSetsFolder = "附加写真集"
    private static let coverName = "封面"
    static let folders: Set<String> = [videoFolder, samplesName, photoSetsFolder]

    func indexEntries(prefix: [String]) -> [ScanEntry] {
        func path(_ file: ScanEntry) -> String { (prefix + [file.relativePath]).joined(separator: "/") }
        let videoPath = path(video)
        func image(_ file: ScanEntry, role: VideoWorkImageRole, set: Int, position: Int) -> ScanEntry {
            ScanEntry(relativePath: path(file), kind: .image,
                      videoWork: .image(videoPath: videoPath, role: role, set: set, position: position))
        }
        var entries = [ScanEntry(relativePath: videoPath, kind: .video, videoWork: .video(structure))]
        entries += samples.enumerated().map { image($1, role: .sample, set: 0, position: $0) }
        for (set, book) in photoSets.enumerated() {
            if let cover = book.cover { entries.append(image(cover, role: .cover, set: set, position: 0)) }
            entries += book.photos.enumerated().map { image($1, role: .photo, set: set, position: $0) }
        }
        return entries
    }

    static func recognize(root: URL, entries: [ScanEntry]) -> VideoWorkRecognition {
        let byParent = Dictionary(grouping: entries) { entry -> String in
            guard let slash = entry.relativePath.lastIndex(of: "/") else { return "" }
            return String(entry.relativePath[..<slash])
        }
        let atRoot = byParent["", default: []]
        let rootVideos = atRoot.filter { $0.kind == .video }
        let rootSamples = atRoot.filter { $0.kind == .image && stem($0) == samplesName }
        let folderVideos = byParent[videoFolder, default: []].filter { $0.kind == .video }
        let folderSamples = byParent[samplesName, default: []].filter { $0.kind == .image }
        let flatPhotos = byParent[photoSetsFolder, default: []].filter { $0.kind == .image }
        let nestedPhotoSets = byParent.keys.filter { $0.hasPrefix(photoSetsFolder + "/") }
            .sorted { compareNaturally($0, $1) == .orderedAscending }

        guard !rootSamples.isEmpty || byParent[samplesName] != nil || byParent[photoSetsFolder] != nil
                || !nestedPhotoSets.isEmpty else { return .unrecognized }

        if byParent[videoFolder] != nil || byParent[samplesName] != nil || !nestedPhotoSets.isEmpty {
            guard folderVideos.count == 1, !folderSamples.isEmpty, !nestedPhotoSets.isEmpty,
                  rootVideos.isEmpty, rootSamples.isEmpty, flatPhotos.isEmpty else { return .ambiguous }
            var photoSets: [PhotoSet] = []
            for path in nestedPhotoSets {
                let images = byParent[path, default: []].filter { $0.kind == .image }
                let covers = images.filter { stem($0) == coverName }
                let photos = images.filter { stem($0) != coverName }
                guard covers.count == 1, !photos.isEmpty else { return .ambiguous }
                photoSets.append(PhotoSet(relativePath: path, cover: covers[0], photos: sorted(photos)))
            }
            return .recognized(VideoWork(root: root, structure: .complete, video: folderVideos[0],
                                         samples: sorted(folderSamples), photoSets: photoSets))
        }

        guard rootVideos.count == 1, rootSamples.count == 1, !flatPhotos.isEmpty else { return .ambiguous }
        let book = PhotoSet(relativePath: photoSetsFolder, cover: nil, photos: sorted(flatPhotos))
        return .recognized(VideoWork(root: root, structure: .compact, video: rootVideos[0],
                                     samples: rootSamples, photoSets: [book]))
    }

    private static func stem(_ entry: ScanEntry) -> String {
        let filename = (entry.relativePath as NSString).lastPathComponent
        return (filename as NSString).deletingPathExtension
    }

    private static func sorted(_ entries: [ScanEntry]) -> [ScanEntry] {
        entries.sorted { compareNaturally($0.relativePath, $1.relativePath) == .orderedAscending }
    }
}

enum VideoWorkImageRole: String {
    case sample, cover, photo
}

enum VideoWorkMembership: Sendable {
    case video(VideoWork.Structure)
    case image(videoPath: String, role: VideoWorkImageRole, set: Int, position: Int)
}

public struct IndexedVideoWork: Hashable, Identifiable, Sendable {
    public struct PhotoSet: Hashable, Sendable {
        public let cover: Media?
        public let photos: [Media]

        public var title: String { photos[0].components.dropLast().last! }
    }

    public let video: Media
    public let structure: VideoWork.Structure
    public let samples: [Media]
    public let photoSets: [PhotoSet]

    public var id: Int64 { video.id }
    public var relativePath: String { Self.albumPath(for: video.relativePath, structure: structure) }

    static func albumPath(for videoPath: String, structure: VideoWork.Structure) -> String {
        videoPath.split(separator: "/").dropLast(structure == .complete ? 2 : 1).joined(separator: "/")
    }
    public var title: String { relativePath.split(separator: "/").last.map(String.init) ?? video.source.name }
}
