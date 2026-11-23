namespace IPreview;

internal enum Layout { Flat, Creator, MultiCreator }

internal sealed record Source(long Id, string Path, Layout Layout, bool Available)
{
    public string Name => MediaFiles.FolderName(Path);
}

internal sealed record Media(long Id, Source Source, string RelativePath, bool IsVideo, bool Present,
    string? WorkAlbumPath = null)
{
    public string FileName => RelativePath.Split('/')[^1];
    public string DisplayPath => Source.Name + "/" + RelativePath;
    public bool Available => Present && Source.Available;
}

internal sealed record Album(long Id, string Name);
internal sealed record ScannedMedia(string RelativePath, bool IsVideo, VideoWorkMembership? VideoWork = null);
internal sealed record ImportSummary(string Path, IReadOnlyDictionary<Layout, List<ScannedMedia>> Options);

internal static class MediaFiles
{
    private const FileAttributes Skipped = FileAttributes.Hidden | FileAttributes.ReparsePoint;
    private static readonly HashSet<string> Images = new(StringComparer.OrdinalIgnoreCase)
    {
        ".jpg", ".jpeg", ".png", ".webp", ".gif", ".heic"
    };

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
        return ProbeVideoWork(path, children, ReadFiles(path, children));
    }

    public static List<ScannedMedia> Scan(string root, Layout layout)
    {
        var directories = ReadDirectoryTree(root, (int)layout);
        return directories[Layout.Flat].Any(item => item.VideoWork is VideoWorkMembership.Video)
            ? directories[Layout.Flat] : directories[layout];
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

    private static Dictionary<Layout, List<ScannedMedia>> ReadDirectoryTree(string path, int maximumDepth = 2)
    {
        EnsureReadableLocalRoot(path);
        var files = Enum.GetValues<Layout>().ToDictionary(layout => layout, _ => new List<ScannedMedia>());
        Scan(path, path, 0);
        return files;

        void Scan(string root, string directory, int depth)
        {
            var children = ReadChildren(directory);
            var direct = ReadFiles(directory, children);
            var prefix = depth == 0 ? "" : RelativePath(root, directory) + "/";
            var level = files[(Layout)depth];
            if (ProbeVideoWork(directory, children, direct) is VideoWorkRecognition.Recognized(var work))
            {
                var tagged = work.IndexEntries(prefix);
                var included = tagged.Select(item => item.RelativePath).ToHashSet(StringComparer.Ordinal);
                level.AddRange(tagged);
                level.AddRange(direct.Select(item => item with { RelativePath = prefix + item.RelativePath })
                    .Where(item => !included.Contains(item.RelativePath)));
                return;
            }

            level.AddRange(direct.Select(item => item with { RelativePath = prefix + item.RelativePath }));
            if (depth < maximumDepth)
                foreach (var child in children.OfType<DirectoryInfo>())
                    Scan(root, child.FullName, depth + 1);
        }
    }

    private static VideoWorkRecognition ProbeVideoWork(string root, FileSystemInfo[] children, ScannedMedia[] direct)
    {
        var files = direct.ToList();
        foreach (var folder in children.OfType<DirectoryInfo>().Where(folder => VideoWork.Folders.Contains(folder.Name)))
        {
            var nested = ReadChildren(folder.FullName);
            files.AddRange(ReadFiles(root, nested));
            if (folder.Name == VideoWork.PhotoSetsFolder)
                foreach (var book in nested.OfType<DirectoryInfo>())
                    files.AddRange(ReadFiles(root, ReadChildren(book.FullName)));
        }
        return VideoWork.Recognize(root, files);
    }

    private static FileSystemInfo[] ReadChildren(string path) => new DirectoryInfo(path).EnumerateFileSystemInfos()
        .Where(item => !IsSkipped(item.Name, item.Attributes)).ToArray();

    private static ScannedMedia[] ReadFiles(string root, FileSystemInfo[] items) => items.OfType<FileInfo>()
        .Where(item => IsSupportedExtension(item.Extension))
        .Select(item => new ScannedMedia(RelativePath(root, item.FullName), IsVideoExtension(item.Extension)))
        .ToArray();

    private static string RelativePath(string root, string path) =>
        Path.GetRelativePath(root, path).Replace(Path.DirectorySeparatorChar, '/');

    internal static bool IsSupportedExtension(string extension) => IsVideoExtension(extension) || Images.Contains(extension);

    private static bool IsVideoExtension(string extension) =>
        extension.Equals(".mp4", StringComparison.OrdinalIgnoreCase)
        || extension.Equals(".mov", StringComparison.OrdinalIgnoreCase);

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
