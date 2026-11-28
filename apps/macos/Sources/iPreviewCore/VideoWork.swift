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

    private static let legacyVideoFolder = "视频"
    private static let legacyBookContainer = "附加写真集"
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
        let byParent = Dictionary(grouping: entries.filter { $0.kind != .audio }) {
            ($0.relativePath as NSString).deletingLastPathComponent
        }
        let atRoot = byParent["", default: []]
        let rootVideos = atRoot.filter { $0.kind == .video }
        let firstLevel = byParent.filter { !$0.key.isEmpty && !$0.key.contains("/") }
        let photoFolders = firstLevel.filter { $0.value.allSatisfy { $0.kind == .image } }
        let bookPaths = byParent.keys.filter { $0.contains("/") }
            .sorted { compareNaturally($0, $1) == .orderedAscending }
        let videos = entries.filter { $0.kind == .video }

        if let video = rootVideos.first {
            guard !photoFolders.isEmpty else { return .unrecognized }
            guard videos.count == 1 else { return .ambiguous }
            let rootImages = atRoot.filter { $0.kind == .image }
            let markedSamples = rootImages.filter { stem($0) == samplesName }
            guard markedSamples.count <= 1 else { return .ambiguous }
            let samples = markedSamples.isEmpty && rootImages.count == 1 ? rootImages : markedSamples
            let usesLegacyRoles = !markedSamples.isEmpty && photoFolders[legacyBookContainer] != nil
                && !bookPaths.contains { ($0 as NSString).deletingLastPathComponent == legacyBookContainer }
            let folder = usesLegacyRoles ? legacyBookContainer : photoFolders.first?.key
            guard usesLegacyRoles || (photoFolders.count == 1 && bookPaths.isEmpty),
                  let folder, let photos = photoFolders[folder] else { return .ambiguous }
            let book = PhotoSet(relativePath: folder, cover: nil, photos: sorted(photos))
            return .recognized(VideoWork(root: root, structure: .compact, video: video,
                                         samples: samples, photoSets: [book], videoFolderImages: []))
        }

        guard !bookPaths.isEmpty, let video = videos.first else { return .unrecognized }
        let videoFolder = (video.relativePath as NSString).deletingLastPathComponent
        guard videos.count == 1, let videoFiles = firstLevel[videoFolder] else { return .ambiguous }
        let containers = Set(bookPaths.map { ($0 as NSString).deletingLastPathComponent })
        let usesLegacyRoles = videoFolder == legacyVideoFolder && containers.contains(legacyBookContainer)
            && photoFolders[samplesName] != nil
        let container = usesLegacyRoles ? legacyBookContainer : containers.count == 1 ? containers.first : nil
        guard let container, firstLevel[container] == nil,
              usesLegacyRoles || photoFolders.count <= 1 else { return .ambiguous }

        var photoSets: [PhotoSet] = []
        for path in bookPaths where (path as NSString).deletingLastPathComponent == container {
            let images = byParent[path, default: []]
            let covers = images.filter { stem($0) == coverName }
            let photos = images.filter { stem($0) != coverName }
            guard covers.count <= 1, !photos.isEmpty else { return .ambiguous }
            photoSets.append(PhotoSet(relativePath: path, cover: covers.first, photos: sorted(photos)))
        }
        let samples = usesLegacyRoles ? photoFolders[samplesName] : photoFolders.first?.value
        return .recognized(VideoWork(root: root, structure: .complete, video: video,
                                     samples: sorted(samples ?? []), photoSets: photoSets,
                                     videoFolderImages: sorted(videoFiles.filter { $0.kind == .image })))
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
