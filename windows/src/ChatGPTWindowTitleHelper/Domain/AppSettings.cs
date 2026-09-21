namespace ChatGPTWindowTitleHelper.Domain;

public sealed record AppSettings
{
    public bool ShowConversationTitle { get; init; } = true;
    public bool ShowTrayInspector { get; init; } = false;
    public bool ChangeAltTabTitle { get; init; } = true;
}
