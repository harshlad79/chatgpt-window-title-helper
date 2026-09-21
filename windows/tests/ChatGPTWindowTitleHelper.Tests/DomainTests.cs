using ChatGPTWindowTitleHelper.Domain;
using Xunit;

namespace ChatGPTWindowTitleHelper.Tests;

public sealed class DomainTests
{
    [Fact]
    public void Defaults_enable_both_title_features()
    {
        var settings = new AppSettings();

        Assert.True(settings.ShowConversationTitle);
        Assert.True(settings.ChangeAltTabTitle);
    }

    [Fact]
    public void Tracked_windows_are_keyed_by_handle_and_ignore_empty_titles()
    {
        var first = new TrackedWindow((nint)1, "ChatGPT");
        var second = new TrackedWindow((nint)2, "ChatGPT");

        Assert.NotEqual(first.Handle, second.Handle);
        Assert.False(first.SetTitle(""));
        Assert.True(first.SetTitle("Conversation A"));
        Assert.False(first.SetTitle("Conversation A"));
        Assert.Equal("Conversation A", first.CurrentTitle);
    }
}
