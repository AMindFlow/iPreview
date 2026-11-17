namespace IPreview;

internal enum BrowseMode { Icons, List, Gallery }
internal enum BrowseDirection { Left, Right, Up, Down }

internal readonly record struct BrowseLayout(BrowseMode Mode, int Columns)
{
    public int? NeighborOf(int index, int count, BrowseDirection direction)
    {
        var offset = (Mode, direction) switch
        {
            (BrowseMode.List, BrowseDirection.Up) or (BrowseMode.Gallery, BrowseDirection.Left) => -1,
            (BrowseMode.List, BrowseDirection.Down) or (BrowseMode.Gallery, BrowseDirection.Right) => 1,
            (BrowseMode.Icons, BrowseDirection.Up) => -Columns,
            (BrowseMode.Icons, BrowseDirection.Down) => Columns,
            (BrowseMode.Icons, BrowseDirection.Left) when index % Columns > 0 => -1,
            (BrowseMode.Icons, BrowseDirection.Right) when index % Columns < Columns - 1 => 1,
            _ => 0
        };
        var next = index + offset;
        return offset != 0 && next >= 0 && next < count ? next : null;
    }
}
