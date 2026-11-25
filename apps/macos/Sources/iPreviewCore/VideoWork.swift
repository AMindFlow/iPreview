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
    private let videoFolderImages: [ScanEntry]

    private static let samplesName = "官方样张"
    private static let coverName = "封面"

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
        return entries + videoFolderImages.map { ScanEntry(relativePath: path($0), kind: .image) }
    }

    static func recognize(root: URL, entries: [ScanEntry]) -> VideoWorkRecognition {
        let byParent = Dictionary(grouping: entries) { ($0.relativePath as NSString).deletingLastPathComponent }
        let atRoot = byParent["", default: []]
        let rootVideos = atRoot.filter { $0.kind == .video }
        let firstLevel = byParent.filter { !$0.key.isEmpty && !$0.key.contains("/") }
        let photoFolders = firstLevel.filter { $0.value.allSatisfy { $0.kind == .image } }
        let bookPaths = byParent.keys.filter { $0.contains("/") }
            .sorted { compareNaturally($0, $1) == .orderedAscending }
        let videos = entries.filter { $0.kind == .video }

        if let video = rootVideos.first {
            guard let folder = photoFolders.first else { return .unrecognized }
            guard videos.count == 1, photoFolders.count == 1, bookPaths.isEmpty else { return .ambiguous }
            let rootImages = atRoot.filter { $0.kind == .image }
            let markedSamples = rootImages.filter { stem($0) == samplesName }
            guard markedSamples.count <= 1 else { return .ambiguous }
            let samples = markedSamples.isEmpty && rootImages.count == 1 ? rootImages : markedSamples
            let book = PhotoSet(relativePath: folder.key, cover: nil, photos: sorted(folder.value))
            return .recognized(VideoWork(root: root, structure: .compact, video: video,
                                         samples: samples, photoSets: [book], videoFolderImages: []))
        }

        guard !bookPaths.isEmpty, let video = videos.first else { return .unrecognized }
        let containers = Set(bookPaths.map { ($0 as NSString).deletingLastPathComponent })
        guard videos.count == 1, let videoFolder = firstLevel[(video.relativePath as NSString).deletingLastPathComponent],
              containers.count == 1, let container = containers.first, firstLevel[container] == nil,
              photoFolders.count <= 1 else { return .ambiguous }

        var photoSets: [PhotoSet] = []
        for path in bookPaths {
            let images = byParent[path, default: []]
            let covers = images.filter { stem($0) == coverName }
            let photos = images.filter { stem($0) != coverName }
            guard covers.count <= 1, !photos.isEmpty else { return .ambiguous }
            photoSets.append(PhotoSet(relativePath: path, cover: covers.first, photos: sorted(photos)))
        }
        return .recognized(VideoWork(root: root, structure: .complete, video: video,
                                     samples: sorted(photoFolders.first?.value ?? []), photoSets: photoSets,
                                     videoFolderImages: sorted(videoFolder.filter { $0.kind == .image })))
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
