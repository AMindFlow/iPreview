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

    @ObservationIgnored private var cachedScope: (page: LibraryPage, value: ContentScope)?
    @ObservationIgnored private var inspectionVersion: Int64?
    private let dataDirectory: URL

    init() {
        if let testPath = ProcessInfo.processInfo.environment["IPREVIEW_DATA_DIR"], !testPath.isEmpty {
            dataDirectory = URL(fileURLWithPath: testPath, isDirectory: true)
        } else {
            dataDirectory = URL.applicationSupportDirectory.appendingPathComponent("iPreview", isDirectory: true)
        }
    }

    func contentScope(for page: LibraryPage, matches: [Media]?) -> ContentScope {
        let currentSnapshot = snapshot
        if let matches {
            return ContentScope(page: page, snapshot: currentSnapshot, matches: matches)
        }
        if let cachedScope, cachedScope.page == page {
            return cachedScope.value
        }
        let scope = ContentScope(page: page, snapshot: currentSnapshot, matches: nil)
        cachedScope = (page, scope)
        return scope
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
            if let notice = opened.renameRecoveryNotice {
                error = notice
            }
        } catch {
            catalog = nil
            self.error = error.localizedDescription
        }
    }

    func inspect(_ directory: URL) async {
        guard let catalog, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let dataDirectory = dataDirectory
            let version = try await catalog.scanVersion()
            let inspected = try await Task.detached(priority: .userInitiated) {
                try SourceScanner.inspect(directory, dataDirectory: dataDirectory)
            }.value
            inspectionVersion = version
            inspection = inspected
        } catch {
            self.error = error.localizedDescription
        }
    }

    func register(_ inspection: SourceInspection, candidate: ImportCandidate) async {
        self.inspection = nil
        guard let version = inspectionVersion else { return }
        inspectionVersion = nil
        await change { catalog in
            try await catalog.importSource(root: inspection.root, candidate: candidate, expectedVersion: version)
        }
    }

    func rescan(_ source: Source) async {
        await change { catalog in
            let version = try await catalog.scanVersion(for: source.id)
            do {
                let entries = try await Task.detached(priority: .userInitiated) {
                    try SourceScanner.rescan(source)
                }.value
                try await catalog.update(source: source, entries: entries, expectedVersion: version)
            } catch ScanError.inaccessibleRoot {
                try await catalog.markUnavailable(source: source, expectedVersion: version)
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

    func renameSourceItem(_ edit: SourceNameEdit, to name: String) async throws -> String {
        guard let catalog, !isWorking else { throw SourceRenameError.unavailable }
        isWorking = true
        defer { isWorking = false }
        let path = try await catalog.renameSourceItem(sourceID: edit.source.id, path: edit.path,
                                                      mediaID: edit.mediaID, to: name,
                                                      expectedFolderMemberID: edit.expectedFolderMemberID)
        try await refresh(catalog, rebuildSearch: true)
        return path
    }

    func add(mediaID: Int64, to albumID: Int64) async {
        await add(mediaIDs: [mediaID], to: albumID)
    }

    @discardableResult
    func add(mediaIDs: [Int64], to albumID: Int64) async -> Bool {
        await change(rebuildSearch: false) { catalog in
            try await catalog.append(mediaIDs: mediaIDs, to: albumID)
        }
    }

    func remove(mediaID: Int64, from albumID: Int64) async {
        await remove(mediaIDs: [mediaID], from: albumID)
    }

    @discardableResult
    func remove(mediaIDs: [Int64], from albumID: Int64) async -> Bool {
        await change(rebuildSearch: false) { catalog in
            try await catalog.remove(mediaIDs: mediaIDs, from: albumID)
        }
    }

    func move(mediaID: Int64, in albumID: Int64, by delta: Int) async {
        await change(rebuildSearch: false) { catalog in
            try await catalog.move(mediaID: mediaID, in: albumID, by: delta)
        }
    }

    @discardableResult
    private func change(rebuildSearch: Bool = true, _ action: (Catalog) async throws -> Void) async -> Bool {
        guard let catalog, !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            try await action(catalog)
            try await refresh(catalog, rebuildSearch: rebuildSearch)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    private func refresh(_ catalog: Catalog, rebuildSearch: Bool) async throws {
        let loaded = try await catalog.snapshot()
        if rebuildSearch {
            let media = loaded.media.filter(\.existsInSource)
            searchIndex = await Task.detached(priority: .userInitiated) { SearchIndex(media: media, sources: loaded.sources) }.value
            revision += 1
        }
        cachedScope = nil
        snapshot = loaded
    }
}
