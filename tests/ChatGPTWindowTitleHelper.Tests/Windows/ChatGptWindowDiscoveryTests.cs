using ChatGPTWindowTitleHelper.Windows;
using Xunit;

namespace ChatGPTWindowTitleHelper.Tests.Windows;

public sealed class ChatGptWindowDiscoveryTests
{
    [Fact]
    public void Filters_to_visible_top_level_ChatGPT_widget_windows()
    {
        var candidates = new[]
        {
            new WindowCandidate((nint)1, 42, true, "Chrome_WidgetWin_1", "ChatGPT"),
            new WindowCandidate((nint)2, 42, true, "Chrome_WidgetWin_0", ""),
            new WindowCandidate((nint)3, 42, false, "Chrome_WidgetWin_1", "ChatGPT"),
            new WindowCandidate((nint)4, 42, true, "Chrome_WidgetWin_1", "Other")
        };

        var result = ChatGptWindowDiscovery.FilterCandidates(candidates, 42);

        Assert.Equal(2, result.Count);
        Assert.Contains((nint)1, result);
        Assert.Contains((nint)4, result);
    }
}
