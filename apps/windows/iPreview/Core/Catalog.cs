using System.Reflection;

namespace IPreview;

internal sealed record CatalogSnapshot(
    Dictionary<long, Source> Sources, List<Media> Media, List<Album> Albums,
    Dictionary<long, List<Media>> AlbumMembers, long DataVersion);

internal sealed class AlbumOrderChangedException() :
    InvalidOperationException("合集顺序已在其他窗口更新。请按当前顺序重新拖动。");

internal sealed class AlbumDeletionChangedException() :
    InvalidOperationException("媒体库已在其他窗口更新。请核对合集后重试。");

internal sealed partial class Catalog : IDisposable
{
    private static readonly string[] Migrations = ["001-initial.sql", "002-pending-rename.sql"];
    private readonly Sqlite database;
    private readonly string dataDirectory;

    public Catalog(string dataDirectory)
    {
        this.dataDirectory = Path.TrimEndingDirectorySeparator(Path.GetFullPath(dataDirectory));
        Directory.CreateDirectory(this.dataDirectory);
        database = new Sqlite(Path.Combine(this.dataDirectory, "library.sqlite3"));
        try
        {
            database.InTransaction(() =>
            {
                var version = database.Query("PRAGMA user_version;", row => row.Number(0)).Single();
                if (version < 0 || version > Migrations.Length)
                    throw new InvalidDataException("该媒体库由更高版本的 iPreview 创建。");

                foreach (var migration in Migrations.Skip((int)version))
                {
                    using var resource = Assembly.GetExecutingAssembly()
                        .GetManifestResourceStream("iPreview.Migrations." + migration)
                        ?? throw new InvalidOperationException("The shared catalog migration was not embedded: " + migration);
                    using var reader = new StreamReader(resource);
                    database.ExecuteScript(reader.ReadToEnd());
                }
            });
            RecoverSourceRename();
        }
        catch
        {
            database.Dispose();
            throw;
        }
    }

    public void CheckSourcePath(string path)
    {
        path = Path.TrimEndingDirectorySeparator(Path.GetFullPath(path));
        if (Contains(path, dataDirectory) || Contains(dataDirectory, path))
            throw new IOException("请选取媒体文件夹。应用数据目录及其父子目录不可导入。");
    }

    private static bool Contains(string parent, string child)
    {
        var relative = Path.GetRelativePath(parent, child);
        return !Path.IsPathRooted(relative)
            && !relative.Equals("..", StringComparison.Ordinal)
            && !relative.StartsWith(".." + Path.DirectorySeparatorChar, StringComparison.Ordinal);
    }

    public CatalogSnapshot Read()
    {
        CatalogSnapshot? snapshot = null;
        database.InTransaction(() =>
        {
            var sources = database.Query("SELECT id, path, layout, available FROM sources;", row =>
            {
                var path = row.Text(1);
                return new Source(row.Number(0), path, MediaFiles.DecodeLayout(row.Text(2)),
                    row.Number(3) != 0 && MediaFiles.IsLocalRootAvailable(path));
            }).ToDictionary(source => source.Id);
            var media = database.Query("SELECT id, source_id, relative_path, kind, available FROM media;", row =>
                new Media(row.Number(0), sources[row.Number(1)], row.Text(2), row.Text(3) == "video", row.Number(4) != 0));
            var albums = database.Query("SELECT id, name FROM albums ORDER BY name COLLATE NOCASE, id;",
                row => new Album(row.Number(0), row.Text(1)));
            var mediaById = media.ToDictionary(item => item.Id);
            var members = database.Query(
                "SELECT album_id, media_id FROM album_media ORDER BY position, media_id;",
                row => (Album: row.Number(0), Media: mediaById[row.Number(1)]))
                .GroupBy(member => member.Album)
                .ToDictionary(album => album.Key, album => album.Select(member => member.Media).ToList());
            snapshot = new(sources, media, albums, members, DataVersion);
        }, write: false);
        return snapshot!;
    }

    public long DataVersion => database.Query("PRAGMA data_version;", row => row.Number(0)).Single();

    public long Import(string path, Layout layout, List<ScannedMedia> files, long? scanVersion = null)
    {
        CheckSourcePath(path);
        long id = 0;
        database.InTransaction(() =>
        {
            EnsureCurrentScan(scanVersion);
            EnsureImportOutsidePendingRename(path);
            var existing = database.Query("SELECT id, path FROM sources;", row => (row.Number(0), row.Text(1)))
                .Find(source => StringComparer.OrdinalIgnoreCase.Equals(source.Item2, path));
            id = existing.Item1;
            if (id == 0)
            {
                database.Execute("INSERT INTO sources (path, layout) VALUES (?, ?);", path, MediaFiles.Store(layout));
                id = database.Query("SELECT last_insert_rowid();", row => row.Number(0)).Single();
            }
            else
            {
                database.Execute("UPDATE sources SET path = ?, layout = ? WHERE id = ?;",
                    path, MediaFiles.Store(layout), id);
            }
            ReplaceScan(id, files);
        });
        return id;
    }

    public void Rescan(long source, List<ScannedMedia>? files, long? scanVersion = null)
    {
        database.InTransaction(() =>
        {
            EnsureCurrentScan(scanVersion);
            if (HasPendingRename(source))
                throw new InvalidOperationException("此媒体源有待恢复的重命名，暂时无法重新扫描。");
            if (files is null)
                database.Execute("UPDATE sources SET available = 0 WHERE id = ?;", source);
            else
                ReplaceScan(source, files);
        });
    }

    private void EnsureCurrentScan(long? scanVersion)
    {
        if (scanVersion is long version && version != DataVersion)
            throw new InvalidOperationException("另一个 iPreview 窗口在扫描期间修改了媒体库，请重试。");
    }

    private void ReplaceScan(long source, List<ScannedMedia> files)
    {
        database.Execute("UPDATE sources SET available = 1 WHERE id = ?;", source);
        database.Execute("UPDATE media SET available = 0 WHERE source_id = ?;", source);
        foreach (var file in files)
        {
            var kind = file.IsVideo ? "video" : "image";
            database.Execute("""
                INSERT INTO media (source_id, relative_path, kind) VALUES (?, ?, ?)
                ON CONFLICT (source_id, relative_path) DO UPDATE SET kind = excluded.kind, available = 1;
                """, source, file.RelativePath, kind);
        }
    }

    public long CreateAlbum(string name, long? media = null)
    {
        long id = 0;
        database.InTransaction(() =>
        {
            database.Execute("INSERT INTO albums (name) VALUES (?);", name.Trim());
            id = database.Query("SELECT last_insert_rowid();", row => row.Number(0)).Single();
            if (media is long member)
                InsertAlbumMember(id, member, 0);
        });
        return id;
    }

    public void RenameAlbum(long album, string name) =>
        database.Execute("UPDATE albums SET name = ? WHERE id = ?;", name.Trim(), album);

    public void DeleteAlbum(long album, long expectedDataVersion) =>
        database.InTransaction(() =>
        {
            // A deleted SQLite row ID can be reused by a new album in another process.
            if (expectedDataVersion != DataVersion)
                throw new AlbumDeletionChangedException();
            database.Execute("DELETE FROM albums WHERE id = ?;", album);
        });

    public void AddToAlbum(long album, long media) => AppendToAlbum(album, [media]);

    public void AppendToAlbum(long album, IReadOnlyList<long> media) =>
        database.InTransaction(() =>
        {
            var position = database.Query(
                "SELECT COALESCE(MAX(position) + 1, 0) FROM album_media WHERE album_id = ?;",
                row => row.Number(0), album).Single();
            foreach (var member in media)
                InsertAlbumMember(album, member, position++);
        });

    private void InsertAlbumMember(long album, long media, long position) =>
        database.Execute("""
            INSERT OR IGNORE INTO album_media (album_id, media_id, position) VALUES (?, ?, ?);
            """, album, media, position);

    public void RemoveFromAlbum(long album, IReadOnlyCollection<long> media) =>
        database.InTransaction(() =>
        {
            foreach (var member in media)
                database.Execute("DELETE FROM album_media WHERE album_id = ? AND media_id = ?;", album, member);
        });

    public void MoveInAlbum(long album, long media, int offset) =>
        database.InTransaction(() =>
        {
            var members = AlbumPositions(album);
            var current = members.FindIndex(member => member.Media == media);
            var next = current + offset;
            if (current < 0 || next < 0 || next >= members.Count)
                return;
            database.Execute("UPDATE album_media SET position = ? WHERE album_id = ? AND media_id = ?;",
                members[next].Position, album, media);
            database.Execute("UPDATE album_media SET position = ? WHERE album_id = ? AND media_id = ?;",
                members[current].Position, album, members[next].Media);
        });

    public void MoveInAlbum(long album, long media, int target, IReadOnlyList<long> expectedOrder) =>
        database.InTransaction(() =>
        {
            var order = AlbumPositions(album).Select(member => member.Media).ToList();
            if (!order.SequenceEqual(expectedOrder))
                throw new AlbumOrderChangedException();
            var source = order.IndexOf(media);
            if (source < 0 || source == target || target < 0 || target >= order.Count)
                return;
            order.RemoveAt(source);
            order.Insert(target, media);
            for (var position = 0; position < order.Count; position++)
                database.Execute("UPDATE album_media SET position = ? WHERE album_id = ? AND media_id = ?;",
                    position, album, order[position]);
        });

    private List<(long Media, long Position)> AlbumPositions(long album) =>
        database.Query("""
            SELECT media_id, position FROM album_media WHERE album_id = ? ORDER BY position, media_id;
            """, row => (Media: row.Number(0), Position: row.Number(1)), album);

    public void Dispose() => database.Dispose();
}
