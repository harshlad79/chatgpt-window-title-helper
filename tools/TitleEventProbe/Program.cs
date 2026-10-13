using System.Collections.Concurrent;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Automation;
using System.Windows.Forms;
using FormsTimer = System.Windows.Forms.Timer;

namespace TitleEventProbe;

internal static class Program
{
    private const uint NameChange = 0x800C;
    private const uint Foreground = 0x0003;
    private static readonly ConcurrentQueue<string> Queue = new();
    private static readonly List<nint> Hooks = [];
    private static readonly List<WinEventDelegate> KeepAlive = [];
    private static readonly CancellationTokenSource Exit = new();
    private static string file = "";
    private static int queued;
    private static int dropped;

    [STAThread]
    private static void Main(string[] args)
    {
        if (args.Length > 0 && args[0] == "--snapshot")
        {
            PrintSnapshot();
            return;
        }
        int seconds = args.Length > 0 && int.TryParse(args[0], out var n)
            ? Math.Clamp(n, 20, 3600) : 600;
        string folder = Path.Combine(Environment.GetFolderPath(
            Environment.SpecialFolder.LocalApplicationData),
            "ChatGPTWindowTitleHelper", "logs");
        Directory.CreateDirectory(folder);
        file = Path.Combine(folder, "event-probe-current.log");
        File.WriteAllText(file, "", Encoding.UTF8);
        Log("probe.start pid=" + Environment.ProcessId + " durationSec=" + seconds);
        var windows = FindChatGptWindows();
        Log("probe.window-count=" + windows.Count);
        foreach (var window in windows)
            Log("probe.window hwnd=0x" + window.Hwnd.ToInt64().ToString("X")
                + " pid=" + window.Pid + " name=" + Safe(ReadText(window.Hwnd)));

        foreach (uint pid in windows.Select(x => x.Pid).Distinct())
        {
            WinEventDelegate callback = (_, type, hwnd, objectId, childId, _, _) =>
            {
                if (type == NameChange && hwnd != 0 && objectId != -9)
                    Log("win.name pid=" + pid + " hwnd=0x" + hwnd.ToInt64().ToString("X")
                        + " obj=" + objectId + " child=" + childId);
                else if (type == Foreground)
                    Log("win.foreground pid=" + pid + " hwnd=0x" + hwnd.ToInt64().ToString("X"));
            };
            KeepAlive.Add(callback);
            foreach (uint kind in new[] { NameChange, Foreground })
            {
                var hook = SetWinEventHook(kind, kind, 0, callback, pid, 0, 0);
                if (hook != 0) Hooks.Add(hook);
                Log("probe.winevent pid=" + pid + " kind=0x" + kind.ToString("X")
                    + " subscribed=" + (hook != 0));
            }
        }

        var ready = new ManualResetEventSlim();
        var worker = new Thread(() => MonitorUia(windows, ready))
            { IsBackground = true, Name = "UIA probe MTA" };
        worker.SetApartmentState(ApartmentState.MTA);
        worker.Start();
        ready.Wait(TimeSpan.FromSeconds(15));

        Application.EnableVisualStyles();
        using var context = new System.Windows.Forms.ApplicationContext();
        using var tick = new FormsTimer { Interval = 300 };
        var deadline = DateTime.UtcNow.AddSeconds(seconds);
        tick.Tick += (_, _) => {
            Flush();
            if (DateTime.UtcNow >= deadline) context.ExitThread();
        };
        tick.Start();
        Application.Run(context);

        Exit.Cancel();
        worker.Join(5000);
        foreach (var hook in Hooks) UnhookWinEvent(hook);
        Log("probe.stop dropped=" + dropped);
        Flush();
    }

    // One-shot read after a title change; does not modify the running probe log.
    // Compare RuntimeIds only for the same HWND while ChatGPT remains running.
    private static void PrintSnapshot()
    {
        foreach (var (hwnd, pid) in FindChatGptWindows())
        {
            string id = "0x" + hwnd.ToInt64().ToString("X");
            try
            {
                var root = AutomationElement.FromHandle(hwnd);
                var doc = root?.FindFirst(TreeScope.Descendants,
                    new PropertyCondition(AutomationElement.ControlTypeProperty,
                        ControlType.Document));
                Console.WriteLine("snapshot hwnd=" + id + " pid=" + pid
                    + " name=" + Safe(doc?.Current.Name)
                    + " documentRuntimeId=" + RuntimeId(doc));
            }
            catch (Exception e)
            {
                Console.WriteLine("snapshot hwnd=" + id
                    + " error=" + e.GetType().Name);
            }
        }
    }

    private static string RuntimeId(AutomationElement? element)
    {
        if (element is null) return "none";
        try
        {
            var id = element.GetRuntimeId();
            return id is null ? "none" : string.Join(".", id);
        }
        catch (Exception e) { return "unavailable:" + e.GetType().Name; }
    }

    private static void MonitorUia(List<(nint Hwnd, uint Pid)> windows, ManualResetEventSlim ready)
    {
        var cleanup = new List<Action>();
        try
        {
            foreach (var (hwnd, _) in windows)
            {
                string id = "0x" + hwnd.ToInt64().ToString("X");
                try
                {
                    var root = AutomationElement.FromHandle(hwnd);
                    var doc = root?.FindFirst(TreeScope.Descendants,
                        new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Document));
                    if (root is null || doc is null) { Log("uia.no-document hwnd=" + id); continue; }
                    string name = doc.Current.Name;
                    AutomationPropertyChangedEventHandler documentChanged = (_, e) =>
                        Log("uia.document-name hwnd=" + id + " new=" + Safe(e.NewValue?.ToString()));
                    Automation.AddAutomationPropertyChangedEventHandler(
                        doc, TreeScope.Element, documentChanged, AutomationElement.NameProperty);
                    cleanup.Add(() => Automation.RemoveAutomationPropertyChangedEventHandler(
                        doc, documentChanged));

                    bool foundButton = false;
                    string buttonRuntimeId = "none";
                    if (!string.IsNullOrWhiteSpace(name))
                    {
                        var condition = new AndCondition(
                            new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Button),
                            new PropertyCondition(AutomationElement.NameProperty, name));
                        var button = doc.FindFirst(TreeScope.Descendants, condition);
                        if (button is not null)
                        {
                            AutomationPropertyChangedEventHandler buttonChanged = (_, e) =>
                                Log("uia.button-name hwnd=" + id + " new=" + Safe(e.NewValue?.ToString()));
                            Automation.AddAutomationPropertyChangedEventHandler(
                                button, TreeScope.Element, buttonChanged, AutomationElement.NameProperty);
                            cleanup.Add(() => Automation.RemoveAutomationPropertyChangedEventHandler(
                                button, buttonChanged));
                            foundButton = true;
                            buttonRuntimeId = RuntimeId(button);
                        }
                    }
                    StructureChangedEventHandler structureChanged = (_, e) =>
                        Log("uia.root-structure hwnd=" + id + " change=" + e.StructureChangeType);
                    Automation.AddStructureChangedEventHandler(root, TreeScope.Children, structureChanged);
                    cleanup.Add(() => Automation.RemoveStructureChangedEventHandler(
                        root, structureChanged));
                    Log("uia.ready hwnd=" + id + " doc=" + Safe(name)
                        + " documentRuntimeId=" + RuntimeId(doc)
                        + " titleButton=" + foundButton
                        + " buttonRuntimeId=" + buttonRuntimeId);
                }
                catch (Exception e)
                {
                    Log("uia.error hwnd=" + id + " type=" + e.GetType().Name
                        + " message=" + Safe(e.Message));
                }
            }
        }
        finally { ready.Set(); }

        while (!Exit.IsCancellationRequested) Thread.Sleep(200);
        foreach (var remove in cleanup)
            try { remove(); }
            catch (Exception e) { Log("uia.remove-error type=" + e.GetType().Name); }
    }

    private static List<(nint Hwnd, uint Pid)> FindChatGptWindows()
    {
        var result = new List<(nint Hwnd, uint Pid)>();
        EnumWindows((hwnd, _) => {
            GetWindowThreadProcessId(hwnd, out uint pid);
            if (pid == 0 || !IsWindowVisible(hwnd)) return true;
            var name = new StringBuilder(100);
            GetClassName(hwnd, name, name.Capacity);
            if (name.ToString() != "Chrome_WidgetWin_1") return true;
            try {
                using var p = Process.GetProcessById((int)pid);
                if (p.ProcessName.Equals("ChatGPT", StringComparison.OrdinalIgnoreCase))
                    result.Add((hwnd, pid));
            } catch { }
            return true;
        }, 0);
        return result;
    }

    private static string Safe(string? value)
    {
        var text = (value ?? "").Replace('\r', ' ').Replace('\n', ' ');
        return text.Length > 160 ? text[..160] : text;
    }
    private static void Log(string value)
    {
        if (Interlocked.Increment(ref queued) > 1000) {
            Interlocked.Decrement(ref queued);
            Interlocked.Increment(ref dropped);
            return;
        }
        Queue.Enqueue(DateTimeOffset.Now.ToString("O") + " " + value);
    }
    private static void Flush()
    {
        var lines = new List<string>();
        while (lines.Count < 300 && Queue.TryDequeue(out var line)) {
            Interlocked.Decrement(ref queued);
            lines.Add(line);
        }
        if (lines.Count > 0) File.AppendAllLines(file, lines);
    }

    private static string ReadText(nint hwnd)
    {
        var buffer = new StringBuilder(512);
        GetWindowText(hwnd, buffer, buffer.Capacity);
        return buffer.ToString();
    }

    private delegate bool EnumWindowDelegate(nint hwnd, nint data);
    private delegate void WinEventDelegate(nint h, uint type, nint hwnd,
        int objectId, int childId, uint threadId, uint time);
    [DllImport("user32.dll")] private static extern bool EnumWindows(
        EnumWindowDelegate callback, nint data);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(
        nint hwnd, out uint processId);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern int GetWindowText(
        nint hwnd, StringBuilder buffer, int length);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern int GetClassName(
        nint hwnd, StringBuilder buffer, int length);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(nint hwnd);
    [DllImport("user32.dll")] private static extern nint SetWinEventHook(
        uint min, uint max, nint module, WinEventDelegate callback, uint pid, uint threadId, uint flags);
    [DllImport("user32.dll")] private static extern bool UnhookWinEvent(nint hook);
}