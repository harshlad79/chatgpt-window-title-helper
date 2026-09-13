using ChatGPTWindowTitleHelper.Automation;
using Xunit;

namespace ChatGPTWindowTitleHelper.Tests.Automation;

public sealed class ConversationTitleParserTests
{
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
