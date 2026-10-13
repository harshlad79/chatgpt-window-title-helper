using System.Windows.Automation;
using ChatGPTWindowTitleHelper.Diagnostics;

namespace ChatGPTWindowTitleHelper.Automation;

// Created, accessed, and disposed exclusively by the dedicated MTA UIA worker.
// Callbacks must not traverse UIA or synchronously invoke the WinForms thread.
internal sealed class TitleButtonEventMonitor : IDisposable
{
    private readonly Dictionary<nint, Subscription> subscriptions = [];
    private readonly Action<nint, string> notify;
    private sealed record Subscription(
        AutomationElement Element, AutomationPropertyChangedEventHandler Handler);
    public TitleButtonEventMonitor(Action<nint, string> notify) => this.notify = notify;

    public bool HasSubscription(nint hwnd) => subscriptions.ContainsKey(hwnd);

    public void Ensure(nint hwnd, string title)
    {
        if (string.IsNullOrWhiteSpace(title) || title == "ChatGPT") return;

        if (subscriptions.TryGetValue(hwnd, out var sub))
        {
            try
            {
                // Valid existing button keeps working even as its Name changes.
                _ = sub.Element.Current.ControlType;
                return;
            }
            catch (ElementNotAvailableException) { Remove(hwnd); }
            catch (System.Runtime.InteropServices.COMException) { Remove(hwnd); }
        }

        try
        {
            var root = AutomationElement.FromHandle(hwnd);
            var document = root?.FindFirst(TreeScope.Descendants,
                new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Document));
            if (document is null) return;
            var query = new AndCondition(
                new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Button),
                new PropertyCondition(AutomationElement.NameProperty, document.Current.Name));
            var button = document.FindFirst(TreeScope.Descendants, query);
            if (button is null) return;

            AutomationPropertyChangedEventHandler handler = (_, e) =>
            {
                if (e.Property != AutomationElement.NameProperty) return;
                var newTitle = e.NewValue as string;
                if (string.IsNullOrWhiteSpace(newTitle)) return;
                notify(hwnd, newTitle.Trim());
            };
            System.Windows.Automation.Automation.AddAutomationPropertyChangedEventHandler(
                button, TreeScope.Element, handler, AutomationElement.NameProperty);
            subscriptions[hwnd] = new Subscription(button, handler);
            DiagnosticLog.Info($"uia-event-subscribe hwnd=0x{hwnd.ToInt64():X}");
        }
        catch (Exception e)
        {
            DiagnosticLog.Error($"uia-event-subscribe-failed hwnd=0x{hwnd.ToInt64():X}", e);
        }
    }

    public void RemoveMissing(IEnumerable<nint> current)
    {
        var present = current.ToHashSet();
        foreach (var hwnd in subscriptions.Keys.Where(h => !present.Contains(h)).ToArray())
            Remove(hwnd);
    }

    private void Remove(nint hwnd)
    {
        if (!subscriptions.Remove(hwnd, out var existing)) return;
        try
        {
            System.Windows.Automation.Automation.RemoveAutomationPropertyChangedEventHandler(
                existing.Element, existing.Handler);
        }
        catch (Exception e)
        {
            DiagnosticLog.Error($"uia-event-unsubscribe-failed hwnd=0x{hwnd.ToInt64():X}", e);
        }
    }

    public void Dispose()
    {
        foreach (var hwnd in subscriptions.Keys.ToArray()) Remove(hwnd);
    }
}
