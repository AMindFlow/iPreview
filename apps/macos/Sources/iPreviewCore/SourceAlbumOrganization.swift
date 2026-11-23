import Foundation

public struct SourceAlbumKey: Hashable, Sendable {
    public let sourceID: Int64
    public let relativePath: String

    public init(sourceID: Int64, relativePath: String) {
        self.sourceID = sourceID
        self.relativePath = relativePath
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
