namespace IPreview;

internal enum Layout { Flat, Creator, MultiCreator }
internal enum MediaKind { Image, Video, Audio }

internal sealed record Source(long Id, string Path, Layout Layout, bool Available)
{
    public string Name => MediaFiles.FolderName(Path);
}

internal sealed record Media(long Id, Source Source, string RelativePath, MediaKind Kind, bool Present,
    string? WorkAlbumPath = null)
{
    public bool IsImage => Kind == MediaKind.Image;
    public bool IsVideo => Kind == MediaKind.Video;
    public bool IsAudio => Kind == MediaKind.Audio;
    public string FileName => RelativePath.Split('/')[^1];
    public string ParentRelativePath => SourceRename.SplitPath(RelativePath).Parent;
    public string DisplayPath => Source.Name + "/" + RelativePath;
    public bool Available => Present && Source.Available;
}

internal sealed record Album(long Id, string Name);
internal sealed record ScannedMedia(string RelativePath, MediaKind Kind, VideoWorkMembership? VideoWork = null)
{
    public bool IsImage => Kind == MediaKind.Image;
    public bool IsVideo => Kind == MediaKind.Video;
}
internal sealed record ImportSummary(string Path, IReadOnlyDictionary<Layout, List<ScannedMedia>> Options);

internal static class MediaFiles
{
    private const FileAttributes Skipped = FileAttributes.Hidden | FileAttributes.ReparsePoint;
    public static string FolderName(string path)
    {
        var trimmed = Path.TrimEndingDirectorySeparator(path);
        return Path.GetFileName(trimmed) is { Length: > 0 } name ? name : path;
    }

    public static ImportSummary Probe(string path)
    {
        path = Path.TrimEndingDirectorySeparator(Path.GetFullPath(path));
        var directories = ReadDirectoryTree(path);
        var options = new Dictionary<Layout, List<ScannedMedia>>();
        foreach (var layout in new[] { Layout.Creator, Layout.MultiCreator })
        {
            var files = directories[layout];
            if (files.Count != 0)
                options.Add(layout, files);
        }
        if (options.Count == 0 && directories[Layout.Flat].Count != 0)
            options.Add(Layout.Flat, directories[Layout.Flat]);
        return new(path, options);
    }

    public static VideoWorkRecognition ProbeVideoWork(string path)
    {
        path = Path.TrimEndingDirectorySeparator(Path.GetFullPath(path));
        EnsureReadableLocalRoot(path);
        var children = ReadChildren(path);
        return ProbeVideoWork(path, children, ReadFiles(path, children), out _);
    }

    public static List<ScannedMedia> Scan(string root, Layout layout)
    {
        var directories = ReadDirectoryTree(root, (int)layout, retainingLayoutDepth: true);
        var workEntries = directories.Values.SelectMany(level => level)
            .Where(item => item.VideoWork is not null).ToList();
        var workPaths = workEntries.Select(item => item.RelativePath).ToHashSet(StringComparer.Ordinal);
        return directories[layout].Where(item => !workPaths.Contains(item.RelativePath)).Concat(workEntries).ToList();
    }

    public static bool IsLocalRootAvailable(string path)
    {
        try
        {
            EnsureReadableLocalRoot(path);
            return true;
        }
        catch (IOException) { return false; }
        catch (UnauthorizedAccessException) { return false; }
    }

    public static string OpenPath(Media media)
    {
        if (!media.Available)
            throw new IOException("文件所在目录或媒体当前不可用。");
        return ResolveIndexedPath(media.Source, media.RelativePath, isDirectory: false);
    }

    internal static string ResolveIndexedPath(Source source, string relativePath, bool isDirectory)
    {
        EnsureReadableLocalRoot(source.Path);
        if (isDirectory && relativePath.Length == 0)
            return source.Path;

        var path = source.Path;
        var components = relativePath.Split('/');
        for (var index = 0; index < components.Length; index++)
        {
            var component = components[index];
            if (component.Length == 0 || component is "." or ".." ||
                component.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0)
                throw new IOException("媒体路径无效。");
            path = Path.Combine(path, component);
            var attributes = File.GetAttributes(path);
            if (IsSkipped(component, attributes))
                throw new IOException("隐藏文件和重解析点不可预览。");
            var shouldBeDirectory = index < components.Length - 1 || isDirectory;
            if (((attributes & FileAttributes.Directory) != 0) != shouldBeDirectory)
                throw new IOException("文件或文件夹已移动，或类型已改变。");
        }
        return path;
    }

    private static Dictionary<Layout, List<ScannedMedia>> ReadDirectoryTree(
        string path, int maximumDepth = 2, bool retainingLayoutDepth = false)
    {
        EnsureReadableLocalRoot(path);
        var files = Enum.GetValues<Layout>().ToDictionary(layout => layout, _ => new List<ScannedMedia>());
        Scan(path, path, 0, recognizeWorks: true);
        return files;

        void Scan(string root, string directory, int depth, bool recognizeWorks)
        {
            var children = ReadChildren(directory);
            var direct = ReadFiles(directory, children);
            var prefix = depth == 0 ? "" : RelativePath(root, directory) + "/";
            var level = files[(Layout)depth];
            ScannedMedia Scoped(ScannedMedia item) => item with { RelativePath = prefix + item.RelativePath };
            if (recognizeWorks &&
                ProbeVideoWork(directory, children, direct, out var workMedia) is VideoWorkRecognition.Recognized(var work))
            {
                var tagged = work.IndexEntries(prefix);
                var included = tagged.Select(item => item.RelativePath).ToHashSet(StringComparer.Ordinal);
                level.AddRange(tagged);
                var videoFolder = SourceRename.SplitPath(work.Video.RelativePath).Parent;
                var workFiles = workMedia.Where(item =>
                {
                    var parent = SourceRename.SplitPath(item.RelativePath).Parent;
                    return parent.Length == 0 || parent == videoFolder;
                });
                level.AddRange(workFiles.Select(Scoped).Where(item => !included.Contains(item.RelativePath)));
                if (!retainingLayoutDepth)
                    return;
                // A saved layout can contain ordinary media at an additional level inside a work.
                recognizeWorks = false;
            }
            else
                level.AddRange(direct.Select(Scoped));

            if (depth < maximumDepth)
                foreach (var child in children.OfType<DirectoryInfo>())
                    Scan(root, child.FullName, depth + 1, recognizeWorks);
        }
    }

    private static VideoWorkRecognition ProbeVideoWork(
        string root, FileSystemInfo[] children, ScannedMedia[] direct, out List<ScannedMedia> files)
    {
        files = direct.ToList();
        try
        {
            var folders = children.OfType<DirectoryInfo>().Select(folder => ReadChildren(folder.FullName)).ToArray();
            foreach (var folder in folders)
                files.AddRange(ReadFiles(root, folder));
            if (!files.Any(media => media.IsVideo))
                return new VideoWorkRecognition.Unrecognized();

            foreach (var folder in folders.SelectMany(items => items.OfType<DirectoryInfo>()))
                files.AddRange(ReadFiles(root, ReadChildren(folder.FullName)));
            return VideoWork.Recognize(root, files);
        }
        catch (UnauthorizedAccessException)
        {
            // The normal scan still reports errors in directories within its layout.
            return new VideoWorkRecognition.Unrecognized();
        }
    }

    private static FileSystemInfo[] ReadChildren(string path) => new DirectoryInfo(path).EnumerateFileSystemInfos()
        .Where(item => !IsSkipped(item.Name, item.Attributes)).ToArray();

    private static ScannedMedia[] ReadFiles(string root, FileSystemInfo[] items) => items.OfType<FileInfo>()
        .Select(item => KindForExtension(item.Extension) is { } kind
            ? new ScannedMedia(RelativePath(root, item.FullName), kind)
            : null)
        .OfType<ScannedMedia>()
        .ToArray();

    private static string RelativePath(string root, string path) =>
        Path.GetRelativePath(root, path).Replace(Path.DirectorySeparatorChar, '/');

    internal static bool IsSupportedExtension(string extension) => KindForExtension(extension) is not null;

    private static MediaKind? KindForExtension(string extension) => extension.ToLowerInvariant() switch
    {
        ".jpg" or ".jpeg" or ".png" or ".webp" or ".gif" or ".heic" => MediaKind.Image,
        ".mp4" or ".mov" or ".ts" or ".mkv" or ".webm" or ".avi" => MediaKind.Video,
        ".mp3" or ".m4a" or ".flac" or ".wav" => MediaKind.Audio,
        _ => null
    };

    internal static string StoreKind(MediaKind kind) => kind switch
    {
        MediaKind.Image => "image",
        MediaKind.Video => "video",
        MediaKind.Audio => "audio",
        _ => throw new ArgumentOutOfRangeException(nameof(kind))
    };

    internal static MediaKind DecodeKind(string kind) => kind switch
    {
        "image" => MediaKind.Image,
        "video" => MediaKind.Video,
        "audio" => MediaKind.Audio,
        _ => throw new InvalidDataException("媒体类型无效。")
    };

    private static void EnsureReadableLocalRoot(string path)
    {
        var volume = Path.GetPathRoot(path);
        if (volume is null || volume.StartsWith(@"\\", StringComparison.Ordinal) ||
            new DriveInfo(volume).DriveType == DriveType.Network)
            throw new IOException("请选择本机或本机外接磁盘上的文件夹。");

        for (DirectoryInfo? part = new(path); part is not null; part = part.Parent)
        {
            var attributes = File.GetAttributes(part.FullName);
            if ((attributes & FileAttributes.ReparsePoint) != 0 || (attributes & FileAttributes.Directory) == 0)
                throw new IOException("所选路径不是可读取的本机文件夹。");
        }
    }

    private static bool IsSkipped(string name, FileAttributes attributes) =>
        name.StartsWith('.') || (attributes & Skipped) != 0;

    public static string Display(Layout layout) => layout switch
    {
        Layout.Flat => "单个专辑",
        Layout.Creator => "创作者 → 专辑",
        Layout.MultiCreator => "多创作者 → 创作者 → 专辑",
        _ => throw new ArgumentOutOfRangeException(nameof(layout))
    };

    public static string Store(Layout layout) => layout switch
    {
        Layout.Flat => "flat",
        Layout.Creator => "creator",
        Layout.MultiCreator => "multi-creator",
        _ => throw new ArgumentOutOfRangeException(nameof(layout))
    };

    public static Layout DecodeLayout(string layout) => layout switch
    {
        "flat" => Layout.Flat,
        "creator" => Layout.Creator,
        "multi-creator" => Layout.MultiCreator,
        _ => throw new InvalidDataException("不支持此媒体源的目录结构。")
    };
}
