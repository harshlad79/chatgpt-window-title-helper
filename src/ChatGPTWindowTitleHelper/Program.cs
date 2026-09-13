namespace ChatGPTWindowTitleHelper;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        using var singleInstance = new Mutex(true, "ChatGPTWindowTitleHelper.SingleInstance", out var created);
        if (!created) return;
        ApplicationConfiguration.Initialize();
        Application.Run(new ApplicationContext());
    }
}
