namespace IPreview;

/// <summary>The spread containing the active image in the current contiguous run of images.</summary>
internal readonly record struct PhotoSpread(int First, int? Second, int? Previous, int? Next)
{
    public static PhotoSpread Around(int index, int count, bool coverSingle, Func<int, bool> isImage)
    {
        var cover = index;
        while (cover > 0 && isImage(cover - 1))
            cover--;
        var pairedStart = coverSingle ? cover + 1 : cover;
        var first = index < pairedStart ? index : index - (index - pairedStart) % 2;
        var following = first + 1;
        int? second = first >= pairedStart && following < count && isImage(following) ? following : null;
        var prior = first > pairedStart ? first - 2 : first - 1;
        var after = (second ?? first) + 1;
        return new(first, second, prior >= 0 ? prior : null, after < count ? after : null);
    }
}
