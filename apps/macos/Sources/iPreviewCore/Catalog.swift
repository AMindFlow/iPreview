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
            guard (0...4).contains(version) else {
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
            if version < 3 {
                let organization = try Self.migrationURL(named: "003-album-organization", in: appBundle)
                try database.script(String(contentsOf: organization, encoding: .utf8))
            }
            if version < 4 {
                let videoWorks = try Self.migrationURL(named: "004-video-works", in: appBundle)
                try database.script(String(contentsOf: videoWorks, encoding: .utf8))
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
            let videoWorks = try VideoWorkIndex.read(from: database, media: media)
            return LibrarySnapshot(sources: sources, media: media, albums: albums, dataVersion: try scanVersion(),
                                   videoWorks: videoWorks)
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

    public func deleteSource(_ sourceID: Int64, expectedDataVersion: Int64) throws {
        try database.transaction {
            guard try scanVersion() == expectedDataVersion else { throw SourceDeletionChangedError() }
            try SourceRename(database: database).blockScan(sourceID: sourceID)
            let source = SQLiteValue.integer(sourceID)
            try database.execute("DELETE FROM source_album_organization WHERE source_id = ?", [source])
            try database.execute("""
                DELETE FROM album_media WHERE media_id IN (SELECT id FROM media WHERE source_id = ?)
                """, [source])
            try database.execute("DELETE FROM media WHERE source_id = ?", [source])
            try database.execute("DELETE FROM sources WHERE id = ?", [source])
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

    public func delete(albumID: Int64, expectedDataVersion: Int64) throws {
        try database.transaction {
            // A deleted SQLite row ID can be reused by a new album in another process.
            guard try scanVersion() == expectedDataVersion else { throw AlbumDeletionError.changed }
            try database.execute("DELETE FROM albums WHERE id = ?", [.integer(albumID)])
        }
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
        try VideoWorkIndex.replace(in: database, source: source, entries: entries)
    }

    private func validatedAlbumName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\0") else {
            throw SQLiteError(message: "请输入有效的合集名称")
        }
        return trimmed
    }
}

public struct SourceDeletionChangedError: LocalizedError {
    public var errorDescription: String? { "媒体库已在其他窗口更新。请核对媒体源后重试。" }
}

public enum AlbumDeletionError: LocalizedError {
    case changed

    public var errorDescription: String? { "媒体库已在其他窗口更新。请核对合集后重试。" }
}

extension Catalog {
    private static let albumMembers = """
        media.source_id = ?1
        AND substr(media.relative_path, 1, length(?2)) = ?2
        AND instr(substr(media.relative_path, length(?2) + 1), '/') = 0
        """

    public func albumTags() throws -> [SourceAlbumTag] {
        try database.select("SELECT id, name, normalized_name FROM tags ORDER BY normalized_name", row: Self.readTag)
    }

    public func sourceAlbumIndex() throws -> SourceAlbumIndex {
        try database.transaction(write: false) {
            let links = try database.select("""
                SELECT organization.source_id, organization.album_path, source_album_tags.tag_id
                FROM source_album_tags JOIN source_album_organization AS organization
                ON organization.id = source_album_tags.source_album_id
                """) { row in
                (key: SourceAlbumKey(sourceID: sqlite3_column_int64(row, 0), relativePath: textColumn(row, 1)),
                 id: sqlite3_column_int64(row, 2))
            }
            let covers = try database.select("""
                SELECT organization.source_id, organization.album_path, cover.media_id
                FROM source_album_cover_media AS cover JOIN source_album_organization AS organization
                ON organization.id = cover.source_album_id ORDER BY cover.position
                """) { row in
                (key: SourceAlbumKey(sourceID: sqlite3_column_int64(row, 0), relativePath: textColumn(row, 1)),
                 id: sqlite3_column_int64(row, 2))
            }
            return SourceAlbumIndex(tags: try albumTags(),
                                    taggedAlbums: Dictionary(grouping: links, by: \.id).mapValues { Set($0.map(\.key)) },
                                    configuredCovers: Dictionary(grouping: covers, by: \.key).mapValues { $0.map(\.id) })
        }
    }

    public func sourceAlbums(tagID: Int64) throws -> [SourceAlbumKey] {
        try database.select("""
            SELECT albums.source_id, albums.album_path FROM source_album_organization AS albums
            JOIN source_album_tags ON source_album_tags.source_album_id = albums.id
            WHERE source_album_tags.tag_id = ? ORDER BY albums.source_id, albums.album_path
            """, [.integer(tagID)]) {
            SourceAlbumKey(sourceID: sqlite3_column_int64($0, 0), relativePath: textColumn($0, 1))
        }
    }

    public func sourceAlbumOrganization(for album: SourceAlbumKey) throws -> SourceAlbumOrganization {
        let key = try albumBindings(album)
        return try database.transaction(write: false) {
            let stored = try database.select("""
                SELECT id, favorite, rating_half FROM source_album_organization WHERE source_id = ? AND album_path = ?
                """, key) { row in
                let rating = sqlite3_column_type(row, 2) == SQLITE_NULL ? nil : Int(sqlite3_column_int(row, 2))
                return (id: sqlite3_column_int64(row, 0), favorite: sqlite3_column_int(row, 1) == 1, rating: rating)
            }.first

            var tags: [SourceAlbumTag] = []
            var configured: [Int64] = []
            if let stored {
                let identifier = [SQLiteValue.integer(stored.id)]
                tags = try database.select("""
                    SELECT tags.id, tags.name, tags.normalized_name FROM tags
                    JOIN source_album_tags ON source_album_tags.tag_id = tags.id
                    WHERE source_album_tags.source_album_id = ? ORDER BY tags.normalized_name
                    """, identifier, row: Self.readTag)
                configured = try database.select("""
                    SELECT media_id FROM source_album_cover_media WHERE source_album_id = ? ORDER BY position
                    """, identifier) { sqlite3_column_int64($0, 0) }
            }

            let available = try availableAlbumImages(album)
            let effective = SourceAlbumIndex.coverIDs(configured: configured, available: available)
            return SourceAlbumOrganization(favorite: stored?.favorite ?? false, ratingHalf: stored?.rating,
                                           tags: tags, configuredCoverIDs: configured, effectiveCoverIDs: effective)
        }
    }

    public func setFavorite(_ favorite: Bool, for album: SourceAlbumKey) throws {
        try updateOrganization(album) { id in
            try database.execute("UPDATE source_album_organization SET favorite = ? WHERE id = ?",
                                 [.integer(favorite ? 1 : 0), .integer(id)])
        }
    }

    public func setRatingHalf(_ rating: Int?, for album: SourceAlbumKey) throws {
        if let rating, !(0...10).contains(rating) { throw AlbumOrganizationError.invalidRating }
        try updateOrganization(album) { id in
            try database.execute("UPDATE source_album_organization SET rating_half = ? WHERE id = ?",
                                 [rating.map { .integer(Int64($0)) } ?? .null, .integer(id)])
        }
    }

    @discardableResult
    public func addTag(named name: String, to album: SourceAlbumKey) throws -> SourceAlbumTag {
        let (display, normalized) = try Self.validatedTagNames(name)
        return try updateOrganization(album) { id in
            try database.execute("""
                INSERT INTO tags (name, normalized_name) VALUES (?, ?)
                ON CONFLICT (normalized_name) DO NOTHING
                """, [.text(display), .text(normalized)])
            let tag = try tag(named: normalized)!
            try appendTag(tag.id, toOrganization: id)
            return tag
        }
    }

    public func addTag(_ tagID: Int64, to album: SourceAlbumKey) throws {
        try updateOrganization(album) { id in
            try validateTag(tagID)
            try appendTag(tagID, toOrganization: id)
        }
    }

    public func removeTag(_ tagID: Int64, from album: SourceAlbumKey) throws {
        try database.execute("""
            DELETE FROM source_album_tags WHERE tag_id = ? AND source_album_id IN (
                SELECT id FROM source_album_organization WHERE source_id = ? AND album_path = ?
            )
            """, [.integer(tagID)] + albumBindings(album))
    }

    public func renameTag(_ tagID: Int64, to name: String) throws {
        let (display, normalized) = try Self.validatedTagNames(name)
        try database.transaction {
            try validateTag(tagID)
            if let other = try tag(named: normalized), other.id != tagID {
                throw AlbumOrganizationError.tagNameTaken
            }
            try database.execute("UPDATE tags SET name = ?, normalized_name = ? WHERE id = ?",
                                 [.text(display), .text(normalized), .integer(tagID)])
        }
    }

    public func deleteTag(_ tagID: Int64) throws {
        try database.execute("DELETE FROM tags WHERE id = ?", [.integer(tagID)])
    }

    public func replaceCover(_ mediaIDs: [Int64], for album: SourceAlbumKey) throws {
        let selection = Set(mediaIDs)
        guard mediaIDs.count <= 4, selection.count == mediaIDs.count else { throw AlbumOrganizationError.invalidCover }
        try updateOrganization(album) { id in
            if !mediaIDs.isEmpty {
                let availableIDs = try availableAlbumImages(album).map(\.id)
                guard selection.isSubset(of: availableIDs) else { throw AlbumOrganizationError.invalidCover }
            }
            let organization = SQLiteValue.integer(id)
            try database.execute("DELETE FROM source_album_cover_media WHERE source_album_id = ?", [organization])
            try database.repeated("INSERT INTO source_album_cover_media VALUES (?, ?, ?)",
                                  bindings: mediaIDs.enumerated().map { [organization, .integer($1), .integer(Int64($0))] })
        }
    }

    private func updateOrganization<Result>(_ album: SourceAlbumKey, _ update: (Int64) throws -> Result) throws -> Result {
        let key = try albumBindings(album)
        return try database.transaction {
            let indexed = try database.select("SELECT 1 FROM media WHERE \(Self.albumMembers) LIMIT 1",
                                              membershipBindings(album)) { _ in true }
            guard !indexed.isEmpty else { throw AlbumOrganizationError.unknownAlbum }
            try database.execute("""
                INSERT INTO source_album_organization (source_id, album_path) VALUES (?, ?)
                ON CONFLICT (source_id, album_path) DO NOTHING
                """, key)
            let id = try database.select("SELECT id FROM source_album_organization WHERE source_id = ? AND album_path = ?",
                                         key) { sqlite3_column_int64($0, 0) }.first!
            return try update(id)
        }
    }

    private func availableAlbumImages(_ album: SourceAlbumKey) throws -> [(id: Int64, path: String)] {
        try database.select("""
            SELECT media.id, media.relative_path FROM media JOIN sources ON sources.id = media.source_id
            WHERE \(Self.albumMembers) AND media.kind = 'image' AND media.available = 1 AND sources.available = 1
            """, membershipBindings(album)) {
            (id: sqlite3_column_int64($0, 0), path: textColumn($0, 1))
        }
    }

    private func albumBindings(_ album: SourceAlbumKey) throws -> [SQLiteValue] {
        guard !album.relativePath.contains("\0") else { throw AlbumOrganizationError.unknownAlbum }
        return [.integer(album.sourceID), .text(album.relativePath)]
    }

    private func membershipBindings(_ album: SourceAlbumKey) -> [SQLiteValue] {
        let prefix = album.relativePath.isEmpty ? "" : album.relativePath + "/"
        return [.integer(album.sourceID), .text(prefix)]
    }

    private static func readTag(_ row: OpaquePointer) -> SourceAlbumTag {
        SourceAlbumTag(id: sqlite3_column_int64(row, 0), name: textColumn(row, 1), normalizedName: textColumn(row, 2))
    }

    private func tag(named normalized: String) throws -> SourceAlbumTag? {
        try database.select("SELECT id, name, normalized_name FROM tags WHERE normalized_name = ?",
                            [.text(normalized)], row: Self.readTag).first
    }

    private func validateTag(_ tagID: Int64) throws {
        let found = try database.select("SELECT 1 FROM tags WHERE id = ?", [.integer(tagID)]) { _ in true }
        guard !found.isEmpty else { throw AlbumOrganizationError.unknownTag }
    }

    private func appendTag(_ tagID: Int64, toOrganization id: Int64) throws {
        try database.execute("""
            INSERT INTO source_album_tags (source_album_id, tag_id) VALUES (?, ?)
            ON CONFLICT (source_album_id, tag_id) DO NOTHING
            """, [.integer(id), .integer(tagID)])
    }

    private static func validatedTagNames(_ value: String) throws -> (display: String, normalized: String) {
        let (display, normalized) = SourceAlbumTag.names(from: value)
        guard !display.isEmpty, !display.contains("\0") else { throw AlbumOrganizationError.invalidTagName }
        return (display, normalized)
    }
}

public enum AlbumOrderError: LocalizedError {
    case changed

    public var errorDescription: String? {
        "合集内的顺序已在其他窗口更新。请按当前顺序重新拖动。"
    }
}
