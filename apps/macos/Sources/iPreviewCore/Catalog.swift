import Foundation
import SQLite3

public actor Catalog {
    private let database: Database

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try Database(url: directory.appendingPathComponent("catalog.sqlite3"))
        try database.script("PRAGMA foreign_keys = ON")
        try database.transaction {
            let version = try database.select("PRAGMA user_version") { sqlite3_column_int($0, 0) }.first!
            switch version {
            case 0:
                let migration = Bundle.module.url(
                    forResource: "001-initial", withExtension: "sql", subdirectory: "migrations"
                )!
                try database.script(String(contentsOf: migration, encoding: .utf8))
            case 1:
                break
            default:
                throw SQLiteError(message: "数据库版本 \(version) 需要更新版本的 iPreview")
            }
        }
        self.database = database
    }

    public func snapshot() throws -> LibrarySnapshot {
        try database.transaction(write: false) {
            let sources = try database.select("SELECT id, path, layout, available FROM sources") { row in
                Source(
                    id: sqlite3_column_int64(row, 0),
                    path: textColumn(row, 1),
                    layout: Layout(rawValue: textColumn(row, 2))!,
                    isAvailable: sqlite3_column_int(row, 3) == 1
                )
            }.sorted { compareNaturally($0.path, $1.path) == .orderedAscending }
            let sourceByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
            let media = try database.select("SELECT id, source_id, relative_path, kind, available FROM media") { row in
                Media(
                    id: sqlite3_column_int64(row, 0),
                    source: sourceByID[sqlite3_column_int64(row, 1)]!,
                    relativePath: textColumn(row, 2),
                    kind: MediaKind(rawValue: textColumn(row, 3))!,
                    existsInSource: sqlite3_column_int(row, 4) == 1
                )
            }.sorted { compareNaturally($0.source.path + "/" + $0.relativePath, $1.source.path + "/" + $1.relativePath) == .orderedAscending }
            let members = try database.select("SELECT album_id, media_id FROM album_media ORDER BY position, media_id") { row in
                (album: sqlite3_column_int64(row, 0), media: sqlite3_column_int64(row, 1))
            }
            let byAlbum = Dictionary(grouping: members, by: \.album)
            let albums = try database.select("SELECT id, name FROM albums ORDER BY id") { row in
                let id = sqlite3_column_int64(row, 0)
                return VirtualAlbum(id: id, name: textColumn(row, 1), mediaIDs: byAlbum[id, default: []].map(\.media))
            }
            return LibrarySnapshot(sources: sources, media: media, albums: albums)
        }
    }

    public func importSource(root: URL, candidate: ImportCandidate) throws {
        try database.transaction {
            let path = SQLiteValue.text(root.path)
            let layout = SQLiteValue.text(candidate.layout.rawValue)
            try database.execute("INSERT OR IGNORE INTO sources (path, layout) VALUES (?, ?)", [path, layout])
            let id = try database.select("SELECT id FROM sources WHERE path = ?", [path]) { sqlite3_column_int64($0, 0) }.first!
            try database.execute("UPDATE sources SET layout = ?, available = 1 WHERE id = ?", [layout, .integer(id)])
            try replaceMedia(sourceID: id, entries: candidate.entries)
        }
    }

    public func update(source: Source, entries: [ScanEntry]) throws {
        try database.transaction {
            try database.execute("UPDATE sources SET available = 1 WHERE id = ?", [.integer(source.id)])
            try replaceMedia(sourceID: source.id, entries: entries)
        }
    }

    public func markUnavailable(source: Source) throws {
        try database.execute("UPDATE sources SET available = 0 WHERE id = ?", [.integer(source.id)])
    }

    @discardableResult
    public func createAlbum(named name: String, mediaID: Int64? = nil) throws -> Int64 {
        try database.transaction {
            try database.execute("INSERT INTO albums (name) VALUES (?)", [.text(try validatedAlbumName(name))])
            let id = database.insertedID
            if let mediaID {
                try database.execute(
                    "INSERT INTO album_media (album_id, media_id, position) VALUES (?, ?, 0)",
                    [.integer(id), .integer(mediaID)]
                )
            }
            return id
        }
    }

    public func rename(albumID: Int64, to name: String) throws {
        try database.execute(
            "UPDATE albums SET name = ? WHERE id = ?",
            [.text(try validatedAlbumName(name)), .integer(albumID)]
        )
    }

    public func append(mediaIDs: [Int64], to albumID: Int64) throws {
        try database.transaction {
            let album = SQLiteValue.integer(albumID)
            let first = try database.select(
                "SELECT COALESCE(MAX(position) + 1, 0) FROM album_media WHERE album_id = ?", [album]
            ) { sqlite3_column_int64($0, 0) }.first!
            try database.repeated(
                "INSERT OR IGNORE INTO album_media (album_id, media_id, position) VALUES (?, ?, ?)",
                bindings: mediaIDs.enumerated().map { [album, .integer($1), .integer(first + Int64($0))] }
            )
        }
    }

    public func remove(mediaIDs: [Int64], from albumID: Int64) throws {
        try database.transaction {
            try database.repeated(
                "DELETE FROM album_media WHERE album_id = ? AND media_id = ?",
                bindings: mediaIDs.map { [.integer(albumID), .integer($0)] }
            )
        }
    }

    public func move(mediaID: Int64, in albumID: Int64, by delta: Int) throws {
        precondition([-1, 1].contains(delta))
        try database.transaction {
            let album = SQLiteValue.integer(albumID)
            var ids = try database.select(
                "SELECT media_id FROM album_media WHERE album_id = ? ORDER BY position, media_id", [album]
            ) { sqlite3_column_int64($0, 0) }
            guard let index = ids.firstIndex(of: mediaID), ids.indices.contains(index + delta) else { return }
            ids.swapAt(index, index + delta)
            try database.repeated(
                "UPDATE album_media SET position = ? WHERE album_id = ? AND media_id = ?",
                bindings: ids.enumerated().map { [.integer(Int64($0)), album, .integer($1)] }
            )
        }
    }

    private func replaceMedia(sourceID: Int64, entries: [ScanEntry]) throws {
        let source = SQLiteValue.integer(sourceID)
        try database.execute("UPDATE media SET available = 0 WHERE source_id = ?", [source])
        try database.repeated(
            "INSERT OR IGNORE INTO media (source_id, relative_path, kind) VALUES (?, ?, ?)",
            bindings: entries.map { [source, .text($0.relativePath), .text($0.kind.rawValue)] }
        )
        try database.repeated(
            "UPDATE media SET available = 1, kind = ? WHERE source_id = ? AND relative_path = ?",
            bindings: entries.map { [.text($0.kind.rawValue), source, .text($0.relativePath)] }
        )
    }

    private func validatedAlbumName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\0") else {
            throw SQLiteError(message: "请输入有效的专辑名称")
        }
        return trimmed
    }
}
