using System.Text;
using ChatGPTWindowTitleHelper.Interop;
using ChatGPTWindowTitleHelper.Domain;

namespace ChatGPTWindowTitleHelper.Windows;

internal sealed class WindowTitleWriter
{
    private readonly Dictionary<nint, string> originals = [];
    private readonly Dictionary<nint, string> applied = [];

    public void Apply(TrackedWindow window)
    {
        if (string.Equals(window.CurrentTitle, "ChatGPT", StringComparison.Ordinal))
            return;

        if (!originals.ContainsKey(window.Handle))
            originals[window.Handle] = ReadTitle(window.Handle);

        var desired = $"{window.CurrentTitle} - ChatGPT";
        if (applied.TryGetValue(window.Handle, out var current) && current == desired)
            return;

        if (User32.SetWindowText(window.Handle, desired))
            applied[window.Handle] = desired;
    }

    public void ReapplyIfReplaced(TrackedWindow window)
    {
        if (string.Equals(window.CurrentTitle, "ChatGPT", StringComparison.Ordinal)) return;
        var desired = $"{window.CurrentTitle} - ChatGPT";
        if (!string.Equals(ReadTitle(window.Handle), desired, StringComparison.Ordinal))
            User32.SetWindowText(window.Handle, desired);
    }

    public void RestoreAll()
    {
        foreach (var (handle, title) in originals)
            User32.SetWindowText(handle, title);
        originals.Clear();
        applied.Clear();
    }

    private static string ReadTitle(nint handle)
    {
        var value = new StringBuilder(512);
        User32.GetWindowText(handle, value, value.Capacity);
        return value.ToString();
    }
}
