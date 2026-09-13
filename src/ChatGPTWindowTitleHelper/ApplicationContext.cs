using ChatGPTWindowTitleHelper.Automation;
using ChatGPTWindowTitleHelper.Windows;
using ChatGPTWindowTitleHelper.Overlay;
using ChatGPTWindowTitleHelper.Domain;
using ChatGPTWindowTitleHelper.Settings;
using ChatGPTWindowTitleHelper.Interop;
using ChatGPTWindowTitleHelper.Diagnostics;
using System.Diagnostics;
using System.Collections.Concurrent;

namespace ChatGPTWindowTitleHelper;

internal sealed class ApplicationContext : System.Windows.Forms.ApplicationContext
{
    private readonly NotifyIcon trayIcon;
    private readonly System.Windows.Forms.Timer refreshTimer;
    private readonly System.Windows.Forms.Timer overlayGeometryTimer;
    private readonly WindowTracker tracker;
    private readonly UiaConversationTitleReader titleReader;
    private readonly OverlayManager overlays = new();
    private readonly TrayDiagnosticPanel diagnosticPanel = new();
    private readonly WindowTitleWriter titleWriter = new();
    private readonly SettingsStore settingsStore;
    private readonly Control dispatcher = new() { Visible = false };
    private SynchronizationContext uiContext = null!;
    private readonly WindowNameChangeMonitor nameChangeMonitor;
    private AppSettings settings;
    private int titleTick;
    private bool exiting;
    private long refreshSequence;
    private readonly ConcurrentDictionary<nint, long> windowOperations = new();

    public ApplicationContext()
    {
        DiagnosticLog.Info("startup");
        titleReader = new UiaConversationTitleReader();
        tracker = new WindowTracker(new ChatGptWindowDiscovery(), titleReader);
        settingsStore = new SettingsStore(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ChatGPTWindowTitleHelper", "settings.json"));
        settings = settingsStore.Load();
        var menu = new ContextMenuStrip();
        menu.Items.Add("Status", null, (_, _) => ShowStatus());
        var overlayItem = new ToolStripMenuItem("Show Conversation Title") { Checked = settings.ShowConversationTitle, CheckOnClick = true };
        overlayItem.Click += (_, _) =>
        {
            settings = settings with { ShowConversationTitle = overlayItem.Checked };
            if (!overlayItem.Checked) overlays.Clear();
            else RefreshWindows();
            SaveSettings();
        };
        menu.Items.Add(overlayItem);

        var inspectorItem = new ToolStripMenuItem("Show Tray Inspector") { Checked = settings.ShowTrayInspector, CheckOnClick = true };
        inspectorItem.Click += (_, _) =>
        {
            settings = settings with { ShowTrayInspector = inspectorItem.Checked };
            if (!inspectorItem.Checked)
            {
                diagnosticPanel.Hide();
            }
            else
                RefreshWindows();
            SaveSettings();
        };
        menu.Items.Add(inspectorItem);
        var altTabItem = new ToolStripMenuItem("Change Alt+Tab Title") { Checked = settings.ChangeAltTabTitle, CheckOnClick = true };
        altTabItem.Click += (_, _) => { settings = settings with { ChangeAltTabTitle = altTabItem.Checked }; if (!altTabItem.Checked) titleWriter.RestoreAll(); SaveSettings(); };
        menu.Items.Add(altTabItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Exit", null, (_, _) => ExitThread());

        trayIcon = new NotifyIcon { Icon = SystemIcons.Application, Visible = true, Text = "ChatGPT Window Title Helper", ContextMenuStrip = menu };
        refreshTimer = new System.Windows.Forms.Timer { Interval = 2000 };
        overlayGeometryTimer = new System.Windows.Forms.Timer { Interval = 100 };
        dispatcher.CreateControl();
        uiContext = SynchronizationContext.Current ?? new WindowsFormsSynchronizationContext();
        nameChangeMonitor = new WindowNameChangeMonitor(OnWindowNameChanged);
        refreshTimer.Tick += (_, _) => { titleTick++; RefreshWindows(); };
        overlayGeometryTimer.Tick += (_, _) =>
        {
            if (!exiting && settings.ShowConversationTitle)
                overlays.RepositionAll();
        };
        refreshTimer.Start();
        overlayGeometryTimer.Start();
        RefreshWindows();
    }

    private void RefreshWindows()
    {
        if (exiting)
            return;

        var sequence = Interlocked.Increment(ref refreshSequence);
        _ = Task.Factory.StartNew(() =>
        {
            DiagnosticLog.Info($"discovery-start id={sequence}");
            tracker.Refresh();
            var windows = tracker.Windows.ToArray();
            DiagnosticLog.Info($"discovery-complete id={sequence} windows={windows.Length}");
            try { uiContext.Post(_ => ScheduleWindowOperations(windows, sequence), null); }
            catch (Exception ex) { DiagnosticLog.Error($"discovery-dispatch-failed id={sequence}", ex); }
        }, CancellationToken.None, TaskCreationOptions.DenyChildAttach, TaskScheduler.Default);
    }

    private void ScheduleWindowOperations(IReadOnlyList<TrackedWindow> windows, long sequence)
    {
        foreach (var window in windows)
        {
            if (!windowOperations.TryAdd(window.Handle, sequence))
            {
                DiagnosticLog.Info($"uia-skip hwnd=0x{window.Handle.ToInt64():X} reason=in-flight");
                continue;
            }

            _ = Task.Run(() => RunWindowOperation(window.Handle, sequence));
        }
    }

    private void RunWindowOperation(nint hwnd, long sequence)
    {
        try
        {
            if (User32.IsIconic(hwnd))
            {
                DiagnosticLog.Info($"uia-skip id={sequence} hwnd=0x{hwnd.ToInt64():X} reason=minimized");
                return;
            }

            var before = tracker.Windows.FirstOrDefault(x => x.Handle == hwnd)?.CurrentTitle;
            var result = tracker.TryUpdateTitle(hwnd);
            var headerBounds = titleReader.TryReadSectionHeaderBounds(hwnd, out var hasVisibleTitleButton);
            tracker.SetSectionHeaderBounds(hwnd, headerBounds);
            if (headerBounds.HasValue)
                tracker.SetHasVisibleTitleButton(hwnd, hasVisibleTitleButton);
            var window = tracker.Windows.FirstOrDefault(x => x.Handle == hwnd);
            if (window is null) return;
            DiagnosticLog.Info($"uia-complete id={sequence} hwnd=0x{hwnd.ToInt64():X} result={result} titleChanged={!string.Equals(before, window.CurrentTitle, StringComparison.Ordinal)} title={Sanitize(window.CurrentTitle)}");
            try { uiContext.Post(_ => ApplyWindowResult(window, sequence), null); }
            catch (Exception ex) { DiagnosticLog.Error($"uia-dispatch-failed id={sequence} hwnd=0x{hwnd.ToInt64():X}", ex); }
        }
        catch (Exception ex) { DiagnosticLog.Error($"uia-failed id={sequence} hwnd=0x{hwnd.ToInt64():X}", ex); }
        finally { windowOperations.TryRemove(hwnd, out _); }
    }

    private void ApplyWindowResult(TrackedWindow window, long sequence)
    {
        if (exiting || !tracker.Windows.Any(x => x.Handle == window.Handle)) return;
        DiagnosticLog.Info($"apply-window id={sequence} hwnd=0x{window.Handle.ToInt64():X} state={window.TitleButtonState} title={Sanitize(window.CurrentTitle)}");
        if (settings.ShowConversationTitle
            && !string.Equals(window.CurrentTitle, "ChatGPT", StringComparison.Ordinal)
            && window.TitleButtonState == TitleButtonState.Absent)
            overlays.SetTitle(window.Handle, window.CurrentTitle, window.SectionHeaderBounds);
        else if (window.TitleButtonState == TitleButtonState.Present || window.TitleButtonState == TitleButtonState.Unknown)
            overlays.RemoveTitle(window.Handle);
        if (settings.ChangeAltTabTitle) titleWriter.Apply(window);
    }

    private static string Sanitize(string value)
    {
        var sanitized = value.Replace("\r", " ").Replace("\n", " ");
        return sanitized.Length <= 160 ? sanitized : sanitized[..160] + "…";
    }

    private void ApplyWindowResults(IReadOnlyList<TrackedWindow> windows)
    {
        if (exiting) return;

        DiagnosticLog.Info($"apply-start windows={windows.Count} show={settings.ShowConversationTitle}");
        if (settings.ShowTrayInspector) diagnosticPanel.UpdateWindows(windows);
        else diagnosticPanel.Hide();

        foreach (var window in windows)
        {
            if (settings.ShowConversationTitle
                && !string.Equals(window.CurrentTitle, "ChatGPT", StringComparison.Ordinal)
                && window.TitleButtonState == TitleButtonState.Absent)
                overlays.SetTitle(window.Handle, window.CurrentTitle, window.SectionHeaderBounds);
            else if (window.TitleButtonState == TitleButtonState.Present || window.TitleButtonState == TitleButtonState.Unknown)
                overlays.RemoveTitle(window.Handle);
            if (settings.ChangeAltTabTitle && titleTick % 2 == 0) titleWriter.Apply(window);
        }

        overlays.RemoveMissing(windows.Select(x => x.Handle).ToHashSet());
    }

    private void OnWindowNameChanged(nint hwnd)
    {
        if (exiting || !settings.ChangeAltTabTitle) return;
        try
        {
            uiContext.Post(_ =>
            {
                var window = tracker.Windows.FirstOrDefault(x => x.Handle == hwnd);
                if (window is not null)
                {
                    titleWriter.ReapplyIfReplaced(window);
                    if (settings.ShowConversationTitle) overlays.Reposition(hwnd);
                }
            }, null);
        }
        catch (ObjectDisposedException) { }
        catch (InvalidOperationException) { }
    }

    private void ShowStatus()
        => trayIcon.ShowBalloonTip(1500, "ChatGPT Window Title Helper", $"{tracker.Windows.Count} window(s) detected", ToolTipIcon.Info);

    private void SaveSettings()
    {
        try { settingsStore.Save(settings); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    protected override void ExitThreadCore()
    {
        DiagnosticLog.Info("shutdown");
        exiting = true;
        refreshTimer.Stop();
        refreshTimer.Dispose();
        overlayGeometryTimer.Stop();
        overlayGeometryTimer.Dispose();
        trayIcon.Visible = false;
        trayIcon.Dispose();
        overlays.Dispose();
        diagnosticPanel.Close();
        diagnosticPanel.Dispose();
        titleWriter.RestoreAll();
        nameChangeMonitor.Dispose();
        dispatcher.Dispose();
        base.ExitThreadCore();
    }
}
