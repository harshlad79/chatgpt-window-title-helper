using ChatGPTWindowTitleHelper.Automation;
using Xunit;

namespace ChatGPTWindowTitleHelper.Tests.Automation;

public sealed class ConversationTitleParserTests
{
    [Fact]
    public void Matches_native_conversation_title_button_in_chatgpt_2026_toolbar()
    {
        var document = new System.Drawing.Rectangle(914, 107, 915, 854);
        var titleButton = new System.Drawing.Rectangle(1031, 180, 328, 31);

        Assert.True(ConversationTitleParser.IsVisibleHeaderTitleButton(
            "261012 chatgpt-title-helper-windows #1",
            "261012 chatgpt-title-helper-windows #1", document, titleButton, false));
        Assert.False(ConversationTitleParser.IsVisibleHeaderTitleButton(
            "261012 chatgpt-title-helper-windows #1",
            "홈", document, titleButton, false));
        Assert.False(ConversationTitleParser.IsVisibleHeaderTitleButton(
            "ChatGPT", "ChatGPT", document, titleButton, false));
        Assert.False(ConversationTitleParser.IsVisibleHeaderTitleButton(
            "Topic", "Topic", document, titleButton, true));
        Assert.False(ConversationTitleParser.IsVisibleHeaderTitleButton(
            "Topic", "Topic", document,
            new System.Drawing.Rectangle(1031, 420, 328, 31), false));
        Assert.False(ConversationTitleParser.IsVisibleHeaderTitleButton(
            "Topic", "Topic", document,
            new System.Drawing.Rectangle(1800, 180, 328, 31), false));
    }

    [Fact]
    public void Returns_name_of_element_with_current_page_aria_property()
    {
        var elements = new[]
        {
            ("", "Old conversation"),
            ("expanded=true;current=page", "Current conversation")
        };

        Assert.Equal("Current conversation", ConversationTitleParser.TryGetTitle(elements));
    }

    [Fact]
    public void Returns_null_when_current_element_has_no_name()
    {
        var elements = new[] { ("current=page", " ") };

        Assert.Null(ConversationTitleParser.TryGetTitle(elements));
    }
}
