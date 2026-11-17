using IPreview;

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
    Console.WriteLine("Windows catalog and search checks passed.");
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
