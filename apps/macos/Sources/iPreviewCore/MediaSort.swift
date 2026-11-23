import Foundation

public struct MediaFileFacts: Sendable {
    public let modified: Date?
    public let size: Int?

    public init(_ media: Media) {
        let url = try? media.readableURL()
        let values = try? url?.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        modified = values?.contentModificationDate
        size = values?.fileSize
    }
}

public struct MediaSort: Equatable, Sendable {
    public enum Field: CaseIterable, Sendable {
        case original, name, modified, size

        public var title: String {
            switch self {
            case .original: "原次序"
            case .name: "文件名"
            case .modified: "修改时间"
            case .size: "文件大小"
            }
        }
    }

    public var field: Field = .original
    public var descending = false

    public init(field: Field = .original, descending: Bool = false) {
        self.field = field
        self.descending = descending
    }

    public var needsFileFacts: Bool { field == .modified || field == .size }

    public func arrange(_ items: [Media]) -> [Media] {
        guard field != .original, items.count > 1 else { return items }
        var facts: [Int64: MediaFileFacts] = [:]
        if needsFileFacts {
            for item in items {
                if Task.isCancelled { return items }
                facts[item.id] = MediaFileFacts(item)
            }
        }

        return items.sorted { lhs, rhs in
            let nameOrder = compareNaturally(lhs.name, rhs.name)
            let order = switch field {
            case .original: ComparisonResult.orderedSame
            case .name: descending ? compareNaturally(rhs.name, lhs.name) : nameOrder
            case .modified: compare(facts[lhs.id]!.modified, facts[rhs.id]!.modified)
            case .size: compare(facts[lhs.id]!.size, facts[rhs.id]!.size)
            }
            if order != .orderedSame { return order == .orderedAscending }
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return lhs.id < rhs.id
        }
    }

    private func compare<Value: Comparable>(_ lhs: Value?, _ rhs: Value?) -> ComparisonResult {
        switch (lhs, rhs) {
        case (.some(let a), .some(let b)):
            if a == b { return .orderedSame }
            return (descending ? a > b : a < b) ? .orderedAscending : .orderedDescending
        case (.some, .none): return .orderedAscending
        case (.none, .some): return .orderedDescending
        case (.none, .none): return .orderedSame
        }
    }
}
