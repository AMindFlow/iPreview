using Microsoft.Win32.SafeHandles;

namespace IPreview;

internal sealed partial class Catalog
{
    private sealed record PendingRename(long Source, string Before, string After, bool Directory, string Identity);

    public string? RenameRecoveryNotice { get; private set; }

    public bool HasPendingRename(long source) => ReadPendingRename()?.Source == source;

    public string? CurrentRenameNotice() => ReadPendingRename() is null ? null :
        RenameRecoveryNotice ?? "有一项重命名尚待完成，请稍后重试。";

    public string RenameSourceItem(long sourceId, string oldPath, string baseName, bool isDirectory,
        long expectedMediaId)
    {
        if (CurrentRenameNotice() is { } notice)
            throw new IOException(notice);
        var newPath = SourceRename.Destination(oldPath, baseName, isDirectory);
        if (oldPath == newPath)
            return oldPath;

        SafeFileHandle? target = null;
        try
        {
            var source = database.Query("SELECT path, layout, available FROM sources WHERE id = ?;",
                row => new Source(sourceId, row.Text(0), MediaFiles.DecodeLayout(row.Text(1)), row.Number(2) != 0),
                sourceId).Single();
            if (!source.Available)
                throw new IOException("媒体源离线，无法重命名。");
            SourceRename.RequireStableIdentity(source);
            using var parent = SourceRename.OpenParent(source, oldPath);
            EnsureRenameLocation(source, oldPath, newPath);
            target = SourceRename.Open(source, oldPath, isDirectory, forRename: true);
            var pending = new PendingRename(sourceId, oldPath, newPath, isDirectory, SourceRename.Identity(target));
            database.InTransaction(() =>
            {
                if (ReadPendingRename() is not null)
                    throw new IOException("有一项重命名尚待恢复，请先处理后再试。");
                EnsureSeparateRoots(source, pending);
                ValidateRenameProjection(pending, expectedMediaId);
                database.Execute("""
                    INSERT INTO pending_rename (id, source_id, old_path, new_path, is_directory, file_identity)
                    VALUES (1, ?, ?, ?, ?, ?);
                    """, sourceId, oldPath, newPath, isDirectory ? 1 : 0, pending.Identity);
            });

            var moved = false;
            try
            {
                database.InTransaction(() =>
                {
                    if (ReadPendingRename() != pending)
                        throw new IOException("重命名记录已在另一个 iPreview 窗口处理。");
                    var registeredPath = ReadSourcePath(sourceId);
                    if (!StringComparer.OrdinalIgnoreCase.Equals(registeredPath, source.Path))
                        throw new IOException("媒体源路径已改变。");
                    EnsureSeparateRoots(source, pending);
                    ValidateRenameProjection(pending, expectedMediaId);
                    EnsureRenameLocation(source, oldPath, newPath);
                    SourceRename.AssertPath(target, source, oldPath, isDirectory);
                    SourceRename.Move(target, parent, SourceRename.SplitPath(newPath).Leaf);
                    moved = true;
                    var location = SourceRename.Inspect(source, oldPath, newPath);
                    if (location != (false, true, false))
                        throw new IOException("磁盘未保留请求的新名称。");
                    SourceRename.AssertPath(target, source, newPath, isDirectory);
                    UpdateRenamedPaths(pending);
                    ClearPendingRename();
                });
            }
            catch (Exception error) when (RenameFailure(error))
            {
                try
                {
                    database.InTransaction(() => ReverseSourceRename(source, pending, target, parent, moved));
                }
                catch (Exception recovery) when (RenameFailure(recovery))
                {
                    RenameRecoveryNotice = DescribeRecovery(pending);
                    throw new IOException(RenameRecoveryNotice, new AggregateException(error, recovery));
                }
                throw;
            }

            RenameRecoveryNotice = null;
            return newPath;
        }
        finally
        {
            target?.Dispose();
        }
    }

    private static void EnsureRenameLocation(Source source, string oldPath, string newPath)
    {
        var (before, after, other) = SourceRename.Inspect(source, oldPath, newPath);
        if (!before)
            throw new IOException("所选文件或文件夹已移走，或原名称已改变。");
        if (after || other)
            throw new IOException("目录中已经存在同名项目。");
    }

    private void ValidateRenameProjection(PendingRename pending, long? expectedMediaId = null)
    {
        var items = database.Query("SELECT id, relative_path, available FROM media WHERE source_id = ?;",
            row => (Id: row.Number(0), Path: row.Text(1), Present: row.Number(2) != 0), pending.Source);
        var memberPrefix = pending.Before + "/";
        var targetPrefix = pending.After + "/";
        var hasPresentMember = false;
        foreach (var (id, path, present) in items)
        {
            var belongs = pending.Directory ? path.StartsWith(memberPrefix, StringComparison.Ordinal) : path == pending.Before;
            if (belongs)
                hasPresentMember |= present && (expectedMediaId is null || expectedMediaId == id);
            else if (StringComparer.OrdinalIgnoreCase.Equals(path, pending.After) ||
                     path.StartsWith(targetPrefix, StringComparison.OrdinalIgnoreCase))
                throw new IOException("新名称与媒体库中的已有路径冲突。");
        }
        if (!hasPresentMember)
            throw new IOException("所选项目已不在活动索引中。");
    }

    private void UpdateRenamedPaths(PendingRename pending)
    {
        if (pending.Directory)
        {
            database.Execute("""
                UPDATE media
                SET relative_path = ? || substr(relative_path, length(?) + 1)
                WHERE source_id = ? AND substr(relative_path, 1, length(?) + 1) = ? || '/';
                """, pending.After, pending.Before, pending.Source, pending.Before, pending.Before);
            database.Execute("""
                UPDATE source_album_organization
                SET album_path = ? || substr(album_path, length(?) + 1)
                WHERE source_id = ? AND (album_path = ? OR substr(album_path, 1, length(?) + 1) = ? || '/');
                """, pending.After, pending.Before, pending.Source, pending.Before, pending.Before, pending.Before);
        }
        else
        {
            database.Execute("UPDATE media SET relative_path = ? WHERE source_id = ? AND relative_path = ?;",
                pending.After, pending.Source, pending.Before);
        }
    }

    private string ReadSourcePath(long sourceId) =>
        database.Query("SELECT path FROM sources WHERE id = ?;", row => row.Text(0), sourceId).Single();

    private void EnsureSeparateRoots(Source source, PendingRename pending)
    {
        var before = Path.Combine(source.Path, pending.Before.Replace('/', Path.DirectorySeparatorChar));
        var after = Path.Combine(source.Path, pending.After.Replace('/', Path.DirectorySeparatorChar));
        var otherRoots = database.Query("SELECT path FROM sources WHERE id <> ?;", row => row.Text(0), source.Id);
        if (otherRoots.Any(root => PathsOverlap(root, before) || PathsOverlap(root, after)))
            throw new IOException("此项目的路径与另一个已登记的媒体源重叠。");
    }

    private void EnsureImportOutsidePendingRename(string path)
    {
        if (ReadPendingRename() is not { } pending)
            return;
        var root = ReadSourcePath(pending.Source);
        var before = Path.Combine(root, pending.Before.Replace('/', Path.DirectorySeparatorChar));
        var after = Path.Combine(root, pending.After.Replace('/', Path.DirectorySeparatorChar));
        if (PathsOverlap(path, before) || PathsOverlap(path, after))
            throw new InvalidOperationException("此目录涉及一项待恢复的重命名，暂时无法导入。");
    }

    private static bool PathsOverlap(string first, string second) => Contains(first, second) || Contains(second, first);

    private PendingRename? ReadPendingRename() => database.Query("""
        SELECT source_id, old_path, new_path, is_directory, file_identity FROM pending_rename WHERE id = 1;
        """, row => new PendingRename(row.Number(0), row.Text(1), row.Text(2), row.Number(3) != 0, row.Text(4)))
        .SingleOrDefault();

    private void ClearPendingRename() => database.Execute("DELETE FROM pending_rename WHERE id = 1;");

    private void RecoverSourceRename()
    {
        PendingRename? observed = null;
        try
        {
            database.InTransaction(() =>
            {
                observed = ReadPendingRename();
                if (observed is not { } pending)
                    return;
                var source = new Source(pending.Source, ReadSourcePath(pending.Source), Layout.Flat, Available: true);
                SourceRename.RequireStableIdentity(source);
                var (before, after, other) = SourceRename.Inspect(source, pending.Before, pending.After);
                if (!other && before && !after &&
                    SourceRename.Identity(source, pending.Before, pending.Directory) == pending.Identity)
                {
                    ClearPendingRename();
                }
                else if (!other && !before && after &&
                         SourceRename.Identity(source, pending.After, pending.Directory) == pending.Identity)
                {
                    EnsureSeparateRoots(source, pending);
                    ValidateRenameProjection(pending);
                    UpdateRenamedPaths(pending);
                    ClearPendingRename();
                }
                else
                    RenameRecoveryNotice = DescribeRecovery(pending);
            });
        }
        catch (Exception error) when (observed is not null && RenameFailure(error))
        {
            RenameRecoveryNotice = DescribeRecovery(observed);
        }
    }

    private void ReverseSourceRename(Source source, PendingRename pending, SafeFileHandle target, SafeFileHandle parent,
        bool moved)
    {
        if (ReadPendingRename() != pending)
            return;

        var location = SourceRename.Inspect(source, pending.Before, pending.After);
        if (moved && location == (false, true, false))
        {
            SourceRename.AssertPath(target, source, pending.After, pending.Directory);
            SourceRename.Move(target, parent, SourceRename.SplitPath(pending.Before).Leaf);
            location = SourceRename.Inspect(source, pending.Before, pending.After);
        }
        if (!location.OldExists || moved && (location.NewExists || location.OtherSpellingExists))
            throw new IOException("无法安全恢复原名称。");
        SourceRename.AssertPath(target, source, pending.Before, pending.Directory);
        ClearPendingRename();
    }

    private static bool RenameFailure(Exception error) =>
        error is IOException or UnauthorizedAccessException or InvalidOperationException;

    private static string DescribeRecovery(PendingRename pending) =>
        $"无法确认「{pending.Before}」和「{pending.After}」之间的重命名状态。此媒体源暂停重扫。";
}
