using IPreview;

var list = new BrowseLayout(BrowseMode.List, 1);
Check(list.NeighborOf(1, 3, BrowseDirection.Up) == 0 &&
      list.NeighborOf(1, 3, BrowseDirection.Down) == 2 &&
      list.NeighborOf(1, 3, BrowseDirection.Left) is null &&
      list.NeighborOf(1, 3, BrowseDirection.Right) is null, "preview follows list axis");

var gallery = new BrowseLayout(BrowseMode.Gallery, 1);
Check(gallery.NeighborOf(1, 3, BrowseDirection.Left) == 0 &&
      gallery.NeighborOf(1, 3, BrowseDirection.Right) == 2 &&
      gallery.NeighborOf(1, 3, BrowseDirection.Up) is null &&
      gallery.NeighborOf(1, 3, BrowseDirection.Down) is null, "preview follows gallery axis");

var grid = new BrowseLayout(BrowseMode.Icons, 3);
Check(grid.NeighborOf(1, 8, BrowseDirection.Right) == 2 &&
      grid.NeighborOf(2, 8, BrowseDirection.Right) is null &&
      grid.NeighborOf(3, 8, BrowseDirection.Left) is null, "preview stays in a grid row");
Check(grid.NeighborOf(1, 8, BrowseDirection.Down) == 4 &&
      grid.NeighborOf(7, 8, BrowseDirection.Up) == 4 &&
      grid.NeighborOf(5, 8, BrowseDirection.Down) is null, "preview stays in a grid column");

var work = Directory.CreateTempSubdirectory("ipreview-check-").FullName;
try
{
    var creator = Path.Combine(work, "北京");
    var mixed = Path.Combine(work, "catalog");
    var flat = Path.Combine(work, "flat");
    AddFile(creator, "Summer 2/城楼10.PNG");
    AddFile(creator, "Summer 2/城楼2.PNG");
    AddFile(creator, "Summer 2/.隐藏.jpg");
    AddFile(creator, "Summer 2/clip.MOV");
    AddFile(creator, "ignored.txt");
    AddFile(mixed, "Standalone/one.jpg");
    AddFile(mixed, "Other/Album/other.jpg");
    AddFile(flat, "frame.jpg");

    var single = MediaFiles.Probe(creator);
    Check(single.Options[Layout.Creator].Count == 3, "creator depth, hidden filter and video indexing");
    var ambiguous = MediaFiles.Probe(mixed);
    Check(ambiguous.Options.Keys.ToHashSet().SetEquals([Layout.Creator, Layout.MultiCreator]),
        "ambiguous options");
    Check(MediaFiles.Probe(flat).Options.Keys.Single() == Layout.Flat, "flat album");

    var data = Path.Combine(work, "db");
    long albumId;
    long firstId;
    long secondId;
    using (var catalog = new Catalog(data))
    {
        catalog.Import(single.Path, Layout.Creator, single.Options[Layout.Creator]);
        catalog.Import(ambiguous.Path, Layout.MultiCreator, ambiguous.Options[Layout.MultiCreator]);

        var items = catalog.Read().Media;
        try
        {
            catalog.CheckSourcePath(work);
            throw new InvalidOperationException("Core check failed: catalog overlap rejected");
        }
        catch (IOException) { }
        Check(items.Count == 4, "persisted import");
        var ordered = MediaSearch.Find(items, "城楼", false, false, true);
        Check(ordered.Select(item => item.FileName).SequenceEqual(["城楼2.PNG", "城楼10.PNG"]),
            "natural file ordering");
        Check(MediaSearch.Find(items, "ＣＬＩＰ.mov", true, false, true).Count == 1,
            "compatibility and case normalization");
        Check(MediaSearch.Find(items, "clip", true, false, true).Count == 0, "exact file includes extension");
        Check(MediaSearch.Find(items, "bj", false, true, false).Count == 3, "directory pinyin initials");
        Check(MediaSearch.Find(items, "beijing", false, true, false).Count == 3, "directory full pinyin");
        Check(MediaSearch.Find(items, "beijing", false, false, true).Count == 0, "scope isolation");
        Check(MediaSearch.Find(items, "sumer", false, true, false).Count == 3, "directory typo");

        albumId = catalog.CreateAlbum("预览");
        firstId = ordered[0].Id;
        secondId = items.Single(item => item.FileName == "other.jpg").Id;
        catalog.AddToAlbum(albumId, firstId);
        catalog.AddToAlbum(albumId, secondId);
        catalog.AddToAlbum(albumId, firstId);
        catalog.MoveInAlbum(albumId, secondId, -1);
        catalog.RenameAlbum(albumId, "海外");
    }

    using (var catalog = new Catalog(data))
    {
        var snapshot = catalog.Read();
        Check(snapshot.Albums.Single().Name == "海外", "persisted album rename");
        Check(snapshot.AlbumMembers[albumId].Select(item => item.Id).SequenceEqual([secondId, firstId]),
            "persisted album order and deduplication");

        var other = snapshot.Sources.Values.Single(source => source.Path == mixed);
        var offlinePath = Path.Combine(work, "offline");
        Directory.Move(mixed, offlinePath);
        catalog.Rescan(other.Id, null);
        var offline = catalog.Read().AlbumMembers[albumId][0];
        Check(offline.Id == secondId && !offline.Available, "offline member retained");
        Directory.Move(offlinePath, mixed);
        catalog.Rescan(other.Id, MediaFiles.Scan(other.Path, other.Layout));
        var online = catalog.Read().AlbumMembers[albumId][0];
        Check(online.Id == secondId && online.Available, "rescan restores stable member");
        Check(MediaFiles.OpenPath(online) == Path.Combine(mixed, "Other", "Album", "other.jpg"),
            "preview resolves source-relative media");

        catalog.RemoveFromAlbum(albumId, secondId);
        Check(catalog.Read().AlbumMembers[albumId].Single().Id == firstId, "remove album reference");
        Check(File.Exists(MediaFiles.OpenPath(online)), "removing a reference preserves original");
    }
    CheckSourceRename(work);
    Console.WriteLine("Windows catalog, search, preview navigation and source rename checks passed.");
}
finally
{
    Directory.Delete(work, recursive: true);
}

static void AddFile(string folder, string relative)
{
    var path = Path.Combine(folder, relative);
    Directory.CreateDirectory(Path.GetDirectoryName(path)!);
    File.WriteAllText(path, "fixture");
}

static void Check(bool result, string name)
{
    if (!result)
        throw new InvalidOperationException("Core check failed: " + name);
}

static void CheckSourceRename(string work)
{
    var sourcePath = Path.Combine(work, "rename-source");
    AddFile(sourcePath, "Maker/Album/front.jpg");
    AddFile(sourcePath, "Maker/Album/second.png");
    AddFile(sourcePath, "Maker/Album/used.jpg");
    AddFile(sourcePath, "Maker/Album2/untouched.jpg");
    var data = Path.Combine(work, "rename-db");
    Directory.CreateDirectory(data);
    var indexPath = Path.Combine(data, "library.sqlite3");
    using (var versionOne = new Sqlite(indexPath))
    {
        using var stream = typeof(Catalog).Assembly.GetManifestResourceStream("iPreview.Migrations.001-initial.sql")!;
        using var script = new StreamReader(stream);
        versionOne.ExecuteScript(script.ReadToEnd());
        versionOne.Execute("INSERT INTO albums (name) VALUES (?);", "保留既有专辑");
    }

    long sourceId;
    long coverId;
    long secondId;
    long albumId;
    using (var catalog = new Catalog(data))
    {
        Check(catalog.Read().Albums.Single().Name == "保留既有专辑", "version one upgrade preserves existing row");
        sourceId = catalog.Import(sourcePath, Layout.MultiCreator, MediaFiles.Scan(sourcePath, Layout.MultiCreator));
        var indexed = catalog.Read().Media;
        coverId = indexed.Single(item => item.FileName == "front.jpg").Id;
        secondId = indexed.Single(item => item.FileName == "second.png").Id;
        albumId = catalog.CreateAlbum("物理重命名检查", coverId);
        catalog.AddToAlbum(albumId, secondId);

        const string cover = "Maker/Album/front.jpg";
        AddFile(sourcePath, "Maker/Album/not-indexed.jpg");
        File.Delete(Path.Combine(sourcePath, "Maker/Album/used.jpg"));
        catalog.Rescan(sourceId, MediaFiles.Scan(sourcePath, Layout.MultiCreator)
            .Where(item => item.RelativePath != "Maker/Album/not-indexed.jpg").ToList());
        Reject<IOException>(() => catalog.RenameSourceItem(sourceId, cover, "not-indexed", false, coverId), "unindexed collision");
        Reject<IOException>(() => catalog.RenameSourceItem(sourceId, cover, "used", false, coverId), "historical collision");
        Reject<IOException>(() => catalog.RenameSourceItem(sourceId, cover, "COM¹.txt", false, coverId), "Windows device name");
        Reject<IOException>(() => catalog.RenameSourceItem(sourceId, cover, "../bad", false, coverId), "rename stays within parent");
        Reject<IOException>(() => catalog.RenameSourceItem(sourceId, cover, ".hidden", false, coverId), "hidden name");

        using (var failure = new Sqlite(indexPath))
        {
            failure.ExecuteScript("""
                CREATE TRIGGER reject_path_update BEFORE UPDATE OF relative_path ON media
                BEGIN SELECT RAISE(ABORT, 'injected path update failure'); END;
                """);
            Reject<InvalidOperationException>(
                () => catalog.RenameSourceItem(sourceId, cover, "rolled-back", false, coverId), "rollback on index error");
            Check(File.Exists(Path.Combine(sourcePath, cover)) && !File.Exists(Path.Combine(sourcePath, "Maker/Album/rolled-back.jpg"))
                && !catalog.HasPendingRename(sourceId), "database failure restores original disk and clears pending record");
            failure.ExecuteScript("DROP TRIGGER reject_path_update;");
        }

        var renamed = catalog.RenameSourceItem(sourceId, cover, "Front", false, coverId);
        Check(renamed == "Maker/Album/Front.jpg" &&
            Directory.EnumerateFiles(Path.Combine(sourcePath, "Maker/Album")).Any(item => Path.GetFileName(item) == "Front.jpg"),
            "case-only rename preserves exact disk spelling and extension");
        using (var replica = new Catalog(data))
        {
            var staleVersion = replica.DataVersion;
            var staleFiles = MediaFiles.Scan(sourcePath, Layout.MultiCreator);
            renamed = catalog.RenameSourceItem(sourceId, renamed, "新版封面", false, coverId);
            Reject<InvalidOperationException>(() => replica.Rescan(sourceId, staleFiles, staleVersion),
                "a scan collected before another window renames cannot reinsert obsolete paths");
        }
        Check(File.ReadAllText(Path.Combine(sourcePath, renamed)) == "fixture", "file bytes preserved");
        AddFile(sourcePath, cover);
        catalog.Rescan(sourceId, MediaFiles.Scan(sourcePath, Layout.MultiCreator));
        Check(catalog.Read().Media.Single(item => item.RelativePath == cover).Id != coverId, "reused path has another ID");
        Reject<IOException>(() => catalog.RenameSourceItem(sourceId, cover, "wrong-target", false, coverId),
            "stale selected ID cannot rename a replacement at the same path");
        Check(File.Exists(Path.Combine(sourcePath, cover)) &&
            !File.Exists(Path.Combine(sourcePath, "Maker/Album/wrong-target.jpg")), "replacement is untouched");

        Check(catalog.RenameSourceItem(sourceId, "Maker/Album", "New Album", true, coverId) == "Maker/New Album",
            "indexed album folder renamed");
        Check(catalog.Read().Media.Single(item => item.FileName == "untouched.jpg").RelativePath == "Maker/Album2/untouched.jpg",
            "same-prefix sibling folder remains distinct");
        catalog.RenameSourceItem(sourceId, "Maker", "新创作者", true, coverId);
        catalog.Rescan(sourceId, MediaFiles.Scan(sourcePath, Layout.MultiCreator));
        var members = catalog.Read().AlbumMembers[albumId];
        Check(members.Select(item => item.Id).SequenceEqual([coverId, secondId]) &&
            members[0].RelativePath == "新创作者/New Album/新版封面.jpg",
            "renaming files and ancestors retains reference order and stable IDs after rescan");

        var nested = Path.Combine(sourcePath, "新创作者/Album2");
        catalog.Import(nested, Layout.Flat, MediaFiles.Scan(nested, Layout.Flat));
        var other = catalog.Read().Media.Single(item => item.Source.Id == sourceId && item.FileName == "untouched.jpg");
        Reject<IOException>(() => catalog.RenameSourceItem(sourceId, "新创作者", "Blocked", true, coverId), "nested registered root collision");
        Reject<IOException>(() => catalog.RenameSourceItem(sourceId, other.RelativePath, "Blocked", false, other.Id),
            "file also indexed by another source");

        var previous = Path.Combine(work, "previous-folder-name");
        AddFile(previous, "Future.jpg/Old.png");
        catalog.Import(previous, Layout.Creator, MediaFiles.Scan(previous, Layout.Creator));
        Directory.Move(Path.Combine(previous, "Future.jpg"), Path.Combine(work, "saved-fixture-folder"));
        AddFile(previous, "Direct.jpg");
        var flatId = catalog.Import(previous, Layout.Flat, MediaFiles.Scan(previous, Layout.Flat));
        var direct = catalog.Read().Media.Single(item => item.Source.Id == flatId && item.FileName == "Direct.jpg");
        Reject<IOException>(() => catalog.RenameSourceItem(flatId, direct.RelativePath, "Future", false, direct.Id),
            "an unavailable folder subtree reserves its historical name even for a file destination");
    }

    var source = new Source(sourceId, sourcePath, Layout.MultiCreator, Available: true);
    const string oldPath = "新创作者/New Album/second.png";
    const string newPath = "新创作者/New Album/Recovered.png";
    var identity = SourceRename.Identity(source, oldPath, isDirectory: false);
    WriteRenameIntent(indexPath, sourceId, oldPath, newPath, identity);
    using (var catalog = new Catalog(data))
    {
        Check(!catalog.HasPendingRename(sourceId) &&
              catalog.Read().Media.Single(item => item.Id == secondId).RelativePath == oldPath,
            "interrupted operation before a disk change preserves old path");
    }

    WriteRenameIntent(indexPath, sourceId, oldPath, newPath, identity);
    File.Move(Path.Combine(sourcePath, oldPath), Path.Combine(sourcePath, newPath));
    using (var catalog = new Catalog(data))
    {
        Check(!catalog.HasPendingRename(sourceId) &&
              catalog.Read().AlbumMembers[albumId].Single(item => item.Id == secondId).RelativePath == newPath,
            "interrupted operation after a disk change reconciles destination and preserves references");
    }

    WriteRenameIntent(indexPath, sourceId, newPath, oldPath, identity);
    AddFile(sourcePath, oldPath);
    using (var catalog = new Catalog(data))
    {
        Check(catalog.RenameRecoveryNotice is not null && catalog.HasPendingRename(sourceId), "ambiguous recovery is visible");
        Check(catalog.CurrentRenameNotice() == catalog.RenameRecoveryNotice, "pending rename blocks another editor");
        Reject<InvalidOperationException>(() => catalog.Rescan(sourceId, null), "ambiguous source cannot rescan");
        Check(File.Exists(Path.Combine(sourcePath, oldPath)) && File.Exists(Path.Combine(sourcePath, newPath)) &&
              catalog.Read().Media.Single(item => item.Id == secondId).RelativePath == newPath,
            "ambiguous recovery preserves both originals and the existing index");
    }
}

static void WriteRenameIntent(string index, long source, string before, string after, string identity)
{
    using var database = new Sqlite(index);
    database.Execute("""
        INSERT INTO pending_rename (id, source_id, old_path, new_path, is_directory, file_identity)
        VALUES (1, ?, ?, ?, 0, ?);
        """, source, before, after, identity);
}

static void Reject<T>(Action action, string name) where T : Exception
{
    try
    {
        action();
    }
    catch (T)
    {
        return;
    }
    throw new InvalidOperationException("Core check failed: " + name);
}
