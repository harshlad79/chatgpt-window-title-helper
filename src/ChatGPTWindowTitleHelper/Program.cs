namespace ChatGPTWindowTitleHelper;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        var singleInstance = SingleInstanceControl.CreateMutex(out var created);
        if (!created)
        {
            bool restart;
            try { restart = SingleInstanceControl.RunDuplicateFlow(); }
            catch (WaitHandleCannotBeOpenedException)
            { MessageBox.Show("ChatGPT Window Title Helper is already running.", "ChatGPT Window Title Helper", MessageBoxButtons.OK, MessageBoxIcon.Information); return; }
            if (!restart) return;
            singleInstance.Dispose();
            singleInstance = SingleInstanceControl.AcquireAfterShutdown();
            if (singleInstance is null) return;
        }
        ApplicationConfiguration.Initialize();
        Application.Run(new ApplicationContext());
        singleInstance.Dispose();
    }
}
