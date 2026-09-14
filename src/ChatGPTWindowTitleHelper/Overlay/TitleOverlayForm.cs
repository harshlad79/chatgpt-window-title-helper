using ChatGPTWindowTitleHelper.Interop;

namespace ChatGPTWindowTitleHelper.Overlay;

internal sealed class TitleOverlayForm : Form
{
    private readonly Font captionFont = new(SystemFonts.CaptionFont, FontStyle.Bold);
    private readonly Label label = new ClickThroughLabel { AutoSize = false, AutoEllipsis = true, TextAlign = ContentAlignment.MiddleCenter };

    public TitleOverlayForm()
    {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        TopMost = false;
        ControlBox = false;
        // Use the Windows selection palette for a deliberately strong,
        // readable contrast. These colors also follow high-contrast themes.
        BackColor = SystemColors.Highlight;
        ForeColor = SystemColors.HighlightText;
        label.BackColor = SystemColors.Highlight;
        label.ForeColor = SystemColors.HighlightText;
        label.Font = captionFont;
        Controls.Add(label);
        label.Dock = DockStyle.Fill;
    }

    public void SetTitle(string title)
    {
        label.Text = title;
        label.Font = captionFont;
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

    protected override void Dispose(bool disposing)
    {
        if (disposing) captionFont.Dispose();
        base.Dispose(disposing);
    }

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
