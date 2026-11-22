import Foundation
import SQLite3

public enum CatalogResourceError: LocalizedError {
    case missingMigration

    public var errorDescription: String? {
        "缺少媒体库数据库迁移资源。请重新解压完整的 iPreview 应用包。"
    }
}

public actor Catalog {
    private let database: Database
    public nonisolated let renameRecoveryNotice: String?

    public init(directory: URL, appBundle: Bundle = .main) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try Database(url: directory.appendingPathComponent("catalog.sqlite3"))
        try database.script("PRAGMA foreign_keys = ON")
        try database.transaction {
            let version = try database.select("PRAGMA user_version") { sqlite3_column_int($0, 0) }.first!
            guard (0...2).contains(version) else {
                throw SQLiteError(message: "数据库版本 \(version) 需要更新版本的 iPreview")
            }
            if version == 0 {
                let initial = try Self.migrationURL(named: "001-initial", in: appBundle)
                try database.script(String(contentsOf: initial, encoding: .utf8))
            }
            if version < 2 {
                let rename = try Self.migrationURL(named: "002-pending-rename", in: appBundle)
                try database.script(String(contentsOf: rename, encoding: .utf8))
            }
        }
        self.database = database
        let rename = SourceRename(database: database)
        do {
            try rename.recover()
            renameRecoveryNotice = nil
        } catch {
            renameRecoveryNotice = try rename.recoveryNotice() ?? error.localizedDescription
        }
    }

    private static func migrationURL(named name: String, in appBundle: Bundle) throws -> URL {
        let resources: Bundle
        if appBundle.bundleURL.pathExtension.lowercased() == "app" {
            // The release script installs SwiftPM's resource bundle in Contents/Resources.
            guard let directory = appBundle.resourceURL,
                  let bundledResources = Bundle(url: directory.appendingPathComponent("iPreview_iPreviewCore.bundle")) else {
                throw CatalogResourceError.missingMigration
            }
            resources = bundledResources
        } else {
            resources = Bundle.module
        }
        guard let migration = resources.url(forResource: name, withExtension: "sql", subdirectory: "migrations") else {
            throw CatalogResourceError.missingMigration
        }
        return migration
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

    public func scanVersion(for sourceID: Int64? = nil) throws -> Int64 {
        if let sourceID {
            try SourceRename(database: database).blockScan(sourceID: sourceID)
        }
        return try database.select("PRAGMA data_version") { sqlite3_column_int64($0, 0) }.first!
    }

    private func validateScan(_ expectedVersion: Int64?) throws {
        if let expectedVersion, try scanVersion() != expectedVersion { throw SourceRenameError.staleScan }
    }

    public func importSource(root: URL, candidate: ImportCandidate, expectedVersion: Int64? = nil) throws {
        try database.transaction {
            try validateScan(expectedVersion)
            try SourceRename(database: database).blockImport(path: root.path)
            let path = SQLiteValue.text(root.path)
            let layout = SQLiteValue.text(candidate.layout.rawValue)
            try database.execute("INSERT OR IGNORE INTO sources (path, layout) VALUES (?, ?)", [path, layout])
            let id = try database.select("SELECT id FROM sources WHERE path = ?", [path]) { sqlite3_column_int64($0, 0) }.first!
            try database.execute("UPDATE sources SET layout = ?, available = 1 WHERE id = ?", [layout, .integer(id)])
            try replaceMedia(sourceID: id, entries: candidate.entries)
        }
    }

    public func update(source: Source, entries: [ScanEntry], expectedVersion: Int64? = nil) throws {
        try database.transaction {
            try validateScan(expectedVersion)
            try SourceRename(database: database).blockScan(sourceID: source.id)
            try database.execute("UPDATE sources SET available = 1 WHERE id = ?", [.integer(source.id)])
            try replaceMedia(sourceID: source.id, entries: entries)
        }
    }

    public func markUnavailable(source: Source, expectedVersion: Int64? = nil) throws {
        try database.transaction {
            try validateScan(expectedVersion)
            try database.execute("UPDATE sources SET available = 0 WHERE id = ?", [.integer(source.id)])
        }
    }

    public func renameSourceItem(sourceID: Int64, path: String, mediaID: Int64?, to name: String,
                                 expectedFolderMemberID: Int64? = nil) throws -> String {
        try SourceRename(database: database).rename(sourceID: sourceID, path: path, mediaID: mediaID, to: name,
                                                    expectedFolderMemberID: expectedFolderMemberID)
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
        try updateOrder(in: albumID) { ids in
            guard let index = ids.firstIndex(of: mediaID), ids.indices.contains(index + delta) else { return }
            ids.swapAt(index, index + delta)
        }
    }

    public func move(mediaID: Int64, in albumID: Int64, to targetIndex: Int, expectedOrder: [Int64]) throws {
        try updateOrder(in: albumID) { ids in
            guard ids == expectedOrder else {
                throw AlbumOrderError.changed
            }
            guard let index = ids.firstIndex(of: mediaID), ids.indices.contains(targetIndex) else { return }
            ids.insert(ids.remove(at: index), at: targetIndex)
        }
    }

    private func updateOrder(in albumID: Int64, change: (inout [Int64]) throws -> Void) throws {
        try database.transaction {
            let album = SQLiteValue.integer(albumID)
            let original = try database.select(
                "SELECT media_id FROM album_media WHERE album_id = ? ORDER BY position, media_id", [album]
            ) { sqlite3_column_int64($0, 0) }
            var ids = original
            try change(&ids)
            guard ids != original else { return }
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
            throw SQLiteError(message: "请输入有效的合集名称")
        }
        return trimmed
    }
}

public enum AlbumOrderError: LocalizedError {
    case changed

    public var errorDescription: String? {
        "合集内的顺序已在其他窗口更新。请按当前顺序重新拖动。"
    }
}
