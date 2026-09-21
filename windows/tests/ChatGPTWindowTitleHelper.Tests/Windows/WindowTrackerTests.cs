using ChatGPTWindowTitleHelper.Domain;
using Xunit;

namespace ChatGPTWindowTitleHelper.Tests.Windows;

public sealed class WindowTrackerTests
{
    [Fact]
    public void Keeps_last_valid_title_when_reader_temporarily_fails()
    {
        var window = new TrackedWindow((nint)10, "ChatGPT");
        Assert.True(window.SetTitle("Known title"));

        Assert.Equal("Known title", window.CurrentTitle);
    }
}
