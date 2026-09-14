using System.Drawing;

namespace ChatGPTWindowTitleHelper.Overlay;

public static class OverlayBoundsCalculator
{
    private const int Padding = 8;

    public static Rectangle Calculate(Rectangle sectionHeader, Rectangle shareButton, Rectangle? writeButton)
    {
        var left = writeButton?.Right + Padding ?? sectionHeader.Left + Padding;
        var right = shareButton.Left - Padding;
        return new Rectangle(left, sectionHeader.Top, Math.Max(0, right - left), sectionHeader.Height);
    }
}
