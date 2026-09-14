using ChatGPTWindowTitleHelper.Interop;

namespace ChatGPTWindowTitleHelper.Overlay;

internal sealed class OverlayManager : IDisposable
{
    private const int HeaderTitleInset = 0;
    private readonly Dictionary<nint, TitleOverlayForm> overlays = [];
    private readonly Dictionary<(nint Target, bool Maximized), (int OffsetX, int OffsetY, int Width)> headerLayouts = [];

    public void UpdateLayout(nint target, System.Drawing.Rectangle relativeHeader)
    {
        if (!IsTargetUsable(target)) return;
        headerLayouts[(target, User32.IsZoomed(target))] =
            (relativeHeader.Left, relativeHeader.Top, relativeHeader.Width);
    }

    public void SetTitle(nint target, string title)
    {
        if (!IsTargetUsable(target))
        {
            Remove(target);
            return;
        }

        if (User32.IsIconic(target))
        {
            if (overlays.TryGetValue(target, out var minimizedOverlay)) User32.ShowWindow(minimizedOverlay.Handle, User32.SW_HIDE);
            return;
        }

        if (!User32.GetWindowRect(target, out var rect)) return;
        var layoutKey = (target, User32.IsZoomed(target));
        if (!headerLayouts.ContainsKey(layoutKey))
            // Keep fallback coordinates relative to the target window. A
            // transient UIA failure must not move the overlay to a new
            // absolute location or erase the last known good header layout.
            headerLayouts[layoutKey] = (0, 4, Math.Max(240, rect.Right - rect.Left - 320));
        if (!overlays.TryGetValue(target, out var overlay))
        {
            overlay = new TitleOverlayForm();
            overlays[target] = overlay;
            // Keep the overlay unowned. Making it an owned window of a
            // cross-process ChatGPT HWND can cause Windows to activate the
            // owner when the overlay is shown.
            overlay.CreateControl();
        }

        overlay.ShowNoActivate();
        overlay.SetTitle(title);
        PositionOverlay(target, overlay, rect, headerLayouts.GetValueOrDefault(layoutKey));
    }

    public void Reposition(nint target)
    {
        if (!overlays.TryGetValue(target, out var overlay) || !IsTargetUsable(target))
            return;
        if (User32.IsIconic(target))
        {
            User32.ShowWindow(overlay.Handle, User32.SW_HIDE);
            return;
        }
        if (User32.GetWindowRect(target, out var rect))
            PositionOverlay(target, overlay, rect, headerLayouts.GetValueOrDefault((target, User32.IsZoomed(target))));
    }

    public void RepositionAll()
    {
        foreach (var target in overlays.Keys.ToArray())
            Reposition(target);
    }

    public void RemoveTitle(nint target) => Remove(target);

    public void HideTitle(nint target)
    {
        if (overlays.TryGetValue(target, out var overlay) && overlay.IsHandleCreated)
            User32.ShowWindow(overlay.Handle, User32.SW_HIDE);
    }

    private static void PositionOverlay(nint target, TitleOverlayForm overlay, User32.RECT rect, (int OffsetX, int OffsetY, int Width)? layout)
    {
        var left = layout.HasValue ? rect.Left + layout.Value.OffsetX + HeaderTitleInset : rect.Left + HeaderTitleInset;
        var width = layout.HasValue
            ? Math.Max(1, layout.Value.Width - HeaderTitleInset)
            : Math.Max(240, rect.Right - rect.Left - HeaderTitleInset - 150);
        var x = left;
        var y = layout.HasValue ? rect.Top + layout.Value.OffsetY + 4 : rect.Top + 4;
        // Place the overlay immediately above the target in z-order. A
        // global HWND_TOP would incorrectly put it above unrelated windows.
        var windowAboveTarget = User32.GetWindow(target, User32.GW_HWNDPREV);
        // Once the overlay is immediately above the target, GW_HWNDPREV can
        // return the overlay itself. Passing the window itself as insertAfter
        // makes SetWindowPos a no-op, which breaks tracking while the target
        // is the foreground window.
        if (windowAboveTarget == overlay.Handle)
            windowAboveTarget = User32.GetWindow(windowAboveTarget, User32.GW_HWNDPREV);
        var insertAfter = windowAboveTarget == 0 ? User32.HWND_TOP : windowAboveTarget;
        User32.SetWindowPos(overlay.Handle, insertAfter, x, y, width, 32,
            User32.SWP_NOACTIVATE | User32.SWP_NOOWNERZORDER);
    }

    public void RemoveMissing(IReadOnlySet<nint> active)
    {
        foreach (var handle in overlays.Keys.Where(x => !active.Contains(x)).ToArray())
        {
            overlays[handle].Close();
            overlays.Remove(handle);
            foreach (var key in headerLayouts.Keys.Where(x => x.Target == handle).ToArray()) headerLayouts.Remove(key);
        }
    }

    private static bool IsTargetUsable(nint target)
        => target != 0 && User32.IsWindow(target);

    private void Remove(nint target)
    {
        if (!overlays.Remove(target, out var overlay)) return;
        foreach (var key in headerLayouts.Keys.Where(x => x.Target == target).ToArray()) headerLayouts.Remove(key);
        overlay.Close();
        overlay.Dispose();
    }

    public void Dispose()
    {
        Clear();
    }

    public void Clear()
    {
        foreach (var overlay in overlays.Values) overlay.Close();
        overlays.Clear();
        headerLayouts.Clear();
    }
}
