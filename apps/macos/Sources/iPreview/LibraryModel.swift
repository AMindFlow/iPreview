import Foundation
import Observation
import iPreviewCore

@MainActor
@Observable
final class LibraryModel {
    private var catalog: Catalog?
    private(set) var isWorking = false
    private(set) var snapshot = LibrarySnapshot.empty
    private(set) var searchIndex = SearchIndex(media: [])
    private(set) var revision = 0
    var error: String?
    var inspection: SourceInspection?

    private let dataDirectory: URL

    init() {
        if let testPath = ProcessInfo.processInfo.environment["IPREVIEW_DATA_DIR"], !testPath.isEmpty {
            dataDirectory = URL(fileURLWithPath: testPath, isDirectory: true)
        } else {
            dataDirectory = URL.applicationSupportDirectory.appendingPathComponent("iPreview", isDirectory: true)
        }
    }

    func start() async {
        guard catalog == nil, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let directory = dataDirectory
            let opened = try await Task.detached(priority: .userInitiated) {
                try Catalog(directory: directory)
            }.value
            catalog = opened
            for source in try await opened.snapshot().sources where source.isAvailable {
                let available = await Task.detached { SourceScanner.isRootAvailable(source) }.value
                if !available {
                    try await opened.markUnavailable(source: source)
                }
            }
            try await refresh(opened, rebuildSearch: true)
        } catch {
            catalog = nil
            self.error = error.localizedDescription
        }
    }

    func inspect(_ directory: URL) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let dataDirectory = dataDirectory
            inspection = try await Task.detached(priority: .userInitiated) {
                try SourceScanner.inspect(directory, dataDirectory: dataDirectory)
            }.value
        } catch {
            self.error = error.localizedDescription
        }
    }

    func register(_ inspection: SourceInspection, candidate: ImportCandidate) async {
        self.inspection = nil
        await change { catalog in
            try await catalog.importSource(root: inspection.root, candidate: candidate)
        }
    }

    func rescan(_ source: Source) async {
        await change { catalog in
            do {
                let entries = try await Task.detached(priority: .userInitiated) {
                    try SourceScanner.rescan(source)
                }.value
                try await catalog.update(source: source, entries: entries)
            } catch ScanError.inaccessibleRoot {
                try await catalog.markUnavailable(source: source)
            }
        }
    }

    func createAlbum(named name: String, with mediaID: Int64?) async -> Int64? {
        var created: Int64?
        await change(rebuildSearch: false) { catalog in
            let id = try await catalog.createAlbum(named: name, mediaID: mediaID)
            created = id
        }
        return created
    }

    func rename(albumID: Int64, to name: String) async {
        await change(rebuildSearch: false) { catalog in
            try await catalog.rename(albumID: albumID, to: name)
        }
    }

    func add(mediaID: Int64, to albumID: Int64) async {
        await change(rebuildSearch: false) { catalog in
            try await catalog.append(mediaIDs: [mediaID], to: albumID)
        }
    }

    func remove(mediaID: Int64, from albumID: Int64) async {
        await change(rebuildSearch: false) { catalog in
            try await catalog.remove(mediaIDs: [mediaID], from: albumID)
        }
    }

    func move(mediaID: Int64, in albumID: Int64, by delta: Int) async {
        await change(rebuildSearch: false) { catalog in
            try await catalog.move(mediaID: mediaID, in: albumID, by: delta)
        }
    }

    private func change(rebuildSearch: Bool = true, _ action: (Catalog) async throws -> Void) async {
        guard let catalog, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await action(catalog)
            try await refresh(catalog, rebuildSearch: rebuildSearch)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func refresh(_ catalog: Catalog, rebuildSearch: Bool) async throws {
        let loaded = try await catalog.snapshot()
        if rebuildSearch {
            let media = loaded.media.filter(\.existsInSource)
            searchIndex = await Task.detached(priority: .userInitiated) { SearchIndex(media: media) }.value
            revision += 1
        }
        snapshot = loaded
    }
}
