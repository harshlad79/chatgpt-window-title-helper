using ChatGPTWindowTitleHelper.Interop;
using System.Diagnostics;
using System.Text;

namespace ChatGPTWindowTitleHelper.Windows;

internal sealed class WindowNameChangeMonitor : IDisposable
{
    private readonly User32.WinEventDelegate callback;
    private readonly Action<nint> onWindowNameChanged;
    private readonly Action<nint, bool> onMoveSizeChanged;
    private nint hook;
    private nint moveSizeHook;

    public WindowNameChangeMonitor(Action<nint> onWindowNameChanged, Action<nint, bool> onMoveSizeChanged)
    {
        this.onWindowNameChanged = onWindowNameChanged;
        this.onMoveSizeChanged = onMoveSizeChanged;
        callback = HandleEvent;
        hook = User32.SetWinEventHook(User32.EVENT_OBJECT_LOCATIONCHANGE, User32.EVENT_OBJECT_NAMECHANGE, 0, callback, 0, 0,
            User32.WINEVENT_OUTOFCONTEXT | User32.WINEVENT_SKIPOWNPROCESS);
        moveSizeHook = User32.SetWinEventHook(User32.EVENT_SYSTEM_MOVESIZESTART, User32.EVENT_SYSTEM_MOVESIZEEND, 0, callback, 0, 0,
            User32.WINEVENT_OUTOFCONTEXT | User32.WINEVENT_SKIPOWNPROCESS);
    }

    private void HandleEvent(nint hookHandle, uint eventType, nint hwnd, int objectId, int childId, uint threadId, uint time)
    {
        if (eventType == User32.EVENT_SYSTEM_MOVESIZESTART && IsChatGptWindow(hwnd))
            onMoveSizeChanged(hwnd, true);
        else if (eventType == User32.EVENT_SYSTEM_MOVESIZEEND && IsChatGptWindow(hwnd))
            onMoveSizeChanged(hwnd, false);
        else if (objectId == User32.OBJID_WINDOW && IsChatGptWindow(hwnd))
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
        if (moveSizeHook != 0) User32.UnhookWinEvent(moveSizeHook);
        hook = 0;
        moveSizeHook = 0;
    }
}
