using ChatGPTWindowTitleHelper.Interop;

namespace ChatGPTWindowTitleHelper.Overlay;

internal sealed class TitleOverlayForm : Form
{
    private readonly Label label = new ClickThroughLabel { AutoSize = false, AutoEllipsis = true, TextAlign = ContentAlignment.MiddleCenter, ForeColor = Color.Gainsboro, BackColor = Color.FromArgb(32, 32, 32) };

    public TitleOverlayForm()
    {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        TopMost = false;
        ControlBox = false;
        BackColor = Color.FromArgb(32, 32, 32);
        label.Font = SystemFonts.CaptionFont;
        Controls.Add(label);
        label.Dock = DockStyle.Fill;
    }

    public void SetTitle(string title)
    {
        label.Text = title;
        label.Font = SystemFonts.CaptionFont;
    }

    public void ShowNoActivate()
    {
        if (!IsHandleCreated) CreateHandle();
        // Keep WinForms' visible/paint state in sync. WS_EX_NOACTIVATE and
        // ShowWithoutActivation prevent this from activating the target.
        base.SetVisibleCore(true);
        User32.ShowWindow(Handle, User32.SW_SHOWNOACTIVATE);
    }

    // Showing this helper window must never activate it or move keyboard focus.
    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            var parameters = base.CreateParams;
            // Tool window + no activation. Keep this as an ordinary painted
            // window so the title is reliably rendered by WinForms.
            parameters.ExStyle |= 0x00000080 | 0x08000000 | 0x00000020;
            return parameters;
        }
    }

    protected override void WndProc(ref Message message)
    {
        // Never let this helper window activate itself through mouse input.
        if (message.Msg == 0x21) { message.Result = (nint)3; return; } // WM_MOUSEACTIVATE / MA_NOACTIVATE
        if (message.Msg == 0x84) { message.Result = (nint)(-1); return; }
        base.WndProc(ref message);
    }

    private sealed class ClickThroughLabel : Label
    {
        protected override void WndProc(ref Message message)
        {
            if (message.Msg == 0x84) { message.Result = (nint)(-1); return; }
            if (message.Msg == 0x21) { message.Result = (nint)3; return; }
            base.WndProc(ref message);
        }
    }
}
