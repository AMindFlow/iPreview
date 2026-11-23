import Foundation

public enum Layout: String, Sendable, CaseIterable, Identifiable {
    case flat, creator
    case multiCreator = "multi-creator"

    public var id: Self { self }

    public var albumDepth: Int {
        switch self {
        case .flat: 0
        case .creator: 1
        case .multiCreator: 2
        }
    }

    public var title: String {
        switch self {
        case .flat: "单个专辑"
        case .creator: "创作者 → 专辑"
        case .multiCreator: "多创作者 → 创作者 → 专辑"
        }
    }
}

public enum MediaKind: String, Sendable {
    case image, video

    init?(extension pathExtension: String) {
        switch pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "webp", "gif", "heic": self = .image
        case "mp4", "mov", "ts", "mkv", "webm", "avi": self = .video
        default: return nil
        }
    }
}

public struct Source: Sendable, Identifiable, Hashable {
    public let id: Int64
    public let path: String
    public let layout: Layout
    public let isAvailable: Bool

    public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
    public var name: String { url.lastPathComponent }
}

public struct Media: Sendable, Identifiable, Hashable {
    public let id: Int64
    public let source: Source
    public let relativePath: String
    public let kind: MediaKind
    public let existsInSource: Bool
    public internal(set) var workAlbumPath: String?

    public var isAvailable: Bool { source.isAvailable && existsInSource }
    public var components: [String] { relativePath.components(separatedBy: "/") }
    public var name: String { components.last! }
    public var directories: [String] { [source.name] + components.dropLast() }

    public var creator: String { source.layout == .multiCreator ? components[0] : source.name }
    var albumComponents: ArraySlice<String> { components.dropLast().prefix(source.layout.albumDepth) }
    public var album: String {
        if let workAlbumPath { return workAlbumPath.split(separator: "/").last.map(String.init) ?? source.name }
        return albumComponents.last ?? source.name
    }

    /// Resolve a live path without accepting symlink redirection added since the scan.
    public func readableURL() throws -> URL {
        guard isAvailable else { throw FileError.unavailable }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        var url = source.url
        let root = try url.resourceValues(forKeys: keys)
        guard root.isDirectory == true, root.isSymbolicLink != true else { throw FileError.unavailable }
        for (offset, component) in components.enumerated() {
            guard component != "", component != ".", component != ".." else { throw FileError.unavailable }
            let directory = offset < components.count - 1
            url.appendPathComponent(component, isDirectory: directory)
            let values = try url.resourceValues(forKeys: keys)
            let expectedType = directory ? values.isDirectory : values.isRegularFile
            guard values.isSymbolicLink != true, expectedType == true else { throw FileError.unavailable }
        }
        guard hasUnredirectedPath(url) else { throw FileError.unavailable }
        return url
    }
}

public enum FileError: LocalizedError {
    case unavailable

    public var errorDescription: String? { "源文件已离线、移动或无法安全读取。" }
}

public struct VirtualAlbum: Sendable, Identifiable, Hashable {
    public let id: Int64
    public let name: String
    public let mediaIDs: [Int64]
}

public struct LibrarySnapshot: Sendable {
    public let sources: [Source]
    public let media: [Media]
    public let albums: [VirtualAlbum]
    public let dataVersion: Int64
    public let videoWorks: [IndexedVideoWork]

    public static let empty = Self(sources: [], media: [], albums: [], dataVersion: 0, videoWorks: [])
}

func compareNaturally(_ lhs: String, _ rhs: String) -> ComparisonResult {
    let order = lhs.compare(rhs, options: [.caseInsensitive, .numeric], locale: Locale(identifier: "en_US_POSIX"))
    if order == .orderedSame {
        return lhs.compare(rhs, options: .literal)
    }
    return order
}

func hasUnredirectedPath(_ url: URL) -> Bool {
    url.standardizedFileURL.path == url.resolvingSymlinksInPath().standardizedFileURL.path
}
