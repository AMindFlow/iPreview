import Darwin
import Foundation
import SQLite3

public enum SourceRenameError: LocalizedError {
    case invalidName
    case unavailable
    case collision
    case overlappingSources
    case unsupportedVolume
    case unsafeFilesystem(String)
    case pending
    case uncertain(oldPath: String, newPath: String)
    case staleScan

    public var errorDescription: String? {
        switch self {
        case .invalidName: "请输入有效的名称。名称不能以点开头或包含路径分隔符。"
        case .unavailable: "源文件或文件夹已离线、移动或无法安全定位。"
        case .collision: "目标名称已存在于磁盘或媒体索引中。"
        case .overlappingSources: "此项与另一个已导入的媒体源重叠，无法安全重命名。"
        case .unsupportedVolume: "此版本的 macOS 源文件重命名需要 APFS 磁盘。"
        case .unsafeFilesystem(let detail): "无法安全重命名源文件或文件夹：\(detail)"
        case .pending: "上次重命名无法自动核对。请检查原名称和目标名称，处理后重新打开 iPreview。"
        case .uncertain(let oldPath, let newPath):
            "无法确认重命名结果。请核对原路径「\(oldPath)」和目标路径「\(newPath)」。确认文件身份后恢复原名称，再打开 iPreview。"
        case .staleScan: "媒体库在扫描期间已更新。请重新扫描。"
        }
    }
}

private struct RenameIntent: Equatable {
    let sourceID: Int64
    let oldPath: String
    let newPath: String
    let isDirectory: Bool
    let identity: String

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.sourceID == rhs.sourceID && lhs.isDirectory == rhs.isDirectory && lhs.identity == rhs.identity
            && literalEqual(lhs.oldPath, rhs.oldPath) && literalEqual(lhs.newPath, rhs.newPath)
    }

    var oldName: String { oldPath.components(separatedBy: "/").last! }
    var newName: String { newPath.components(separatedBy: "/").last! }

    var recoveryError: SourceRenameError { .uncertain(oldPath: oldPath, newPath: newPath) }
}

struct SourceRename {
    let database: Database

    private let pendingSQL = "SELECT source_id, old_path, new_path, is_directory, file_identity FROM pending_rename"

    func rename(sourceID: Int64, path: String, mediaID: Int64?, to name: String,
                expectedFolderMemberID: Int64?) throws -> String {
        let expectedID = mediaID ?? expectedFolderMemberID
        let newName = try validatedName(name)
        let oldParts = path.components(separatedBy: "/")
        guard oldParts.allSatisfy(isSafeComponent) else { throw SourceRenameError.unavailable }

        let oldName = oldParts.last!
        let suffix = (oldName as NSString).pathExtension
        let newLeaf = mediaID == nil ? newName : newName + "." + suffix
        let newPath = (oldParts.dropLast() + [newLeaf]).joined(separator: "/")

        let prepared = try database.transaction { () -> (RenameIntent, RenameParent)? in
            guard try pending() == nil else { throw SourceRenameError.pending }
            let source = try availableSource(id: sourceID)
            let albumDepth = switch source.layout {
            case .flat: 0
            case .creator: 1
            case .multiCreator: 2
            }
            let validDepth = mediaID == nil ? oldParts.count <= albumDepth : oldParts.count == albumDepth + 1
            guard validDepth else { throw SourceRenameError.unavailable }
            let parent = try RenameParent(root: source.path, components: oldParts.dropLast())
            guard let identity = try parent.exactIdentity(of: oldName, directory: mediaID == nil) else {
                throw SourceRenameError.unavailable
            }
            let intent = RenameIntent(sourceID: sourceID, oldPath: path, newPath: newPath,
                                      isDirectory: mediaID == nil, identity: identity)
            _ = try checkedChanges(for: intent, expectedID: expectedID)
            if literalEqual(path, newPath) { return nil }
            try checkOverlaps(source: source, intent: intent)
            try parent.checkDestination(old: oldName, new: newLeaf, beingMoved: identity, directory: intent.isDirectory)
            try database.execute(
                "INSERT INTO pending_rename VALUES (1, ?, ?, ?, ?, ?)",
                [.integer(sourceID), .text(path), .text(newPath), .integer(intent.isDirectory ? 1 : 0), .text(identity)]
            )
            return (intent, parent)
        }
        guard let (intent, parent) = prepared else { return path }

        var moved = false
        do {
            try database.transaction {
                guard try pending() == intent else { throw SourceRenameError.pending }
                let source = try availableSource(id: sourceID)
                try checkOverlaps(source: source, intent: intent)
                try parent.verifyLocation(root: source.path, components: oldParts.dropLast())
                let changes = try checkedChanges(for: intent, expectedID: expectedID)
                guard try parent.state(of: intent) == .original else { throw SourceRenameError.pending }
                try parent.checkDestination(old: intent.oldName, new: intent.newName,
                                            beingMoved: intent.identity, directory: intent.isDirectory)
                try parent.move(intent.oldName, to: intent.newName)
                moved = true
                guard try parent.state(of: intent) == .final else { throw SourceRenameError.pending }
                try parent.verifyLocation(root: source.path, components: oldParts.dropLast())
                try parent.synchronize()
                try update(changes)
                try clear()
            }
        } catch let operationError {
            do {
                try database.transaction {
                    guard try pending() == intent else { return }
                    if moved, try parent.state(of: intent) == .final {
                        try parent.move(intent.newName, to: intent.oldName)
                        try parent.synchronize()
                    }
                    guard try parent.state(of: intent) == .original else { throw SourceRenameError.pending }
                    try clear()
                }
            } catch {
                throw intent.recoveryError
            }
            throw operationError
        }
        return newPath
    }

    func recover() throws {
        try database.transaction {
            guard let intent = try pending() else { return }
            let source = try source(id: intent.sourceID)
            let oldParts = intent.oldPath.components(separatedBy: "/")
            let newParts = intent.newPath.components(separatedBy: "/")
            guard oldParts.allSatisfy(isSafeComponent), newParts.allSatisfy(isSafeComponent),
                  literalEqual(oldParts.dropLast().joined(separator: "/"), newParts.dropLast().joined(separator: "/")),
                  !literalEqual(intent.oldPath, intent.newPath) else { throw SourceRenameError.pending }
            let parent = try RenameParent(root: source.path, components: oldParts.dropLast())
            switch try parent.state(of: intent) {
            case .original:
                try clear()
            case .final:
                try checkOverlaps(source: source, intent: intent)
                let changes = try checkedChanges(for: intent, expectedID: nil)
                try parent.synchronize()
                try update(changes)
                try clear()
            case .uncertain:
                throw SourceRenameError.pending
            }
        }
    }

    func recoveryNotice() throws -> String? {
        guard let intent = try pending() else { return nil }
        let root = try source(id: intent.sourceID).path
        return root + "\n" + intent.recoveryError.localizedDescription
    }

    func blockScan(sourceID: Int64) throws {
        if let intent = try pending(), intent.sourceID == sourceID { throw intent.recoveryError }
    }

    func blockImport(path: String) throws {
        if let intent = try pending() {
            let root = try source(id: intent.sourceID).path
            if sameOrInside(path, root) || sameOrInside(root, path) {
                throw SourceRenameError.pending
            }
        }
    }

    private func pending() throws -> RenameIntent? {
        try database.select(pendingSQL) { row in
            RenameIntent(sourceID: sqlite3_column_int64(row, 0), oldPath: textColumn(row, 1),
                         newPath: textColumn(row, 2), isDirectory: sqlite3_column_int(row, 3) == 1,
                         identity: textColumn(row, 4))
        }.first
    }

    private func clear() throws {
        try database.execute("DELETE FROM pending_rename WHERE id = 1")
    }

    private func source(id: Int64) throws -> Source {
        guard let source = try database.select("SELECT path, layout, available FROM sources WHERE id = ?",
                                               [.integer(id)], row: { row in
            Source(id: id, path: textColumn(row, 0), layout: Layout(rawValue: textColumn(row, 1))!,
                   isAvailable: sqlite3_column_int(row, 2) == 1)
        }).first else { throw SourceRenameError.unavailable }
        return source
    }

    private func availableSource(id: Int64) throws -> Source {
        let source = try source(id: id)
        guard source.isAvailable else { throw SourceRenameError.unavailable }
        return source
    }

    private func checkOverlaps(source: Source, intent: RenameIntent) throws {
        let paths = try database.select("SELECT path FROM sources WHERE id <> ?", [.integer(source.id)]) {
            textColumn($0, 0)
        }
        let old = source.url.appendingPathComponent(intent.oldPath).path
        let new = source.url.appendingPathComponent(intent.newPath).path
        if paths.contains(where: { other in
            sameOrInside(old, other) || sameOrInside(new, other)
            || (intent.isDirectory && (sameOrInside(other, old) || sameOrInside(other, new)))
        }) {
            throw SourceRenameError.overlappingSources
        }
    }

    private func checkedChanges(for intent: RenameIntent, expectedID: Int64?) throws -> [(id: Int64, path: String)] {
        let rows = try database.select("SELECT id, relative_path, available FROM media WHERE source_id = ?",
                                       [.integer(intent.sourceID)]) { row in
            (id: sqlite3_column_int64(row, 0), path: textColumn(row, 1), available: sqlite3_column_int(row, 2) == 1)
        }
        let oldPrefix = intent.oldPath + "/"
        let affected = rows.filter { row in
            intent.isDirectory ? row.path.utf8.starts(with: oldPrefix.utf8) : literalEqual(row.path, intent.oldPath)
        }
        guard affected.contains(where: { $0.available && (expectedID == nil || $0.id == expectedID) }) else {
            throw SourceRenameError.unavailable
        }
        let affectedIDs = Set(affected.map(\.id))
        let newKey = collisionKey(intent.newPath)
        if rows.contains(where: { row in
            guard !affectedIDs.contains(row.id) else { return false }
            let key = collisionKey(row.path)
            return key == newKey || key.hasPrefix(newKey + "/")
        }) {
            throw SourceRenameError.collision
        }
        return affected.map { row in
            let suffix = String(decoding: row.path.utf8.dropFirst(intent.oldPath.utf8.count), as: UTF8.self)
            return (row.id, intent.newPath + suffix)
        }
    }

    private func update(_ changes: [(id: Int64, path: String)]) throws {
        try database.repeated("UPDATE media SET relative_path = ? WHERE id = ?",
                              bindings: changes.map { [.text($0.path), .integer($0.id)] })
    }

    private func validatedName(_ name: String) throws -> String {
        guard isSafeComponent(name), !name.hasPrefix("."), !name.contains("\\"), !name.contains(":"),
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.rangeOfCharacter(from: .controlCharacters) == nil else { throw SourceRenameError.invalidName }
        return name
    }

    private func isSafeComponent(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".."
        && !name.contains("/") && !name.contains("\0")
    }

    private func sameOrInside(_ path: String, _ root: String) -> Bool {
        let key = collisionKey(path)
        let rootKey = collisionKey(root)
        return key == rootKey || key.hasPrefix(rootKey == "/" ? "/" : rootKey + "/")
    }

    private func collisionKey(_ text: String) -> String {
        text.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .precomposedStringWithCanonicalMapping
    }
}

private func literalEqual(_ left: String, _ right: String) -> Bool {
    left.utf8.elementsEqual(right.utf8)
}

private final class RenameParent {
    enum DiskState { case original, final, uncertain }

    private static let openFlags = O_RDONLY | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW_ANY
    private let descriptor: Int32
    private let volumeID: String

    init(root: String, components: ArraySlice<String>) throws {
        let directory = try Self.openDirectory(root: root, components: components)
        do {
            volumeID = try Self.readVolumeID(directory)
        } catch {
            close(directory)
            throw error
        }
        descriptor = directory
    }

    deinit { close(descriptor) }

    private static func openDirectory(root: String, components: ArraySlice<String>) throws -> Int32 {
        guard let resolved = realpath(root, nil) else { throw SourceRenameError.unavailable }
        defer { free(resolved) }
        let realRoot = String(cString: resolved)
        // Finder may store the system's /var, /tmp or /etc aliases without the /private prefix.
        let systemAlias = ["/var", "/tmp", "/etc"].contains { root == $0 || root.hasPrefix($0 + "/") }
        guard literalEqual(root, realRoot) || (systemAlias && literalEqual("/private" + root, realRoot)) else {
            throw SourceRenameError.unavailable
        }
        var directory = open(realRoot, openFlags)
        guard directory >= 0 else { throw SourceRenameError.unavailable }
        for component in components {
            let child = openat(directory, component, openFlags)
            close(directory)
            guard child >= 0 else { throw SourceRenameError.unavailable }
            directory = child
        }
        return directory
    }

    private static func readVolumeID(_ directory: Int32) throws -> String {
        var volume = statfs()
        guard fstatfs(directory, &volume) == 0 else { throw SourceRenameError.unsupportedVolume }
        let filesystem = withUnsafePointer(to: &volume.f_fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSNAMELEN)) { String(cString: $0) }
        }
        // APFS preserves both inode identity and the exact case and Unicode spelling supplied to rename.
        guard filesystem == "apfs" else { throw SourceRenameError.unsupportedVolume }

        var attributes = attrlist()
        attributes.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        attributes.volattr = ATTR_VOL_INFO | UInt32(ATTR_VOL_UUID)
        // The attribute list contains a 32-bit length followed by a single 16-byte UUID.
        let headerSize = MemoryLayout<UInt32>.size
        var data = [UInt8](repeating: 0, count: headerSize + MemoryLayout<uuid_t>.size)
        let result = data.withUnsafeMutableBytes {
            fgetattrlist(directory, &attributes, $0.baseAddress, $0.count, 0)
        }
        let uuid = data.dropFirst(headerSize)
        guard result == 0, uuid.contains(where: { $0 != 0 }) else { throw SourceRenameError.unsupportedVolume }
        return Data(uuid).base64EncodedString()
    }

    func verifyLocation(root: String, components: ArraySlice<String>) throws {
        let current = try Self.openDirectory(root: root, components: components)
        defer { close(current) }
        var expected = stat()
        var actual = stat()
        guard fstat(descriptor, &expected) == 0, fstat(current, &actual) == 0,
              expected.st_dev == actual.st_dev, expected.st_ino == actual.st_ino else {
            throw SourceRenameError.unavailable
        }
    }

    func exactIdentity(of name: String, directory: Bool) throws -> String? {
        guard try exactNames([name]).contains(where: { literalEqual($0, name) }) else { return nil }
        return try identity(of: name, directory: directory)
    }

    func state(of intent: RenameIntent) throws -> DiskState {
        let names = try exactNames([intent.oldName, intent.newName])
        let original = try names.contains(where: { literalEqual($0, intent.oldName) })
            && identity(of: intent.oldName, directory: intent.isDirectory) == intent.identity
        let renamed = try names.contains(where: { literalEqual($0, intent.newName) })
            && identity(of: intent.newName, directory: intent.isDirectory) == intent.identity
        switch (original, renamed) {
        case (true, false): return .original
        case (false, true): return .final
        default: return .uncertain
        }
    }

    func checkDestination(old: String, new: String, beingMoved: String, directory: Bool) throws {
        var target = stat()
        if fstatat(descriptor, new, &target, AT_SYMLINK_NOFOLLOW) == 0 {
            // A case-insensitive lookup may find the old entry under both spellings.
            let occupied = try exactNames([old, new])
            guard occupied.count == 1, literalEqual(occupied[0], old),
                  try identity(of: new, directory: directory) == beingMoved else { throw SourceRenameError.collision }
        } else if errno != ENOENT {
            throw systemError()
        }
    }

    func move(_ old: String, to new: String) throws {
        guard renameatx_np(descriptor, old, descriptor, new, UInt32(RENAME_EXCL | RENAME_NOFOLLOW_ANY)) == 0 else {
            if errno == EEXIST { throw SourceRenameError.collision }
            throw systemError()
        }
    }

    func synchronize() throws {
        guard fsync(descriptor) == 0 else { throw systemError() }
    }

    private func identity(of name: String, directory: Bool) throws -> String? {
        var entry = stat()
        if fstatat(descriptor, name, &entry, AT_SYMLINK_NOFOLLOW) != 0 {
            if errno == ENOENT { return nil }
            throw systemError()
        }
        let type = UInt16(directory ? S_IFDIR : S_IFREG)
        guard entry.st_mode & UInt16(S_IFMT) == type, entry.st_flags & UInt32(UF_HIDDEN) == 0 else { return nil }
        var parent = stat()
        guard fstat(descriptor, &parent) == 0 else { throw systemError() }
        guard entry.st_dev == parent.st_dev, entry.st_ino != 0,
              entry.st_birthtimespec.tv_sec != 0 else { throw SourceRenameError.unsupportedVolume }
        return "\(volumeID):\(entry.st_ino):\(entry.st_birthtimespec.tv_sec):\(entry.st_birthtimespec.tv_nsec)"
    }

    private func exactNames(_ names: [String]) throws -> [String] {
        let listing = openat(descriptor, ".", Self.openFlags)
        guard listing >= 0 else { throw systemError() }
        guard let stream = fdopendir(listing) else {
            let error = systemError()
            close(listing)
            throw error
        }
        defer { closedir(stream) }
        var found: [String] = []
        while found.count < names.count {
            errno = 0
            guard let entry = readdir(stream) else {
                if errno != 0 { throw systemError() }
                break
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                    String(validatingCString: $0)
                }
            }
            if let name, names.contains(where: { literalEqual(name, $0) }) { found.append(name) }
        }
        return found
    }

    private func systemError() -> SourceRenameError {
        .unsafeFilesystem(String(cString: strerror(errno)))
    }
}
