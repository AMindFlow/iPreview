import Darwin
import Foundation
import SQLite3
import iPreviewCore

@main
struct CatalogChecks {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if !arguments.isEmpty {
            try verify(arguments.count == 2)
            let url = URL(fileURLWithPath: arguments[1], isDirectory: true)
            try verify(url.pathExtension == "app")
            let app = try required(Bundle(url: url))
            let fixtures = try Fixtures()
            switch arguments[0] {
            case "--check-packaged-migration":
                let catalog = try Catalog(directory: fixtures.databaseDirectory, appBundle: app)
                let id = try await catalog.createAlbum(named: "Package smoke")
                let snapshot = try await catalog.snapshot()
                try verify(snapshot.albums.first?.id == id)
                print("iPreview packaged migration check passed")
            case "--check-missing-migration":
                try expectError(CatalogResourceError.self) {
                    try Catalog(directory: fixtures.databaseDirectory, appBundle: app)
                }
                print("iPreview missing packaged migration error check passed")
            default:
                throw CheckFailure(location: "unknown check argument")
            }
            return
        }

        try checkLayouts()
        try await checkPersistence()
        try await checkOrderingAndBatchReferenceRemoval()
        try await checkSearch()
        try await checkSourceRename()
        try await checkReservedDirectoryName()
        try await checkStaleFolderAnchor()
        try await checkRenameRecovery()
        print("iPreview macOS catalog checks passed")
    }

    static func checkLayouts() throws {
        let fixtures = try Fixtures()
        let root = fixtures.directory("Creators")
        try fixtures.file("Creators/Existing/01.JPG")
        try fixtures.file("Creators/北京/旅行/10.png")
        try fixtures.file("Creators/北京/旅行/2.MOV")
        try fixtures.file("Creators/北京/旅行/nested/ignored.png")
        try fixtures.file("Creators/北京/旅行/.ignored.gif")
        try fixtures.file("Creators/北京/旅行/note.txt")
        try fixtures.file("outside.webp")
        try FileManager.default.createSymbolicLink(
            at: fixtures.directory("Creators/北京/旅行/link.webp"),
            withDestinationURL: fixtures.directory("outside.webp")
        )

        let inspection = try SourceScanner.inspect(root, dataDirectory: fixtures.databaseDirectory)
        try verify(inspection.candidates.map(\.layout) == [.creator, .multiCreator])
        try verify(inspection.candidates[0].entries.map(\.relativePath) == ["Existing/01.JPG"])
        try verify(Set(inspection.candidates[1].entries.map(\.relativePath)) == ["北京/旅行/10.png", "北京/旅行/2.MOV"])
        try verify(inspection.candidates[1].albumCount == 1)
    }

    static func checkPersistence() async throws {
        let fixtures = try Fixtures()
        let catalog = try Catalog(directory: fixtures.databaseDirectory)
        try fixtures.file("First/Album/10.png")
        try fixtures.file("First/Album/2.png")
        try fixtures.file("Second/01.MOV")

        for name in ["First", "Second"] {
            let inspection = try SourceScanner.inspect(fixtures.directory(name), dataDirectory: fixtures.databaseDirectory)
            try await catalog.importSource(root: inspection.root, candidate: try required(inspection.candidates.first))
        }

        let before = try await catalog.snapshot()
        try verify(before.media.map(\.name) == ["2.png", "10.png", "01.MOV"])
        let albumID = try await catalog.createAlbum(named: "混合精选")
        let memberIDs = [before.media[1].id, before.media[2].id]
        try await catalog.append(mediaIDs: memberIDs, to: albumID)
        try await catalog.append(mediaIDs: [memberIDs[0]], to: albumID)
        try await catalog.move(mediaID: memberIDs[0], in: albumID, by: 1)
        try await catalog.rename(albumID: albumID, to: "新名称")

        let reopened = try Catalog(directory: fixtures.databaseDirectory)
        let reopenedSnapshot = try await reopened.snapshot()
        try verify(reopenedSnapshot.albums.first?.name == "新名称")
        try verify(reopenedSnapshot.albums.first?.mediaIDs == Array(memberIDs.reversed()))

        let source = try required(reopenedSnapshot.sources.first)
        let offline = fixtures.directory("First-offline")
        try FileManager.default.moveItem(at: source.url, to: offline)
        try expectError(ScanError.self) { try SourceScanner.rescan(source) }
        try await reopened.markUnavailable(source: source)
        let unavailable = try await reopened.snapshot()
        try verify(unavailable.media.first?.isAvailable == false)
        try verify(unavailable.albums.first?.mediaIDs == Array(memberIDs.reversed()))

        try FileManager.default.moveItem(at: offline, to: source.url)
        try await reopened.update(source: source, entries: SourceScanner.rescan(source))
        let restored = try await reopened.snapshot()
        try verify(restored.media.allSatisfy(\.isAvailable))
        try verify(restored.media.map(\.id) == before.media.map(\.id))

        let replaced = try restored.media[1].readableURL()
        try FileManager.default.moveItem(at: replaced, to: fixtures.directory("Moved.png"))
        try FileManager.default.createSymbolicLink(at: replaced, withDestinationURL: fixtures.directory("Moved.png"))
        try expectError(FileError.self) { try restored.media[1].readableURL() }
        try await reopened.update(source: source, entries: SourceScanner.rescan(source))
        let missing = try await reopened.snapshot()
        try verify(missing.media[1].existsInSource == false)
        try verify(missing.albums.first?.mediaIDs == Array(memberIDs.reversed()))

        try await reopened.remove(mediaIDs: [memberIDs[0]], from: albumID)
        let removed = try await reopened.snapshot()
        try verify(removed.albums.first?.mediaIDs == [memberIDs[1]])
    }

    static func checkOrderingAndBatchReferenceRemoval() async throws {
        let fixtures = try Fixtures()
        for path in ["First/01.png", "First/02.png", "Second/03.mov", "Second/04.png"] {
            try fixtures.file(path)
        }
        let catalog = try Catalog(directory: fixtures.databaseDirectory)
        for name in ["First", "Second"] {
            let inspection = try SourceScanner.inspect(fixtures.directory(name), dataDirectory: fixtures.databaseDirectory)
            try await catalog.importSource(root: inspection.root, candidate: try required(inspection.candidates.first))
        }

        let before = try await catalog.snapshot()
        let mediaIDs = before.media.map(\.id)
        let selectedIDs = [mediaIDs[0], mediaIDs[2]]
        let order = [mediaIDs[3], mediaIDs[0], mediaIDs[1], mediaIDs[2]]
        let albumID = try await catalog.createAlbum(named: "Batch")
        let otherAlbumID = try await catalog.createAlbum(named: "Shared")
        try await catalog.append(mediaIDs: order, to: albumID)
        try await catalog.append(mediaIDs: selectedIDs, to: otherAlbumID)

        let paths = try before.media.map { try $0.readableURL() }
        let bytes = try paths.map { try Data(contentsOf: $0) }
        let times = try paths.map { try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }

        try await catalog.move(mediaID: mediaIDs[3], in: albumID, to: 2, expectedOrder: order)
        let reordered = try await catalog.snapshot()
        try verify(reordered.albums.first { $0.id == albumID }?.mediaIDs == [mediaIDs[0], mediaIDs[1], mediaIDs[3], mediaIDs[2]])
        let otherWindow = try Catalog(directory: fixtures.databaseDirectory)
        try await expectAsyncError(AlbumOrderError.self) {
            try await otherWindow.move(mediaID: mediaIDs[0], in: albumID, to: 0, expectedOrder: order)
        }

        try await catalog.remove(mediaIDs: selectedIDs, from: albumID)

        let reopened = try Catalog(directory: fixtures.databaseDirectory)
        let after = try await reopened.snapshot()
        try verify(after.albums.first { $0.id == albumID }?.mediaIDs == [mediaIDs[1], mediaIDs[3]])
        try verify(after.albums.first { $0.id == otherAlbumID }?.mediaIDs == selectedIDs)
        try verify(after.media == before.media)
        let afterBytes = try paths.map { try Data(contentsOf: $0) }
        let afterTimes = try paths.map { try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        try verify(afterBytes == bytes && afterTimes == times)
    }

    static func checkSourceRename() async throws {
        let fixtures = try Fixtures()
        try fixtures.file("Source/Artist/Album/Original.PNG")
        try fixtures.file("Source/Artist/Album/Offline.png")
        try fixtures.file("Source/Artist/Album2/Other.png")
        try fixtures.file("Source/Second Creator/Album/Second.png")
        let root = fixtures.directory("Source")
        let inspection = try SourceScanner.inspect(root, dataDirectory: fixtures.databaseDirectory)
        let initial = try Catalog(directory: fixtures.databaseDirectory)
        try await initial.importSource(root: inspection.root, candidate: try required(inspection.candidates.first))
        let before = try await initial.snapshot()
        let source = try required(before.sources.first)
        let original = try required(before.media.first { $0.name == "Original.PNG" })
        let offline = try required(before.media.first { $0.name == "Offline.png" })
        let other = try required(before.media.first { $0.name == "Other.png" })
        let secondCreatorItem = try required(before.media.first { $0.name == "Second.png" })
        let favourite = try await initial.createAlbum(named: "Pinned", mediaID: original.id)

        // Reopen a populated version 1 database and retain all IDs and virtual references.
        try fixtures.sql("DROP TABLE pending_rename; PRAGMA user_version = 1;")
        let catalog = try Catalog(directory: fixtures.databaseDirectory)
        let migrated = try await catalog.snapshot()
        try verify(migrated.media.map(\.id) == before.media.map(\.id))
        try verify(migrated.albums.first { $0.id == favourite }?.mediaIDs == [original.id])

        let originalURL = try original.readableURL()
        let bytes = try Data(contentsOf: originalURL)
        let originalModificationDate = try originalURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        try FileManager.default.moveItem(at: try offline.readableURL(), to: fixtures.directory("Unavailable.png"))
        try await catalog.update(source: source, entries: SourceScanner.rescan(source))
        try fixtures.file("Source/Artist/Album/Occupied.PNG")
        try await expectAsyncError(SourceRenameError.self) {
            try await catalog.renameSourceItem(sourceID: source.id, path: original.relativePath, mediaID: original.id, to: "Occupied")
        }
        // The unavailable row also reserves this basename regardless of extension case.
        try await expectAsyncError(SourceRenameError.self) {
            try await catalog.renameSourceItem(sourceID: source.id, path: original.relativePath, mediaID: original.id, to: "offline")
        }
        for target in ["", ".hidden", "../escape", "nested/name", "bad:name", "bad\\name", " NUL\0"] {
            try await expectAsyncError(SourceRenameError.self) {
                try await catalog.renameSourceItem(sourceID: source.id, path: original.relativePath, mediaID: original.id, to: target)
            }
        }

        // A failed SQLite write after moving must restore the original name and allow retry.
        try fixtures.sql("""
            CREATE TRIGGER reject_rename BEFORE UPDATE OF relative_path ON media
            BEGIN SELECT RAISE(ABORT, 'test index failure'); END;
            """)
        do {
            _ = try await catalog.renameSourceItem(sourceID: source.id, path: original.relativePath,
                                                   mediaID: original.id, to: "Rollback")
            throw CheckFailure(location: "rename must report index failure")
        } catch {
            try verify(error.localizedDescription.contains("test index failure"))
        }
        try verify(FileManager.default.fileExists(atPath: originalURL.path))
        try verify(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Artist/Album/Rollback.PNG").path))
        try fixtures.sql("DROP TRIGGER reject_rename")

        let staleVersion = try await catalog.scanVersion(for: source.id)
        let staleScan = try SourceScanner.rescan(source)
        let separate = try Catalog(directory: fixtures.databaseDirectory)
        let caseOnly = try await separate.renameSourceItem(sourceID: source.id, path: original.relativePath,
                                                          mediaID: original.id, to: "original")
        try await expectAsyncError(SourceRenameError.self) {
            try await catalog.update(source: source, entries: staleScan, expectedVersion: staleVersion)
        }
        try await expectAsyncError(SourceRenameError.self) {
            let staleCandidate = try required(inspection.candidates.first)
            try await catalog.importSource(root: inspection.root, candidate: staleCandidate, expectedVersion: staleVersion)
        }
        let composed = try await catalog.renameSourceItem(sourceID: source.id, path: caseOnly,
                                                         mediaID: original.id, to: "Café")
        let decomposedName = "Café".decomposedStringWithCanonicalMapping
        let decomposed = try await catalog.renameSourceItem(sourceID: source.id, path: composed,
                                                           mediaID: original.id, to: decomposedName)
        let spellings = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Artist/Album").path)
        try verify(spellings.contains { $0.utf8.elementsEqual((decomposedName + ".PNG").utf8) })
        let changedURL = root.appendingPathComponent(decomposed)
        let changedBytes = try Data(contentsOf: changedURL)
        let changedDate = try changedURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        try verify(changedBytes == bytes && changedDate == originalModificationDate)

        // Album and Album2 are distinct path components even though one name begins with the other.
        let nested = try SourceScanner.inspect(root.appendingPathComponent("Artist/Album2"), dataDirectory: fixtures.databaseDirectory)
        try await catalog.importSource(root: nested.root, candidate: try required(nested.candidates.first))
        let albumPath = try await catalog.renameSourceItem(sourceID: source.id, path: "Artist/Album",
                                                         mediaID: nil, to: "Renamed Album")
        try verify(albumPath == "Artist/Renamed Album")
        let creatorPath = try await catalog.renameSourceItem(sourceID: source.id, path: "Second Creator",
                                                           mediaID: nil, to: "New Creator")
        let after = try await catalog.snapshot()
        try verify(after.media.first { $0.id == original.id }?.relativePath == albumPath + "/" + decomposedName + ".PNG")
        try verify(after.media.first { $0.id == offline.id }?.relativePath == albumPath + "/Offline.png")
        try verify(after.media.first { $0.id == offline.id }?.isAvailable == false)
        try verify(after.media.first { $0.id == other.id }?.relativePath == "Artist/Album2/Other.png")
        try verify(after.media.first { $0.id == secondCreatorItem.id }?.relativePath == creatorPath + "/Album/Second.png")
        try verify(after.albums.first { $0.id == favourite }?.mediaIDs == [original.id])

        try await expectAsyncError(SourceRenameError.self) {
            try await catalog.renameSourceItem(sourceID: source.id, path: "Artist", mediaID: nil, to: "Blocked")
        }
        let movedFolder = fixtures.directory("Redirected")
        let renamedFolder = root.appendingPathComponent(albumPath)
        try FileManager.default.moveItem(at: renamedFolder, to: movedFolder)
        try FileManager.default.createSymbolicLink(at: renamedFolder, withDestinationURL: movedFolder)
        try await expectAsyncError(SourceRenameError.self) {
            try await catalog.renameSourceItem(sourceID: source.id, path: albumPath + "/" + decomposedName + ".PNG",
                                               mediaID: original.id, to: "Blocked")
        }
        try verify(FileManager.default.fileExists(atPath: movedFolder.appendingPathComponent(decomposedName + ".PNG").path))
        try verify(!FileManager.default.fileExists(atPath: movedFolder.appendingPathComponent("Blocked.PNG").path))
    }

    static func checkReservedDirectoryName() async throws {
        let fixtures = try Fixtures()
        try fixtures.file("Source/Future.PNG/Archived.jpg")
        try fixtures.file("Source/Direct.PNG")
        let root = fixtures.directory("Source")
        let catalog = try Catalog(directory: fixtures.databaseDirectory)
        let withAlbum = try SourceScanner.inspect(root, dataDirectory: fixtures.databaseDirectory)
        try await catalog.importSource(root: withAlbum.root, candidate: try required(withAlbum.candidates.first))
        try FileManager.default.moveItem(at: root.appendingPathComponent("Future.PNG"), to: fixtures.directory("Outside"))
        let flat = try SourceScanner.inspect(root, dataDirectory: fixtures.databaseDirectory)
        try await catalog.importSource(root: flat.root, candidate: try required(flat.candidates.first))
        let snapshot = try await catalog.snapshot()
        let media = try required(snapshot.media.first { $0.relativePath == "Direct.PNG" })
        try await expectAsyncError(SourceRenameError.self) {
            try await catalog.renameSourceItem(sourceID: media.source.id, path: media.relativePath,
                                               mediaID: media.id, to: "Future")
        }
        try verify(FileManager.default.fileExists(atPath: root.appendingPathComponent("Direct.PNG").path))
    }

    static func checkStaleFolderAnchor() async throws {
        let fixtures = try Fixtures()
        try fixtures.file("Source/Album/Original.PNG")
        let root = fixtures.directory("Source")
        let firstWindow = try Catalog(directory: fixtures.databaseDirectory)
        let inspection = try SourceScanner.inspect(root, dataDirectory: fixtures.databaseDirectory)
        try await firstWindow.importSource(root: inspection.root, candidate: try required(inspection.candidates.first))
        let initial = try await firstWindow.snapshot()
        let original = try required(initial.media.first)

        let secondWindow = try Catalog(directory: fixtures.databaseDirectory)
        _ = try await secondWindow.renameSourceItem(sourceID: original.source.id, path: "Album", mediaID: nil, to: "Moved")
        try fixtures.file("Source/Album/Replacement.PNG")
        try await secondWindow.update(source: original.source, entries: SourceScanner.rescan(original.source))
        try await expectAsyncError(SourceRenameError.self) {
            try await firstWindow.renameSourceItem(sourceID: original.source.id, path: "Album", mediaID: nil, to: "Wrong",
                                                   expectedFolderMemberID: original.id)
        }
        try verify(FileManager.default.fileExists(atPath: root.appendingPathComponent("Album/Replacement.PNG").path))
        try verify(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Wrong").path))
    }

    static func checkRenameRecovery() async throws {
        let fixtures = try Fixtures()
        try fixtures.file("Source/Before.PNG")
        let inspection = try SourceScanner.inspect(fixtures.directory("Source"), dataDirectory: fixtures.databaseDirectory)
        let first = try Catalog(directory: fixtures.databaseDirectory)
        try await first.importSource(root: inspection.root, candidate: try required(inspection.candidates.first))
        let before = try await first.snapshot()
        let item = try required(before.media.first)
        let original = try item.readableURL()
        let identity = try renameFixtureIdentity(original)
        let moved = inspection.root.appendingPathComponent("After.PNG")

        try fixtures.sql("""
            INSERT INTO pending_rename VALUES (1, \(item.source.id), 'Before.PNG', 'After.PNG', 0, '\(identity)');
            """)
        let unchanged = try Catalog(directory: fixtures.databaseDirectory)
        try verify(unchanged.renameRecoveryNotice == nil)
        let unchangedSnapshot = try await unchanged.snapshot()
        try verify(unchangedSnapshot.media.first?.name == "Before.PNG")

        try fixtures.sql("""
            INSERT INTO pending_rename VALUES (1, \(item.source.id), 'Before.PNG', 'After.PNG', 0, '\(identity)');
            """)
        try FileManager.default.moveItem(at: original, to: moved)
        let recovered = try Catalog(directory: fixtures.databaseDirectory)
        try verify(recovered.renameRecoveryNotice == nil)
        let recoveredSnapshot = try await recovered.snapshot()
        try verify(recoveredSnapshot.media.first?.name == "After.PNG" && recoveredSnapshot.media.first?.id == item.id)

        try fixtures.sql("""
            INSERT INTO pending_rename VALUES (1, \(item.source.id), 'After.PNG', 'Unknown.PNG', 0, '\(identity)');
            """)
        try FileManager.default.moveItem(at: moved, to: inspection.root.appendingPathComponent("Third.PNG"))
        let uncertain = try Catalog(directory: fixtures.databaseDirectory)
        let notice = try required(uncertain.renameRecoveryNotice)
        try verify(notice.contains(inspection.root.path) && notice.contains("After.PNG") && notice.contains("Unknown.PNG"))
        try await expectAsyncError(SourceRenameError.self) {
            try await uncertain.update(source: item.source, entries: SourceScanner.rescan(item.source))
        }
        let uncertainSnapshot = try await uncertain.snapshot()
        try verify(uncertainSnapshot.media.first?.name == "After.PNG" && uncertainSnapshot.media.first?.id == item.id)
        try verify(FileManager.default.fileExists(atPath: inspection.root.appendingPathComponent("Third.PNG").path))
    }

    static func checkSearch() async throws {
        let fixtures = try Fixtures()
        try fixtures.file("Library/北京/旅行.PNG")
        try fixtures.file("Library/Summer Library/2.png")
        try fixtures.file("Library/Summer Library/10.png")
        try fixtures.file("Elsewhere/2.png")
        try fixtures.file("Elsewhere/Frame.v2.jpg")
        let catalog = try Catalog(directory: fixtures.databaseDirectory)
        let inspection = try SourceScanner.inspect(fixtures.directory("Library"), dataDirectory: fixtures.databaseDirectory)
        try await catalog.importSource(root: inspection.root, candidate: try required(inspection.candidates.first))
        let elsewhere = try SourceScanner.inspect(fixtures.directory("Elsewhere"), dataDirectory: fixtures.databaseDirectory)
        try await catalog.importSource(root: elsewhere.root, candidate: try required(elsewhere.candidates.first))
        let snapshot = try await catalog.snapshot()
        let index = SearchIndex(media: snapshot.media, sources: snapshot.sources)

        try verify(index.search("旅行.ＰＮＧ", mode: .exact, directories: false, files: true).map(\.name) == ["旅行.PNG"])
        try verify(index.search("旅行", mode: .exact, directories: false, files: true).map(\.name) == ["旅行.PNG"])
        try verify(index.search("旅行.jpg", mode: .exact, directories: false, files: true).isEmpty)
        try verify(index.search("旅行.pn", mode: .exact, directories: false, files: true).isEmpty)
        try verify(index.search("beijing", mode: .fuzzy, directories: true, files: false).map(\.name) == ["旅行.PNG"])
        try verify(index.search("bj", mode: .fuzzy, directories: true, files: false).map(\.name) == ["旅行.PNG"])
        try verify(index.search("beijing", mode: .fuzzy, directories: false, files: true).isEmpty)
        try verify(index.search("lvxing", mode: .fuzzy, directories: false, files: true).map(\.name) == ["旅行.PNG"])
        try verify(index.search("sumer", mode: .fuzzy, directories: true, files: false).map(\.name) == ["2.png", "10.png"])
        try verify(index.search("北京", mode: .exact, directories: false, files: false).isEmpty)

        let local = index.search("2.png", mode: .exact, directories: false, files: true) { $0.source.name == "Library" }
        try verify(local.map(\.directories) == [["Library", "Summer Library"]])
        let barePrefix = GlobalSearchTerm("@")
        try verify(barePrefix.mode == .fuzzy && barePrefix.text == "@")
        let joinedPrefix = GlobalSearchTerm("@2.png")
        try verify(joinedPrefix.mode == .fuzzy && joinedPrefix.text == "@2.png")
        let pendingExact = GlobalSearchTerm("@ ")
        try verify(pendingExact.mode == .exact && pendingExact.text.isEmpty)
        let exactTerm = GlobalSearchTerm("  ＠　2.png ")
        let globalFiles = index.globalSearch(exactTerm.text, mode: exactTerm.mode, directories: false, files: true).compactMap { hit -> Media? in
            if case .file(let item) = hit { item } else { nil }
        }
        try verify(Set(globalFiles.map { $0.source.name }) == ["Library", "Elsewhere"])
        try verify(index.globalSearch("2", mode: .exact, directories: false, files: true).count == 2)
        try verify(index.globalSearch("2.jpg", mode: .exact, directories: false, files: true).isEmpty)
        try verify(index.globalSearch("frame.v2", mode: .exact, directories: false, files: true).count == 1)
        try verify(index.globalSearch("frame.v2.png", mode: .exact, directories: false, files: true).isEmpty)
        try verify(index.globalSearch("Summer", mode: .exact, directories: true, files: false).isEmpty)
        let globalFolders = index.globalSearch("sumer", mode: .fuzzy, directories: true, files: false)
        try verify(globalFolders.count == 1)
        guard case .directory(let directory) = globalFolders[0] else {
            throw CheckFailure(location: "global search must return the matching directory")
        }
        try verify(directory.components == ["Library", "Summer Library"])
    }
}

private struct Fixtures {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("iPreview-tests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    var databaseDirectory: URL { directory("Data") }

    func directory(_ path: String) -> URL { root.appendingPathComponent(path) }

    func sql(_ command: String) throws {
        let path = databaseDirectory.appendingPathComponent("catalog.sqlite3").path
        var db: OpaquePointer?
        let opened = sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE, nil)
        defer { sqlite3_close(db) }
        try verify(opened == SQLITE_OK)
        try verify(sqlite3_exec(db, command, nil, nil, nil) == SQLITE_OK)
    }

    func file(_ path: String) throws {
        let url = directory(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: url)
    }
}

private struct CheckFailure: LocalizedError {
    let location: String

    var errorDescription: String? { "Catalog check failed at \(location)" }
}

private func verify(_ condition: @autoclosure () -> Bool, line: UInt = #line) throws {
    guard condition() else { throw CheckFailure(location: "line \(line)") }
}

private func required<T>(_ value: T?, line: UInt = #line) throws -> T {
    guard let value else { throw CheckFailure(location: "line \(line)") }
    return value
}

private func expectError<T, Failure: Error>(
    _ type: Failure.Type,
    line: UInt = #line,
    operation: () throws -> T
) throws {
    do {
        _ = try operation()
    } catch is Failure {
        return
    }
    throw CheckFailure(location: "line \(line)")
}

private func expectAsyncError<T, Failure: Error>(
    _ type: Failure.Type,
    line: UInt = #line,
    operation: () async throws -> T
) async throws {
    do {
        _ = try await operation()
    } catch is Failure {
        return
    }
    throw CheckFailure(location: "line \(line)")
}

private func renameFixtureIdentity(_ url: URL) throws -> String {
    let volumeName = try url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
    let volume = try required(volumeName.flatMap(UUID.init(uuidString:)))
    let volumeKey = withUnsafeBytes(of: volume.uuid) { Data($0).base64EncodedString() }
    var entry = stat()
    try verify(lstat(url.path, &entry) == 0)
    return "\(volumeKey):\(entry.st_ino):\(entry.st_birthtimespec.tv_sec):\(entry.st_birthtimespec.tv_nsec)"
}
