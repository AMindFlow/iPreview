using System.Buffers.Binary;

namespace IPreview;

internal static class Mp3Artwork
{
    private const int HeaderSize = 10;
    private const int MaxTagSize = 32 * 1024 * 1024;

    public static async Task<IReadOnlyList<ArraySegment<byte>>> ReadAsync(Stream input, CancellationToken cancellationToken)
    {
        var header = new byte[HeaderSize];
        if (await input.ReadAtLeastAsync(header, HeaderSize, false, cancellationToken) != HeaderSize ||
            !header.AsSpan(0, 3).SequenceEqual("ID3"u8) || header[3] is not (3 or 4))
            return [];

        var size = SyncSafeLength(header.AsSpan(6));
        if (size <= 0 || size > MaxTagSize || input.CanSeek && size > input.Length - input.Position)
            return [];
        var tag = new byte[size];
        if (await input.ReadAtLeastAsync(tag, size, false, cancellationToken) != size)
            return [];

        return Pictures(tag, header[3], header[5]);
    }

    private static List<ArraySegment<byte>> Pictures(byte[] tag, int version, byte flags)
    {
        var unsynchronised = (flags & 0x80) != 0;
        var length = version == 3 && unsynchronised ? RemoveUnsynchronisation(tag) : tag.Length;
        var offset = 0;
        if ((flags & 0x40) != 0)
        {
            if (length < 4)
                return [];
            // v2.3 stores the length following the size field. v2.4 includes the size field.
            var extendedSize = version == 3 ? BinaryPrimitives.ReadInt32BigEndian(tag) : SyncSafeLength(tag);
            var sizeField = version == 3 ? 4 : 0;
            if (extendedSize < 6 || extendedSize > length - sizeField)
                return [];
            offset = extendedSize + sizeField;
        }

        var pictures = new List<ArraySegment<byte>>();
        while (length - offset >= HeaderSize && tag[offset] != 0)
        {
            var frame = tag.AsSpan(offset, HeaderSize);
            var size = version == 3
                ? BinaryPrimitives.ReadInt32BigEndian(frame[4..])
                : SyncSafeLength(frame[4..]);
            offset += HeaderSize;
            if (size <= 0 || size > length - offset)
                break;
            if (frame[..4].SequenceEqual("APIC"u8) &&
                ReadPicture(new(tag, offset, size), version, frame[9], unsynchronised) is { } picture)
                pictures.Add(picture);
            offset += size;
        }
        return pictures;
    }

    private static ArraySegment<byte>? ReadPicture(ArraySegment<byte> frame, int version, byte format, bool unsynchronised)
    {
        int prefix;
        if (version == 3)
        {
            if ((format & 0xC0) != 0) // Requires decompression or decryption.
                return null;
            prefix = (format & 0x20) != 0 ? 1 : 0;
        }
        else
        {
            if ((format & 0x0C) != 0) // Requires decompression or decryption.
                return null;
            if (unsynchronised || (format & 0x02) != 0)
                frame = frame.Slice(0, RemoveUnsynchronisation(frame.AsSpan()));
            prefix = ((format & 0x40) != 0 ? 1 : 0) + ((format & 0x01) != 0 ? 4 : 0);
        }

        var bytes = frame.AsSpan();
        if (prefix >= bytes.Length || bytes[prefix] > 3)
            return null;

        var mime = bytes[(prefix + 1)..];
        var mimeEnd = mime.IndexOf((byte)0);
        if (mimeEnd <= 0 || mime[..mimeEnd].SequenceEqual("-->"u8))
            return null; // Linked covers are not local embedded images.

        var description = prefix + mimeEnd + 3; // Encoding, MIME terminator and picture type.
        var width = bytes[prefix] is 1 or 2 ? 2 : 1;
        for (var index = description; index + width < bytes.Length; index += width)
        {
            if (bytes[index] == 0 && (width == 1 || bytes[index + 1] == 0))
                return frame.Slice(index + width);
        }
        return null;
    }

    private static int SyncSafeLength(ReadOnlySpan<byte> bytes)
    {
        var value = 0;
        foreach (var part in bytes[..4])
        {
            if ((part & 0x80) != 0)
                return -1;
            value = (value << 7) | part;
        }
        return value;
    }

    private static int RemoveUnsynchronisation(Span<byte> bytes)
    {
        var output = 0;
        for (var index = 0; index < bytes.Length; index++)
        {
            var value = bytes[index];
            bytes[output++] = value;
            if (value == 0xFF && index + 1 < bytes.Length && bytes[index + 1] == 0)
                index++;
        }
        return output;
    }
}
