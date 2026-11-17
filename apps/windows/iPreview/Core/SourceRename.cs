using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace IPreview;

internal static class SourceRename
{
    private const string Kernel = "kernel32.dll";
    private const uint ReadAttributes = 0x80;
    private const uint DeleteAccess = 0x10000;
    private const uint OpenExisting = 3;
    private const uint BackupSemantics = 0x02000000;
    private const uint OpenReparsePoint = 0x00200000;
    private const int FileRenameInfo = 3;
    private const int FileAttributeTagInfo = 9;
    private const int FileIdInfo = 18;

    public static (string Parent, string Leaf) SplitPath(string relativePath)
    {
        var separator = relativePath.LastIndexOf('/');
        return separator < 0 ? ("", relativePath) : (relativePath[..separator], relativePath[(separator + 1)..]);
    }

    public static string Destination(string oldPath, string baseName, bool isDirectory)
    {
        ValidateName(baseName);
        var (parent, leaf) = SplitPath(oldPath);
        var target = isDirectory ? baseName : baseName + Path.GetExtension(leaf);
        ValidateName(target);
        return parent.Length == 0 ? target : parent + '/' + target;
    }

    private static void ValidateName(string name)
    {
        if (string.IsNullOrWhiteSpace(name) || name.Length > 255 ||
            name.StartsWith('.') || name.EndsWith('.') || name.EndsWith(' ') ||
            name.AsSpan().ContainsAny(Path.GetInvalidFileNameChars()))
            throw new IOException("名称为空、过长、隐藏，或包含 Windows 文件名不可用的字符。");
        var device = name.Split('.', 2)[0].TrimEnd(' ').ToUpperInvariant();
        if (device is "CON" or "PRN" or "AUX" or "NUL" or "CONIN$" or "CONOUT$" ||
            device.Length == 4 && (device.StartsWith("COM", StringComparison.Ordinal) ||
                                   device.StartsWith("LPT", StringComparison.Ordinal)) &&
            "123456789¹²³".Contains(device[3]))
            throw new IOException("名称是 Windows 保留的设备名。");
    }

    public static void RequireStableIdentity(Source source)
    {
        var path = MediaFiles.ResolveIndexedPath(source, "", isDirectory: true);
        var format = new DriveInfo(Path.GetPathRoot(path)!).DriveFormat;
        if (format is not ("NTFS" or "ReFS"))
            throw new IOException("Windows 实体重命名支持 NTFS 和 ReFS 本地磁盘。");
    }

    public static (bool OldExists, bool NewExists, bool OtherSpellingExists) Inspect(
        Source source, string oldPath, string newPath)
    {
        var (parent, oldLeaf) = SplitPath(oldPath);
        var (newParent, newLeaf) = SplitPath(newPath);
        if (parent != newParent)
            throw new IOException("重命名必须保留原有父目录。");
        ValidateName(oldLeaf);
        ValidateName(newLeaf);
        var directory = MediaFiles.ResolveIndexedPath(source, parent, isDirectory: true);
        var oldExists = false;
        var newExists = false;
        var otherSpellingExists = false;
        foreach (var path in Directory.EnumerateFileSystemEntries(directory))
        {
            var name = Path.GetFileName(path);
            if (name == oldLeaf)
                oldExists = true;
            else if (name == newLeaf)
                newExists = true;
            else if (StringComparer.OrdinalIgnoreCase.Equals(name, oldLeaf) ||
                     StringComparer.OrdinalIgnoreCase.Equals(name, newLeaf))
                otherSpellingExists = true;
        }
        return (oldExists, newExists, otherSpellingExists);
    }

    public static SafeFileHandle Open(Source source, string relativePath, bool isDirectory, bool forRename)
    {
        var path = MediaFiles.ResolveIndexedPath(source, relativePath, isDirectory);
        var access = ReadAttributes | (forRename ? DeleteAccess : 0u);
        var share = FileShare.ReadWrite | (forRename ? FileShare.None : FileShare.Delete);
        var handle = CreateFileW(@"\\?\" + path, access, share, IntPtr.Zero, OpenExisting,
            BackupSemantics | OpenReparsePoint, IntPtr.Zero);
        try
        {
            if (handle.IsInvalid)
                throw NativeError("无法打开待重命名的项目");
            if (!GetFileInformationByHandleEx(handle, FileAttributeTagInfo, out AttributeTag attributes,
                    (uint)Marshal.SizeOf<AttributeTag>()))
                throw NativeError("无法检查待重命名项目的属性");
            if ((attributes.Attributes & (FileAttributes.Hidden | FileAttributes.ReparsePoint)) != 0 ||
                ((attributes.Attributes & FileAttributes.Directory) != 0) != isDirectory)
                throw new IOException("待重命名项目是隐藏项、重解析点，或类型已改变。");
            AssertPath(handle, source, relativePath, isDirectory);
            return handle;
        }
        catch
        {
            handle.Dispose();
            throw;
        }
    }

    public static void AssertPath(SafeFileHandle handle, Source source, string relativePath, bool isDirectory)
    {
        var expected = @"\\?\" + MediaFiles.ResolveIndexedPath(source, relativePath, isDirectory);
        var actual = new StringBuilder(expected.Length + 1);
        var length = GetFinalPathNameByHandleW(handle, actual, (uint)actual.Capacity, 0);
        if (length == 0)
            throw NativeError("无法确认待重命名项目的实际路径");
        if (!StringComparer.OrdinalIgnoreCase.Equals(actual.ToString(), expected))
            throw new IOException("待重命名项目的实际路径已发生变化。");
    }

    public static string Identity(SafeFileHandle handle)
    {
        if (!GetFileInformationByHandleEx(handle, FileIdInfo, out FileIdentity info,
                (uint)Marshal.SizeOf<FileIdentity>()))
            throw NativeError("无法读取待重命名项目的文件标识");
        return $"{info.Volume:X16}:{info.Low:X16}{info.High:X16}";
    }

    public static string Identity(Source source, string relativePath, bool isDirectory)
    {
        using var handle = Open(source, relativePath, isDirectory, forRename: false);
        return Identity(handle);
    }

    public static void Move(SafeFileHandle handle, string leaf)
    {
        ValidateName(leaf);
        var name = Encoding.Unicode.GetBytes(leaf);
        var lengthOffset = (int)Marshal.OffsetOf<RenameInfo>(nameof(RenameInfo.NameBytes));
        var nameOffset = (int)Marshal.OffsetOf<RenameInfo>(nameof(RenameInfo.FirstCharacter));
        var buffer = new byte[Math.Max(Marshal.SizeOf<RenameInfo>(), nameOffset + name.Length + sizeof(char))];
        // A zero-filled header disallows replacement and leaves RootDirectory NULL.
        BitConverter.TryWriteBytes(buffer.AsSpan(lengthOffset, sizeof(uint)), (uint)name.Length);
        name.CopyTo(buffer, nameOffset);
        if (!SetFileInformationByHandle(handle, FileRenameInfo, buffer, (uint)buffer.Length))
            throw NativeError("无法在原目录中重命名项目");
    }

    private static IOException NativeError(string message)
    {
        var cause = new Win32Exception(Marshal.GetLastPInvokeError());
        return new IOException($"{message}。{cause.Message}", cause);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct AttributeTag
    {
        public FileAttributes Attributes;
        public uint ReparseTag;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct FileIdentity
    {
        public ulong Volume;
        public ulong Low;
        public ulong High;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct RenameInfo
    {
        public uint Flags;
        public IntPtr RootDirectory;
        public uint NameBytes;
        public char FirstCharacter;
    }

    [DllImport(Kernel, ExactSpelling = true, CharSet = CharSet.Unicode, SetLastError = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    private static extern SafeFileHandle CreateFileW(string name, uint access, FileShare share,
        IntPtr security, uint creation, uint flags, IntPtr template);

    [DllImport(Kernel, ExactSpelling = true, SetLastError = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetFileInformationByHandleEx(SafeFileHandle handle, int kind,
        out AttributeTag information, uint size);

    [DllImport(Kernel, ExactSpelling = true, SetLastError = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetFileInformationByHandleEx(SafeFileHandle handle, int kind,
        out FileIdentity information, uint size);

    [DllImport(Kernel, ExactSpelling = true, CharSet = CharSet.Unicode, SetLastError = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    private static extern uint GetFinalPathNameByHandleW(SafeFileHandle handle, StringBuilder path,
        uint capacity, uint flags);

    [DllImport(Kernel, ExactSpelling = true, SetLastError = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetFileInformationByHandle(SafeFileHandle handle, int kind,
        byte[] information, uint size);
}
