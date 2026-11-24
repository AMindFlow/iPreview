using System.Text;

namespace IPreview;

internal readonly record struct SourceAlbumKey(long SourceId, string RelativePath)
{
    public static SourceAlbumKey FromMedia(Media item) =>
        new(item.Source.Id, item.WorkAlbumPath ??
            string.Join('/', item.RelativePath.Split('/').SkipLast(1).Take((int)item.Source.Layout)));

    public bool MatchesLayout(Layout layout) =>
        (RelativePath.Length == 0 ? 0 : RelativePath.Count(character => character == '/') + 1) == (int)layout;

    public SourceAlbumKey? ContainingWork(IReadOnlySet<SourceAlbumKey> roots)
    {
        if (roots.Count == 0)
            return null;
        var path = RelativePath;
        while (true)
        {
            var candidate = new SourceAlbumKey(SourceId, path);
            if (roots.Contains(candidate))
                return candidate;
            if (path.Length == 0)
                return null;
            path = SourceRename.SplitPath(path).Parent;
        }
    }
}
internal sealed record SourceAlbumTag(long Id, string Name, string NormalizedName)
{
    public static List<SourceAlbumTag> Suggestions(string prefix, IReadOnlyList<SourceAlbumTag> tags)
    {
        var (_, query) = NamesFrom(prefix);
        return tags.Where(tag => tag.NormalizedName.Contains(query, StringComparison.Ordinal))
            .OrderBy(tag => tag.NormalizedName == query ? 0
                : tag.NormalizedName.StartsWith(query, StringComparison.Ordinal) ? 1 : 2)
            .ThenBy(tag => tag.NormalizedName, StringComparer.Ordinal).ToList();
    }

    public static (string Display, string Normalized) NamesFrom(string input)
    {
        var display = string.Join(' ', input.Normalize(NormalizationForm.FormKC).Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        var normalized = display.Normalize(NormalizationForm.FormD).ToLowerInvariant().Normalize(NormalizationForm.FormC);
        return (display, normalized);
    }
}
internal sealed record SourceAlbumOrganization(bool Favorite, int? RatingHalf, IReadOnlyList<SourceAlbumTag> Tags,
    IReadOnlyList<long> ConfiguredCoverIds, IReadOnlyList<long> EffectiveCoverIds);

internal sealed record SourceAlbumIndex(List<SourceAlbumTag> Tags,
    Dictionary<long, HashSet<SourceAlbumKey>> TaggedAlbums, Dictionary<SourceAlbumKey, long[]> ConfiguredCovers,
    HashSet<SourceAlbumKey> FavoriteAlbums, Dictionary<SourceAlbumKey, int> RatingsHalf)
{
    public static SourceAlbumIndex Empty { get; } = new([], [], [], [], []);

    public IReadOnlySet<SourceAlbumKey>? AlbumsMatchingAnyTagIds(IReadOnlySet<long> tagIds)
    {
        if (tagIds.Count == 0)
            return null;

        var matches = new HashSet<SourceAlbumKey>();
        foreach (var id in tagIds)
            if (TaggedAlbums.TryGetValue(id, out var albums))
                matches.UnionWith(albums);
        return matches;
    }

    public IReadOnlyList<SourceAlbumTag> TagsFor(SourceAlbumKey album) =>
        Tags.Where(tag => TaggedAlbums.TryGetValue(tag.Id, out var albums) && albums.Contains(album)).ToArray();

    public IReadOnlyList<Media> Covers(SourceAlbumKey album, IEnumerable<Media> members)
    {
        var available = members.Where(item => item.Available && !item.IsVideo).ToDictionary(item => item.Id);
        var ids = CoverIds(ConfiguredCovers.GetValueOrDefault(album) ?? [],
            available.Values.Select(item => (item.Id, item.RelativePath)));
        return ids.Select(id => available[id]).ToArray();
    }

    internal static IReadOnlyList<long> CoverIds(IReadOnlyList<long> configured, IEnumerable<(long Id, string Path)> images)
    {
        var available = images.ToList();
        var availableIds = available.Select(image => image.Id).ToHashSet();
        return configured.Count > 0 && configured.All(availableIds.Contains)
            ? configured : MediaSearch.ByNaturalPath(available, image => image.Path)
                .ThenBy(image => image.Path, StringComparer.Ordinal).Take(1).Select(image => image.Id).ToList();
    }
}

internal sealed partial class Catalog
{
    private const string AlbumMembers = """
        media.source_id = ?1
        AND substr(media.relative_path, 1, length(?2)) = ?2
        """;

    public List<SourceAlbumTag> ReadAlbumTags() =>
        database.Query("SELECT id, name, normalized_name FROM tags ORDER BY normalized_name;", ReadTag);

    public SourceAlbumIndex ReadSourceAlbumIndex() => database.InTransaction(() =>
    {
        var links = database.Query("""
            SELECT organization.source_id, organization.album_path, source_album_tags.tag_id
            FROM source_album_tags JOIN source_album_organization AS organization
            ON organization.id = source_album_tags.source_album_id;
            """, row => (Key: new SourceAlbumKey(row.Number(0), row.Text(1)), Id: row.Number(2)));
        var covers = database.Query("""
            SELECT organization.source_id, organization.album_path, cover.media_id
            FROM source_album_cover_media AS cover JOIN source_album_organization AS organization
            ON organization.id = cover.source_album_id ORDER BY cover.position;
            """, row => (Key: new SourceAlbumKey(row.Number(0), row.Text(1)), Id: row.Number(2)));
        var metadata = database.Query("""
            SELECT source_id, album_path, favorite, rating_half FROM source_album_organization
            WHERE favorite = 1 OR rating_half IS NOT NULL;
            """, row => (Key: new SourceAlbumKey(row.Number(0), row.Text(1)),
                Favorite: row.Number(2) == 1, Rating: (int?)row.NullableNumber(3)));
        return new SourceAlbumIndex(ReadAlbumTags(),
            links.GroupBy(link => link.Id).ToDictionary(group => group.Key, group => group.Select(link => link.Key).ToHashSet()),
            covers.GroupBy(cover => cover.Key).ToDictionary(group => group.Key, group => group.Select(cover => cover.Id).ToArray()),
            metadata.Where(entry => entry.Favorite).Select(entry => entry.Key).ToHashSet(),
            metadata.Where(entry => entry.Rating.HasValue).ToDictionary(entry => entry.Key, entry => entry.Rating!.Value));
    }, write: false);

    public List<SourceAlbumKey> ReadSourceAlbumsForTag(long tagId) => database.Query("""
        SELECT albums.source_id, albums.album_path FROM source_album_organization AS albums
        JOIN source_album_tags ON source_album_tags.source_album_id = albums.id
        WHERE source_album_tags.tag_id = ? ORDER BY albums.source_id, albums.album_path;
        """, row => new SourceAlbumKey(row.Number(0), row.Text(1)), tagId);

    public SourceAlbumOrganization ReadSourceAlbumOrganization(SourceAlbumKey album)
    {
        ValidateAlbumPath(album);
        return database.InTransaction(() =>
        {
            var stored = database.Query("""
                SELECT id, favorite, rating_half FROM source_album_organization WHERE source_id = ? AND album_path = ?;
                """, row => (Id: row.Number(0), Favorite: row.Number(1) == 1, Rating: (int?)row.NullableNumber(2)),
                album.SourceId, album.RelativePath);

            List<SourceAlbumTag> tags = [];
            List<long> configured = [];
            var entry = stored.SingleOrDefault();
            if (stored.Count > 0)
            {
                tags = database.Query("""
                    SELECT tags.id, tags.name, tags.normalized_name FROM tags
                    JOIN source_album_tags ON source_album_tags.tag_id = tags.id
                    WHERE source_album_tags.source_album_id = ? ORDER BY tags.normalized_name;
                    """, ReadTag, entry.Id);
                configured = database.Query("""
                    SELECT media_id FROM source_album_cover_media WHERE source_album_id = ? ORDER BY position;
                    """, row => row.Number(0), entry.Id);
            }

            var effective = SourceAlbumIndex.CoverIds(configured, AvailableAlbumImages(album));
            return new SourceAlbumOrganization(entry.Favorite, entry.Rating, tags, configured, effective);
        }, write: false);
    }

    public void SetFavorite(bool favorite, SourceAlbumKey album) => database.InTransaction(() =>
    {
        var id = EnsureOrganization(album);
        database.Execute("UPDATE source_album_organization SET favorite = ? WHERE id = ?;", favorite ? 1 : 0, id);
    });

    public void SetRatingHalf(int? rating, SourceAlbumKey album)
    {
        if (rating is < 0 or > 10)
            throw new ArgumentException("评分必须在 0 到 5 星之间，每半星一档。", nameof(rating));
        database.InTransaction(() =>
        {
            var id = EnsureOrganization(album);
            database.Execute("UPDATE source_album_organization SET rating_half = ? WHERE id = ?;", rating, id);
        });
    }

    public SourceAlbumTag AddAlbumTag(string name, SourceAlbumKey album)
    {
        var (display, normalized) = ValidatedTagNames(name);
        return database.InTransaction(() =>
        {
            var id = EnsureOrganization(album);
            database.Execute("""
                INSERT INTO tags (name, normalized_name) VALUES (?, ?)
                ON CONFLICT (normalized_name) DO NOTHING;
                """, display, normalized);
            var tag = FindTag(normalized) ?? throw new InvalidOperationException("缺少刚写入的标签。");
            AppendTag(tag.Id, id);
            return tag;
        });
    }

    public void AddAlbumTag(long tagId, SourceAlbumKey album) => database.InTransaction(() =>
    {
        var id = EnsureOrganization(album);
        ValidateTag(tagId);
        AppendTag(tagId, id);
    });

    public void RemoveAlbumTag(long tagId, SourceAlbumKey album)
    {
        ValidateAlbumPath(album);
        database.Execute("""
            DELETE FROM source_album_tags WHERE tag_id = ? AND source_album_id IN (
                SELECT id FROM source_album_organization WHERE source_id = ? AND album_path = ?
            );
            """, tagId, album.SourceId, album.RelativePath);
    }

    public void RenameTag(long tagId, string name)
    {
        var (display, normalized) = ValidatedTagNames(name);
        database.InTransaction(() =>
        {
            ValidateTag(tagId);
            if (FindTag(normalized) is { } other && other.Id != tagId)
                throw new InvalidOperationException("已有同名标签。");
            database.Execute("UPDATE tags SET name = ?, normalized_name = ? WHERE id = ?;", display, normalized, tagId);
        });
    }

    public void DeleteTag(long tagId) => database.Execute("DELETE FROM tags WHERE id = ?;", tagId);

    public void ReplaceCover(IReadOnlyList<long> mediaIds, SourceAlbumKey album)
    {
        var selection = mediaIds.ToHashSet();
        if (mediaIds.Count > 4 || selection.Count != mediaIds.Count)
            throw new ArgumentException("请从当前专辑中选择不超过四张不同的可用图片。", nameof(mediaIds));
        database.InTransaction(() =>
        {
            var id = EnsureOrganization(album);
            if (mediaIds.Count != 0 && !selection.IsSubsetOf(AvailableAlbumImages(album).Select(image => image.Id)))
                throw new ArgumentException("请从当前专辑中选择不超过四张不同的可用图片。", nameof(mediaIds));
            database.Execute("DELETE FROM source_album_cover_media WHERE source_album_id = ?;", id);
            for (var position = 0; position < mediaIds.Count; position++)
                database.Execute("INSERT INTO source_album_cover_media VALUES (?, ?, ?);", id, mediaIds[position], position);
        });
    }

    private long EnsureOrganization(SourceAlbumKey album)
    {
        ValidateAlbumPath(album);
        var layouts = database.Query($"""
            SELECT sources.layout FROM media JOIN sources ON sources.id = media.source_id
            WHERE {AlbumMembers} LIMIT 1;
            """, row => MediaFiles.DecodeLayout(row.Text(0)), album.SourceId, AlbumPrefix(album));
        var work = album.ContainingWork(ReadWorkAlbumRoots(album.SourceId));
        if (layouts.Count == 0 || (work is { } root ? root != album : !album.MatchesLayout(layouts[0])))
            throw new InvalidOperationException("此专辑已不在资料库中。");

        database.Execute("""
            INSERT INTO source_album_organization (source_id, album_path) VALUES (?, ?)
            ON CONFLICT (source_id, album_path) DO NOTHING;
            """, album.SourceId, album.RelativePath);
        return database.Query("SELECT id FROM source_album_organization WHERE source_id = ? AND album_path = ?;",
            row => row.Number(0), album.SourceId, album.RelativePath).Single();
    }

    private List<(long Id, string Path)> AvailableAlbumImages(SourceAlbumKey album) => database.Query($"""
        SELECT media.id, media.relative_path FROM media JOIN sources ON sources.id = media.source_id
        WHERE {AlbumMembers} AND media.kind = 'image' AND media.available = 1 AND sources.available = 1;
        """, row => (row.Number(0), row.Text(1)), album.SourceId, AlbumPrefix(album));

    private static string AlbumPrefix(SourceAlbumKey album) => album.RelativePath.Length == 0 ? "" : album.RelativePath + "/";

    private static void ValidateAlbumPath(SourceAlbumKey album)
    {
        if (album.RelativePath.Contains('\0'))
            throw new InvalidOperationException("此专辑已不在资料库中。");
    }

    private static SourceAlbumTag ReadTag(Sqlite.Fields row) => new(row.Number(0), row.Text(1), row.Text(2));

    private SourceAlbumTag? FindTag(string normalized) =>
        database.Query("SELECT id, name, normalized_name FROM tags WHERE normalized_name = ?;", ReadTag, normalized).SingleOrDefault();

    private void ValidateTag(long tagId)
    {
        if (database.Query("SELECT 1 FROM tags WHERE id = ?;", _ => true, tagId).Count == 0)
            throw new InvalidOperationException("此标签已不存在。");
    }

    private void AppendTag(long tagId, long organizationId) => database.Execute("""
        INSERT INTO source_album_tags (source_album_id, tag_id) VALUES (?, ?)
        ON CONFLICT (source_album_id, tag_id) DO NOTHING;
        """, organizationId, tagId);

    private static (string Display, string Normalized) ValidatedTagNames(string name)
    {
        var (display, normalized) = SourceAlbumTag.NamesFrom(name);
        if (display.Length == 0 || display.Contains('\0'))
            throw new ArgumentException("请输入有效的标签名称。", nameof(name));
        return (display, normalized);
    }
}
