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
    CheckMediaSort(work);
    CheckNativeVideoFormats(work);
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

        var imported = catalog.Read();
        var items = imported.Media;
        try
        {
            catalog.CheckSourcePath(work);
            throw new InvalidOperationException("Core check failed: catalog overlap rejected");
        }
        catch (IOException) { }
        Check(items.Count == 4, "persisted import");
        var sourceList = imported.Sources.Values;
        var ordered = MediaSearch.Find(sourceList, items, new("城楼", false), GlobalSearchScope.Files)
            .Select(result => result.Media!).ToList();
        Check(ordered.Select(item => item.FileName).SequenceEqual(["城楼2.PNG", "城楼10.PNG"]),
            "natural file ordering");
        Check(MediaSearch.Find(sourceList, items, new("bj", false), GlobalSearchScope.Directories)
                .Any(result => result is { Folder: null, Name: "北京", Category: SearchResultCategory.Creator }),
            "a single-creator source matches its creator name by pinyin initials");
        Check(MediaSearch.Find(sourceList, items, new("beijing", false), GlobalSearchScope.Directories)
                .Any(result => result.Folder is null && result.Name == "北京"), "directory full pinyin");
        Check(MediaSearch.Find(sourceList, items, new("beijing", false), GlobalSearchScope.Files).Count == 0,
            "file scope excludes matching parent directories");
        Check(MediaSearch.Find(sourceList, items, new("sumer", false), GlobalSearchScope.Directories)
                .Any(result => result.Folder == "Summer 2/"), "directory typo");
        var directories = MediaSearch.Find(imported.Sources.Values, items, GlobalSearchTerm.Parse("@ Summer 2"),
            GlobalSearchScope.Directories);
        Check(directories.Count == 1 && directories[0] is
              { Folder: "Summer 2/", Media: null, Category: SearchResultCategory.Album },
            "global search shows a distinct directory hit");
        var flatSource = new Source(long.MaxValue, flat, Layout.Flat, true);
        Check(MediaSearch.Find([flatSource], [], new("flat", true), GlobalSearchScope.Directories)
                .Single().Category == SearchResultCategory.Album, "a flat source is a single album");
        Check(MediaSearch.Find(sourceList, items, new("catalog", true), GlobalSearchScope.Directories)
                .Single().Category == SearchResultCategory.Directory, "multi-creator source root remains a directory");
        Check(MediaSearch.Find(sourceList, items, new("Album", true), GlobalSearchScope.Directories)
                .Single() is { Folder: "Other/Album/", Category: SearchResultCategory.Album },
            "the album under a multi-creator source keeps its full path");
        Check(MediaSearch.Find(sourceList, items, new("Other", true), GlobalSearchScope.All)
                .Select(result => result.Category).SequenceEqual([SearchResultCategory.Creator, SearchResultCategory.File]),
            "same-name creator directory and media keep distinct categories and order");
        Check(GlobalSearchTerm.Parse("@") is { Text: "@", Exact: false }, "an at sign alone keeps fuzzy search");
        Check(GlobalSearchTerm.Parse("@clip") is { Text: "@clip", Exact: false }, "the prefix requires a space");
        Check(GlobalSearchTerm.Parse("@ ") is { Text.Length: 0, Exact: true }, "space activates exact mode before a name");
        var exactClip = GlobalSearchTerm.Parse("  ＠　ＣＬＩＰ.mov");
        var exactFiles = MediaSearch.Find(imported.Sources.Values, items, exactClip, GlobalSearchScope.Files);
        Check(exactFiles.Count == 1 && exactFiles[0] is { Media.FileName: "clip.MOV", Folder: "Summer 2/" },
            "global exact prefix permits normalized file names and returns the containing directory");
        Check(MediaSearch.Find(imported.Sources.Values, items, GlobalSearchTerm.Parse("@ clip"), GlobalSearchScope.Files)
                .Single().Name == "clip.MOV", "global exact file allows omitting the suffix");
        Check(MediaSearch.Find(imported.Sources.Values, items, GlobalSearchTerm.Parse("@ clip.png"), GlobalSearchScope.Files).Count == 0,
            "global exact file respects an explicit suffix");
        Check(MediaSearch.Find(imported.Sources.Values, items, GlobalSearchTerm.Parse("@ Summer"), GlobalSearchScope.Directories).Count == 0,
            "global exact directory requires its complete name");
        var dottedStem = items[0] with { RelativePath = "Summer 2/Frame.v2.jpg", IsVideo = false };
        Check(MediaSearch.Find(imported.Sources.Values, [dottedStem], GlobalSearchTerm.Parse("@ frame.v2"), GlobalSearchScope.Files)
                .Single().Name == "Frame.v2.jpg", "the file stem can contain dots");
        Check(MediaSearch.Find(imported.Sources.Values, items, exactClip, GlobalSearchScope.Directories).Count == 0,
            "global directory scope excludes matching files");

        var withinAlbum = items[0] with { RelativePath = "Other/Album/Shared.png" };
        var inSibling = items[0] with { RelativePath = "Other/Albums/Shared.png" };
        var outsideScope = items[0] with { RelativePath = "Shared.png" };
        Media[] scopedFixture = [withinAlbum, inSibling, outsideScope];
        Check(MediaSearch.Find(sourceList, scopedFixture, new("Shared", true), GlobalSearchScope.Files,
                "Other/Album/").Single().Media == withinAlbum,
            "current folder results exclude siblings and files outside the subtree");
        Check(MediaSearch.Find(sourceList, scopedFixture, new("Other", true), GlobalSearchScope.Directories,
                "Other/Album/").Count == 0, "current folder results exclude ancestors");
        Check(MediaSearch.Find(sourceList, scopedFixture, new("Album", true), GlobalSearchScope.Directories,
                "Other/Album/").Single().Folder == "Other/Album/",
            "current folder results include the selected folder");

        albumId = catalog.CreateAlbum("预览");
        firstId = ordered[0].Id;
        secondId = items.Single(item => item.FileName == "other.jpg").Id;
        catalog.AddToAlbum(albumId, firstId);
        var clipId = items.Single(item => item.IsVideo).Id;
        catalog.AppendToAlbum(albumId, [secondId, firstId, clipId, secondId]);
        Check(catalog.Read().AlbumMembers[albumId].Select(item => item.Id).SequenceEqual([firstId, secondId, clipId]),
            "batch append preserves existing and staged order and deduplicates");
        var badBatchFailed = false;
        try
        {
            catalog.AppendToAlbum(albumId, [ordered[1].Id, long.MaxValue]);
        }
        catch (InvalidOperationException)
        {
            badBatchFailed = true;
        }
        Check(badBatchFailed, "batch append fails for missing member ID");
        Check(catalog.Read().AlbumMembers[albumId].Select(item => item.Id).SequenceEqual([firstId, secondId, clipId]),
            "failed batch leaves no partial references");
        catalog.RemoveFromAlbum(albumId, [clipId]);
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

        var clip = snapshot.Media.Single(item => item.IsVideo);
        var retainedPhoto = snapshot.Media.Single(item => item.FileName == "城楼10.PNG");
        var batchAlbum = catalog.CreateAlbum("批量移除");
        long[] oldOrder = [secondId, firstId, clip.Id, retainedPhoto.Id];
        catalog.AppendToAlbum(batchAlbum, oldOrder);
        var removedFiles = new[] { online, clip }.Select(MediaFiles.OpenPath).ToArray();
        var originalTimes = removedFiles.Select(File.GetLastWriteTimeUtc).ToArray();
        catalog.MoveInAlbum(batchAlbum, retainedPhoto.Id, 0, oldOrder);
        Check(catalog.Read().AlbumMembers[batchAlbum].Select(item => item.Id)
            .SequenceEqual([retainedPhoto.Id, secondId, firstId, clip.Id]), "drag order persists across sources");
        Reject<AlbumOrderChangedException>(() => catalog.MoveInAlbum(batchAlbum, secondId, 2, oldOrder),
            "a stale drag leaves the current album order unchanged");
        catalog.RemoveFromAlbum(batchAlbum, [clip.Id, secondId]);
        using (var reopened = new Catalog(data))
        {
            var members = reopened.Read().AlbumMembers;
            Check(members[batchAlbum].Select(item => item.Id).SequenceEqual([retainedPhoto.Id, firstId]),
                "batch removal persists remaining album order");
            Check(members[albumId].Select(item => item.Id).SequenceEqual([secondId, firstId]),
                "batch removal preserves references in another album");
        }
        Check(removedFiles.All(path => File.ReadAllText(path) == "fixture") &&
              removedFiles.Select(File.GetLastWriteTimeUtc).SequenceEqual(originalTimes),
            "batch removal preserves original content and modification time");

        CheckAlbumDeletion(catalog, data, albumId, [firstId, secondId]);
        catalog.RemoveFromAlbum(albumId, [secondId]);
        Check(catalog.Read().AlbumMembers[albumId].Single().Id == firstId, "remove album reference");
        Check(File.Exists(MediaFiles.OpenPath(online)), "removing a reference preserves original");
    }
    CheckSourceAlbumOrganization(work);
    CheckSourceDeletion(work);
    CheckVideoWorks(work);
    CheckStructuralVideoWorks(work);
    CheckVideoWorkIndex(work);
    CheckLegacyVideoWorkRescan(work);
    CheckLegacyWorkAlbumOrganization(work);
    CheckSourceRename(work);
    Console.WriteLine("Windows catalog, search, preview navigation and source rename checks passed.");
}
finally
{
    Directory.Delete(work, recursive: true);
}

static void CheckNativeVideoFormats(string work)
{
    var source = Path.Combine(work, "native-video");
    foreach (var name in new[] { "clip.TS", "clip.MKV", "clip.WEBM", "clip.AVI", "clip.mkv.mov", "clip.flv" })
        AddFile(source, name);
    var probe = MediaFiles.Probe(source);
    var entries = probe.Options[Layout.Flat];
    Check(entries.Select(entry => entry.RelativePath).ToHashSet().SetEquals(["clip.TS", "clip.MKV", "clip.WEBM", "clip.AVI", "clip.mkv.mov"])
        && entries.All(entry => entry.IsVideo), "native extensions retain their video catalog type");
    using var catalog = new Catalog(Path.Combine(work, "native-video-db"));
    catalog.Import(source, Layout.Flat, entries);
    var library = catalog.Read();
    foreach (var extension in new[] { "ts", "mkv", "webm", "avi" })
    {
        var results = MediaSearch.Find(library.Sources.Values, library.Media, new("clip." + extension, true), GlobalSearchScope.Files);
        Check(results.Single().Name == "clip." + extension.ToUpperInvariant(), "native video suffix filters exact results");
    }
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

static void CheckSourceDeletion(string work)
{
    var removedPath = Path.Combine(work, "removed-source");
    var keptPath = Path.Combine(work, "kept-source");
    AddFile(removedPath, "photo.png");
    AddFile(keptPath, "one.png");
    AddFile(keptPath, "two.png");
    var data = Path.Combine(work, "removal-catalog");
    using var catalog = new Catalog(data);
    var kept = catalog.Import(keptPath, Layout.Flat, MediaFiles.Scan(keptPath, Layout.Flat));
    var removed = catalog.Import(removedPath, Layout.Flat, MediaFiles.Scan(removedPath, Layout.Flat));
    var media = catalog.Read().Media;
    var removedItem = media.Single(item => item.Source.Id == removed);
    var keptItems = media.Where(item => item.Source.Id == kept).Select(item => item.Id).Reverse().ToArray();
    var collection = catalog.CreateAlbum("Shared");
    catalog.AppendToAlbum(collection, [keptItems[0], removedItem.Id, keptItems[1]]);
    var tag = catalog.AddAlbumTag("Shared Tag", new(removed, ""));
    catalog.Rescan(removed, null);

    var stale = catalog.Read();
    using var otherWindow = new Catalog(data);
    otherWindow.CreateAlbum("Other");
    Reject<SourceDeletionChangedException>(() => catalog.DeleteSource(removed, stale.DataVersion),
        "a stale source deletion is rejected");
    var current = catalog.Read();
    Check(current.Sources.ContainsKey(removed), "a rejected deletion preserves the offline source");
    catalog.DeleteSource(removed, current.DataVersion);

    var after = otherWindow.Read();
    Check(after.Sources.Keys.SequenceEqual([kept]) && after.Media.Count == 2, "only the removed source is unindexed");
    Check(after.AlbumMembers[collection].Select(item => item.Id).SequenceEqual(keptItems),
        "shared album keeps remaining members in order");
    Check(otherWindow.ReadSourceAlbumsForTag(tag.Id).Count == 0, "removed source no longer matches tags");
    Check(File.ReadAllText(Path.Combine(removedPath, "photo.png")) == "fixture", "removing a source preserves the file");

    using var reopened = new Catalog(data);
    var reimported = reopened.Import(removedPath, Layout.Flat, MediaFiles.Scan(removedPath, Layout.Flat));
    var restored = reopened.Read();
    var newMedia = restored.Media.Single(item => item.Source.Id == reimported);
    Check(reimported > removed && newMedia.Id > removedItem.Id && newMedia.RelativePath == removedItem.RelativePath,
        "reimporting the same path after restart allocates new source and media identities");
    Check(restored.AlbumMembers[collection].Select(item => item.Id).SequenceEqual(keptItems),
        "reimport does not restore removed album references");
}

static void CheckAlbumDeletion(Catalog catalog, string data, long retained, long[] memberIds)
{
    var sourcePaths = catalog.Read().Media.Select(MediaFiles.OpenPath).ToArray();
    var originalTimes = sourcePaths.Select(File.GetLastWriteTimeUtc).ToArray();
    var deleted = catalog.CreateAlbum("Shared");
    catalog.AppendToAlbum(deleted, memberIds);
    using var external = new Sqlite(Path.Combine(data, "library.sqlite3"));
    external.ExecuteScript("""
        CREATE TRIGGER reject_member_delete BEFORE DELETE ON album_media
        BEGIN SELECT RAISE(ABORT, 'test member delete failure'); END;
        """);
    var beforeFailure = catalog.Read();
    try
    {
        catalog.DeleteAlbum(deleted, beforeFailure.DataVersion);
        throw new Exception("Core check failed: album deletion must report cascade failure");
    }
    catch (InvalidOperationException error)
    {
        Check(error.Message.Contains("test member delete failure"), "cascade reports database error");
    }
    var failed = catalog.Read();
    Check(failed.Albums.SequenceEqual(beforeFailure.Albums) &&
          failed.AlbumMembers[deleted].Select(item => item.Id).SequenceEqual(memberIds),
          "cascade failure preserves the album and all its references");
    external.ExecuteScript("DROP TRIGGER reject_member_delete;");

    var original = catalog.Read();
    using var otherWindow = new Catalog(data);
    otherWindow.DeleteAlbum(deleted, otherWindow.Read().DataVersion);
    var recreated = otherWindow.CreateAlbum("Shared");
    Check(recreated == deleted, "the fixture reuses a deleted album ID");
    Reject<AlbumDeletionChangedException>(() => catalog.DeleteAlbum(deleted, original.DataVersion),
        "a stale confirmation cannot delete the replacement album");
    var after = catalog.Read();
    Check(after.Albums.Any(album => album.Id == recreated) && !after.AlbumMembers.ContainsKey(recreated),
        "a recreated album has none of the deleted references");
    Check(after.AlbumMembers[retained].SequenceEqual(original.AlbumMembers[retained]) &&
          after.Media.SequenceEqual(original.Media), "deletion preserves other album order and media index");
    catalog.DeleteAlbum(recreated, after.DataVersion);
    Check(otherWindow.Read().Albums.All(album => album.Id != recreated), "deletion persists in another connection");
    Check(sourcePaths.All(path => File.ReadAllText(path) == "fixture") &&
          sourcePaths.Select(File.GetLastWriteTimeUtc).SequenceEqual(originalTimes),
        "deletion preserves source media contents and modification times");
}

static void CheckSourceAlbumOrganization(string work)
{
    var sourcePath = Path.Combine(work, "organization-source");
    foreach (var file in new[] { "Maker/Album/Image 2.png", "Maker/Album/Image 10.jpg", "Maker/Album/Clip.mp4",
                                "Maker/Album2/Image.png" })
        AddFile(sourcePath, file);
    var data = Path.Combine(work, "organization-db");
    Directory.CreateDirectory(data);
    var databasePath = Path.Combine(data, "library.sqlite3");
    using (var versionTwo = new Sqlite(databasePath))
    {
        foreach (var migration in new[] { "001-initial.sql", "002-pending-rename.sql" })
        {
            using var stream = typeof(Catalog).Assembly.GetManifestResourceStream("iPreview.Migrations." + migration)!;
            using var script = new StreamReader(stream);
            versionTwo.ExecuteScript(script.ReadToEnd());
        }
        versionTwo.Execute("INSERT INTO sources (id, path, layout) VALUES (4, ?, 'multi-creator');", sourcePath);
        versionTwo.ExecuteScript("""
            INSERT INTO media (id, source_id, relative_path, kind)
                VALUES (8, 4, 'Maker/Album/Image 2.png', 'image'), (9, 4, 'Maker/Album/Image 10.jpg', 'image'),
                       (10, 4, 'Maker/Album/Clip.mp4', 'video'), (11, 4, 'Maker/Album2/Image.png', 'image');
            INSERT INTO albums (id, name) VALUES (20, '旧版合集');
            INSERT INTO album_media VALUES (20, 8, 1), (20, 11, 0);
            """);
        Check(versionTwo.Query("PRAGMA user_version;", row => row.Number(0)).Single() == 2, "populated version two fixture");
    }

    var album = new SourceAlbumKey(4, "Maker/Album");
    var sibling = new SourceAlbumKey(4, "Maker/Album2");
    SourceAlbumTag trip;
    SourceAlbumTag scenic;
    using (var catalog = new Catalog(data))
    {
        var baseline = catalog.ReadSourceAlbumOrganization(album);
        Check(!baseline.Favorite && baseline.RatingHalf is null && baseline.ConfiguredCoverIds.Count == 0 &&
            baseline.EffectiveCoverIds.SequenceEqual([8L]), "default cover follows natural order after upgrade");
        catalog.SetFavorite(true, album);
        catalog.SetRatingHalf(0, album);
        catalog.SetRatingHalf(7, sibling);
        trip = catalog.AddAlbumTag("　 ＴＲＩＰ   图片 ", album);
        var duplicate = catalog.AddAlbumTag("trip 图片", sibling);
        Check(duplicate == trip && trip.Name == "TRIP 图片" && trip.NormalizedName == "trip 图片", "normalized tag identity");
        Check(SourceAlbumTag.NamesFrom("ΟΣ İ").Normalized == "οσ i\u0307", "normalized accented label identity");
        scenic = catalog.AddAlbumTag("风景", album);
        catalog.AddAlbumTag(trip.Id, sibling);
        Check(catalog.ReadSourceAlbumsForTag(trip.Id).SequenceEqual([album, sibling]), "tagged source album query");
        Reject<InvalidOperationException>(() => catalog.RenameTag(trip.Id, scenic.Name), "rename avoids tag identity collision");
        catalog.RenameTag(trip.Id, "旅行");
        catalog.ReplaceCover([9, 8], album);
        Reject<ArgumentException>(() => catalog.ReplaceCover([9, 11], album), "cover excludes same-prefix sibling");
        Reject<ArgumentException>(() => catalog.ReplaceCover([10], album), "cover excludes video");

        using var failure = new Sqlite(databasePath);
        failure.ExecuteScript("""
            CREATE TRIGGER reject_second_cover BEFORE INSERT ON source_album_cover_media
            WHEN NEW.position = 1 BEGIN SELECT RAISE(ABORT, 'fixture failure'); END;
            """);
        Reject<InvalidOperationException>(() => catalog.ReplaceCover([8, 9], album), "cover failure rolls back delete and first insert");
        failure.ExecuteScript("DROP TRIGGER reject_second_cover;");
    }

    using var reopened = new Catalog(data);
    var persisted = reopened.ReadSourceAlbumOrganization(album);
    var persistedSibling = reopened.ReadSourceAlbumOrganization(sibling);
    Check(persisted.Favorite && persisted.RatingHalf == 0 && persisted.Tags.Any(tag => tag.Name == "旅行"), "organization persists");
    Check(!persistedSibling.Favorite && persistedSibling.RatingHalf == 7, "half-star rating is independent");
    Check(persisted.ConfiguredCoverIds.SequenceEqual([9L, 8L]) && persisted.EffectiveCoverIds.SequenceEqual([9L, 8L]),
        "ordered cover survives restart and a failed replacement");
    var library = reopened.Read();
    Check(library.AlbumMembers[20].Select(media => media.Id).SequenceEqual([11L, 8L]), "v2 references and order preserved");
    var organizationIndex = reopened.ReadSourceAlbumIndex();
    Check(organizationIndex.ConfiguredCovers[album].SequenceEqual([9L, 8L]), "card cover order matches stored selection");
    Check(organizationIndex.FavoriteAlbums.SetEquals([album]) && organizationIndex.RatingsHalf.Count == 2 &&
        organizationIndex.RatingsHalf[album] == 0 && organizationIndex.RatingsHalf[sibling] == 7,
        "organization index preserves favorites and zero and half-star ratings");
    Check(organizationIndex.TagsFor(album).SequenceEqual(persisted.Tags) &&
        organizationIndex.TagsFor(sibling).SequenceEqual(persistedSibling.Tags), "organization index projects tags in display order");
    Check(SourceAlbumTag.Suggestions("旅", organizationIndex.Tags).Select(tag => tag.Id).SequenceEqual([trip.Id]),
        "tag suggestion uses the current display name");
    var filtered = MediaSearch.Find(library.Sources.Values, library.Media, new("", false), GlobalSearchScope.All,
        taggedAlbums: organizationIndex.TaggedAlbums[scenic.Id]);
    Check(filtered.Count == 4 && filtered.Count(hit => hit.Category == SearchResultCategory.Album) == 1 &&
        filtered.All(hit => hit.SourceAlbum == album), "tag scope includes only its album and member files");
    var filteredFiles = MediaSearch.Find(library.Sources.Values, library.Media, new("Image", false), GlobalSearchScope.Files,
        taggedAlbums: organizationIndex.TaggedAlbums[scenic.Id]);
    Check(filteredFiles.Count == 2 && filteredFiles.All(hit => hit.SourceAlbum == album),
        "filename search remains confined to tagged media");

    var other = reopened.AddAlbumTag("Other", sibling);
    var tagIndex = reopened.ReadSourceAlbumIndex();
    Check(tagIndex.AlbumsMatchingAnyTagIds(new HashSet<long> { scenic.Id, other.Id })?.SetEquals([album, sibling]) == true,
        "distinct tag memberships combine as a union");
    var overlapping = tagIndex.AlbumsMatchingAnyTagIds(new HashSet<long> { scenic.Id, other.Id, trip.Id });
    var unionAlbums = MediaSearch.Find(library.Sources.Values, library.Media, new("", false), GlobalSearchScope.Directories,
        taggedAlbums: overlapping);
    Check(unionAlbums.Count == 2 && unionAlbums.Select(hit => hit.SourceAlbum).ToHashSet().SetEquals([album, sibling]),
        "a tag-only search returns each matching source album once");
    var unionHits = MediaSearch.Find(library.Sources.Values, library.Media, new("Image", false), GlobalSearchScope.Files,
        taggedAlbums: overlapping);
    Check(unionHits.Count == 3 && unionHits.Select(hit => hit.SourceAlbum).ToHashSet().SetEquals([album, sibling]),
        "overlapping tags do not duplicate fuzzy file hits");
    var exact = MediaSearch.Find(library.Sources.Values, library.Media, new("Image.png", true), GlobalSearchScope.Files,
        taggedAlbums: overlapping);
    Check(exact.Count == 1 && exact[0].SourceAlbum == sibling, "tag union intersects exact filename and suffix");
    var unfiltered = tagIndex.AlbumsMatchingAnyTagIds(new HashSet<long>());
    var stale = tagIndex.AlbumsMatchingAnyTagIds(new HashSet<long> { long.MaxValue });
    Check(unfiltered is null && stale is { Count: 0 }, "empty selection and selection with no albums are distinct");
    Check(MediaSearch.Find(library.Sources.Values, library.Media, new("Image", false), GlobalSearchScope.Files,
        taggedAlbums: unfiltered).Count == 3 && MediaSearch.Find(library.Sources.Values, library.Media,
        new("Image", false), GlobalSearchScope.Files, taggedAlbums: stale).Count == 0, "stale tag selection does not expose unfiltered results");
    reopened.RemoveAlbumTag(other.Id, sibling);
    var unlinked = reopened.ReadSourceAlbumIndex();
    Check(unlinked.Tags.Contains(other) && unlinked.AlbumsMatchingAnyTagIds(new HashSet<long> { other.Id }) is { Count: 0 },
        "an existing tag without links filters out all albums");
    reopened.DeleteTag(other.Id);

    var coverPath = Path.Combine(sourcePath, "Maker/Album/Image 10.jpg");
    var outside = Path.Combine(work, "out-of-source.jpg");
    File.Move(coverPath, outside);
    reopened.Rescan(4, MediaFiles.Scan(sourcePath, Layout.MultiCreator));
    var fallback = reopened.ReadSourceAlbumOrganization(album);
    Check(fallback.ConfiguredCoverIds.SequenceEqual([9L, 8L]) && fallback.EffectiveCoverIds.SequenceEqual([8L]),
        "missing cover falls back without dropping configuration");
    File.Move(outside, coverPath);
    reopened.Rescan(4, MediaFiles.Scan(sourcePath, Layout.MultiCreator));
    Check(reopened.ReadSourceAlbumOrganization(album).EffectiveCoverIds.SequenceEqual([9L, 8L]), "returned cover restores order");
    AddFile(sourcePath, "Maker/Album/Later.png");
    reopened.Rescan(4, MediaFiles.Scan(sourcePath, Layout.MultiCreator));
    var upgraded = reopened.Read();
    Check(upgraded.Media.Single(item => item.FileName == "Later.png").Id > 11 &&
        upgraded.AlbumMembers[20].Select(item => item.Id).SequenceEqual([11L, 8L]),
        "migration keeps existing identities and appends new ones");
    reopened.Rescan(4, null);
    var offline = reopened.ReadSourceAlbumOrganization(album);
    Check(offline.ConfiguredCoverIds.SequenceEqual([9L, 8L]) && offline.EffectiveCoverIds.Count == 0, "offline cover configuration persists");

    reopened.SetRatingHalf(null, album);
    reopened.RemoveAlbumTag(trip.Id, album);
    Check(reopened.ReadSourceAlbumsForTag(trip.Id).SequenceEqual([sibling]), "detaching preserves other albums");
    reopened.DeleteTag(trip.Id);
    Check(reopened.ReadAlbumTags().SequenceEqual([scenic]) && reopened.ReadSourceAlbumsForTag(trip.Id).Count == 0, "global delete removes links");
    var cleared = reopened.ReadSourceAlbumOrganization(album);
    Check(cleared.Favorite && cleared.RatingHalf is null, "clearing rating preserves favorite");
    var clearedIndex = reopened.ReadSourceAlbumIndex();
    Check(clearedIndex.FavoriteAlbums.SetEquals([album]) && clearedIndex.RatingsHalf.Count == 1 && clearedIndex.RatingsHalf[sibling] == 7,
        "organization index omits a removed rating and preserves favorites");
    Check(clearedIndex.AlbumsMatchingAnyTagIds(new HashSet<long> { trip.Id }) is { Count: 0 }, "deleted tags do not match albums");
}

static void CheckVideoWorks(string root)
{
    foreach (var path in new[]
    {
        "Complete/视频/影片.mp4", "Complete/官方样张/样张.jpg",
        "Complete/附加写真集/写真集 10/封面.png", "Complete/附加写真集/写真集 10/图片.png",
        "Complete/附加写真集/写真集 2/封面.jpg", "Complete/附加写真集/写真集 2/图片.png",
        "Compact/影片.MOV", "Compact/官方样张.jpg", "Compact/其他.jpg",
        "Compact/附加写真集/图片 10.png", "Compact/附加写真集/图片 2.png",
        "Ordinary/影片.mp4", "Ordinary/其他.jpg",
    })
        AddFile(root, path);

    var completeRoot = Path.Combine(root, "Complete");
    AddFile(completeRoot, "视频/.隐藏.mp4");
    if (MediaFiles.ProbeVideoWork(completeRoot) is not VideoWorkRecognition.Recognized(var work))
        throw new InvalidOperationException("Core check failed: complete video work");
    Check(work.Structure == VideoWorkStructure.Complete && work.Video.RelativePath == "视频/影片.mp4", "complete work video");
    Check(work.Samples.Select(media => media.RelativePath).SequenceEqual(["官方样张/样张.jpg"]), "complete work samples");
    Check(work.PhotoSets.Select(book => book.RelativePath).SequenceEqual(["附加写真集/写真集 2", "附加写真集/写真集 10"]),
        "complete work photo sets");
    Check(work.PhotoSets[0].Cover?.RelativePath == "附加写真集/写真集 2/封面.jpg" &&
        work.PhotoSets[1].Photos.Select(media => media.RelativePath).SequenceEqual(["附加写真集/写真集 10/图片.png"]),
        "complete work cover and photos");

    var compactRoot = Path.Combine(root, "Compact");
    if (MediaFiles.ProbeVideoWork(compactRoot) is not VideoWorkRecognition.Recognized(var flat))
        throw new InvalidOperationException("Core check failed: compact video work");
    Check(flat.Structure == VideoWorkStructure.Compact && flat.Video.RelativePath == "影片.MOV", "compact work video");
    Check(flat.Samples.Select(media => media.RelativePath).SequenceEqual(["官方样张.jpg"]), "compact work samples");
    var compactBook = flat.PhotoSets.Single();
    Check(compactBook.Cover is null && compactBook.Photos.Select(media => media.RelativePath)
        .SequenceEqual(["附加写真集/图片 2.png", "附加写真集/图片 10.png"]), "compact work flat photo set");

    var ordinary = Path.Combine(root, "Ordinary");
    Check(MediaFiles.ProbeVideoWork(ordinary) is VideoWorkRecognition.Unrecognized &&
        MediaFiles.Probe(ordinary).Options.Keys.Single() == Layout.Flat, "ordinary videos remain in the generic album");
    AddFile(compactRoot, "第二个影片.mp4");
    Check(MediaFiles.ProbeVideoWork(compactRoot) is VideoWorkRecognition.Ambiguous, "ambiguous main video");
    AddFile(completeRoot, "附加写真集/写真集 2/封面.png");
    Check(MediaFiles.ProbeVideoWork(completeRoot) is VideoWorkRecognition.Ambiguous, "ambiguous photo set cover");
}

static void CheckStructuralVideoWorks(string root)
{
    var parent = Path.Combine(root, "Structural works");
    foreach (var file in new[]
    {
        "album/video.mp4", "album/pictures/1.png", "album/pictures/2.png",
        "seventeen/movie.MKV", "seventeen/Photos/.hidden.jpg",
        "boxed/Screen/main.mp4", "boxed/Screen/behind-the-scenes.png",
        "boxed/Extras/Book 2/p1.png", "boxed/Extras/Book 10/p2.jpg",
        "boxed/Sample cards/promo.png", "boxed/ordinary.jpg",
        "books/Disc/main.mov", "books/Pages/Set A/front.jpg",
        "Ordinary album/frame.png"
    })
        AddFile(parent, file);
    foreach (var number in Enumerable.Range(1, 17).Reverse())
        AddFile(parent, $"seventeen/Photos/{number}.png");

    var exact = MediaFiles.Probe(Path.Combine(parent, "album")).Options[Layout.Flat];
    Check(exact.Count == 3 && exact.Count(file => file.VideoWork is VideoWorkMembership.Video) == 1,
        "the minimal arbitrary-name compact work imports three files at the root album level");

    var summary = MediaFiles.Probe(parent);
    Check(summary.Options.Keys.Single() == Layout.Creator, "sibling works and an ordinary album share the parent layout");
    var data = Path.Combine(root, "structural-works-index");
    long source;
    using (var catalog = new Catalog(data))
        source = catalog.Import(summary.Path, Layout.Creator, summary.Options[Layout.Creator]);

    using var reopened = new Catalog(data);
    var snapshot = reopened.Read();
    Check(snapshot.VideoWorks.Select(work => work.RelativePath).ToHashSet().SetEquals(["album", "seventeen", "boxed", "books"]),
        "arbitrary-name works are persisted individually");
    var minimal = snapshot.VideoWorks.Single(work => work.RelativePath == "album");
    Check(minimal.Structure == VideoWorkStructure.Compact && minimal.Samples.Count == 0 &&
        minimal.PhotoSets.Single().Title == "pictures" && minimal.PhotoSets.Single().Photos
            .Select(photo => photo.FileName).SequenceEqual(["1.png", "2.png"]),
        "a work without samples retains the disk and the named picture group");
    var many = snapshot.VideoWorks.Single(work => work.RelativePath == "seventeen");
    Check(many.Samples.Count == 0 &&
        many.PhotoSets.Single().Photos.Select(photo => photo.FileName).SequenceEqual(
            Enumerable.Range(1, 17).Select(number => $"{number}.png")), "a sample-free work with 17 photos in natural order");
    var complete = snapshot.VideoWorks.Single(work => work.RelativePath == "boxed");
    Check(complete.Structure == VideoWorkStructure.Complete && complete.Samples.Single().FileName == "promo.png" &&
        complete.PhotoSets.Select(book => book.Title).SequenceEqual(["Book 2", "Book 10"]) &&
        complete.PhotoSets.All(book => book.Cover is null), "complete work recognizes arbitrary directory names and optional covers");
    var noSamples = snapshot.VideoWorks.Single(work => work.RelativePath == "books");
    Check(noSamples.Samples.Count == 0 && noSamples.PhotoSets.Single().Photos.Single().FileName == "front.jpg",
        "complete work accepts a book without a dedicated cover or samples");
    Check(snapshot.Media.Count(item => item.RelativePath is "boxed/ordinary.jpg" or "boxed/Screen/behind-the-scenes.png") == 2 &&
        snapshot.Media.Single(item => item.RelativePath == "Ordinary album/frame.png").WorkAlbumPath is null,
        "work import retains non-group media and an ordinary album remains independent");

    AddFile(parent, "album/pictures/10.png");
    AddFile(parent, "seventeen/alphabetical.jpg");
    reopened.Rescan(source, MediaFiles.Scan(parent, Layout.Creator));
    var rescanned = reopened.Read();
    var updated = rescanned.VideoWorks.Single(work => work.RelativePath == "album");
    Check(updated.Video.Id == minimal.Video.Id && updated.Samples.Count == 0 &&
        updated.PhotoSets.Single().Photos.Select(photo => photo.FileName).SequenceEqual(["1.png", "2.png", "10.png"]),
        "rescan keeps a sample-free work and refreshes its picture group");
    Check(rescanned.VideoWorks.Single(work => work.Video.Id == many.Video.Id)
        .Samples.Single().FileName == "alphabetical.jpg", "rescan adds a single optional root sample");
    var available = rescanned.Media.Where(item => item.Present).ToDictionary(item => item.RelativePath, item => item.Id);
    Check(snapshot.Media.All(item => available.TryGetValue(item.RelativePath, out var id) && id == item.Id),
        "rescan preserves work, ordinary media and their identities");

    var ordinary = Path.Combine(root, "Ordinary creators");
    AddFile(ordinary, "Photos A/1.png");
    AddFile(ordinary, "Photos B/2.png");
    var ordinaryFiles = MediaFiles.Probe(ordinary).Options[Layout.Creator];
    Check(ordinaryFiles.Count == 2 && ordinaryFiles.All(file => file.VideoWork is null),
        "an ordinary picture collection keeps its independent albums");
    var split = Path.Combine(root, "Separate albums");
    AddFile(split, "Video album/movie.mp4");
    AddFile(split, "Picture album/1.png");
    var splitFiles = MediaFiles.Probe(split).Options[Layout.Creator];
    Check(splitFiles.Count == 2 && splitFiles.All(file => file.VideoWork is null),
        "adjacent video and picture albums without nested books are independent");
    AddFile(ordinary, "movie.mp4");
    Check(MediaFiles.ProbeVideoWork(ordinary) is VideoWorkRecognition.Ambiguous,
        "a root video with competing photo folders is ambiguous");
}

static void CheckLegacyVideoWorkRescan(string root)
{
    using var catalog = new Catalog(Path.Combine(root, "legacy-works-index"));
    (string Directory, Layout Layout, string Work, string[] Previous, string Added)[] cases =
    [
        ("Legacy Multi", Layout.MultiCreator, "Work",
            ["Work/视频/movie.mp4", "Work/视频/幕后.jpg", "Work/官方样张/sample.jpg", "Maker/Album/keep.png"],
            "Work/附加写真集/写真集/图片.png"),
        ("Legacy Creator", Layout.Creator, "",
            ["视频/movie.mp4", "视频/幕后.jpg", "官方样张/sample.jpg"],
            "附加写真集/写真集/图片.png"),
        ("Legacy Flat", Layout.Flat, "",
            ["movie.mp4", "官方样张.jpg", "keep.png"], "附加写真集/图片.png")
    ];

    foreach (var test in cases)
    {
        var path = Path.Combine(root, test.Directory);
        foreach (var file in test.Previous)
            AddFile(path, file);
        var inspection = MediaFiles.Probe(path);
        var source = catalog.Import(inspection.Path, test.Layout, inspection.Options[test.Layout]);
        var before = catalog.Read();
        var original = before.Media.Where(item => item.Source.Id == source).ToArray();
        Check(original.Any(item => item.FileName == "movie.mp4") &&
            before.VideoWorks.All(work => work.Video.Source.Id != source), "legacy media exists before work recognition");

        AddFile(path, test.Added);
        catalog.Rescan(source, MediaFiles.Scan(path, test.Layout));
        var rescanned = catalog.Read();
        var result = rescanned.VideoWorks.Single(work => work.Video.Source.Id == source);
        Check(result.RelativePath == test.Work && result.Video.Source.Layout == test.Layout, "rescan recognizes work without changing layout");
        Check(result.Samples.Count == 1 && result.PhotoSets.Single().Photos.Count == 1, "rescan indexes all work roles");
        var available = rescanned.Media.Where(item => item.Source.Id == source && item.Present)
            .ToDictionary(item => item.RelativePath, item => item.Id);
        Check(original.All(item => available.TryGetValue(item.RelativePath, out var id) && id == item.Id),
            "rescan preserves legacy depth and media identities");
    }
}

static void CheckVideoWorkIndex(string root)
{
    var works = Path.Combine(root, "Works");
    var compact = Path.Combine(root, "Compact-index");
    const string complete = "Maker/Complete/";
    foreach (var name in new[] { "视频/影片.mp4", "官方样张/样张.jpg", "附加写真集/图册 2/封面.jpg", "附加写真集/图册 2/照片 1.jpg" })
        AddFile(works, complete + name);
    foreach (var name in new[] { "影片.mov", "官方样张.jpg", "附加写真集/照片 2.png" })
        AddFile(compact, name);

    var data = Path.Combine(root, "works-index");
    using (var catalog = new Catalog(data))
    {
        foreach (var (path, layout) in new[] { (works, Layout.MultiCreator), (compact, Layout.Flat) })
        {
            var summary = MediaFiles.Probe(path);
            Check(summary.Options.Keys.Single() == layout, "work imports using its source album level");
            catalog.Import(summary.Path, layout, summary.Options[layout]);
        }
    }
    using var reopened = new Catalog(data);
    var snapshot = reopened.Read();
    var nested = snapshot.VideoWorks.Single(work => work.Structure == VideoWorkStructure.Complete);
    var flat = snapshot.VideoWorks.Single(work => work.Structure == VideoWorkStructure.Compact);
    Check(nested.RelativePath == "Maker/Complete" && nested.Samples.Single().FileName == "样张.jpg" &&
        nested.PhotoSets.Single().Cover?.FileName == "封面.jpg", "nested work and its roles survive restart");
    Check(flat.RelativePath.Length == 0 && flat.PhotoSets.Single().Cover is null, "compact flat photo set survives restart");

    var completeAlbum = SourceAlbumKey.FromMedia(nested.Video);
    var compactAlbum = SourceAlbumKey.FromMedia(flat.Video);
    long[] completeCover = [nested.Samples[0].Id, nested.PhotoSets[0].Photos[0].Id];
    long[] compactCover = [flat.PhotoSets[0].Photos[0].Id];
    var worksTag = reopened.AddAlbumTag("作品", completeAlbum);
    reopened.AddAlbumTag(worksTag.Id, compactAlbum);
    reopened.ReplaceCover(completeCover, completeAlbum);
    reopened.ReplaceCover(compactCover, compactAlbum);
    var completeSettings = reopened.ReadSourceAlbumOrganization(completeAlbum);
    var compactSettings = reopened.ReadSourceAlbumOrganization(compactAlbum);
    Check(completeSettings.EffectiveCoverIds.SequenceEqual(completeCover) &&
        compactSettings.EffectiveCoverIds.SequenceEqual(compactCover), "nested work images serve as ordered album covers");
    Check(completeSettings.Tags.SequenceEqual([worksTag]) && compactSettings.Tags.SequenceEqual([worksTag]),
        "both work structures can be tagged at album level");

    var tagged = reopened.ReadSourceAlbumIndex().TaggedAlbums[worksTag.Id];
    var taggedPhotos = MediaSearch.Find(snapshot.Sources.Values, snapshot.Media, new("照片", false),
        GlobalSearchScope.Files, taggedAlbums: tagged);
    Check(taggedPhotos.Count == 2 && taggedPhotos.Select(hit => hit.SourceAlbum).ToHashSet()
        .SetEquals([completeAlbum, compactAlbum]), "tagged album search includes nested photos for both work structures");
    var intermediate = new SourceAlbumKey(nested.Video.Source.Id, nested.RelativePath + "/官方样张");
    Reject<InvalidOperationException>(() => reopened.SetFavorite(true, intermediate),
        "an intermediate work directory cannot be organized as an album");

    reopened.Rescan(nested.Video.Source.Id, null);
    Check(!reopened.Read().VideoWorks.Single(work => work.Video.Id == nested.Video.Id).Video.Available,
        "unavailable source retains the indexed work");
    AddFile(works, complete + "附加写真集/图册 2/照片 2.jpg");
    var scanned = MediaFiles.Scan(works, Layout.MultiCreator);
    reopened.Rescan(nested.Video.Source.Id, scanned);
    var updated = reopened.Read().VideoWorks.Single(work => work.Video.Id == nested.Video.Id);
    Check(updated.Video.Available && updated.PhotoSets.Single().Photos.Select(item => item.FileName)
        .SequenceEqual(["照片 1.jpg", "照片 2.jpg"]), "rescan keeps identity and updates photo membership");
    Check(scanned.All(file => File.ReadAllText(Path.Combine(works, file.RelativePath)) == "fixture"),
        "work indexing preserves source media");
}

static void CheckLegacyWorkAlbumOrganization(string work)
{
    var source = Path.Combine(work, "legacy-work-albums");
    foreach (var name in new[] { "Complete/视频/影片.mp4", "Complete/官方样张/样张.jpg", "Complete/附加写真集/写真/封面.jpg",
                                "Complete/附加写真集/写真/完整照片.jpg", "Compact/影片.mov", "Compact/官方样张.jpg",
                                "Compact/附加写真集/简化照片.jpg" })
        AddFile(source, name);
    var found = MediaFiles.Probe(source);
    var data = Path.Combine(work, "legacy-work-albums-db");
    using var catalog = new Catalog(data);
    // Model the indexed rows after a legacy multi-creator source recognizes its shallow works.
    var sourceId = catalog.Import(found.Path, Layout.MultiCreator, found.Options[Layout.Creator]);
    var snapshot = catalog.Read();
    var complete = snapshot.VideoWorks.Single(item => item.Structure == VideoWorkStructure.Complete);
    var compact = snapshot.VideoWorks.Single(item => item.Structure == VideoWorkStructure.Compact);
    var completeKey = new SourceAlbumKey(sourceId, "Complete");
    var compactKey = new SourceAlbumKey(sourceId, "Compact");
    var completePhoto = complete.PhotoSets[0].Photos[0];
    var compactPhoto = compact.PhotoSets[0].Photos[0];
    Check(SourceAlbumKey.FromMedia(completePhoto) == completeKey && SourceAlbumKey.FromMedia(compactPhoto) == compactKey,
        "shallow work photos use the indexed work album root");
    var tag = catalog.AddAlbumTag("浅层作品", completeKey);
    catalog.AddAlbumTag(tag.Id, compactKey);
    catalog.ReplaceCover([completePhoto.Id, complete.Samples[0].Id], completeKey);
    catalog.ReplaceCover([compactPhoto.Id], compactKey);
    var collectionId = catalog.CreateAlbum("作品选片");
    catalog.AppendToAlbum(collectionId, [compactPhoto.Id]);
    Reject<InvalidOperationException>(() => catalog.SetFavorite(true, new(sourceId, "Complete/官方样张")),
        "a nominal-depth internal folder is not a work album");

    using var reopened = new Catalog(data);
    var loaded = reopened.Read();
    var albumIndex = reopened.ReadSourceAlbumIndex();
    var tagged = albumIndex.TaggedAlbums[tag.Id];
    var albums = MediaSearch.Find(loaded.Sources.Values, loaded.Media, new("", false), GlobalSearchScope.Directories,
        taggedAlbums: tagged);
    Check(albums.Count == 2 && albums.Select(hit => hit.SourceAlbum).ToHashSet().SetEquals([completeKey, compactKey]),
        "tagged directory results use shallow work album roots");
    var group = MediaSearch.Find(loaded.Sources.Values, loaded.Media, new("官方样张", true), GlobalSearchScope.Directories).Single();
    Check(group.Category == SearchResultCategory.Directory && group.SourceAlbum is null,
        "work subdirectories retain their directory classification");

    var selectedAlbums = albumIndex.AlbumsMatchingAnyTagIds(new HashSet<long> { tag.Id, long.MaxValue });
    Check(MediaSearch.Find(loaded.Sources.Values, loaded.Media, new("官方样张", true), GlobalSearchScope.Directories,
        taggedAlbums: selectedAlbums).Count == 0, "tag selection does not expose internal work directories");
    var collectionHits = MediaSearch.Find(loaded.Sources.Values, loaded.AlbumMembers[collectionId],
        new("照片", false), GlobalSearchScope.Files, taggedAlbums: selectedAlbums);
    Check(collectionHits.Single() is { Media: { } selectedMedia } &&
        selectedMedia.Id == compactPhoto.Id && collectionHits[0].SourceAlbum == compactKey,
        "collection search preserves the selected shallow work photo and its tag scope");

    foreach (var (photo, key) in new[] { (completePhoto, completeKey), (compactPhoto, compactKey) })
    {
        var hit = MediaSearch.Find(loaded.Sources.Values, loaded.Media, new(photo.FileName, true), GlobalSearchScope.Files,
            taggedAlbums: tagged).Single();
        Check(hit.Media?.Id == photo.Id && hit.SourceAlbum == key, "search selects the original media in its work album");
        var organization = reopened.ReadSourceAlbumOrganization(key);
        Check(organization.Tags.SequenceEqual([tag]) && organization.EffectiveCoverIds[0] == photo.Id,
            "work tags and cover survive reopening");
    }
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
        using (var organization = new Sqlite(indexPath))
        {
            organization.Execute("""
                INSERT INTO source_album_organization (id, source_id, album_path, favorite, rating_half)
                    VALUES (101, ?, 'Maker/Album', 1, 0), (102, ?, 'Maker/Album2', 0, NULL);
                """, sourceId, sourceId);
            organization.Execute("INSERT INTO tags (id, name, normalized_name) VALUES (103, 'Travel', 'travel');");
            organization.Execute("INSERT INTO source_album_tags VALUES (101, 103);");
            organization.Execute("INSERT INTO source_album_cover_media VALUES (101, ?, 0), (101, ?, 1);", coverId, secondId);
        }

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
        using (var organization = new Sqlite(indexPath))
        {
            var identifiers = organization.Query("""
                SELECT id FROM source_album_organization WHERE
                    (album_path = '新创作者/New Album' AND favorite = 1 AND rating_half = 0)
                    OR (album_path = '新创作者/Album2' AND favorite = 0 AND rating_half IS NULL)
                ORDER BY id;
                """, row => row.Number(0));
            Check(identifiers.SequenceEqual([101L, 102L]), "album organization follows folder and creator renames");
            Check(organization.Query("SELECT tag_id FROM source_album_tags WHERE source_album_id = 101;",
                row => row.Number(0)).SequenceEqual([103L]), "album tag stays linked");
            Check(organization.Query("SELECT media_id FROM source_album_cover_media WHERE source_album_id = 101 ORDER BY position;",
                row => row.Number(0)).SequenceEqual([coverId, secondId]), "cover order stays linked");
        }

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

static void CheckMediaSort(string work)
{
    var root = Directory.CreateDirectory(Path.Combine(work, "Sort")).FullName;
    var source = new Source(1, root, Layout.Flat, Available: true);
    var early = DateTime.UnixEpoch.AddHours(1);
    var late = early.AddHours(1);
    (string Name, int Size, DateTime Modified)[] fixtures =
        [("1.png", 20, late), ("2.png", 20, early), ("10.png", 3, early), ("20.png", 10, late)];
    var items = fixtures.Select((fixture, index) =>
    {
        var path = Path.Combine(root, fixture.Name);
        File.WriteAllBytes(path, new byte[fixture.Size]);
        File.SetLastWriteTimeUtc(path, fixture.Modified);
        return new Media(index + 1, source, fixture.Name, IsVideo: false, Present: true);
    }).Reverse().ToArray();
    File.Move(Path.Combine(root, "20.png"), Path.Combine(work, "unavailable.png"));

    IEnumerable<string> Names(MediaSortField field, bool descending = false) =>
        new MediaSort(field, descending).Arrange(items, item => item).Select(item => item.FileName);

    Check(new MediaSort().Arrange(items, item => item).SequenceEqual(items), "original file order");
    Check(Names(MediaSortField.Name).SequenceEqual(["1.png", "2.png", "10.png", "20.png"]), "natural name sort");
    Check(Names(MediaSortField.Name, true).SequenceEqual(["20.png", "10.png", "2.png", "1.png"]), "descending name sort");
    Check(Names(MediaSortField.Size).SequenceEqual(["10.png", "1.png", "2.png", "20.png"]), "sort by file bytes");
    Check(Names(MediaSortField.Size, true).SequenceEqual(["1.png", "2.png", "10.png", "20.png"]), "descending bytes with missing last");
    Check(Names(MediaSortField.Modified).SequenceEqual(["2.png", "10.png", "1.png", "20.png"]), "sort by modification date");
    Check(Names(MediaSortField.Modified, true).SequenceEqual(["1.png", "2.png", "10.png", "20.png"]), "descending dates with missing last");
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
