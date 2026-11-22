import Foundation

public struct ScanEntry: Sendable {
    public let relativePath: String
    public let kind: MediaKind
}

public struct ImportCandidate: Identifiable, Sendable {
    public var id: Layout { layout }

    public let layout: Layout
    public let entries: [ScanEntry]

    public var albumCount: Int {
        Set(entries.map { $0.relativePath.split(separator: "/").dropLast().joined(separator: "/") }).count
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
        let levels = try scanLevels(root)
        var candidates: [ImportCandidate] = []
        if !levels.creator.isEmpty {
            candidates.append(ImportCandidate(layout: .creator, entries: levels.creator))
        }
        if !levels.multiCreator.isEmpty {
            candidates.append(ImportCandidate(layout: .multiCreator, entries: levels.multiCreator))
        }
        if candidates.isEmpty, !levels.flat.isEmpty {
            candidates.append(ImportCandidate(layout: .flat, entries: levels.flat))
        }

        guard !candidates.isEmpty else { throw ScanError.noSupportedMedia }
        return SourceInspection(root: root, candidates: candidates)
    }

    public static func inspectVideoWork(_ selected: URL, dataDirectory: URL) throws -> VideoWorkRecognition {
        let root = try validatedRoot(selected, dataDirectory: dataDirectory)
        let levels = try scanLevels(root)
        return VideoWork.recognize(root: root, entries: levels.flat + levels.creator + levels.multiCreator)
    }

    public static func rescan(_ source: Source) throws -> [ScanEntry] {
        let rootChildren = try readRoot(source.url)
        switch source.layout {
        case .flat:
            return entries(in: rootChildren, prefix: [])
        case .creator:
            return try rootChildren.flatMap { child, values -> [ScanEntry] in
                guard values.isDirectory == true else { return [] }
                return entries(in: try children(of: child), prefix: [child.lastPathComponent])
            }
        case .multiCreator:
            return try rootChildren.flatMap { child, values -> [ScanEntry] in
                guard values.isDirectory == true else { return [] }
                return try children(of: child).flatMap { grandchild, nestedValues -> [ScanEntry] in
                    guard nestedValues.isDirectory == true else { return [] }
                    return entries(in: try children(of: grandchild), prefix: [child.lastPathComponent, grandchild.lastPathComponent])
                }
            }
        }
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

    private static func scanLevels(_ root: URL) throws -> (flat: [ScanEntry], creator: [ScanEntry], multiCreator: [ScanEntry]) {
        let rootChildren = try readRoot(root)
        var creatorEntries: [ScanEntry] = []
        var multiEntries: [ScanEntry] = []
        for (child, values) in rootChildren where values.isDirectory == true {
            let first = try children(of: child)
            creatorEntries += entries(in: first, prefix: [child.lastPathComponent])
            for (grandchild, nestedValues) in first where nestedValues.isDirectory == true {
                let second = try children(of: grandchild)
                multiEntries += entries(in: second, prefix: [child.lastPathComponent, grandchild.lastPathComponent])
            }
        }
        return (entries(in: rootChildren, prefix: []), creatorEntries, multiEntries)
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
