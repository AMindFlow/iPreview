using System.Runtime.InteropServices;

namespace IPreview;

internal sealed class Sqlite : IDisposable
{
    private const int Ok = 0;
    private const int Row = 100;
    private const int Done = 101;
    private const string Library = "winsqlite3.dll";
    private IntPtr database;

    public Sqlite(string path)
    {
        try
        {
            const int readWriteCreate = 0x00000002 | 0x00000004;
            Check(sqlite3_open_v2(path, out database, readWriteCreate, IntPtr.Zero));
            Check(sqlite3_busy_timeout(database, 3000));
            ExecuteScript("PRAGMA foreign_keys = ON;");
        }
        catch
        {
            Dispose();
            throw;
        }
    }

    public void ExecuteScript(string script)
    {
        var result = sqlite3_exec(database, script, IntPtr.Zero, IntPtr.Zero, out var message);
        if (result == Ok)
            return;
        try
        {
            throw new InvalidOperationException(Marshal.PtrToStringUTF8(message) ?? ErrorMessage);
        }
        finally
        {
            sqlite3_free(message);
        }
    }

    public void Execute(string sql, params object[] values)
    {
        WithStatement(sql, values, statement =>
        {
            var result = sqlite3_step(statement);
            if (result != Done)
                Check(result);
            return true;
        });
    }

    public List<T> Query<T>(string sql, Func<Fields, T> project, params object[] values) =>
        WithStatement(sql, values, statement =>
        {
            var rows = new List<T>();
            int result;
            while ((result = sqlite3_step(statement)) == Row)
                rows.Add(project(new Fields(statement)));
            if (result != Done)
                Check(result);
            return rows;
        });

    public void InTransaction(Action action)
    {
        ExecuteScript("BEGIN IMMEDIATE;");
        try
        {
            action();
            ExecuteScript("COMMIT;");
        }
        catch
        {
            if (sqlite3_get_autocommit(database) == 0)
                ExecuteScript("ROLLBACK;");
            throw;
        }
    }

    private T WithStatement<T>(string sql, object[] values, Func<IntPtr, T> action)
    {
        Check(sqlite3_prepare_v2(database, sql, -1, out var statement, IntPtr.Zero));
        try
        {
            for (var index = 0; index < values.Length; index++)
            {
                var parameter = index + 1;
                var result = values[index] switch
                {
                    string text => sqlite3_bind_text(statement, parameter, text, -1, new IntPtr(-1)),
                    long number => sqlite3_bind_int64(statement, parameter, number),
                    int number => sqlite3_bind_int64(statement, parameter, number),
                    _ => throw new ArgumentException("Unsupported SQLite parameter.")
                };
                Check(result);
            }
            return action(statement);
        }
        finally
        {
            sqlite3_finalize(statement);
        }
    }

    private void Check(int result)
    {
        if (result != Ok)
            throw new InvalidOperationException(ErrorMessage);
    }

    private string ErrorMessage => database == IntPtr.Zero
        ? "无法打开媒体库数据库。"
        : Marshal.PtrToStringUTF8(sqlite3_errmsg(database)) ?? "媒体库数据库错误。";

    public void Dispose()
    {
        if (database == IntPtr.Zero)
            return;
        sqlite3_close(database);
        database = IntPtr.Zero;
    }

    public readonly struct Fields(IntPtr statement)
    {
        public long Number(int index) => sqlite3_column_int64(statement, index);
        public string Text(int index) => Marshal.PtrToStringUTF8(sqlite3_column_text(statement, index))
            ?? throw new InvalidOperationException("Unexpected NULL in catalog database.");
    }

    [DllImport(Library, ExactSpelling = true, CallingConvention = CallingConvention.Cdecl)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    private static extern int sqlite3_open_v2([MarshalAs(UnmanagedType.LPUTF8Str)] string path,
        out IntPtr database, int flags, IntPtr vfs);

    [DllImport(Library, ExactSpelling = true, CallingConvention = CallingConvention.Cdecl)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    private static extern int sqlite3_close(IntPtr database);

    [DllImport(Library, ExactSpelling = true, CallingConvention = CallingConvention.Cdecl)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    private static extern IntPtr sqlite3_errmsg(IntPtr database);

    [DllImport(Library, ExactSpelling = true, CallingConvention = CallingConvention.Cdecl)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    private static extern int sqlite3_busy_timeout(IntPtr database, int milliseconds);

    [DllImport(Library, ExactSpelling = true, CallingConvention = CallingConvention.Cdecl)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    private static extern int sqlite3_get_autocommit(IntPtr database);

    [DllImport(Library, ExactSpelling = true, CallingConvention = CallingConvention.Cdecl)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    private static extern int sqlite3_exec(IntPtr database, [MarshalAs(UnmanagedType.LPUTF8Str)] string sql,
        IntPtr callback, IntPtr argument, out IntPtr message);

    [DllImport(Library, ExactSpelling = true, CallingConvention = CallingConvention.Cdecl)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    private static extern void sqlite3_free(IntPtr memory);

    [DllImport(Library, ExactSpelling = true, CallingConvention = CallingConvention.Cdecl)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    private static extern int sqlite3_prepare_v2(IntPtr database, [MarshalAs(UnmanagedType.LPUTF8Str)] string sql,
        int length, out IntPtr statement, IntPtr tail);

    [DllImport(Library, ExactSpelling = true, CallingConvention = CallingConvention.Cdecl)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    private static extern int sqlite3_bind_text(IntPtr statement, int index,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string value, int length, IntPtr destructor);

    [DllImport(Library, ExactSpelling = true, CallingConvention = CallingConvention.Cdecl)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    private static extern int sqlite3_bind_int64(IntPtr statement, int index, long value);

    [DllImport(Library, ExactSpelling = true, CallingConvention = CallingConvention.Cdecl)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    private static extern int sqlite3_step(IntPtr statement);

    [DllImport(Library, ExactSpelling = true, CallingConvention = CallingConvention.Cdecl)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    private static extern int sqlite3_finalize(IntPtr statement);

    [DllImport(Library, ExactSpelling = true, CallingConvention = CallingConvention.Cdecl)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    private static extern long sqlite3_column_int64(IntPtr statement, int index);

    [DllImport(Library, ExactSpelling = true, CallingConvention = CallingConvention.Cdecl)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    private static extern IntPtr sqlite3_column_text(IntPtr statement, int index);
}
