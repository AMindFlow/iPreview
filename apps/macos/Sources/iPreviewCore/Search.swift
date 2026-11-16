import Foundation

public enum MatchMode: String, Sendable, CaseIterable, Identifiable {
    case exact, fuzzy

    public var id: Self { self }
    public var title: String { self == .exact ? "精确" : "模糊" }
}

public struct SearchIndex: Sendable {
    private struct Entry: Sendable {
        let media: Media
        let directories: [Name]
        let file: Name
    }

    private let entries: [Entry]

    public init(media: [Media]) {
        var names: [String: Name] = [:]
        func parameters(for value: String) -> Name {
            if let cached = names[value] { return cached }
            let name = Name(value)
            names[value] = name
            return name
        }
        entries = media.map {
            Entry(media: $0, directories: $0.directories.map(parameters(for:)), file: parameters(for: $0.name))
        }
    }

    public func search(_ query: String, mode: MatchMode, directories: Bool, files: Bool) -> [Media] {
        let query = normalize(query)
        guard !query.isEmpty, directories || files else { return [] }
        let lookup = Name.Query(text: query)
        return entries.enumerated().compactMap { index, entry -> (rank: Int, index: Int, media: Media)? in
            var candidates = directories ? entry.directories : []
            if files { candidates.append(entry.file) }
            return candidates.compactMap { $0.rank(lookup, mode: mode) }.min().map { ($0, index, entry.media) }
        }
        .sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }
        .map(\.media)
    }
}

private struct Name: Sendable {
    let text: String
    let words: [String]
    let pinyin: String
    let initials: String

    init(_ name: String) {
        text = normalize(name)
        words = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let containsChinese = text.unicodeScalars.contains { scalar in
            (0x3400...0x9FFF).contains(scalar.value) || (0x20000...0x323AF).contains(scalar.value)
        }
        if containsChinese, let latin = text.applyingTransform(.mandarinToLatin, reverse: false) {
            let syllables = latin.lowercased()
                .decomposedStringWithCanonicalMapping
                .replacingOccurrences(of: "u\u{308}", with: "v", options: .literal)
                .folding(options: .diacriticInsensitive, locale: nil)
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            pinyin = syllables.joined()
            initials = String(syllables.compactMap(\.first))
        } else {
            pinyin = ""
            initials = ""
        }
    }

    struct Query {
        let text: String
        let compact: String
        let limit: Int

        init(text: String) {
            self.text = text
            compact = text.filter { !$0.isWhitespace }
            switch text.count {
            case 0...2: limit = 0
            case 3...6: limit = 1
            default: limit = 2
            }
        }
    }

    func rank(_ query: Query, mode: MatchMode) -> Int? {
        if text == query.text { return 0 }
        guard mode == .fuzzy else { return nil }
        if text.hasPrefix(query.text) { return 1 }
        if text.contains(query.text) { return 2 }
        if pinyin.contains(query.compact) { return 3 }
        if initials.contains(query.compact) { return 4 }
        if query.limit > 0 && ([text] + words).contains(where: { distance(query.text, $0, within: query.limit) }) {
            return 5
        }
        return nil
    }
}

private func normalize(_ value: String) -> String {
    value.precomposedStringWithCompatibilityMapping
        .folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func distance(_ lhs: String, _ rhs: String, within limit: Int) -> Bool {
    let left = Array(lhs)
    let right = Array(rhs)
    guard abs(left.count - right.count) <= limit else { return false }
    var previous = Array(0...right.count)
    var current = previous
    for (i, character) in left.enumerated() {
        current[0] = i + 1
        for (j, target) in right.enumerated() {
            current[j + 1] = min(current[j] + 1, previous[j + 1] + 1, previous[j] + (character == target ? 0 : 1))
        }
        if current.min()! > limit { return false }
        swap(&previous, &current)
    }
    return previous.last! <= limit
}
