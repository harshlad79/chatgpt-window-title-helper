using ChatGPTWindowTitleHelper.Interop;
using System.Diagnostics;
using System.Text;

namespace ChatGPTWindowTitleHelper.Windows;

internal sealed class WindowNameChangeMonitor : IDisposable
{
    private readonly User32.WinEventDelegate callback;
    private readonly Action<nint> onWindowNameChanged;
    private readonly Action<nint, bool> onMoveSizeChanged;
    private readonly Action<nint> onForegroundChanged;
    private nint hook;
    private nint moveSizeHook;
    private nint foregroundHook;

    public WindowNameChangeMonitor(Action<nint> onWindowNameChanged, Action<nint, bool> onMoveSizeChanged,
        Action<nint> onForegroundChanged)
    {
        this.onWindowNameChanged = onWindowNameChanged;
        this.onMoveSizeChanged = onMoveSizeChanged;
        this.onForegroundChanged = onForegroundChanged;
        callback = HandleEvent;
        // No location-change flood. Win32 window name changes only (not caret and child UIA changes).
        hook = User32.SetWinEventHook(User32.EVENT_OBJECT_NAMECHANGE, User32.EVENT_OBJECT_NAMECHANGE, 0, callback, 0, 0,
            User32.WINEVENT_OUTOFCONTEXT | User32.WINEVENT_SKIPOWNPROCESS);
        foregroundHook = User32.SetWinEventHook(User32.EVENT_SYSTEM_FOREGROUND, User32.EVENT_SYSTEM_FOREGROUND, 0, callback, 0, 0,
            User32.WINEVENT_OUTOFCONTEXT | User32.WINEVENT_SKIPOWNPROCESS);
        moveSizeHook = User32.SetWinEventHook(User32.EVENT_SYSTEM_MOVESIZESTART, User32.EVENT_SYSTEM_MOVESIZEEND, 0, callback, 0, 0,
            User32.WINEVENT_OUTOFCONTEXT | User32.WINEVENT_SKIPOWNPROCESS);
    }

    private void HandleEvent(nint hookHandle, uint eventType, nint hwnd, int objectId, int childId, uint threadId, uint time)
    {
        // Cheap filtering first: most NAMECHANGE notifications refer to accessibility
        // children, not a ChatGPT top-level HWND. Never query their process/class.
        if (eventType == User32.EVENT_OBJECT_NAMECHANGE && objectId != User32.OBJID_WINDOW)
            return;
        if (!IsChatGptWindow(hwnd)) return;
        if (eventType == User32.EVENT_SYSTEM_FOREGROUND)
            onForegroundChanged(hwnd);
        else if (eventType == User32.EVENT_SYSTEM_MOVESIZESTART)
            onMoveSizeChanged(hwnd, true);
        else if (eventType == User32.EVENT_SYSTEM_MOVESIZEEND)
            onMoveSizeChanged(hwnd, false);
        else if (eventType == User32.EVENT_OBJECT_NAMECHANGE)
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
        if (foregroundHook != 0) User32.UnhookWinEvent(foregroundHook);
        hook = 0;
        moveSizeHook = 0;
    }
}
