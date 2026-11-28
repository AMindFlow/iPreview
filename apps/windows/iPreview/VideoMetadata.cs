using Windows.Storage;

namespace IPreview;

internal sealed record VideoMetadata(uint Width, uint Height, TimeSpan Duration, string? Title, string? Author)
{
    internal static async Task<VideoMetadata> ReadAsync(StorageFile file, CancellationToken token)
    {
        var video = await file.Properties.GetVideoPropertiesAsync().AsTask(token);
        if ((video.Width == 0 || video.Height == 0) && video.Duration <= TimeSpan.Zero)
            throw new InvalidDataException("无法识别视频元信息。");

        string[] authorKeys = [SystemProperties.Author, SystemProperties.Music.Artist];
        var tags = await file.Properties.RetrievePropertiesAsync(authorKeys).AsTask(token);
        var author = authorKeys.Select(key => TextValue(tags.TryGetValue(key, out var tag) ? tag : null))
            .FirstOrDefault(value => value is not null);
        return new(video.Width, video.Height, video.Duration, TextValue(video.Title), author);
    }

    private static string? TextValue(object? value)
    {
        var text = value switch
        {
            string single => single.Trim(),
            IEnumerable<string> names => string.Join("、", names.Select(name => name.Trim()).Where(name => name.Length != 0)),
            _ => null,
        };
        return string.IsNullOrEmpty(text) ? null : text;
    }
}
