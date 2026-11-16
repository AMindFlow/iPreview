import Foundation
import iPreviewCore

@main
struct CatalogChecks {
    static func main() async throws {
        try checkLayouts()
        try await checkPersistence()
        try await checkSearch()
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

    static func checkSearch() async throws {
        let fixtures = try Fixtures()
        try fixtures.file("Library/北京/旅行.PNG")
        try fixtures.file("Library/Summer Library/2.png")
        try fixtures.file("Library/Summer Library/10.png")
        let catalog = try Catalog(directory: fixtures.databaseDirectory)
        let inspection = try SourceScanner.inspect(fixtures.directory("Library"), dataDirectory: fixtures.databaseDirectory)
        try await catalog.importSource(root: inspection.root, candidate: try required(inspection.candidates.first))
        let index = SearchIndex(media: try await catalog.snapshot().media)

        try verify(index.search("旅行.ＰＮＧ", mode: .exact, directories: false, files: true).map(\.name) == ["旅行.PNG"])
        try verify(index.search("旅行", mode: .exact, directories: false, files: true).isEmpty)
        try verify(index.search("beijing", mode: .fuzzy, directories: true, files: false).map(\.name) == ["旅行.PNG"])
        try verify(index.search("bj", mode: .fuzzy, directories: true, files: false).map(\.name) == ["旅行.PNG"])
        try verify(index.search("beijing", mode: .fuzzy, directories: false, files: true).isEmpty)
        try verify(index.search("lvxing", mode: .fuzzy, directories: false, files: true).map(\.name) == ["旅行.PNG"])
        try verify(index.search("sumer", mode: .fuzzy, directories: true, files: false).map(\.name) == ["2.png", "10.png"])
        try verify(index.search("北京", mode: .exact, directories: false, files: false).isEmpty)
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
