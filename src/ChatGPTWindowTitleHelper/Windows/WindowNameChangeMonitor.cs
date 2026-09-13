using ChatGPTWindowTitleHelper.Interop;
using System.Diagnostics;
using System.Text;

namespace ChatGPTWindowTitleHelper.Windows;

internal sealed class WindowNameChangeMonitor : IDisposable
{
    private readonly User32.WinEventDelegate callback;
    private readonly Action<nint> onWindowNameChanged;
    private nint hook;

    public WindowNameChangeMonitor(Action<nint> onWindowNameChanged)
    {
        this.onWindowNameChanged = onWindowNameChanged;
        callback = HandleEvent;
        hook = User32.SetWinEventHook(User32.EVENT_OBJECT_LOCATIONCHANGE, User32.EVENT_OBJECT_NAMECHANGE, 0, callback, 0, 0,
            User32.WINEVENT_OUTOFCONTEXT | User32.WINEVENT_SKIPOWNPROCESS);
    }

    private void HandleEvent(nint hookHandle, uint eventType, nint hwnd, int objectId, int childId, uint threadId, uint time)
    {
        if (objectId == User32.OBJID_WINDOW && IsChatGptWindow(hwnd))
            onWindowNameChanged(hwnd);
    }

    private static bool IsChatGptWindow(nint hwnd)
    {
        try
        {
            User32.GetWindowThreadProcessId(hwnd, out var processId);
            using var process = Process.GetProcessById((int)processId);
            if (!string.Equals(process.ProcessName, "ChatGPT", StringComparison.OrdinalIgnoreCase)) return false;
            var className = new StringBuilder(64);
            return User32.GetClassName(hwnd, className, className.Capacity) > 0
                && string.Equals(className.ToString(), "Chrome_WidgetWin_1", StringComparison.Ordinal);
        }
        catch { return false; }
    }

    public void Dispose()
    {
        if (hook == 0) return;
        User32.UnhookWinEvent(hook);
        hook = 0;
    }
}
