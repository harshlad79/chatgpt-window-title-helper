namespace ChatGPTWindowTitleHelper.Domain;

public enum TitleButtonState { Unknown, Present, Absent }

public sealed class TrackedWindow(nint handle, string originalTitle)
{
    public nint Handle { get; } = handle;
    public string OriginalTitle { get; } = originalTitle;
    public string CurrentTitle { get; private set; } = "ChatGPT";
    public System.Drawing.Rectangle? SectionHeaderBounds { get; private set; }
    public TitleButtonState TitleButtonState { get; private set; }
    public void SetSectionHeaderBounds(System.Drawing.Rectangle? bounds)
    {
        // A transient UIA failure is not a new position. Keep the last
        // successful bounds until a later read succeeds.
        if (bounds.HasValue)
            SectionHeaderBounds = bounds;
    }
    public void SetHasVisibleTitleButton(bool value)
        => TitleButtonState = value ? TitleButtonState.Present : TitleButtonState.Absent;

    public bool SetTitle(string title)
    {
        if (string.IsNullOrWhiteSpace(title) || string.Equals(CurrentTitle, title, StringComparison.Ordinal))
            return false;

        CurrentTitle = title;
        return true;
    }
}
