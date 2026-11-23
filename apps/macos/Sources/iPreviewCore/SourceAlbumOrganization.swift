import Foundation

public struct SourceAlbumKey: Hashable, Sendable {
    public let sourceID: Int64
    public let relativePath: String

    public init(sourceID: Int64, relativePath: String) {
        self.sourceID = sourceID
        self.relativePath = relativePath
    }

    public init(media: Media) {
        self.init(sourceID: media.source.id, relativePath: media.components.dropLast().joined(separator: "/"))
    }

    public static func == (left: Self, right: Self) -> Bool {
        left.sourceID == right.sourceID && left.relativePath.utf8.elementsEqual(right.relativePath.utf8)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(sourceID)
        // SQLite's path key uses the actual spelling, including Unicode normalization.
        for byte in relativePath.utf8 { hasher.combine(byte) }
    }
}

public struct SourceAlbumTag: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let name: String
    public let normalizedName: String

    public static func suggestions(matching prefix: String, from tags: [Self]) -> [Self] {
        let query = names(from: prefix).normalized
        return tags.filter { query.isEmpty || $0.normalizedName.contains(query) }.sorted {
            let lhs = $0.normalizedName == query ? 0 : $0.normalizedName.hasPrefix(query) ? 1 : 2
            let rhs = $1.normalizedName == query ? 0 : $1.normalizedName.hasPrefix(query) ? 1 : 2
            return (lhs, $0.normalizedName) < (rhs, $1.normalizedName)
        }
    }

    public static func names(from input: String) -> (display: String, normalized: String) {
        let display = input.precomposedStringWithCompatibilityMapping.unicodeScalars
            .split(whereSeparator: { $0.properties.isWhitespace }).map(String.init).joined(separator: " ")
        let normalized = display.decomposedStringWithCanonicalMapping.lowercased().precomposedStringWithCanonicalMapping
        return (display, normalized)
    }
}

public struct SourceAlbumOrganization: Equatable, Sendable {
    public let favorite: Bool
    public let ratingHalf: Int?
    public let tags: [SourceAlbumTag]
    public let configuredCoverIDs: [Int64]
    public let effectiveCoverIDs: [Int64]
}

public enum AlbumOrganizationError: LocalizedError {
    case unknownAlbum
    case invalidTagName
    case tagNameTaken
    case unknownTag
    case invalidRating
    case invalidCover

    public var errorDescription: String? {
        switch self {
        case .unknownAlbum: "此专辑已不在资料库中。"
        case .invalidTagName: "请输入有效的标签名称。"
        case .tagNameTaken: "已有同名标签。"
        case .unknownTag: "此标签已不存在。"
        case .invalidRating: "评分必须在 0 到 5 星之间，每半星一档。"
        case .invalidCover: "请从当前专辑中选择不超过四张不同的可用图片。"
        }
    }
}

public struct SourceAlbumIndex: Sendable {
    public let tags: [SourceAlbumTag]
    public let taggedAlbums: [Int64: Set<SourceAlbumKey>]
    public let configuredCovers: [SourceAlbumKey: [Int64]]

    public static let empty = Self(tags: [], taggedAlbums: [:], configuredCovers: [:])

    public func covers(for album: SourceAlbumKey, members: [Media]) -> [Media] {
        let available = members.filter { $0.isAvailable && $0.kind == .image }
        let ids = Self.coverIDs(configured: configuredCovers[album, default: []],
                                available: available.map { ($0.id, $0.relativePath) })
        let byID = Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    static func coverIDs(configured: [Int64], available: [(id: Int64, path: String)]) -> [Int64] {
        let availableIDs = Set(available.map(\.id))
        if !configured.isEmpty && configured.allSatisfy(availableIDs.contains) { return configured }
        let first = available.min { compareNaturally($0.path, $1.path) == .orderedAscending }
        return first.map { [$0.id] } ?? []
    }
}
