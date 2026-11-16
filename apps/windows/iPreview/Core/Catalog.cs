using System.Reflection;

namespace IPreview;

internal sealed class Catalog : IDisposable
{
    private const string Migration = "iPreview.Migrations.001-initial.sql";
    private readonly Sqlite database;

    public Catalog(string dataDirectory)
    {
        Directory.CreateDirectory(dataDirectory);
        database = new Sqlite(Path.Combine(dataDirectory, "library.sqlite3"));
        try
        {
            database.InTransaction(() =>
            {
                var version = database.Query("PRAGMA user_version;", row => row.Number(0)).Single();
                if (version == 1)
                    return;
                if (version != 0)
                    throw new InvalidDataException("该媒体库由更高版本的 iPreview 创建。");

                using var resource = Assembly.GetExecutingAssembly().GetManifestResourceStream(Migration)
                    ?? throw new InvalidOperationException("The shared catalog migration was not embedded.");
                using var reader = new StreamReader(resource);
                database.ExecuteScript(reader.ReadToEnd());
            });
        }
        catch
        {
            database.Dispose();
            throw;
        }
    }

    public List<Source> Sources() =>
        database.Query("SELECT id, path, layout, available FROM sources;", row =>
        {
            var path = row.Text(1);
            return new Source(row.Number(0), path, MediaFiles.DecodeLayout(row.Text(2)),
                row.Number(3) != 0 && MediaFiles.IsLocalRootAvailable(path));
        });

    public List<Album> Albums() =>
        database.Query("SELECT id, name FROM albums ORDER BY name COLLATE NOCASE, id;",
            row => new Album(row.Number(0), row.Text(1)));

    public List<Media> Items(IReadOnlyDictionary<long, Source> sources, long? album = null) =>
        album is long albumId
            ? database.Query("""
                SELECT m.id, m.source_id, m.relative_path, m.kind, m.available
                FROM album_media AS a JOIN media AS m ON a.media_id = m.id
                WHERE a.album_id = ? ORDER BY a.position, a.media_id;
                """, row => ReadMedia(row, sources), albumId)
            : database.Query("SELECT id, source_id, relative_path, kind, available FROM media;", row => ReadMedia(row, sources));

    private static Media ReadMedia(Sqlite.Fields row, IReadOnlyDictionary<long, Source> sources) =>
        new(row.Number(0), sources[row.Number(1)], row.Text(2), row.Text(3) == "video", row.Number(4) != 0);

    public void Import(string path, Layout layout, List<ScannedMedia> files) =>
        database.InTransaction(() =>
        {
            var existing = database.Query("SELECT id, path FROM sources;", row => (row.Number(0), row.Text(1)))
                .Find(source => StringComparer.OrdinalIgnoreCase.Equals(source.Item2, path));
            var id = existing.Item1;
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

    public void Rescan(long source, List<ScannedMedia>? files)
    {
        if (files is null)
            database.Execute("UPDATE sources SET available = 0 WHERE id = ?;", source);
        else
            database.InTransaction(() => ReplaceScan(source, files));
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

    public long CreateAlbum(string name)
    {
        database.Execute("INSERT INTO albums (name) VALUES (?);", name.Trim());
        return database.Query("SELECT last_insert_rowid();", row => row.Number(0)).Single();
    }

    public void RenameAlbum(long album, string name) =>
        database.Execute("UPDATE albums SET name = ? WHERE id = ?;", name.Trim(), album);

    public void AddToAlbum(long album, long media) =>
        database.Execute("""
            INSERT OR IGNORE INTO album_media (album_id, media_id, position)
            VALUES (?, ?, (SELECT COALESCE(MAX(position) + 1, 0) FROM album_media WHERE album_id = ?));
            """, album, media, album);

    public void RemoveFromAlbum(long album, long media) =>
        database.Execute("DELETE FROM album_media WHERE album_id = ? AND media_id = ?;", album, media);

    public void MoveInAlbum(long album, long media, int offset) =>
        database.InTransaction(() =>
        {
            var members = database.Query("""
                SELECT media_id, position FROM album_media WHERE album_id = ? ORDER BY position, media_id;
                """, row => (Media: row.Number(0), Position: row.Number(1)), album);
            var current = members.FindIndex(member => member.Media == media);
            var next = current + offset;
            if (current < 0 || next < 0 || next >= members.Count)
                return;
            database.Execute("UPDATE album_media SET position = ? WHERE album_id = ? AND media_id = ?;",
                members[next].Position, album, media);
            database.Execute("UPDATE album_media SET position = ? WHERE album_id = ? AND media_id = ?;",
                members[current].Position, album, members[next].Media);
        });

    public void Dispose() => database.Dispose();
}
