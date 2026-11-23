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
        try await checkMediaSort()
        try checkVideoWorks()
        try await checkVideoWorkIndex()
        try await checkLegacyVideoWorkRescan()
        try await checkLegacyWorkAlbumOrganization()
        try await checkVideoFormats()
        try await checkPersistence()
        try await checkSourceAlbumOrganization()
        try await checkOrderingAndBatchReferenceRemoval()
        try await checkAlbumDeletion()
        try await checkSourceDeletion()
        try await checkSearch()
        try await checkSourceRename()
        try await checkReservedDirectoryName()
        try await checkStaleFolderAnchor()
        try await checkRenameRecovery()
        print("iPreview macOS catalog checks passed")
    }

    static func checkLegacyVideoWorkRescan() async throws {
        let fixtures = try Fixtures()
        let catalog = try Catalog(directory: fixtures.databaseDirectory)
        let cases: [(directory: String, layout: Layout, work: String, previous: [String], added: String)] = [
            ("Legacy Multi", .multiCreator, "Work", [
                "Work/视频/movie.mp4", "Work/视频/幕后.jpg", "Work/官方样张/sample.jpg",
                "Work/附加写真集/写真集/图片.png", "Maker/Album/keep.png",
            ], "Work/附加写真集/写真集/封面.png"),
            ("Legacy Creator", .creator, "", [
                "视频/movie.mp4", "视频/幕后.jpg", "官方样张/sample.jpg", "附加写真集/写真集/图片.png",
            ], "附加写真集/写真集/封面.png"),
            ("Legacy Flat", .flat, "", [
                "movie.mp4", "官方样张.jpg", "keep.png",
            ], "附加写真集/图片.png"),
        ]

        for test in cases {
            let root = fixtures.directory(test.directory)
            for path in test.previous { try fixtures.file(test.directory + "/" + path) }
            let inspection = try SourceScanner.inspect(root, dataDirectory: fixtures.databaseDirectory)
            let candidate = try required(inspection.candidates.first { $0.layout == test.layout })
            try await catalog.importSource(root: inspection.root, candidate: candidate)
            let before = try await catalog.snapshot()
            let source = try required(before.sources.first { $0.path == inspection.root.path })
            let original = before.media.filter { $0.source.id == source.id }
            try verify(original.contains { $0.name == "movie.mp4" })
            try verify(!before.videoWorks.contains { $0.video.source.id == source.id })

            try fixtures.file(test.directory + "/" + test.added)
            try await catalog.update(source: source, entries: SourceScanner.rescan(source))
            let rescanned = try await catalog.snapshot()
            let result = try required(rescanned.videoWorks.first { $0.video.source.id == source.id })
            try verify(result.relativePath == test.work && result.video.source.layout == test.layout)
            try verify(result.samples.count == 1 && result.photoSets.first?.photos.count == 1)
            let available = Dictionary(uniqueKeysWithValues: rescanned.media.filter {
                $0.source.id == source.id && $0.existsInSource
            }.map { ($0.relativePath, $0.id) })
            try verify(original.allSatisfy { available[$0.relativePath] == $0.id })
        }
    }

    static func checkVideoWorkIndex() async throws {
        let fixtures = try Fixtures()
        let complete = "Works/Maker/Complete"
        let compact = "Compact"
        for file in ["视频/影片.mp4", "官方样张/样张.jpg", "附加写真集/图册 2/封面.jpg", "附加写真集/图册 2/照片 1.jpg"] {
            try fixtures.file(complete + "/" + file)
        }
        for file in ["影片.mov", "官方样张.jpg", "附加写真集/照片 2.png"] {
            try fixtures.file(compact + "/" + file)
        }
        let catalog = try Catalog(directory: fixtures.databaseDirectory)
        for (path, layout) in [("Works", Layout.multiCreator), (compact, .flat)] {
            let inspection = try SourceScanner.inspect(fixtures.directory(path), dataDirectory: fixtures.databaseDirectory)
            try verify(inspection.candidates.map(\.layout) == [layout])
            let candidate = try required(inspection.candidates.first)
            try verify(candidate.videoWorkCount == 1 && candidate.albumCount == 1)
            try await catalog.importSource(root: inspection.root, candidate: candidate)
        }
        let reopened = try Catalog(directory: fixtures.databaseDirectory)
        let initial = try await reopened.snapshot()
        let work = try required(initial.videoWorks.first { $0.structure == .complete })
        let flat = try required(initial.videoWorks.first { $0.structure == .compact })
        try verify(work.relativePath == "Maker/Complete" && work.samples.map(\.name) == ["样张.jpg"])
        try verify(work.photoSets.first?.cover?.name == "封面.jpg")
        try verify(flat.relativePath.isEmpty && flat.photoSets.first?.cover == nil)

        let completeAlbum = SourceAlbumKey(media: work.video)
        let compactAlbum = SourceAlbumKey(media: flat.video)
        let completeCover = [work.samples[0].id, work.photoSets[0].photos[0].id]
        let compactCover = [flat.photoSets[0].photos[0].id]
        let worksTag = try await reopened.addTag(named: "作品", to: completeAlbum)
        try await reopened.addTag(worksTag.id, to: compactAlbum)
        try await reopened.replaceCover(completeCover, for: completeAlbum)
        try await reopened.replaceCover(compactCover, for: compactAlbum)
        let completeSettings = try await reopened.sourceAlbumOrganization(for: completeAlbum)
        let compactSettings = try await reopened.sourceAlbumOrganization(for: compactAlbum)
        try verify(completeSettings.effectiveCoverIDs == completeCover && compactSettings.effectiveCoverIDs == compactCover)
        try verify(completeSettings.tags == [worksTag] && compactSettings.tags == [worksTag])

        let tagged = try await reopened.sourceAlbumIndex().taggedAlbums[worksTag.id]
        let index = SearchIndex(media: initial.media, sources: initial.sources)
        let taggedPhotos = index.globalSearch("照片", mode: .fuzzy, directories: false, files: true, taggedAlbums: tagged)
        try verify(Set(taggedPhotos.compactMap(\.sourceAlbum)) == [completeAlbum, compactAlbum])
        try verify(taggedPhotos.count == 2)
        let intermediate = SourceAlbumKey(sourceID: work.video.source.id, relativePath: work.relativePath + "/官方样张")
        try await expectAsyncError(AlbumOrganizationError.self) {
            try await reopened.setFavorite(true, for: intermediate)
        }

        try await reopened.markUnavailable(source: work.video.source)
        let offline = try await reopened.snapshot()
        try verify(offline.videoWorks.first { $0.id == work.id }?.video.isAvailable == false)
        try fixtures.file(complete + "/附加写真集/图册 2/照片 2.jpg")
        let scanned = try SourceScanner.rescan(work.video.source)
        try await reopened.update(source: work.video.source, entries: scanned)
        let rescanned = try await reopened.snapshot()
        let updated = try required(rescanned.videoWorks.first { $0.id == work.id })
        try verify(updated.video.isAvailable && updated.photoSets[0].photos.map(\.name) == ["照片 1.jpg", "照片 2.jpg"])
        for file in scanned {
            let contents = try Data(contentsOf: work.video.source.url.appendingPathComponent(file.relativePath))
            try verify(contents == Data("fixture".utf8))
        }
    }

    static func checkLegacyWorkAlbumOrganization() async throws {
        let fixtures = try Fixtures()
        for path in ["Complete/视频/影片.mp4", "Complete/官方样张/样张.jpg", "Complete/附加写真集/写真/封面.jpg",
                     "Complete/附加写真集/写真/完整照片.jpg", "Compact/影片.mov", "Compact/官方样张.jpg",
                     "Compact/附加写真集/简化照片.jpg"] {
            try fixtures.file("Legacy/" + path)
        }
        let inspection = try SourceScanner.inspect(fixtures.directory("Legacy"), dataDirectory: fixtures.databaseDirectory)
        let shallowWorks = try required(inspection.candidates.first { $0.layout == .creator })
        let catalog = try Catalog(directory: fixtures.databaseDirectory)
        try await catalog.importSource(root: inspection.root, candidate: shallowWorks)
        // Model the indexed rows after a legacy multi-creator source recognizes its shallow works.
        try fixtures.sql("UPDATE sources SET layout = 'multi-creator'")
        let snapshot = try await catalog.snapshot()
        let complete = try required(snapshot.videoWorks.first { $0.structure == .complete })
        let compact = try required(snapshot.videoWorks.first { $0.structure == .compact })
        let completeKey = SourceAlbumKey(sourceID: complete.video.source.id, relativePath: "Complete")
        let compactKey = SourceAlbumKey(sourceID: compact.video.source.id, relativePath: "Compact")
        let photographs = [complete.photoSets[0].photos[0], compact.photoSets[0].photos[0]]
        try verify(SourceAlbumKey(media: photographs[0]) == completeKey && SourceAlbumKey(media: photographs[1]) == compactKey)
        let tag = try await catalog.addTag(named: "浅层作品", to: completeKey)
        try await catalog.addTag(tag.id, to: compactKey)
        try await catalog.replaceCover([photographs[0].id, complete.samples[0].id], for: completeKey)
        try await catalog.replaceCover([photographs[1].id], for: compactKey)
        let collectionID = try await catalog.createAlbum(named: "作品选片")
        try await catalog.append(mediaIDs: [photographs[1].id], to: collectionID)
        let intermediary = SourceAlbumKey(sourceID: complete.video.source.id, relativePath: "Complete/官方样张")
        try await expectAsyncError(AlbumOrganizationError.self) {
            try await catalog.setFavorite(true, for: intermediary)
        }

        let reopened = try Catalog(directory: fixtures.databaseDirectory)
        let loaded = try await reopened.snapshot()
        let albums = try await reopened.sourceAlbumIndex()
        let index = SearchIndex(media: loaded.media, sources: loaded.sources)
        let workHits = index.globalSearch("", mode: .fuzzy, directories: true, files: false,
                                          taggedAlbums: albums.taggedAlbums[tag.id])
        try verify(Set(workHits.compactMap(\.sourceAlbum)) == [completeKey, compactKey] && workHits.count == 2)
        let groups = index.globalSearch("官方样张", mode: .exact, directories: true, files: false)
        try verify(groups.count == 1 && groups[0].category == .directory && groups[0].sourceAlbum == nil)

        let collection = try required(loaded.albums.first { $0.id == collectionID })
        let collectionResults = index.globalSearch("照片", mode: .fuzzy, directories: false, files: true,
                                                   taggedAlbums: albums.taggedAlbums[tag.id]) { result in
            if case .file(let item) = result { return collection.mediaIDs.contains(item.id) }
            return false
        }
        try verify(collectionResults.count == 1 && collectionResults.first?.sourceAlbum == compactKey)
        if case .file(let item) = try required(collectionResults.first) { try verify(item.id == photographs[1].id) }

        for (photo, key) in zip(photographs, [completeKey, compactKey]) {
            let hits = index.globalSearch(photo.name, mode: .exact, directories: false, files: true,
                                          taggedAlbums: albums.taggedAlbums[tag.id])
            guard case .file(let found) = try required(hits.first) else {
                throw CheckFailure(location: "作品照片未生成文件搜索结果")
            }
            try verify(found.id == photo.id && SourceAlbumKey(media: found) == key)
            let organization = try await reopened.sourceAlbumOrganization(for: key)
            try verify(organization.tags == [tag] && organization.effectiveCoverIDs.first == photo.id)
        }
    }

    static func checkSourceAlbumOrganization() async throws {
        let fixtures = try Fixtures()
        let sourceURL = fixtures.directory("Source")
        for name in ["Maker/Album/Image 2.png", "Maker/Album/Image 10.jpg", "Maker/Album/Clip.mp4", "Maker/Album2/Image.png"] {
            try fixtures.file("Source/" + name)
        }
        let root = sourceURL.path.replacingOccurrences(of: "'", with: "''")
        let sourceFile = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let migrations = sourceFile.appendingPathComponent("../../../../shared/migrations").standardizedFileURL
        try FileManager.default.createDirectory(at: fixtures.databaseDirectory, withIntermediateDirectories: true)
        try Data().write(to: fixtures.databaseDirectory.appendingPathComponent("catalog.sqlite3"))
        for migration in ["001-initial.sql", "002-pending-rename.sql"] {
            try fixtures.sql(String(contentsOf: migrations.appendingPathComponent(migration), encoding: .utf8))
        }
        try fixtures.sql("""
            INSERT INTO sources (id, path, layout) VALUES (4, '\(root)', 'multi-creator');
            INSERT INTO media (id, source_id, relative_path, kind)
                VALUES (8, 4, 'Maker/Album/Image 2.png', 'image'), (9, 4, 'Maker/Album/Image 10.jpg', 'image'),
                       (10, 4, 'Maker/Album/Clip.mp4', 'video'), (11, 4, 'Maker/Album2/Image.png', 'image');
            INSERT INTO albums (id, name) VALUES (20, '旧版合集');
            INSERT INTO album_media VALUES (20, 8, 1), (20, 11, 0);
            """)
        let originalVersion = try fixtures.scalar("PRAGMA user_version")
        try verify(originalVersion == 2)

        let catalog = try Catalog(directory: fixtures.databaseDirectory)
        let source = try required(try await catalog.snapshot().sources.first)
        let album = SourceAlbumKey(sourceID: source.id, relativePath: "Maker/Album")
        let sibling = SourceAlbumKey(sourceID: source.id, relativePath: "Maker/Album2")
        let defaultOrganization = try await catalog.sourceAlbumOrganization(for: album)
        try verify(defaultOrganization.ratingHalf == nil && !defaultOrganization.favorite &&
                   defaultOrganization.configuredCoverIDs.isEmpty && defaultOrganization.effectiveCoverIDs == [8])
        try await catalog.setFavorite(true, for: album)
        try await catalog.setRatingHalf(0, for: album)
        try await catalog.setRatingHalf(7, for: sibling)
        let trip = try await catalog.addTag(named: "　 ＴＲＩＰ   图片 ", to: album)
        let duplicate = try await catalog.addTag(named: "trip 图片", to: sibling)
        try verify(duplicate == trip && trip.name == "TRIP 图片" && trip.normalizedName == "trip 图片")
        try verify(SourceAlbumTag.names(from: "ΟΣ İ").normalized == "οσ i\u{0307}")
        let scenic = try await catalog.addTag(named: "风景", to: album)
        try await catalog.addTag(trip.id, to: sibling)
        let tagged = try await catalog.sourceAlbums(tagID: trip.id)
        try verify(tagged == [album, sibling])
        try await expectAsyncError(AlbumOrganizationError.self) {
            try await catalog.renameTag(trip.id, to: scenic.name)
        }
        try await catalog.renameTag(trip.id, to: "旅行")
        try await catalog.replaceCover([9, 8], for: album)
        try await expectAsyncError(AlbumOrganizationError.self) {
            try await catalog.replaceCover([9, 11], for: album)
        }
        try await expectAsyncError(AlbumOrganizationError.self) {
            try await catalog.replaceCover([10], for: album)
        }
        try fixtures.sql("""
            CREATE TRIGGER reject_second_cover BEFORE INSERT ON source_album_cover_media
            WHEN NEW.position = 1 BEGIN SELECT RAISE(ABORT, 'fixture failure'); END;
            """)
        do {
            try await catalog.replaceCover([8, 9], for: album)
            throw CheckFailure(location: "封面写入局部失败未报告")
        } catch {
            try verify(error.localizedDescription.contains("fixture failure"))
        }
        try fixtures.sql("DROP TRIGGER reject_second_cover")

        let reopened = try Catalog(directory: fixtures.databaseDirectory)
        let persisted = try await reopened.sourceAlbumOrganization(for: album)
        let persistedSibling = try await reopened.sourceAlbumOrganization(for: sibling)
        let library = try await reopened.snapshot()
        try verify(persisted.favorite && persisted.ratingHalf == 0 && persisted.tags.contains { $0.name == "旅行" })
        try verify(persistedSibling.ratingHalf == 7 && !persistedSibling.favorite)
        try verify(persisted.configuredCoverIDs == [9, 8] && persisted.effectiveCoverIDs == [9, 8])
        try verify(library.albums.first?.mediaIDs == [11, 8])
        let organizationIndex = try await reopened.sourceAlbumIndex()
        try verify(organizationIndex.configuredCovers[album] == [9, 8])
        try verify(SourceAlbumTag.suggestions(matching: "旅", from: organizationIndex.tags).map(\.id) == [trip.id])
        let search = SearchIndex(media: library.media, sources: library.sources)
        let filtered = search.globalSearch("", mode: .fuzzy, directories: true, files: true,
                                           taggedAlbums: organizationIndex.taggedAlbums[scenic.id])
        try verify(filtered.filter { $0.category == .album }.map(\.sourceAlbum) == [album])
        try verify(filtered.count == 4 && filtered.allSatisfy { $0.sourceAlbum == album })
        let filteredFiles = search.globalSearch("Image", mode: .fuzzy, directories: false, files: true,
                                                taggedAlbums: organizationIndex.taggedAlbums[scenic.id])
        try verify(filteredFiles.count == 2 && filteredFiles.allSatisfy { $0.sourceAlbum == album })

        let removedCover = sourceURL.appendingPathComponent("Maker/Album/Image 10.jpg")
        let outside = fixtures.directory("Unavailable.jpg")
        try FileManager.default.moveItem(at: removedCover, to: outside)
        try await reopened.update(source: source, entries: SourceScanner.rescan(source))
        let fallback = try await reopened.sourceAlbumOrganization(for: album)
        try verify(fallback.configuredCoverIDs == [9, 8] && fallback.effectiveCoverIDs == [8])
        try FileManager.default.moveItem(at: outside, to: removedCover)
        try await reopened.update(source: source, entries: SourceScanner.rescan(source))
        let recovered = try await reopened.sourceAlbumOrganization(for: album)
        try verify(recovered.effectiveCoverIDs == [9, 8])
        try fixtures.file("Source/Maker/Album/Later.png")
        try await reopened.update(source: source, entries: SourceScanner.rescan(source))
        let upgraded = try await reopened.snapshot()
        let added = try required(upgraded.media.first { $0.name == "Later.png" })
        try verify(added.id > 11 && upgraded.albums.first?.mediaIDs == [11, 8])
        try await reopened.markUnavailable(source: source)
        let offline = try await reopened.sourceAlbumOrganization(for: album)
        try verify(offline.configuredCoverIDs == [9, 8] && offline.effectiveCoverIDs.isEmpty)

        try await reopened.setRatingHalf(nil, for: album)
        try await reopened.removeTag(trip.id, from: album)
        let detached = try await reopened.sourceAlbums(tagID: trip.id)
        try verify(detached == [sibling])
        try await reopened.deleteTag(trip.id)
        let remaining = try await reopened.albumTags()
        let deletedLinks = try await reopened.sourceAlbums(tagID: trip.id)
        let cleared = try await reopened.sourceAlbumOrganization(for: album)
        try verify(remaining == [scenic] && deletedLinks.isEmpty && cleared.ratingHalf == nil && cleared.favorite)
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

    static func checkMediaSort() async throws {
        let fixtures = try Fixtures()
        let root = fixtures.directory("Sort")
        let early = Date(timeIntervalSince1970: 1_000)
        let late = Date(timeIntervalSince1970: 2_000)

        for (name, size, time) in [("1.png", 20, late), ("2.png", 20, early),
                                   ("10.png", 3, early), ("20.png", 10, late)] {
            try fixtures.file("Sort/" + name)
            let url = root.appendingPathComponent(name)
            try Data(repeating: 1, count: size).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: url.path)
        }

        let catalog = try Catalog(directory: fixtures.databaseDirectory)
        let inspected = try SourceScanner.inspect(root, dataDirectory: fixtures.databaseDirectory)
        try await catalog.importSource(root: root, candidate: try required(inspected.candidates.first))
        let indexed = try await catalog.snapshot().media.reversed()
        let items = Array(indexed)
        // Leave a stale entry in the catalog to exercise live metadata failure.
        try FileManager.default.moveItem(at: root.appendingPathComponent("20.png"),
                                          to: fixtures.directory("unavailable.png"))

        try verify(MediaSort().arrange(items) == items)
        try verify(MediaSort(field: .name).arrange(items).map(\.name) == ["1.png", "2.png", "10.png", "20.png"])
        try verify(MediaSort(field: .name, descending: true).arrange(items).map(\.name) == ["20.png", "10.png", "2.png", "1.png"])
        try verify(MediaSort(field: .size).arrange(items).map(\.name) == ["10.png", "1.png", "2.png", "20.png"])
        try verify(MediaSort(field: .size, descending: true).arrange(items).map(\.name) == ["1.png", "2.png", "10.png", "20.png"])
        try verify(MediaSort(field: .modified).arrange(items).map(\.name) == ["2.png", "10.png", "1.png", "20.png"])
        try verify(MediaSort(field: .modified, descending: true).arrange(items).map(\.name) == ["1.png", "2.png", "10.png", "20.png"])
    }

    static func checkVideoWorks() throws {
        let fixtures = try Fixtures()
        for path in [
            "Complete/视频/影片.mp4", "Complete/官方样张/样张.jpg",
            "Complete/附加写真集/写真集 10/封面.png", "Complete/附加写真集/写真集 10/图片.png",
            "Complete/附加写真集/写真集 2/封面.jpg", "Complete/附加写真集/写真集 2/图片.png",
            "Compact/影片.MOV", "Compact/官方样张.jpg", "Compact/其他.jpg",
            "Compact/附加写真集/图片 10.png", "Compact/附加写真集/图片 2.png",
            "Ordinary/影片.mp4", "Ordinary/其他.jpg",
        ] {
            try fixtures.file(path)
        }
        let completeRoot = fixtures.directory("Complete")
        try FileManager.default.createSymbolicLink(
            at: completeRoot.appendingPathComponent("视频/链接.mp4"),
            withDestinationURL: fixtures.directory("Ordinary/影片.mp4")
        )
        let complete = try SourceScanner.inspectVideoWork(completeRoot, dataDirectory: fixtures.databaseDirectory)
        guard case .recognized(let work) = complete else {
            throw CheckFailure(location: "完整作品目录无法识别")
        }
        try verify(work.structure == .complete && work.video.relativePath == "视频/影片.mp4")
        try verify(work.samples.map(\.relativePath) == ["官方样张/样张.jpg"])
        try verify(work.photoSets.map(\.relativePath) == ["附加写真集/写真集 2", "附加写真集/写真集 10"])
        try verify(work.photoSets[0].cover?.relativePath == "附加写真集/写真集 2/封面.jpg")
        try verify(work.photoSets[1].photos.map(\.relativePath) == ["附加写真集/写真集 10/图片.png"])

        let compactRoot = fixtures.directory("Compact")
        let compact = try SourceScanner.inspectVideoWork(compactRoot, dataDirectory: fixtures.databaseDirectory)
        guard case .recognized(let flat) = compact else {
            throw CheckFailure(location: "简化作品目录无法识别")
        }
        try verify(flat.structure == .compact && flat.video.relativePath == "影片.MOV")
        try verify(flat.samples.map(\.relativePath) == ["官方样张.jpg"])
        try verify(flat.photoSets.count == 1 && flat.photoSets[0].cover == nil)
        try verify(flat.photoSets[0].photos.map(\.relativePath) == ["附加写真集/图片 2.png", "附加写真集/图片 10.png"])

        let ordinary = fixtures.directory("Ordinary")
        guard case .unrecognized = try SourceScanner.inspectVideoWork(ordinary, dataDirectory: fixtures.databaseDirectory) else {
            throw CheckFailure(location: "普通媒体目录被误判为作品")
        }
        let normalImport = try SourceScanner.inspect(ordinary, dataDirectory: fixtures.databaseDirectory)
        try verify(normalImport.candidates.map(\.layout) == [.flat])

        try fixtures.file("Compact/第二个影片.mp4")
        guard case .ambiguous = try SourceScanner.inspectVideoWork(compactRoot, dataDirectory: fixtures.databaseDirectory) else {
            throw CheckFailure(location: "多个主视频应报告歧义")
        }
        try fixtures.file("Complete/附加写真集/写真集 2/封面.png")
        guard case .ambiguous = try SourceScanner.inspectVideoWork(completeRoot, dataDirectory: fixtures.databaseDirectory) else {
            throw CheckFailure(location: "多个封面应报告歧义")
        }
    }

    static func checkVideoFormats() async throws {
        let fixtures = try Fixtures()
        let source = fixtures.directory("Video")
        for name in ["clip.TS", "clip.ts.mov", "clip.mkv", "clip.webm", "clip.avi"] {
            try fixtures.file("Video/" + name)
        }
        let inspection = try SourceScanner.inspect(source, dataDirectory: fixtures.databaseDirectory)
        let candidate = try required(inspection.candidates.first)
        try verify(Set(candidate.entries.map(\.relativePath)) == ["clip.TS", "clip.ts.mov", "clip.mkv", "clip.webm", "clip.avi"])
        try verify(candidate.entries.allSatisfy { $0.kind == .video })
        let catalog = try Catalog(directory: fixtures.databaseDirectory)
        try await catalog.importSource(root: source, candidate: candidate)
        let library = try await catalog.snapshot()
        let index = SearchIndex(media: library.media, sources: library.sources)
        for name in ["clip.TS", "clip.mkv", "clip.webm", "clip.avi"] {
            let found = index.search(name.lowercased(), mode: .exact, directories: false, files: true)
            try verify(found.map(\.name) == [name])
        }
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

    static func checkSourceDeletion() async throws {
        let fixtures = try Fixtures()
        try fixtures.file("Removed/photo.png")
        try fixtures.file("Kept/one.png")
        try fixtures.file("Kept/two.png")
        let catalog = try Catalog(directory: fixtures.databaseDirectory)
        for name in ["Kept", "Removed"] {
            let inspection = try SourceScanner.inspect(fixtures.directory(name), dataDirectory: fixtures.databaseDirectory)
            try await catalog.importSource(root: inspection.root, candidate: try required(inspection.candidates.first))
        }
        let imported = try await catalog.snapshot()
        let removed = try required(imported.sources.first { $0.name == "Removed" })
        let item = try required(imported.media.first { $0.source.id == removed.id })
        let path = try item.readableURL()
        let contents = try Data(contentsOf: path)
        let kept = imported.media.filter { $0.source.id != removed.id }.map(\.id).reversed()
        let memberOrder = Array(kept.prefix(1)) + [item.id] + Array(kept.dropFirst())
        let collection = try await catalog.createAlbum(named: "Shared")
        try await catalog.append(mediaIDs: memberOrder, to: collection)
        let tag = try await catalog.addTag(named: "Shared Tag", to: SourceAlbumKey(sourceID: removed.id, relativePath: ""))
        try await catalog.markUnavailable(source: removed)

        let stale = try await catalog.snapshot()
        let otherWindow = try Catalog(directory: fixtures.databaseDirectory)
        _ = try await otherWindow.createAlbum(named: "Other")
        try await expectAsyncError(SourceDeletionChangedError.self) {
            try await catalog.deleteSource(removed.id, expectedDataVersion: stale.dataVersion)
        }
        let refreshed = try await catalog.snapshot()
        try verify(refreshed.sources.contains { $0.id == removed.id })
        try await catalog.deleteSource(removed.id, expectedDataVersion: refreshed.dataVersion)

        let after = try await otherWindow.snapshot()
        let remainingTagged = try await otherWindow.sourceAlbums(tagID: tag.id)
        try verify(after.sources.map(\.name) == ["Kept"] && after.media.count == 2)
        try verify(after.albums.first { $0.id == collection }?.mediaIDs == Array(kept))
        try verify(remainingTagged.isEmpty)
        let preserved = try Data(contentsOf: path)
        try verify(preserved == contents)

        let reopened = try Catalog(directory: fixtures.databaseDirectory)
        let inspection = try SourceScanner.inspect(fixtures.directory("Removed"), dataDirectory: fixtures.databaseDirectory)
        try await reopened.importSource(root: inspection.root, candidate: try required(inspection.candidates.first))
        let reimported = try await reopened.snapshot()
        let newSource = try required(reimported.sources.first { $0.name == removed.name })
        let newMedia = try required(reimported.media.first { $0.source.id == newSource.id })
        try verify(newSource.id > removed.id && newMedia.id > item.id && newMedia.relativePath == item.relativePath)
        try verify(reimported.albums.first { $0.id == collection }?.mediaIDs == Array(kept))
    }

    static func checkAlbumDeletion() async throws {
        let fixtures = try Fixtures()
        try fixtures.file("First/01.png")
        try fixtures.file("Second/02.mov")
        let catalog = try Catalog(directory: fixtures.databaseDirectory)
        for name in ["First", "Second"] {
            let inspection = try SourceScanner.inspect(fixtures.directory(name), dataDirectory: fixtures.databaseDirectory)
            try await catalog.importSource(root: inspection.root, candidate: try required(inspection.candidates.first))
        }

        let imported = try await catalog.snapshot()
        let paths = try imported.media.map { try $0.readableURL() }
        let bytes = try paths.map { try Data(contentsOf: $0) }
        let times = try paths.map { try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        let memberIDs = imported.media.map(\.id)
        let retained = try await catalog.createAlbum(named: "Retained")
        let deleted = try await catalog.createAlbum(named: "Shared")
        try await catalog.append(mediaIDs: Array(memberIDs.reversed()), to: retained)
        try await catalog.append(mediaIDs: memberIDs, to: deleted)
        try await catalog.markUnavailable(source: imported.sources[0])

        try fixtures.sql("""
            CREATE TRIGGER reject_member_delete BEFORE DELETE ON album_media
            BEGIN SELECT RAISE(ABORT, 'test member delete failure'); END;
            """)
        let beforeFailure = try await catalog.snapshot()
        do {
            try await catalog.delete(albumID: deleted, expectedDataVersion: beforeFailure.dataVersion)
            throw CheckFailure(location: "album deletion must report cascade failure")
        } catch {
            try verify(error.localizedDescription.contains("test member delete failure"))
        }
        let failed = try await catalog.snapshot()
        try verify(failed.albums == beforeFailure.albums)
        try fixtures.sql("DROP TRIGGER reject_member_delete")

        let original = try await catalog.snapshot()
        let otherWindow = try Catalog(directory: fixtures.databaseDirectory)
        let otherSnapshot = try await otherWindow.snapshot()
        try await otherWindow.delete(albumID: deleted, expectedDataVersion: otherSnapshot.dataVersion)
        let recreated = try await otherWindow.createAlbum(named: "Shared")
        try verify(recreated == deleted)
        try await expectAsyncError(AlbumDeletionError.self) {
            try await catalog.delete(albumID: deleted, expectedDataVersion: original.dataVersion)
        }
        let after = try await catalog.snapshot()
        try verify(after.albums.first { $0.id == recreated }?.mediaIDs == [])
        try verify(after.albums.first { $0.id == retained }?.mediaIDs == Array(memberIDs.reversed()))
        try verify(after.media == original.media)
        try await catalog.delete(albumID: recreated, expectedDataVersion: after.dataVersion)
        let reopened = try await otherWindow.snapshot()
        try verify(reopened.albums.map(\.id) == [retained])
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
        try fixtures.sql("""
            DROP TRIGGER remember_source_id;
            DROP TRIGGER remember_media_id;
            DROP TABLE catalog_identity_sequence;
            DROP TABLE video_work_images;
            DROP TABLE video_works;
            DROP TABLE source_album_cover_media;
            DROP TABLE source_album_tags;
            DROP TABLE tags;
            DROP TABLE source_album_organization;
            DROP TABLE pending_rename;
            PRAGMA user_version = 1;
            """)
        let catalog = try Catalog(directory: fixtures.databaseDirectory)
        let migrated = try await catalog.snapshot()
        try verify(migrated.media.map(\.id) == before.media.map(\.id))
        try verify(migrated.albums.first { $0.id == favourite }?.mediaIDs == [original.id])
        try fixtures.sql("""
            INSERT INTO source_album_organization (id, source_id, album_path, favorite, rating_half)
                VALUES (101, \(source.id), 'Artist/Album', 1, 0),
                       (102, \(source.id), 'Artist/Album2', 0, NULL),
                       (103, \(source.id), 'Second Creator/Album', 0, 7);
            INSERT INTO tags (id, name, normalized_name) VALUES (104, 'Travel', 'travel');
            INSERT INTO source_album_tags VALUES (101, 104);
            INSERT INTO source_album_cover_media VALUES (101, \(original.id), 0), (101, \(offline.id), 1);
            """)

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
        let organizationRows = try fixtures.scalar("""
            SELECT COUNT(*) FROM source_album_organization WHERE
                (id = 101 AND album_path = 'Artist/Renamed Album' AND favorite = 1 AND rating_half = 0)
                OR (id = 102 AND album_path = 'Artist/Album2' AND rating_half IS NULL)
                OR (id = 103 AND album_path = 'New Creator/Album' AND rating_half = 7);
            """)
        let tagCount = try fixtures.scalar("SELECT COUNT(*) FROM source_album_tags WHERE source_album_id = 101 AND tag_id = 104")
        let coverCount = try fixtures.scalar("""
            SELECT COUNT(*) FROM source_album_cover_media WHERE source_album_id = 101 AND
                ((position = 0 AND media_id = \(original.id)) OR (position = 1 AND media_id = \(offline.id)));
            """)
        try verify(organizationRows == 3 && tagCount == 1 && coverCount == 2)

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
        try fixtures.file("Teams/远山/湖光/湖光.png")
        try fixtures.file("Teams/海岛/湖光/海岸.png")
        let catalog = try Catalog(directory: fixtures.databaseDirectory)
        let inspection = try SourceScanner.inspect(fixtures.directory("Library"), dataDirectory: fixtures.databaseDirectory)
        try await catalog.importSource(root: inspection.root, candidate: try required(inspection.candidates.first))
        let elsewhere = try SourceScanner.inspect(fixtures.directory("Elsewhere"), dataDirectory: fixtures.databaseDirectory)
        try await catalog.importSource(root: elsewhere.root, candidate: try required(elsewhere.candidates.first))
        let teams = try SourceScanner.inspect(fixtures.directory("Teams"), dataDirectory: fixtures.databaseDirectory)
        try await catalog.importSource(root: teams.root, candidate: try required(teams.candidates.first))
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
        let scopedFiles = index.globalSearch(exactTerm.text, mode: exactTerm.mode, directories: true, files: true) {
            if case .file(let media) = $0 { return media.source.name == "Library" }
            return false
        }
        try verify(scopedFiles == local.map(GlobalSearchResult.file))
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
        try verify(globalFolders[0].category == .album)
        try verify(index.globalSearch("Library", mode: .exact, directories: true, files: false).map(\.category) == [.creator])
        try verify(index.globalSearch("Elsewhere", mode: .exact, directories: true, files: false).map(\.category) == [.album])
        try verify(index.globalSearch("Teams", mode: .exact, directories: true, files: false).map(\.category) == [.directory])
        try verify(index.globalSearch("远山", mode: .exact, directories: true, files: false).map(\.category) == [.creator])
        let sameName = index.globalSearch("湖光", mode: .exact, directories: true, files: true)
        try verify(sameName.map(\.category) == [.album, .album, .file])
        let scoped = index.globalSearch("湖光", mode: .exact, directories: true, files: true) { result in
            switch result {
            case .directory(let directory): directory.relativePath.hasPrefix("远山/")
            case .file(let item): item.relativePath.hasPrefix("远山/")
            }
        }
        try verify(scoped.map(\.category) == [.album, .file])
        try verify(index.globalSearch("sumer", mode: .fuzzy, directories: true, files: false) {
            if case .directory(let folder) = $0 { return folder.source.name == "Elsewhere" }
            return false
        }.isEmpty)
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
        try withDatabase { database in
            try verify(sqlite3_exec(database, command, nil, nil, nil) == SQLITE_OK)
        }
    }

    func scalar(_ query: String) throws -> Int64 {
        try withDatabase { database in
            var statement: OpaquePointer?
            try verify(sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK)
            defer { sqlite3_finalize(statement) }
            try verify(sqlite3_step(statement) == SQLITE_ROW)
            return sqlite3_column_int64(statement, 0)
        }
    }

    private func withDatabase<T>(_ operation: (OpaquePointer) throws -> T) throws -> T {
        let path = databaseDirectory.appendingPathComponent("catalog.sqlite3").path
        var database: OpaquePointer?
        let opened = sqlite3_open_v2(path, &database, SQLITE_OPEN_READWRITE, nil)
        defer { sqlite3_close(database) }
        try verify(opened == SQLITE_OK)
        return try operation(required(database))
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
