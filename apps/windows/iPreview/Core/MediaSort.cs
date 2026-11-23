namespace IPreview;

internal enum MediaSortField { Original, Name, Modified, Size }

internal readonly record struct MediaFileFacts(DateTime? Modified, long? Size)
{
    public static MediaFileFacts Read(Media media)
    {
        try
        {
            var file = new FileInfo(MediaFiles.OpenPath(media));
            var size = file.Length;
            return new(file.LastWriteTimeUtc, size);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or ArgumentException)
        {
            return default;
        }
    }
}

internal readonly record struct MediaSort(MediaSortField Field, bool Descending)
{
    public bool NeedsFileFacts => Field is MediaSortField.Modified or MediaSortField.Size;

    public List<T> Arrange<T>(IReadOnlyList<T> items, Func<T, Media> media, CancellationToken cancellation = default)
    {
        if (Field == MediaSortField.Original || items.Count < 2)
            return items.ToList();

        var sort = this;
        var facts = new Dictionary<long, MediaFileFacts>();
        if (NeedsFileFacts)
        {
            foreach (var item in items)
            {
                cancellation.ThrowIfCancellationRequested();
                var file = media(item);
                facts[file.Id] = MediaFileFacts.Read(file);
            }
        }

        var ordered = items.ToList();
        ordered.Sort((left, right) =>
        {
            var a = media(left);
            var b = media(right);
            var nameOrder = MediaSearch.NaturalName.Compare(a.FileName, b.FileName);
            if (nameOrder == 0)
                nameOrder = StringComparer.Ordinal.Compare(a.FileName, b.FileName);
            var order = sort.Field switch
            {
                MediaSortField.Name => sort.Descending ? -Math.Sign(nameOrder) : nameOrder,
                MediaSortField.Modified => sort.Compare(facts[a.Id].Modified, facts[b.Id].Modified),
                MediaSortField.Size => sort.Compare(facts[a.Id].Size, facts[b.Id].Size),
                _ => throw new ArgumentOutOfRangeException(nameof(Field))
            };
            if (order != 0)
                return order;
            return nameOrder != 0 ? nameOrder : a.Id.CompareTo(b.Id);
        });
        return ordered;
    }

    private int Compare<T>(T? a, T? b) where T : struct, IComparable<T>
    {
        if (a is null)
            return b is null ? 0 : 1;
        if (b is null)
            return -1;
        return Descending ? b.Value.CompareTo(a.Value) : a.Value.CompareTo(b.Value);
    }
}
