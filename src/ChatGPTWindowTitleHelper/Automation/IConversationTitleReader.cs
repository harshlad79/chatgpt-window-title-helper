namespace ChatGPTWindowTitleHelper.Automation;

public interface IConversationTitleReader
{
    bool TryReadTitle(nint hwnd, out string title);
}
