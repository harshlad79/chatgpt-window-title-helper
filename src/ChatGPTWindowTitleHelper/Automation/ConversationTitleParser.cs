namespace ChatGPTWindowTitleHelper.Automation;

public static class ConversationTitleParser
{
    public static bool IsVisibleHeaderTitleButton(
        string documentTitle, string buttonName, System.Drawing.Rectangle documentBounds,
        System.Drawing.Rectangle buttonBounds, bool isOffscreen)
    {
        // Reject a matching sidebar item or an offscreen duplicate: only the
        // visible content toolbar near the document top qualifies.
        return !isOffscreen
            && !string.IsNullOrWhiteSpace(documentTitle)
            && !string.Equals(documentTitle, "ChatGPT", StringComparison.OrdinalIgnoreCase)
            && string.Equals(documentTitle.Trim(), buttonName?.Trim(), StringComparison.Ordinal)
            && documentBounds.Width > 0 && documentBounds.Height > 0
            && buttonBounds.Width >= 30 && buttonBounds.Height >= 15
            && buttonBounds.Left >= documentBounds.Left
            && buttonBounds.Right <= documentBounds.Right
            && buttonBounds.Top >= documentBounds.Top
            && buttonBounds.Bottom <= documentBounds.Top + 155;
    }

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
