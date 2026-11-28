using System.Buffers.Binary;
using System.Text;
using IPreview;

internal static class Mp3ArtworkChecks
{
    public static async Task Run()
    {
        var png = Convert.FromBase64String(
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jGf0AAAAASUVORK5CYII=");
        var linked = Picture(4, "https://example.invalid/cover.jpg"u8.ToArray(), "-->", 0, [0]);
        var unicodeDescription = Encoding.BigEndianUnicode.GetBytes(new string('封', 32) + "\0");
        var pngFrame = Picture(4, png, "image/png", 2, unicodeDescription);
        var tag = Tag(4, 0, [.. linked, .. pngFrame]);
        using (var file = new MemoryStream(tag))
        {
            var art = await Mp3Artwork.ReadAsync(file, CancellationToken.None);
            Require(art.Count == 1 && art[0].AsSpan().SequenceEqual(png),
                "ID3v2.4 uses sync-safe frame lengths, skips linked art and reads the embedded PNG");
        }

        byte[] jpeg = [0xFF, 0xD8, 0xFF, 0xE1, 0x00, 0x00, .. new byte[128], 0xFF, 0xD9];
        var jpegFrame = Picture(3, jpeg, "image/jpeg", 0, [0]);
        var escaped = new List<byte>();
        for (var index = 0; index < jpegFrame.Length; index++)
        {
            var value = jpegFrame[index];
            escaped.Add(value);
            if (value == 0xFF && index + 1 < jpegFrame.Length && (jpegFrame[index + 1] is 0 or >= 0xE0))
                escaped.Add(0);
        }
        using (var file = new MemoryStream(Tag(3, 0x80, escaped.ToArray())))
        {
            var art = await Mp3Artwork.ReadAsync(file, CancellationToken.None);
            Require(art.Count == 1 && art[0].AsSpan().SequenceEqual(jpeg),
                "ID3v2.3 uses big-endian frame lengths and restores unsynchronised attachment bytes");
        }

        using var damaged = new MemoryStream(tag[..^2]);
        Require((await Mp3Artwork.ReadAsync(damaged, CancellationToken.None)).Count == 0,
            "a truncated MP3 tag has no usable artwork");
    }

    private static byte[] Picture(int version, byte[] image, string mime, byte encoding, byte[] description)
    {
        byte[] payload = [encoding, .. Encoding.ASCII.GetBytes(mime), 0, 3, .. description, .. image];
        var size = SyncSafe(payload.Length);
        if (version == 3)
            BinaryPrimitives.WriteInt32BigEndian(size, payload.Length);
        return [.. "APIC"u8, .. size, 0, 0, .. payload];
    }

    private static byte[] Tag(byte version, byte flags, byte[] data) =>
        [.. "ID3"u8, version, 0, flags, .. SyncSafe(data.Length), .. data];

    private static byte[] SyncSafe(int size) =>
        [(byte)(size >> 21), (byte)(size >> 14 & 127), (byte)(size >> 7 & 127), (byte)(size & 127)];

    private static void Require(bool condition, string description)
    {
        if (!condition)
            throw new InvalidOperationException("MP3 artwork check failed: " + description);
    }
}
