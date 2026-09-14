using System.Runtime.InteropServices;
using System.Text;
using System.Drawing;

namespace ChatGPTWindowTitleHelper.Interop;

internal static class User32
{
    internal delegate bool EnumWindowsProc(nint hwnd, nint lParam);

    [DllImport("user32.dll")]
    internal static extern bool EnumWindows(EnumWindowsProc callback, nint lParam);

    [DllImport("user32.dll")]
    internal static extern uint GetWindowThreadProcessId(nint hwnd, out uint processId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    internal static extern int GetWindowText(nint hwnd, StringBuilder text, int maxCount);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    internal static extern int GetClassName(nint hwnd, StringBuilder className, int maxCount);

    [DllImport("user32.dll")]
    internal static extern bool IsWindowVisible(nint hwnd);

    [DllImport("user32.dll")]
    internal static extern bool IsWindow(nint hwnd);

    [DllImport("user32.dll")]
    internal static extern bool IsIconic(nint hwnd);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool IsZoomed(nint hwnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    internal static extern bool SetWindowText(nint hwnd, string text);

    internal static string GetWindowTitle(nint hwnd)
    {
        var value = new StringBuilder(512);
        GetWindowText(hwnd, value, value.Capacity);
        return value.ToString();
    }

    internal delegate void WinEventDelegate(nint hook, uint eventType, nint hwnd, int objectId, int childId, uint threadId, uint time);

    [DllImport("user32.dll")]
    internal static extern nint SetWinEventHook(uint eventMin, uint eventMax, nint module, WinEventDelegate callback, uint processId, uint threadId, uint flags);

    [DllImport("user32.dll")]
    internal static extern bool UnhookWinEvent(nint hook);

    [StructLayout(LayoutKind.Sequential)]
    internal struct RECT { public int Left, Top, Right, Bottom; }

    [DllImport("user32.dll")]
    internal static extern bool GetWindowRect(nint hwnd, out RECT rect);

    [DllImport("user32.dll", SetLastError = true)]
    internal static extern nint SetWindowLongPtr(nint hwnd, int index, nint value);

    [DllImport("user32.dll")]
    internal static extern bool SetWindowPos(nint hwnd, nint insertAfter, int x, int y, int width, int height, uint flags);

    [DllImport("user32.dll")]
    internal static extern nint GetWindow(nint hwnd, uint command);

    [DllImport("user32.dll")]
    internal static extern bool ShowWindow(nint hwnd, int command);

    internal const int GWL_HWNDPARENT = -8;
    internal const uint SWP_NOACTIVATE = 0x0010;
    internal const uint SWP_NOOWNERZORDER = 0x0200;
    internal const uint SWP_SHOWWINDOW = 0x0040;
    internal const int SW_SHOWNOACTIVATE = 4;
    internal static readonly nint HWND_TOPMOST = new(-1);
    internal static readonly nint HWND_TOP = new(0);
    internal const uint GW_HWNDPREV = 3;
    internal const int SW_HIDE = 0;
    internal const uint EVENT_OBJECT_NAMECHANGE = 0x800C;
    internal const uint EVENT_OBJECT_LOCATIONCHANGE = 0x800B;
    internal const uint EVENT_SYSTEM_MOVESIZESTART = 0x000A;
    internal const uint EVENT_SYSTEM_MOVESIZEEND = 0x000B;
    internal const uint WINEVENT_OUTOFCONTEXT = 0;
    internal const uint WINEVENT_SKIPOWNPROCESS = 0x0002;
    internal const int OBJID_WINDOW = 0;
}
