using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

namespace IPreview;

internal static class MediaSearch
{
    private static readonly StringComparer NaturalName = StringComparer.Create(
        CultureInfo.InvariantCulture, CompareOptions.NumericOrdering);
    private static readonly Regex Words = new(@"[\p{L}\p{N}]+");

    public static IOrderedEnumerable<Media> ByPath(IEnumerable<Media> items) =>
        items.OrderBy(item => Normalize(item.DisplayPath), NaturalName).ThenBy(item => item.Id);

    public static List<Media> Find(IEnumerable<Media> items, string term, bool exact,
                                   bool directories, bool files)
    {
        var query = Normalize(term.Trim());
        if (!directories && !files)
            return [];
        if (query.Length == 0)
            return ByPath(items).ToList();

        var pinyin = new Dictionary<string, (string Full, string Initials)>(StringComparer.Ordinal);
        var compact = string.Concat(Words.Matches(query).Select(match => match.Value));
        var matches = new List<(Media Media, int Rank)>();
        foreach (var item in items)
        {
            var labels = item.DisplayPath.Split('/');
            var first = directories ? 0 : labels.Length - 1;
            var count = files ? labels.Length : labels.Length - 1;
            var rank = int.MaxValue;
            for (var index = first; index < count && rank > 0; index++)
                rank = Math.Min(rank, Rank(Normalize(labels[index]), query, compact, exact, pinyin));
            if (rank != int.MaxValue)
                matches.Add((item, rank));
        }

        return matches.OrderBy(match => match.Rank)
            .ThenBy(match => Normalize(match.Media.DisplayPath), NaturalName)
            .ThenBy(match => match.Media.Id)
            .Select(match => match.Media).ToList();
    }

    private static int Rank(string value, string query, string compact, bool exact,
                            Dictionary<string, (string Full, string Initials)> pinyin)
    {
        if (value.Equals(query, StringComparison.Ordinal))
            return 0;
        if (exact)
            return int.MaxValue;
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
