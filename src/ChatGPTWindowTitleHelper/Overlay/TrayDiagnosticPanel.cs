using System.Text;
using ChatGPTWindowTitleHelper.Domain;
using ChatGPTWindowTitleHelper.Interop;
using ChatGPTWindowTitleHelper.Diagnostics;

namespace ChatGPTWindowTitleHelper.Overlay;

internal sealed class TrayDiagnosticPanel : Form
{
    private readonly Label label = new()
    {
        AutoSize = false,
        Dock = DockStyle.Fill,
        ForeColor = Color.Gainsboro,
        BackColor = Color.FromArgb(32, 32, 32),
        Padding = new Padding(10, 8, 10, 8),
        TextAlign = ContentAlignment.MiddleLeft,
        Font = SystemFonts.MessageBoxFont
    };

    public TrayDiagnosticPanel()
    {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        TopMost = true;
        ShowIcon = false;
        Controls.Add(label);
    }

    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            var parameters = base.CreateParams;
            // TOOLWINDOW + NOACTIVATE. Do not use
            // WS_EX_LAYERED here: without a per-pixel surface it can produce
            // an invisible panel on some Windows configurations.
            parameters.ExStyle |= 0x00000080 | 0x08000000;
            return parameters;
        }
    }

    public void UpdateWindows(IReadOnlyList<TrackedWindow> windows)
    {
        var text = new StringBuilder("ChatGPT Window Title Helper\r\n");
        foreach (var window in windows)
        {
            var nativeTitle = User32.GetWindowTitle(window.Handle);
            var found = !string.Equals(window.CurrentTitle, "ChatGPT", StringComparison.Ordinal);
            text.Append("0x").Append(window.Handle.ToInt64().ToString("X"))
                .Append(" | ").Append(nativeTitle.Length == 0 ? "(no window text)" : nativeTitle)
                .Append(" | ").Append(found ? window.CurrentTitle : "(title not found)")
                .Append(" | ").Append(found ? "OK" : "UIA pending/failed")
                .Append("\r\n");
        }

        label.Text = text.ToString().TrimEnd();
        Size = new Size(Math.Min(760, Math.Max(420, PreferredWidth())), Math.Min(260, Math.Max(58, 38 + windows.Count * 28)));
        var workArea = Screen.PrimaryScreen?.WorkingArea ?? Screen.FromPoint(Cursor.Position).WorkingArea;
        Location = new Point(workArea.Right - Width - 8, workArea.Bottom - Height - 8);
        DiagnosticLog.Info($"panel-update windows={windows.Count} visible={Visible} location={Left},{Top} size={Width}x{Height}");
        if (!Visible) Show();
        User32.SetWindowPos(Handle, User32.HWND_TOPMOST, Left, Top, Width, Height,
            User32.SWP_NOACTIVATE | User32.SWP_SHOWWINDOW);
    }

    private int PreferredWidth() => Math.Max(420, label.PreferredSize.Width + 20);

    protected override void WndProc(ref Message message)
    {
        if (message.Msg == 0x84) { message.Result = (nint)(-1); return; }
        base.WndProc(ref message);
    }
}
