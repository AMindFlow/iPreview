import Foundation

public struct ScanEntry: Sendable {
    public let relativePath: String
    public let kind: MediaKind
    var videoWork: VideoWorkMembership?
}

public struct ImportCandidate: Identifiable, Sendable {
    public var id: Layout { layout }

    public let layout: Layout
    public let entries: [ScanEntry]

    public var videoWorkCount: Int { entries.count { if case .video = $0.videoWork { true } else { false } } }

    public var albumCount: Int {
        Set(entries.map { entry in
            entry.relativePath.split(separator: "/").prefix(layout.albumDepth).joined(separator: "/")
        }).count
    }
}

public struct SourceInspection: Identifiable, Sendable {
    public var id: String { root.path }

    public let root: URL
    public let candidates: [ImportCandidate]
}

public enum ScanError: LocalizedError {
    case inaccessibleRoot(String)
    case noSupportedMedia
    case overlappingCatalog

    public var errorDescription: String? {
        switch self {
        case .inaccessibleRoot(let name): "无法读取媒体源「\(name)」。请确认磁盘已连接并允许访问。"
        case .noSupportedMedia: "此目录未发现支持的媒体或专辑结构。"
        case .overlappingCatalog: "请选择应用数据目录之外的媒体目录。"
        }
    }
}

public enum SourceScanner {
    private static let keys: Set<URLResourceKey> = [
        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isHiddenKey,
    ]

    public static func inspect(_ selected: URL, dataDirectory: URL) throws -> SourceInspection {
        let root = try validatedRoot(selected, dataDirectory: dataDirectory)
        let levels = try scanLevels(root, through: Layout.multiCreator.albumDepth)
        let candidates = [Layout.creator, .multiCreator].compactMap { layout in
            let files = levels[layout.albumDepth]
            return files.isEmpty ? nil : ImportCandidate(layout: layout, entries: files)
        }
        if !candidates.isEmpty { return SourceInspection(root: root, candidates: candidates) }
        guard !levels[0].isEmpty else { throw ScanError.noSupportedMedia }
        return SourceInspection(root: root, candidates: [ImportCandidate(layout: .flat, entries: levels[0])])
    }

    public static func inspectVideoWork(_ selected: URL, dataDirectory: URL) throws -> VideoWorkRecognition {
        let root = try validatedRoot(selected, dataDirectory: dataDirectory)
        return try probeVideoWork(root, children: readRoot(root))
    }

    public static func rescan(_ source: Source) throws -> [ScanEntry] {
        let depth = source.layout.albumDepth
        let levels = try scanLevels(source.url, through: depth, retainingLayoutDepth: true)
        let workEntries = levels.flatMap { level in level.filter { $0.videoWork != nil } }
        let workPaths = Set(workEntries.map(\.relativePath))
        return levels[depth].filter { !workPaths.contains($0.relativePath) } + workEntries
    }

    public static func isRootAvailable(_ source: Source) -> Bool {
        isReadableRoot(source.url)
    }

    private static func isReadableRoot(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: keys) else { return false }
        return values.isDirectory == true && values.isSymbolicLink != true
            && hasUnredirectedPath(url)
            && FileManager.default.isReadableFile(atPath: url.path)
    }

    private static func readRoot(_ url: URL) throws -> [(URL, URLResourceValues)] {
        guard isReadableRoot(url) else { throw ScanError.inaccessibleRoot(url.lastPathComponent) }
        do {
            return try children(of: url)
        } catch {
            throw ScanError.inaccessibleRoot(url.lastPathComponent)
        }
    }

    private static func validatedRoot(_ selected: URL, dataDirectory: URL) throws -> URL {
        let root = selected.standardizedFileURL.resolvingSymlinksInPath()
        let dataPath = dataDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        if dataPath == root.path || dataPath.hasPrefix(root.path == "/" ? "/" : root.path + "/")
            || root.path.hasPrefix(dataPath + "/") {
            throw ScanError.overlappingCatalog
        }
        return root
    }

    private static func scanLevels(
        _ root: URL, through maximumDepth: Int, retainingLayoutDepth: Bool = false
    ) throws -> [[ScanEntry]] {
        var levels = Array(repeating: [ScanEntry](), count: maximumDepth + 1)
        func scan(_ directory: URL, children values: [(URL, URLResourceValues)], prefix: [String],
                  recognizeWorks: Bool) throws {
            var recognizeChildWorks = recognizeWorks
            if recognizeWorks, case .recognized(let work) = try probeVideoWork(directory, children: values) {
                let indexed = work.indexEntries(prefix: prefix)
                let included = Set(indexed.map(\.relativePath))
                let extras = entries(in: values, prefix: prefix).filter { !included.contains($0.relativePath) }
                levels[prefix.count] += indexed + extras
                guard retainingLayoutDepth else { return }
                // A saved layout can contain ordinary media at an additional level inside a work.
                recognizeChildWorks = false
            } else {
                levels[prefix.count] += entries(in: values, prefix: prefix)
            }
            guard prefix.count < maximumDepth else { return }
            for (child, resource) in values where resource.isDirectory == true {
                try scan(child, children: children(of: child), prefix: prefix + [child.lastPathComponent],
                         recognizeWorks: recognizeChildWorks)
            }
        }
        try scan(root, children: readRoot(root), prefix: [], recognizeWorks: true)
        return levels
    }

    private static func probeVideoWork(
        _ root: URL, children values: [(URL, URLResourceValues)]
    ) throws -> VideoWorkRecognition {
        var files = entries(in: values, prefix: [])
        let folders = try values.filter { $0.1.isDirectory == true }.map { folder, _ in
            (name: folder.lastPathComponent, children: try children(of: folder))
        }
        for folder in folders {
            files += entries(in: folder.children, prefix: [folder.name])
        }
        guard files.contains(where: { $0.kind == .video }) else { return .unrecognized }
        for folder in folders {
            for (book, attributes) in folder.children where attributes.isDirectory == true {
                files += entries(in: try children(of: book), prefix: [folder.name, book.lastPathComponent])
            }
        }
        return VideoWork.recognize(root: root, entries: files)
    }

    private static func children(of directory: URL) throws -> [(URL, URLResourceValues)] {
        guard hasUnredirectedPath(directory) else {
            throw FileError.unavailable
        }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        return try urls.compactMap { url in
            let values = try url.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true, values.isHidden != true,
                  !url.lastPathComponent.hasPrefix(".") else { return nil }
            return (url, values)
        }
    }

    private static func entries(in children: [(URL, URLResourceValues)], prefix: [String]) -> [ScanEntry] {
        children.compactMap { url, values in
            guard values.isRegularFile == true, let kind = MediaKind(extension: url.pathExtension) else { return nil }
            return ScanEntry(relativePath: (prefix + [url.lastPathComponent]).joined(separator: "/"), kind: kind)
        }
    }
}
