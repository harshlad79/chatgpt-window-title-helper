using System.Diagnostics;
using System.Text;
using ChatGPTWindowTitleHelper.Interop;

namespace ChatGPTWindowTitleHelper.Windows;

public sealed record WindowCandidate(nint Handle, uint ProcessId, bool IsVisible, string ClassName, string Title);

public interface IChatGptWindowDiscovery
{
    IReadOnlyList<nint> GetWindows();
}

public sealed class ChatGptWindowDiscovery : IChatGptWindowDiscovery
{
    public IReadOnlyList<nint> GetWindows()
    {
        var candidates = new List<WindowCandidate>();
        User32.EnumWindows((hwnd, _) =>
        {
            User32.GetWindowThreadProcessId(hwnd, out var processId);
            try
            {
                using var process = Process.GetProcessById((int)processId);
                if (!string.Equals(process.ProcessName, "ChatGPT", StringComparison.OrdinalIgnoreCase))
                    return true;
            }
            catch { return true; }

            var title = new StringBuilder(512);
            var className = new StringBuilder(256);
            User32.GetWindowText(hwnd, title, title.Capacity);
            User32.GetClassName(hwnd, className, className.Capacity);
            candidates.Add(new WindowCandidate(hwnd, processId, User32.IsWindowVisible(hwnd), className.ToString(), title.ToString()));
            return true;
        }, 0);

        return FilterCandidates(candidates, null);
    }

    public static IReadOnlyList<nint> FilterCandidates(IEnumerable<WindowCandidate> candidates, uint? processId)
        => candidates
            .Where(x => (!processId.HasValue || x.ProcessId == processId.Value)
                && x.IsVisible
                && string.Equals(x.ClassName, "Chrome_WidgetWin_1", StringComparison.Ordinal))
            .Select(x => x.Handle)
            .Distinct()
            .ToArray();
}
