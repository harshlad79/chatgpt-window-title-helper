using System.Drawing;
using ChatGPTWindowTitleHelper.Overlay;
using Xunit;

namespace ChatGPTWindowTitleHelper.Tests;

public sealed class OverlayBoundsCalculatorTests
{
    [Fact]
    public void Expanded_sidebar_uses_section_left_and_share_left()
    {
        var result = OverlayBoundsCalculator.Calculate(
            new Rectangle(100, 40, 800, 46),
            new Rectangle(800, 49, 62, 28),
            null);

        Assert.Equal(new Rectangle(108, 40, 684, 46), result);
    }

    [Fact]
    public void Collapsed_sidebar_uses_write_button_right_and_share_left()
    {
        var result = OverlayBoundsCalculator.Calculate(
            new Rectangle(100, 40, 800, 46),
            new Rectangle(800, 49, 62, 28),
            new Rectangle(108, 49, 28, 28));

        Assert.Equal(new Rectangle(144, 40, 648, 46), result);
    }
}
