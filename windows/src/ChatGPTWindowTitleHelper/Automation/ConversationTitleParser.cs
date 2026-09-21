namespace ChatGPTWindowTitleHelper.Automation;

public static class ConversationTitleParser
{
    public static string? TryGetTitle(IEnumerable<(string AriaProperties, string Name)> elements)
    {
        foreach (var element in elements)
        {
            if (element.AriaProperties.Contains("current=page", StringComparison.OrdinalIgnoreCase)
                && !string.IsNullOrWhiteSpace(element.Name))
                return element.Name.Trim();
        }

        return null;
    }
}
