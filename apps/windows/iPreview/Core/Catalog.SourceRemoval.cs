namespace IPreview;

internal sealed class SourceDeletionChangedException() :
    InvalidOperationException("媒体库已在其他窗口更新。请核对媒体源后重试。");

internal sealed partial class Catalog
{
    public void DeleteSource(long source, long expectedDataVersion) =>
        database.InTransaction(() =>
        {
            if (DataVersion != expectedDataVersion)
                throw new SourceDeletionChangedException();
            if (HasPendingRename(source))
                throw new InvalidOperationException("此媒体源有待恢复的重命名，暂时无法删除。");

            database.Execute("DELETE FROM source_album_organization WHERE source_id = ?;", source);
            database.Execute("""
                DELETE FROM album_media WHERE media_id IN (SELECT id FROM media WHERE source_id = ?);
                """, source);
            database.Execute("DELETE FROM media WHERE source_id = ?;", source);
            database.Execute("DELETE FROM sources WHERE id = ?;", source);
        });
}
