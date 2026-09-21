using System.Diagnostics;

namespace ChatGPTWindowTitleHelper;

internal static class SingleInstanceControl
{
    private const string MutexName = "ChatGPTWindowTitleHelper.SingleInstance";
    private const string RequestName = "ChatGPTWindowTitleHelper.ShutdownRequest";
    private const string AckName = "ChatGPTWindowTitleHelper.ShutdownAck";
    private const string DoneName = "ChatGPTWindowTitleHelper.ShutdownDone";

    internal static Mutex CreateMutex(out bool created) => new(true, MutexName, out created);

    internal static Mutex? AcquireAfterShutdown()
    {
        for (var i = 0; i < 30; i++)
        {
            var mutex = CreateMutex(out var created);
            if (created) return mutex;
            try
            {
                if (mutex.WaitOne(0)) return mutex;
            }
            catch (AbandonedMutexException) { return mutex; }
            mutex.Dispose();
            Thread.Sleep(100);
        }
        return null;
    }

    internal static bool RunDuplicateFlow()
    {
        var answer = MessageBox.Show(
            "ChatGPT Window Title Helper is already running. Close the existing instance and start this one?",
            "ChatGPT Window Title Helper",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Question);
        if (answer != DialogResult.Yes) return false;

        using var request = EventWaitHandle.OpenExisting(RequestName);
        using var ack = EventWaitHandle.OpenExisting(AckName);
        using var done = EventWaitHandle.OpenExisting(DoneName);
        ack.Reset();
        done.Reset();
        request.Set();
        if (!ack.WaitOne(TimeSpan.FromSeconds(1)))
        {
            MessageBox.Show("The running instance did not accept the shutdown request.", "ChatGPT Window Title Helper", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return false;
        }
        if (done.WaitOne(TimeSpan.FromSeconds(3))) return true;

        var forceAnswer = MessageBox.Show("The running instance did not exit within 3 seconds. Force it to close and start a new instance?", "ChatGPT Window Title Helper", MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
        if (forceAnswer != DialogResult.Yes) return false;
        foreach (var process in Process.GetProcessesByName("ChatGPTWindowTitleHelper"))
        {
            try
            {
                if (process.Id != Environment.ProcessId && string.Equals(process.MainModule?.FileName, Environment.ProcessPath, StringComparison.OrdinalIgnoreCase))
                    process.Kill(true);
            }
            catch { }
            finally { process.Dispose(); }
        }
        foreach (var _ in Enumerable.Range(0, 30))
        {
            try { using var mutex = Mutex.OpenExisting(MutexName); Thread.Sleep(100); }
            catch (WaitHandleCannotBeOpenedException) { return true; }
        }
        MessageBox.Show("The existing instance could not be confirmed as terminated. The new instance will not start.", "ChatGPT Window Title Helper", MessageBoxButtons.OK, MessageBoxIcon.Error);
        return false;
    }

    internal static (EventWaitHandle Request, EventWaitHandle Ack, EventWaitHandle Done) CreateSignals()
        => (new EventWaitHandle(false, EventResetMode.AutoReset, RequestName),
            new EventWaitHandle(false, EventResetMode.ManualReset, AckName),
            new EventWaitHandle(false, EventResetMode.ManualReset, DoneName));
}
