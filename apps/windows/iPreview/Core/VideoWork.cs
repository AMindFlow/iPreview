namespace IPreview;

internal abstract record VideoWorkRecognition
{
    public sealed record Unrecognized : VideoWorkRecognition;
    public sealed record Ambiguous : VideoWorkRecognition;
    public sealed record Recognized(VideoWork Work) : VideoWorkRecognition;
}

internal enum VideoWorkStructure { Complete, Compact }

internal sealed record VideoPhotoSet(string RelativePath, ScannedMedia? Cover, IReadOnlyList<ScannedMedia> Photos);

internal sealed record VideoWork(string Root, VideoWorkStructure Structure, ScannedMedia Video,
    IReadOnlyList<ScannedMedia> Samples, IReadOnlyList<VideoPhotoSet> PhotoSets)
{
    private const string LegacyVideoFolder = "视频";
    private const string LegacyBookContainer = "附加写真集";
    private const string SamplesName = "官方样张";
    private const string CoverName = "封面";

    public List<ScannedMedia> IndexEntries(string prefix)
    {
        var videoPath = prefix + Video.RelativePath;
        var entries = new List<ScannedMedia> { new(videoPath, MediaKind.Video, new VideoWorkMembership.Video(Structure)) };
        ScannedMedia Image(ScannedMedia file, VideoWorkImageRole role, int set, int position) =>
            new(prefix + file.RelativePath, MediaKind.Image, new VideoWorkMembership.Image(videoPath, role, set, position));
        entries.AddRange(Samples.Select((file, index) => Image(file, VideoWorkImageRole.Sample, 0, index)));
        for (var set = 0; set < PhotoSets.Count; set++)
        {
            var book = PhotoSets[set];
            if (book.Cover is { } cover)
                entries.Add(Image(cover, VideoWorkImageRole.Cover, set, 0));
            entries.AddRange(book.Photos.Select((file, index) => Image(file, VideoWorkImageRole.Photo, set, index)));
        }
        return entries;
    }

    public static VideoWorkRecognition Recognize(string root, IEnumerable<ScannedMedia> entries)
    {
        var byParent = entries.Where(entry => entry.IsImage || entry.IsVideo)
            .ToLookup(entry => SourceRename.SplitPath(entry.RelativePath).Parent, StringComparer.Ordinal);
        var directFolders = byParent.Where(group => group.Key.Length != 0 && !group.Key.Contains('/')).ToArray();
        var nestedFolders = byParent.Where(group => group.Key.Contains('/')).ToArray();
        var photoFolders = directFolders.Where(group => group.All(media => media.IsImage)).ToArray();
        var rootVideos = byParent[""].Where(media => media.IsVideo).ToArray();

        if (rootVideos.Length != 0)
        {
            if (photoFolders.Length == 0)
                return new VideoWorkRecognition.Unrecognized();
            if (rootVideos.Length != 1 || photoFolders.Length != directFolders.Length ||
                nestedFolders.Any(group => group.Any(media => media.IsVideo)))
                return new VideoWorkRecognition.Ambiguous();

            var rootImages = byParent[""].Where(media => media.IsImage).ToArray();
            var markedSamples = rootImages.Where(media => Stem(media) == SamplesName).ToArray();
            if (markedSamples.Length > 1)
                return new VideoWorkRecognition.Ambiguous();
            var samples = markedSamples.Length == 0 && rootImages.Length == 1 ? rootImages : markedSamples;
            var legacyBook = photoFolders.SingleOrDefault(group => group.Key == LegacyBookContainer);
            var usesLegacyCompactRoles = markedSamples.Length == 1 && legacyBook is not null &&
                !nestedFolders.Any(group => SourceRename.SplitPath(group.Key).Parent == LegacyBookContainer);
            var folder = usesLegacyCompactRoles ? legacyBook :
                photoFolders.Length == 1 && nestedFolders.Length == 0 ? photoFolders[0] : null;
            if (folder is null)
                return new VideoWorkRecognition.Ambiguous();
            var book = new VideoPhotoSet(folder.Key, null, Sorted(folder));
            return new VideoWorkRecognition.Recognized(new(root, VideoWorkStructure.Compact, rootVideos[0], samples, [book]));
        }

        var folderVideos = directFolders.SelectMany(group => group).Where(media => media.IsVideo).ToArray();
        if (folderVideos.Length == 0 || nestedFolders.Length == 0)
            return new VideoWorkRecognition.Unrecognized();
        if (folderVideos.Length != 1 || nestedFolders.Any(group => group.Any(media => media.IsVideo)))
            return new VideoWorkRecognition.Ambiguous();

        var videoFolder = SourceRename.SplitPath(folderVideos[0].RelativePath).Parent;
        var bookContainers = nestedFolders.Select(group => SourceRename.SplitPath(group.Key).Parent)
            .Distinct(StringComparer.Ordinal).ToArray();
        var usesLegacyRoles = videoFolder == LegacyVideoFolder && bookContainers.Contains(LegacyBookContainer) &&
            photoFolders.Any(group => group.Key == SamplesName);
        var container = usesLegacyRoles ? LegacyBookContainer : bookContainers.Length == 1 ? bookContainers[0] : null;
        if (container is null || byParent.Contains(container) || (!usesLegacyRoles && photoFolders.Length > 1))
            return new VideoWorkRecognition.Ambiguous();

        var photoSets = new List<VideoPhotoSet>();
        foreach (var group in nestedFolders.Where(group => SourceRename.SplitPath(group.Key).Parent == container)
            .OrderBy(group => group.Key, MediaSearch.NaturalName)
            .ThenBy(group => group.Key, StringComparer.Ordinal))
        {
            var covers = group.Where(media => Stem(media) == CoverName).ToArray();
            var photos = group.Where(media => Stem(media) != CoverName).ToArray();
            if (covers.Length > 1 || photos.Length == 0)
                return new VideoWorkRecognition.Ambiguous();
            photoSets.Add(new VideoPhotoSet(group.Key, covers.SingleOrDefault(), Sorted(photos)));
        }

        var folderSamples = usesLegacyRoles ? Sorted(byParent[SamplesName]) :
            photoFolders.Length == 0 ? [] : Sorted(photoFolders[0]);
        return new VideoWorkRecognition.Recognized(new(root, VideoWorkStructure.Complete, folderVideos[0],
            folderSamples, photoSets));
    }

    private static string Stem(ScannedMedia entry) => Path.GetFileNameWithoutExtension(entry.RelativePath);

    private static ScannedMedia[] Sorted(IEnumerable<ScannedMedia> entries) => entries
        .OrderBy(entry => entry.RelativePath, MediaSearch.NaturalName)
        .ThenBy(entry => entry.RelativePath, StringComparer.Ordinal).ToArray();
}

internal enum VideoWorkImageRole { Sample, Cover, Photo }

internal abstract record VideoWorkMembership
{
    public sealed record Video(VideoWorkStructure Structure) : VideoWorkMembership;
    public sealed record Image(string VideoPath, VideoWorkImageRole Role, int Set, int Position) : VideoWorkMembership;
}

internal sealed record IndexedVideoPhotoSet(Media? Cover, IReadOnlyList<Media> Photos)
{
    public string Title => Photos[0].RelativePath.Split('/')[^2];
}

internal sealed record IndexedVideoWork(Media Video, VideoWorkStructure Structure,
    IReadOnlyList<Media> Samples, IReadOnlyList<IndexedVideoPhotoSet> PhotoSets)
{
    public string RelativePath => AlbumPath(Video.RelativePath, Structure);
    public static string AlbumPath(string videoPath, VideoWorkStructure structure) =>
        string.Join('/', videoPath.Split('/').SkipLast(structure == VideoWorkStructure.Complete ? 2 : 1));
    public string Title => RelativePath.Length == 0 ? Video.Source.Name : RelativePath.Split('/')[^1];
}
