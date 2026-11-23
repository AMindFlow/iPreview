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
    private const string VideoFolder = "视频";
    private const string SamplesName = "官方样张";
    public const string PhotoSetsFolder = "附加写真集";
    private const string CoverName = "封面";
    public static readonly HashSet<string> Folders = [VideoFolder, SamplesName, PhotoSetsFolder];

    public List<ScannedMedia> IndexEntries(string prefix)
    {
        var videoPath = prefix + Video.RelativePath;
        var entries = new List<ScannedMedia> { new(videoPath, true, new VideoWorkMembership.Video(Structure)) };
        ScannedMedia Image(ScannedMedia file, VideoWorkImageRole role, int set, int position) =>
            new(prefix + file.RelativePath, false, new VideoWorkMembership.Image(videoPath, role, set, position));
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
        var byParent = entries.ToLookup(entry => SourceRename.SplitPath(entry.RelativePath).Parent, StringComparer.Ordinal);
        var atRoot = byParent[""];
        var rootVideos = atRoot.Where(media => media.IsVideo).ToArray();
        var rootSamples = atRoot.Where(media => !media.IsVideo && Stem(media) == SamplesName).ToArray();
        var folderVideos = byParent[VideoFolder].Where(media => media.IsVideo).ToArray();
        var folderSamples = byParent[SamplesName].Where(media => !media.IsVideo).ToArray();
        var flatPhotos = byParent[PhotoSetsFolder].Where(media => !media.IsVideo).ToArray();
        var nestedPhotoSets = byParent.Where(group => group.Key.StartsWith(PhotoSetsFolder + "/", StringComparison.Ordinal))
            .OrderBy(group => group.Key, MediaSearch.NaturalName).ThenBy(group => group.Key, StringComparer.Ordinal).ToArray();

        if (rootSamples.Length == 0 && !byParent.Contains(SamplesName) && !byParent.Contains(PhotoSetsFolder)
            && nestedPhotoSets.Length == 0)
            return new VideoWorkRecognition.Unrecognized();

        if (byParent.Contains(VideoFolder) || byParent.Contains(SamplesName) || nestedPhotoSets.Length != 0)
        {
            if (folderVideos.Length != 1 || folderSamples.Length == 0 || nestedPhotoSets.Length == 0
                || rootVideos.Length != 0 || rootSamples.Length != 0 || flatPhotos.Length != 0)
                return new VideoWorkRecognition.Ambiguous();

            var photoSets = new List<VideoPhotoSet>();
            foreach (var group in nestedPhotoSets)
            {
                var images = group.Where(media => !media.IsVideo).ToArray();
                var covers = images.Where(media => Stem(media) == CoverName).ToArray();
                var photos = images.Where(media => Stem(media) != CoverName).ToArray();
                if (covers.Length != 1 || photos.Length == 0)
                    return new VideoWorkRecognition.Ambiguous();
                photoSets.Add(new VideoPhotoSet(group.Key, covers[0], Sorted(photos)));
            }
            return new VideoWorkRecognition.Recognized(new(root, VideoWorkStructure.Complete, folderVideos[0],
                Sorted(folderSamples), photoSets));
        }

        if (rootVideos.Length != 1 || rootSamples.Length != 1 || flatPhotos.Length == 0)
            return new VideoWorkRecognition.Ambiguous();
        var book = new VideoPhotoSet(PhotoSetsFolder, null, Sorted(flatPhotos));
        return new VideoWorkRecognition.Recognized(new(root, VideoWorkStructure.Compact, rootVideos[0],
            rootSamples, [book]));
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
    public string RelativePath => string.Join('/', Video.RelativePath.Split('/')
        .SkipLast(Structure == VideoWorkStructure.Complete ? 2 : 1));
    public string Title => RelativePath.Length == 0 ? Video.Source.Name : RelativePath.Split('/')[^1];
}
