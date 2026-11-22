import Foundation

public enum MatchMode: String, Sendable, CaseIterable, Identifiable {
    case exact, fuzzy

    public var id: Self { self }
    public var title: String { self == .exact ? "精确" : "模糊" }
}

public struct GlobalSearchTerm: Sendable {
    public let text: String
    public let mode: MatchMode

    public init(_ input: String) {
        let candidate = input.drop(while: \.isWhitespace)
        let remainder = candidate.dropFirst()
        let exact = (candidate.first == "@" || candidate.first == "＠") && remainder.first?.isWhitespace == true
        text = (exact ? remainder : candidate).trimmingCharacters(in: .whitespacesAndNewlines)
        mode = exact ? .exact : .fuzzy
    }
}

public struct IndexedDirectory: Hashable, Sendable {
    public let source: Source
    public let relativePath: String

    public var components: [String] {
        relativePath.isEmpty ? [source.name] : [source.name] + relativePath.components(separatedBy: "/")
    }

    public var name: String { components.last! }
}

public enum SearchResultCategory: Sendable {
    case creator, album, directory, file
}

public enum GlobalSearchResult: Hashable, Sendable, Identifiable {
    case directory(IndexedDirectory)
    case file(Media)

    public var id: Self { self }

    public var category: SearchResultCategory {
        switch self {
        case .file: .file
        case .directory(let directory):
            switch (directory.source.layout, directory.components.count - 1) {
            case (.creator, 0), (.multiCreator, 1): .creator
            case (.flat, 0), (.creator, 1), (.multiCreator, 2): .album
            default: .directory
            }
        }
    }
}

public struct SearchIndex: Sendable {
    private struct Entry: Sendable {
        let media: Media
        let directories: [Name]
        let file: Name
    }

    private let entries: [Entry]
    private let folders: [(directory: IndexedDirectory, name: Name)]

    public init(media: [Media], sources: [Source] = []) {
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

        var seen: Set<IndexedDirectory> = []
        var folders: [(IndexedDirectory, Name)] = []
        func addFolder(_ source: Source, path: String, name: String) {
            let folder = IndexedDirectory(source: source, relativePath: path)
            if seen.insert(folder).inserted { folders.append((folder, parameters(for: name))) }
        }
        for source in sources { addFolder(source, path: "", name: source.name) }
        for item in media {
            addFolder(item.source, path: "", name: item.source.name)
            var path = ""
            for component in item.components.dropLast() {
                path = path.isEmpty ? component : path + "/" + component
                addFolder(item.source, path: path, name: component)
            }
        }
        self.folders = folders
    }

    public func search(_ query: String, mode: MatchMode, directories: Bool, files: Bool,
                       including include: (Media) -> Bool = { _ in true }) -> [Media] {
        let query = normalize(query)
        guard !query.isEmpty, directories || files else { return [] }
        let lookup = Name.Query(text: query)
        return entries.enumerated().compactMap { index, entry -> (rank: Int, index: Int, media: Media)? in
            guard include(entry.media) else { return nil }
            let directoryRank = directories ? entry.directories.compactMap { $0.rank(lookup, mode: mode) }.min() : nil
            let fileRank = files ? entry.file.rank(lookup, mode: mode, isFile: true) : nil
            return [directoryRank, fileRank].compactMap { $0 }.min().map { ($0, index, entry.media) }
        }
        .sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }
        .map(\.media)
    }

    public func globalSearch(_ query: String, mode: MatchMode, directories: Bool, files: Bool,
                             including include: (GlobalSearchResult) -> Bool = { _ in true }) -> [GlobalSearchResult] {
        let query = normalize(query)
        guard !query.isEmpty, directories || files else { return [] }
        let lookup = Name.Query(text: query)
        var matches: [(rank: Int, order: Int, result: GlobalSearchResult)] = []
        if directories {
            for (index, folder) in folders.enumerated() {
                let result = GlobalSearchResult.directory(folder.directory)
                if include(result), let rank = folder.name.rank(lookup, mode: mode) {
                    matches.append((rank, index, result))
                }
            }
        }
        if files {
            for (index, entry) in entries.enumerated() {
                let result = GlobalSearchResult.file(entry.media)
                if include(result), let rank = entry.file.rank(lookup, mode: mode, isFile: true) {
                    matches.append((rank, folders.count + index, result))
                }
            }
        }
        return matches.sorted { ($0.rank, $0.order) < ($1.rank, $1.order) }.map(\.result)
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
        let hasSuffix: Bool

        init(text: String) {
            self.text = text
            compact = text.filter { !$0.isWhitespace }
            if let dot = fileSuffixIndex(in: text) {
                hasSuffix = MediaKind(extension: String(text[text.index(after: dot)...])) != nil
            } else {
                hasSuffix = false
            }
            switch text.count {
            case 0...2: limit = 0
            case 3...6: limit = 1
            default: limit = 2
            }
        }
    }

    func rank(_ query: Query, mode: MatchMode, isFile: Bool = false) -> Int? {
        if text == query.text { return 0 }
        if mode == .exact {
            guard isFile, !query.hasSuffix, let suffix = fileSuffixIndex(in: text),
                  text[..<suffix] == query.text else { return nil }
            return 0
        }
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

private func fileSuffixIndex(in name: String) -> String.Index? {
    guard let dot = name.lastIndex(of: "."), dot != name.startIndex, name.index(after: dot) != name.endIndex else {
        return nil
    }
    return dot
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
