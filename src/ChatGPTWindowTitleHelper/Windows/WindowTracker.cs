using ChatGPTWindowTitleHelper.Automation;
using ChatGPTWindowTitleHelper.Domain;

namespace ChatGPTWindowTitleHelper.Windows;

public enum TitleUpdateResult
{
    NotTracked,
    ReadFailed,
    Unchanged,
    Changed
}

public sealed class WindowTracker(IChatGptWindowDiscovery discovery, IConversationTitleReader titleReader)
{
    private readonly object gate = new();
    private readonly Dictionary<nint, TrackedWindow> windows = [];
    public IReadOnlyCollection<TrackedWindow> Windows
    {
        get { lock (gate) return windows.Values.ToArray(); }
    }

    public void Refresh()
    {
        var current = discovery.GetWindows().ToHashSet();
        lock (gate)
        {
            foreach (var handle in current)
                if (!windows.ContainsKey(handle))
                    windows[handle] = new TrackedWindow(handle, "ChatGPT");
            foreach (var handle in windows.Keys.Where(x => !current.Contains(x)).ToArray())
                windows.Remove(handle);
        }
    }

    public TitleUpdateResult TryUpdateTitle(nint handle)
    {
        lock (gate) { if (!windows.ContainsKey(handle)) return TitleUpdateResult.NotTracked; }
        if (!titleReader.TryReadTitle(handle, out var title)) return TitleUpdateResult.ReadFailed;
        return ApplyTitle(handle, title);
    }

    public TitleUpdateResult TryReadTitle(nint handle, out string title)
    {
        title = string.Empty;
        lock (gate) { if (!windows.ContainsKey(handle)) return TitleUpdateResult.NotTracked; }
        return titleReader.TryReadTitle(handle, out title)
            ? TitleUpdateResult.Unchanged : TitleUpdateResult.ReadFailed;
    }

    public TitleUpdateResult ApplyTitle(nint handle, string title)
    {
        lock (gate)
        {
            if (!windows.TryGetValue(handle, out var window)) return TitleUpdateResult.NotTracked;
            return window.SetTitle(title) ? TitleUpdateResult.Changed : TitleUpdateResult.Unchanged;
        }
    }

    public void SetSectionHeaderBounds(nint handle, System.Drawing.Rectangle? bounds)
    {
        lock (gate)
            if (windows.TryGetValue(handle, out var window)) window.SetSectionHeaderBounds(bounds);
    }

    public void SetHasVisibleTitleButton(nint handle, bool value)
    {
        lock (gate)
            if (windows.TryGetValue(handle, out var window)) window.SetHasVisibleTitleButton(value);
    }
}
