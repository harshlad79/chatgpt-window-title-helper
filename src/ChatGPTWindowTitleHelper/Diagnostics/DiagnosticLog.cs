using System.Text;

namespace ChatGPTWindowTitleHelper.Diagnostics;

internal static class DiagnosticLog
{
    private static readonly object Gate = new();
    private static readonly string DirectoryPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "ChatGPTWindowTitleHelper", "logs");
    private static readonly string FilePath = Path.Combine(DirectoryPath, "current.log");

    static DiagnosticLog()
    {
        try
        {
            Directory.CreateDirectory(DirectoryPath);
            File.WriteAllText(FilePath, string.Empty, Encoding.UTF8);
        }
        catch { /* Diagnostics must never affect the helper. */ }
    }

    public static void Info(string message) => Write("INFO", message);
    public static void Error(string message, Exception? exception = null)
        => Write("ERROR", exception is null ? message : $"{message} exception={exception.GetType().Name}: {exception.Message}");

    private static void Write(string level, string message)
    {
        try
        {
            lock (Gate)
            {
                Directory.CreateDirectory(DirectoryPath);
                File.AppendAllText(FilePath,
                    $"{DateTimeOffset.Now:O} [{level}] {message}{Environment.NewLine}", Encoding.UTF8);
            }
        }
        catch { /* Diagnostics must never affect the helper. */ }
    }
}
