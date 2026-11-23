import SQLite3

enum VideoWorkIndex {
    static func read(from database: Database, media: inout [Media]) throws -> [IndexedVideoWork] {
        let works = try database.select("SELECT video_id, structure FROM video_works ORDER BY video_id") {
            (id: sqlite3_column_int64($0, 0), structure: VideoWork.Structure(rawValue: textColumn($0, 1))!)
        }
        guard !works.isEmpty else { return [] }
        let byVideoID = Dictionary(uniqueKeysWithValues: works.map { ($0.id, $0.structure) })
        let roots = Set(media.compactMap { item -> SourceAlbumKey? in
            guard let structure = byVideoID[item.id] else { return nil }
            return SourceAlbumKey(sourceID: item.source.id,
                                  relativePath: IndexedVideoWork.albumPath(for: item.relativePath, structure: structure))
        })
        for index in media.indices {
            let item = media[index]
            let key = SourceAlbumKey(sourceID: item.source.id, relativePath: item.relativePath)
            media[index].workAlbumPath = key.containingWork(in: roots)?.relativePath
        }

        let mediaByID = Dictionary(uniqueKeysWithValues: media.map { ($0.id, $0) })
        let images = try database.select("""
            SELECT video_id, media_id, role, set_position
            FROM video_work_images ORDER BY set_position, position
            """) {
            (videoID: sqlite3_column_int64($0, 0), media: mediaByID[sqlite3_column_int64($0, 1)]!,
             role: VideoWorkImageRole(rawValue: textColumn($0, 2))!, set: sqlite3_column_int64($0, 3))
        }
        let byVideo = Dictionary(grouping: images, by: \.videoID)
        return works.map { work in
            let entries = byVideo[work.id, default: []]
            let samples = entries.filter { $0.role == .sample }.map(\.media)
            let books = Dictionary(grouping: entries.filter { $0.role != .sample }, by: \.set)
            let photoSets = books.keys.sorted().map { index in
                let book = books[index]!
                return IndexedVideoWork.PhotoSet(cover: book.first { $0.role == .cover }?.media,
                                                 photos: book.filter { $0.role == .photo }.map(\.media))
            }
            return IndexedVideoWork(video: mediaByID[work.id]!, structure: work.structure,
                                    samples: samples, photoSets: photoSets)
        }
    }

    static func albumRoots(in database: Database, sourceID: Int64) throws -> Set<SourceAlbumKey> {
        Set(try database.select("""
            SELECT media.relative_path, video_works.structure FROM video_works
            JOIN media ON media.id = video_works.video_id WHERE media.source_id = ?
            """, [.integer(sourceID)]) {
            let structure = VideoWork.Structure(rawValue: textColumn($0, 1))!
            return SourceAlbumKey(sourceID: sourceID,
                                  relativePath: IndexedVideoWork.albumPath(for: textColumn($0, 0), structure: structure))
        })
    }

    static func replace(in database: Database, source: SQLiteValue, entries: [ScanEntry]) throws {
        try database.execute("DELETE FROM video_works WHERE video_id IN (SELECT id FROM media WHERE source_id = ?)", [source])
        try database.repeated("""
            INSERT INTO video_works (video_id, structure)
            SELECT id, ? FROM media WHERE source_id = ? AND relative_path = ?
            """, bindings: entries.compactMap { entry in
                guard case .video(let structure) = entry.videoWork else { return nil }
                return [.text(structure.rawValue), source, .text(entry.relativePath)]
            })
        try database.repeated("""
            INSERT INTO video_work_images (video_id, media_id, role, set_position, position)
            SELECT video.id, image.id, ?, ?, ? FROM media AS video JOIN media AS image USING (source_id)
            WHERE video.source_id = ? AND video.relative_path = ? AND image.relative_path = ?
            """, bindings: entries.compactMap { entry in
                guard case .image(let videoPath, let role, let set, let position) = entry.videoWork else { return nil }
                return [.text(role.rawValue), .integer(Int64(set)), .integer(Int64(position)),
                        source, .text(videoPath), .text(entry.relativePath)]
            })
    }
}
