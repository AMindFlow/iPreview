using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

namespace IPreview;

internal enum GlobalSearchScope { All, Files, Directories }
internal enum SearchResultCategory { Creator, Album, Directory, File }

internal readonly record struct GlobalSearchTerm(string Text, bool Exact)
{
    public static GlobalSearchTerm Parse(string input)
    {
        var text = input.AsSpan().TrimStart();
        var exact = text.Length >= 2 && (text[0] is '@' or '＠') && char.IsWhiteSpace(text[1]);
        return new((exact ? text[1..] : text).Trim().ToString(), exact);
    }
}

internal sealed record GlobalSearchHit(Source Source, string? Folder, string Name, string Location, Media? Media = null)
{
    public SearchResultCategory Category => Media is not null ? SearchResultCategory.File
        : (Source.Layout, Folder?.Count(character => character == '/') ?? 0) switch
        {
            (Layout.Creator, 0) or (Layout.MultiCreator, 1) => SearchResultCategory.Creator,
            (Layout.Flat, 0) or (Layout.Creator, 1) or (Layout.MultiCreator, 2) => SearchResultCategory.Album,
            _ => SearchResultCategory.Directory
        };

    public SourceAlbumKey? SourceAlbum => Media is { } item ? SourceAlbumKey.FromMedia(item)
        : Category == SearchResultCategory.Album ? new SourceAlbumKey(Source.Id, Folder?.TrimEnd('/') ?? "") : null;

    public string Details => Category switch
    {
        SearchResultCategory.Creator => $"创作者 · {Location}",
        SearchResultCategory.Album => $"专辑 · {Location}",
        _ => Location
    };

    public string Glyph => Category switch
    {
        SearchResultCategory.Creator => "\uE77B",
        SearchResultCategory.Album => "\uE7B8",
        SearchResultCategory.Directory => "\uE8B7",
        _ => Media is { IsVideo: true } ? "\uE714" : "\uEB9F"
    };
}

internal static class MediaSearch
{
    private static readonly StringComparer NaturalName = StringComparer.Create(
        CultureInfo.InvariantCulture, CompareOptions.NumericOrdering);
    private static readonly Regex Words = new(@"[\p{L}\p{N}]+");

    public static IOrderedEnumerable<Media> ByPath(IEnumerable<Media> items) =>
        ByNaturalPath(items, item => item.DisplayPath).ThenBy(item => item.Id);

    internal static IOrderedEnumerable<T> ByNaturalPath<T>(IEnumerable<T> items, Func<T, string> path) =>
        items.OrderBy(item => Normalize(path(item)), NaturalName);

    public static List<GlobalSearchHit> Find(IEnumerable<Source> sources, IEnumerable<Media> items,
                                             GlobalSearchTerm term, GlobalSearchScope scope,
                                             string? folderRoot = null, IReadOnlySet<SourceAlbumKey>? taggedAlbums = null)
    {
        if (term.Text.Length == 0 && taggedAlbums is null)
            return [];

        Func<string, bool, int> rankName = term.Text.Length == 0 ? (_, _) => 0 : Matcher(Normalize(term.Text), term.Exact);
        bool Includes(GlobalSearchHit hit) => taggedAlbums is null ||
            hit.SourceAlbum is { } album && taggedAlbums.Contains(album);
        var seen = new HashSet<(long Source, string Folder)>();
        var matches = new List<(GlobalSearchHit Hit, int Rank)>();
        void AddFolder(Source source, string folder, string label, string location)
        {
            if (!seen.Add((source.Id, folder)))
                return;
            var rank = rankName(label, false);
            var hit = new GlobalSearchHit(source, folder.Length == 0 ? null : folder, label, location);
            if (rank != int.MaxValue && Includes(hit))
                matches.Add((hit, rank));
        }
        if (scope != GlobalSearchScope.Files && folderRoot is null)
            foreach (var source in sources)
                AddFolder(source, "", source.Name, Path.GetDirectoryName(source.Path) ?? source.Path);

        foreach (var item in items.Where(item => item.Present &&
            (folderRoot is null || item.RelativePath.StartsWith(folderRoot, StringComparison.Ordinal))))
        {
            var parts = item.RelativePath.Split('/');
            var folder = "";
            for (var index = 0; index < parts.Length - 1; index++)
            {
                var parent = folder;
                folder += parts[index] + "/";
                if (scope != GlobalSearchScope.Files &&
                    (folderRoot is null || folder.StartsWith(folderRoot, StringComparison.Ordinal)))
                    AddFolder(item.Source, folder, parts[index], DirectoryDisplay(item.Source, parent));
            }
            if (scope == GlobalSearchScope.Directories)
                continue;
            var rank = rankName(parts[^1], true);
            var hit = new GlobalSearchHit(item.Source, folder.Length == 0 ? null : folder, parts[^1],
                DirectoryDisplay(item.Source, folder), item);
            if (rank != int.MaxValue && Includes(hit))
                matches.Add((hit, rank));
        }

        return matches.OrderBy(match => match.Rank)
            .ThenBy(match => match.Hit.Media is not null)
            .ThenBy(match => Normalize(match.Hit.Location), NaturalName)
            .ThenBy(match => Normalize(match.Hit.Name), NaturalName)
            .ThenBy(match => match.Hit.Source.Id)
            .Select(match => match.Hit).ToList();
    }

    private static string DirectoryDisplay(Source source, string folder) =>
        folder.Length == 0 ? source.Name : source.Name + "/" + folder.TrimEnd('/');

    private static Func<string, bool, int> Matcher(string query, bool exact)
    {
        if (exact)
        {
            var suffix = FileSuffixIndex(query);
            var acceptsOmittedSuffix = suffix < 0 || !MediaFiles.IsSupportedExtension(query[suffix..]);
            return (label, isFile) => RankExact(Normalize(label), query, acceptsOmittedSuffix && isFile);
        }

        var pinyin = new Dictionary<string, (string Full, string Initials)>(StringComparer.Ordinal);
        var compact = string.Concat(Words.Matches(query).Select(match => match.Value));
        return (label, _) => Rank(Normalize(label), query, compact, pinyin);
    }

    private static int RankExact(string value, string query, bool acceptsOmittedSuffix)
    {
        if (value.Equals(query, StringComparison.Ordinal))
            return 0;
        var suffix = acceptsOmittedSuffix ? FileSuffixIndex(value) : -1;
        return suffix >= 0 && value.AsSpan(0, suffix).SequenceEqual(query.AsSpan()) ? 0 : int.MaxValue;
    }

    private static int FileSuffixIndex(string value)
    {
        var dot = value.LastIndexOf('.');
        return dot > 0 && dot < value.Length - 1 ? dot : -1;
    }

    private static int Rank(string value, string query, string compact,
                            Dictionary<string, (string Full, string Initials)> pinyin)
    {
        if (value.Equals(query, StringComparison.Ordinal))
            return 0;
        if (value.StartsWith(query, StringComparison.Ordinal))
            return 1;
        if (value.Contains(query, StringComparison.Ordinal))
            return 2;
        if (compact.Length != 0 && HasHan(value))
        {
            if (!pinyin.TryGetValue(value, out var keys))
            {
                keys = Pinyin(value);
                pinyin.Add(value, keys);
            }
            if (keys.Full.Contains(compact, StringComparison.Ordinal))
                return 3;
            if (keys.Initials.Contains(compact, StringComparison.Ordinal))
                return 4;
        }

        var threshold = query.Length switch { < 3 => 0, < 7 => 1, _ => 2 };
        if (threshold != 0 && (WithinDistance(query, value, threshold)
            || Words.Matches(value).Any(word => WithinDistance(query, word.Value, threshold))))
            return 5;
        return int.MaxValue;
    }

    private static string Normalize(string text) => text.Normalize(NormalizationForm.FormKC).ToLowerInvariant();

    private static bool HasHan(string value)
    {
        foreach (var rune in value.EnumerateRunes())
        {
            if (rune.Value is >= 0x3400 and <= 0x9FFF or >= 0xF900 and <= 0xFAFF
                or >= 0x20000 and <= 0x323AF)
                return true;
        }
        return false;
    }

    private static (string Full, string Initials) Pinyin(string text)
    {
        var romanization = PinyinIcu.Transliterate(text)
            .Normalize(NormalizationForm.FormD).ToLowerInvariant();
        var normalized = new StringBuilder(romanization.Length);
        foreach (var rune in romanization.EnumerateRunes())
        {
            var category = Rune.GetUnicodeCategory(rune);
            if (rune.Value == 0x0308 && normalized.Length > 0 && normalized[^1] == 'u')
                normalized[^1] = 'v';
            if (category is not (UnicodeCategory.NonSpacingMark or UnicodeCategory.EnclosingMark))
                normalized.Append(rune);
        }
        var words = Words.Matches(normalized.ToString()).Select(match => match.Value).ToArray();
        return (string.Concat(words), string.Concat(words.Select(word => Rune.GetRuneAt(word, 0).ToString())));
    }

    private static bool WithinDistance(string query, string value, int limit)
    {
        if (Math.Abs(value.Length - query.Length) > limit)
            return false;

        var previous = new int[value.Length + 1];
        var current = new int[value.Length + 1];
        for (var column = 0; column <= value.Length; column++)
            previous[column] = column;
        for (var row = 1; row <= query.Length; row++)
        {
            current[0] = row;
            for (var column = 1; column <= value.Length; column++)
            {
                var replacement = previous[column - 1] + (query[row - 1] == value[column - 1] ? 0 : 1);
                current[column] = Math.Min(replacement, Math.Min(previous[column] + 1, current[column - 1] + 1));
            }
            (previous, current) = (current, previous);
        }

        return previous[value.Length] <= limit;
    }
}

internal static class PinyinIcu
{
    public static unsafe string Transliterate(string text)
    {
        const string transform = "Han-Latin";
        var error = 0;
        var transliterator = utrans_openU(transform, transform.Length, 0, IntPtr.Zero, 0, IntPtr.Zero, ref error);
        if (error > 0 || transliterator == IntPtr.Zero)
            throw new InvalidOperationException($"无法初始化 Windows 拼音转写（ICU {error}）。");

        try
        {
            var capacity = text.Length * 8 + 8;
            while (true)
            {
                var buffer = new char[capacity];
                text.CopyTo(0, buffer, 0, text.Length);
                var length = text.Length;
                var limit = length;
                error = 0;
                fixed (char* data = buffer)
                    utrans_transUChars(transliterator, data, ref length, capacity, 0, ref limit, ref error);
                if (error == 15 && length >= capacity) // U_BUFFER_OVERFLOW_ERROR
                {
                    capacity = length + 1;
                    continue;
                }
                if (error > 0)
                    throw new InvalidOperationException($"Windows 拼音转写失败（ICU {error}）。");
                return new string(buffer, 0, length);
            }
        }
        finally
        {
            utrans_close(transliterator);
        }
    }

    [DllImport("icu.dll", ExactSpelling = true, CharSet = CharSet.Unicode, CallingConvention = CallingConvention.Cdecl)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    private static extern IntPtr utrans_openU([MarshalAs(UnmanagedType.LPWStr)] string id,
        int idLength, int direction, IntPtr rules, int rulesLength, IntPtr parseError, ref int status);

    [DllImport("icu.dll", ExactSpelling = true, CallingConvention = CallingConvention.Cdecl)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    private static extern unsafe void utrans_transUChars(IntPtr transliterator, char* text, ref int length,
        int capacity, int start, ref int limit, ref int status);

    [DllImport("icu.dll", ExactSpelling = true, CallingConvention = CallingConvention.Cdecl)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    private static extern void utrans_close(IntPtr transliterator);
}
