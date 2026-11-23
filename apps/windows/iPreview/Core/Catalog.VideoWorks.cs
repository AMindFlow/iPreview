namespace IPreview;

internal sealed partial class Catalog
{
    private List<IndexedVideoWork> ReadVideoWorks(Dictionary<long, Media> mediaById)
    {
        var works = database.Query("SELECT video_id, structure FROM video_works ORDER BY video_id;",
            row => (Id: row.Number(0), Structure: row.Text(1) switch
            {
                "complete" => VideoWorkStructure.Complete,
                "compact" => VideoWorkStructure.Compact,
                _ => throw new InvalidDataException("无法识别视频作品结构。")
            }));
        var images = database.Query("""
            SELECT video_id, media_id, role, set_position
            FROM video_work_images ORDER BY set_position, position;
            """, row => (Video: row.Number(0), Media: mediaById[row.Number(1)], Role: row.Text(2), Set: row.Number(3)))
            .ToLookup(image => image.Video);
        return works.Select(work =>
        {
            var entries = images[work.Id];
            var samples = entries.Where(image => image.Role == "sample").Select(image => image.Media).ToArray();
            var photoSets = entries.Where(image => image.Role != "sample").GroupBy(image => image.Set)
                .Select(book => new IndexedVideoPhotoSet(book.FirstOrDefault(image => image.Role == "cover").Media,
                    book.Where(image => image.Role == "photo").Select(image => image.Media).ToArray())).ToArray();
            return new IndexedVideoWork(mediaById[work.Id], work.Structure, samples, photoSets);
        }).ToList();
    }

    private void ReplaceVideoWorks(long source, List<ScannedMedia> files)
    {
        database.Execute("DELETE FROM video_works WHERE video_id IN (SELECT id FROM media WHERE source_id = ?);", source);
        foreach (var file in files.Where(file => file.VideoWork is VideoWorkMembership.Video))
        {
            var work = (VideoWorkMembership.Video)file.VideoWork!;
            database.Execute("""
                INSERT INTO video_works (video_id, structure)
                SELECT id, ? FROM media WHERE source_id = ? AND relative_path = ?;
                """, work.Structure == VideoWorkStructure.Complete ? "complete" : "compact", source, file.RelativePath);
        }
        foreach (var file in files.Where(file => file.VideoWork is VideoWorkMembership.Image))
        {
            var image = (VideoWorkMembership.Image)file.VideoWork!;
            database.Execute("""
                INSERT INTO video_work_images (video_id, media_id, role, set_position, position)
                SELECT video.id, image.id, ?, ?, ? FROM media AS video JOIN media AS image USING (source_id)
                WHERE video.source_id = ? AND video.relative_path = ? AND image.relative_path = ?;
                """, image.Role.ToString().ToLowerInvariant(), image.Set, image.Position, source, image.VideoPath, file.RelativePath);
        }
    }
}
