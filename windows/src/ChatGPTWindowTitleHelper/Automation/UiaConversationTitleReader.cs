using System.Windows.Automation;
using System.Runtime.InteropServices;
using ChatGPTWindowTitleHelper.Diagnostics;
using System.Collections.Concurrent;
using ChatGPTWindowTitleHelper.Overlay;

namespace ChatGPTWindowTitleHelper.Automation;

public sealed class UiaConversationTitleReader : IConversationTitleReader
{
    private const bool EnableCurrentPageFallback = true;
    private readonly Dictionary<nint, (AutomationElement[] Elements, DateTime Refreshed)> cache = [];
    private readonly object cacheLock = new();
    private readonly ConcurrentDictionary<nint, byte> structureDumped = [];
    private readonly ConcurrentDictionary<nint, byte> classificationDumped = [];
    private readonly ConcurrentDictionary<nint, byte> newChatWindows = [];
    private readonly ConcurrentDictionary<nint, int> noOverlayObservations = [];
    private static readonly TimeSpan CacheLifetime = TimeSpan.FromSeconds(30);
    private static readonly System.Reflection.FieldInfo RawNodeField =
        typeof(AutomationElement).GetField("_hnode", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!;
    private static readonly System.Reflection.MethodInfo RawPropertyMethod =
        typeof(AutomationElement).Assembly.GetType("MS.Internal.Automation.UiaCoreApi")!
            .GetMethod("RawUiaGetPropertyValue", System.Reflection.BindingFlags.Static | System.Reflection.BindingFlags.NonPublic)!;

    public bool TryReadTitle(nint hwnd, out string title)
    {
        title = string.Empty;

        try
        {
            var root = AutomationElement.FromHandle(hwnd);
            if (root is null)
                return false;

            // Fast path: find the conversation Document first. Do not build
            // the full descendant cache or inspect current=page when the
            // document already exposes a usable title.
            var document = root.FindFirst(
                TreeScope.Descendants,
                new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Document));
            var documentName = document?.Current.Name?.Trim();
            if (!string.IsNullOrWhiteSpace(documentName)
                && !string.Equals(documentName, "ChatGPT", StringComparison.OrdinalIgnoreCase))
            {
                DiagnosticLog.Info($"uia-detail hwnd=0x{hwnd.ToInt64():X} result=document-primary title={Sanitize(documentName)}");
                title = documentName;
                return true;
            }

            if (string.Equals(documentName, "ChatGPT", StringComparison.OrdinalIgnoreCase)
                && document is not null
                && IsNewChat(document))
            {
                newChatWindows[hwnd] = 0;
                DiagnosticLog.Info($"uia-detail hwnd=0x{hwnd.ToInt64():X} result=new-chat");
                title = "ChatGPT";
                return true;
            }
            newChatWindows.TryRemove(hwnd, out _);

            // Fallback path: only now perform the broader UIA traversal.
            var elements = GetElements(hwnd, root);
            var currentPageCount = 0;
            string? currentPageTitle = null;
            foreach (var element in elements)
            {
                var aria = ReadAriaProperties(element);
                var name = element.Current.Name;
                if (aria?.Contains("current=page", StringComparison.OrdinalIgnoreCase) == true
                    && !string.IsNullOrWhiteSpace(name))
                {
                    currentPageCount++;
                    currentPageTitle ??= name.Trim();
                }

            }

            if (currentPageTitle is not null && EnableCurrentPageFallback)
            {
                DiagnosticLog.Info($"uia-detail hwnd=0x{hwnd.ToInt64():X} elements={elements.Length} currentPage={currentPageCount} result=current-page-fallback title={Sanitize(currentPageTitle)}");
                title = currentPageTitle;
                return true;
            }

            if (currentPageTitle is not null)
                DiagnosticLog.Info($"uia-detail hwnd=0x{hwnd.ToInt64():X} elements={elements.Length} currentPage={currentPageCount} result=current-page-fallback-disabled");

            DiagnosticLog.Info($"uia-detail hwnd=0x{hwnd.ToInt64():X} elements={elements.Length} currentPage={currentPageCount} result=no-current-page");
        }
        catch (ElementNotAvailableException ex) { DiagnosticLog.Error($"uia-detail hwnd=0x{hwnd.ToInt64():X} result=element-unavailable", ex); }
        catch (ElementNotEnabledException ex) { DiagnosticLog.Error($"uia-detail hwnd=0x{hwnd.ToInt64():X} result=element-disabled", ex); }
        catch (COMException ex) { DiagnosticLog.Error($"uia-detail hwnd=0x{hwnd.ToInt64():X} result=com-error", ex); }
        catch (System.Reflection.TargetInvocationException ex) { DiagnosticLog.Error($"uia-detail hwnd=0x{hwnd.ToInt64():X} result=reflection-error", ex); }
        catch (InvalidOperationException ex) { DiagnosticLog.Error($"uia-detail hwnd=0x{hwnd.ToInt64():X} result=invalid-operation", ex); }
        catch (Exception ex) { DiagnosticLog.Error($"uia-detail hwnd=0x{hwnd.ToInt64():X} result=unexpected-error", ex); }

        return false;
    }

    public bool IsNewChat(nint hwnd) => newChatWindows.ContainsKey(hwnd);

    private static bool IsNewChat(AutomationElement document)
    {
        foreach (var element in document.FindAll(TreeScope.Descendants, Condition.TrueCondition).Cast<AutomationElement>())
        {
            if (!string.Equals(element.Current.LocalizedControlType, "전환 버튼", StringComparison.OrdinalIgnoreCase)
                && !string.Equals(element.Current.LocalizedControlType, "toggle button", StringComparison.OrdinalIgnoreCase))
                continue;
            if (string.Equals(element.Current.Name?.Trim(), "Chat", StringComparison.OrdinalIgnoreCase))
                return true;
        }
        return false;
    }

    public System.Drawing.Rectangle? TryReadSectionHeaderBounds(nint hwnd, out bool hasVisibleTitleButton)
    {
        hasVisibleTitleButton = false;
        try
        {
            var root = AutomationElement.FromHandle(hwnd);
            if (root is null) return null;
            var documents = GetElements(hwnd, root)
                .Where(element => element.Current.ControlType == ControlType.Document)
                .ToArray();

            // SectionHeader is meaningful only inside the conversation
            // document. Searching the whole window can select a menu/header
            // element from the app chrome instead.
            foreach (var document in documents)
            {
                foreach (var element in document.FindAll(TreeScope.Descendants, Condition.TrueCondition).Cast<AutomationElement>())
                {
                    var type = element.Current.LocalizedControlType;
                    if (!string.Equals(type, "섹션 헤더", StringComparison.OrdinalIgnoreCase) && !string.Equals(type, "section header", StringComparison.OrdinalIgnoreCase)) continue;
                    var current = element.GetType().GetProperty("Current")?.GetValue(element);
                    var r = current?.GetType().GetProperty("BoundingRectangle")?.GetValue(current);
                    if (r is null) continue;
                    var t = r.GetType();
                    var left = Convert.ToDouble(t.GetProperty("Left")?.GetValue(r));
                    var top = Convert.ToDouble(t.GetProperty("Top")?.GetValue(r));
                    var width = Convert.ToDouble(t.GetProperty("Width")?.GetValue(r));
                    var height = Convert.ToDouble(t.GetProperty("Height")?.GetValue(r));
                    if (width > 0 && height > 0)
                    {
                        DumpSectionHeaderStructure(hwnd, element);
                        DumpWindowClassification(hwnd, document, element);
                        hasVisibleTitleButton = HasConversationTitleButton(element, document.Current.Name);
                        UpdateNoOverlayObservation(hwnd, element);
                        DiagnosticLog.Info($"title-button-detection hwnd=0x{hwnd.ToInt64():X} state={(hasVisibleTitleButton ? "Present" : "Absent")}");
                        DiagnosticLog.Info($"uia-header hwnd=0x{hwnd.ToInt64():X} path={BuildPath(document, element)} depth={GetDepth(document, element)} bounds={left:0},{top:0},{width:0},{height:0}");
                        if (!hasVisibleTitleButton && TryGetOverlayBounds(element, (int)left, (int)top, (int)width, (int)height, out var overlayBounds))
                            return overlayBounds;
                        return new System.Drawing.Rectangle((int)left, (int)top, (int)width, (int)height);
                    }
                }
            }
        }
        catch (Exception ex) { DiagnosticLog.Error($"uia-header hwnd=0x{hwnd.ToInt64():X} result=error", ex); }
        return null;
    }

    public bool ShouldSuppressOverlay(nint hwnd)
        => noOverlayObservations.TryGetValue(hwnd, out var count) && count >= 2;

    private void UpdateNoOverlayObservation(nint hwnd, AutomationElement header)
    {
        var buttons = header.FindAll(TreeScope.Descendants, Condition.TrueCondition)
            .Cast<AutomationElement>()
            .Where(x => x.Current.ControlType == ControlType.Button)
            .ToArray();
        var firstName = buttons.FirstOrDefault()?.Current.Name?.Trim() ?? string.Empty;
        var suppress = buttons.Length == 0
            || string.Equals(firstName, "플러그인", StringComparison.OrdinalIgnoreCase)
            || string.Equals(firstName, "Plugin", StringComparison.OrdinalIgnoreCase)
            || string.Equals(firstName, "작성", StringComparison.OrdinalIgnoreCase);
        if (suppress)
            noOverlayObservations.AddOrUpdate(hwnd, 1, (_, count) => Math.Min(2, count + 1));
        else
            noOverlayObservations.TryRemove(hwnd, out _);
        DiagnosticLog.Info($"overlay-observation hwnd=0x{hwnd.ToInt64():X} firstButton={Sanitize(firstName)} suppressCandidate={suppress} count={noOverlayObservations.GetValueOrDefault(hwnd)}");
    }

    private void DumpSectionHeaderStructure(nint hwnd, AutomationElement header)
    {
        if (!structureDumped.TryAdd(hwnd, 0)) return;
        try
        {
            DiagnosticLog.Info($"uia-structure hwnd=0x{hwnd.ToInt64():X} begin");
            DumpElement(hwnd, header, 0);
            DiagnosticLog.Info($"uia-structure hwnd=0x{hwnd.ToInt64():X} end");
        }
        catch (Exception ex) { DiagnosticLog.Error($"uia-structure hwnd=0x{hwnd.ToInt64():X} result=error", ex); }
    }

    private void DumpWindowClassification(nint hwnd, AutomationElement document, AutomationElement header)
    {
        if (!classificationDumped.TryAdd(hwnd, 0)) return;
        var buttons = header.FindAll(TreeScope.Descendants, Condition.TrueCondition)
            .Cast<AutomationElement>()
            .Where(x => x.Current.ControlType == ControlType.Button)
            .ToArray();
        DiagnosticLog.Info($"uia-classification hwnd=0x{hwnd.ToInt64():X} document={Sanitize(document.Current.Name)} buttonCount={buttons.Length}");
        for (var i = 0; i < buttons.Length; i++)
        {
            var button = buttons[i];
            var name = Sanitize(button.Current.Name);
            var bounds = "unavailable";
            if (TryGetBounds(button, out var r))
                bounds = $"{r.Left},{r.Top},{r.Width},{r.Height}";
            DiagnosticLog.Info($"uia-classification hwnd=0x{hwnd.ToInt64():X} buttonIndex={i} name={name} bounds={bounds}");
        }
    }

    private static void DumpElement(nint hwnd, AutomationElement element, int depth)
    {
        if (depth > 12) return;
        var current = element.Current;
        var name = current.Name.Replace("\r", " ").Replace("\n", " ");
        var localizedType = current.LocalizedControlType?.Replace("\r", " ").Replace("\n", " ") ?? string.Empty;
        var bounds = TryGetBounds(element, out var rectangle)
            ? $"{rectangle.Left},{rectangle.Top},{rectangle.Width},{rectangle.Height}"
            : "unavailable";
        DiagnosticLog.Info($"uia-structure hwnd=0x{hwnd.ToInt64():X} depth={depth} type={current.ControlType.ProgrammaticName.Replace("ControlType.", "")} localizedType={Sanitize(localizedType)} name={Sanitize(name)} bounds={bounds}");
        foreach (var child in element.FindAll(TreeScope.Children, Condition.TrueCondition).Cast<AutomationElement>())
            DumpElement(hwnd, child, depth + 1);
    }

    private static string BuildPath(AutomationElement document, AutomationElement element)
    {
        var names = new List<string>();
        var current = element;
        for (var i = 0; i < 12 && current is not null; i++)
        {
            names.Add(current.Current.ControlType.ProgrammaticName.Replace("ControlType.", ""));
            if (current.Equals(document)) break;
            current = TreeWalker.ControlViewWalker.GetParent(current);
        }
        names.Reverse();
        return string.Join(">", names);
    }

    private static bool HasConversationTitleButton(AutomationElement header, string conversationTitle)
    {
        if (string.IsNullOrWhiteSpace(conversationTitle)) return false;
        var children = header.FindAll(TreeScope.Descendants, Condition.TrueCondition)
            .Cast<AutomationElement>()
            .ToArray();
        return children.Any(child => child.Current.ControlType == ControlType.Button
            && string.Equals(child.Current.Name.Trim(), conversationTitle.Trim(), StringComparison.Ordinal));
    }

    private static bool TryGetOverlayBounds(AutomationElement header, int left, int top, int width, int height, out System.Drawing.Rectangle bounds)
    {
        bounds = default;
        var buttons = header.FindAll(TreeScope.Descendants, Condition.TrueCondition).Cast<AutomationElement>()
            .Where(x => x.Current.ControlType == ControlType.Button).ToArray();
        var share = buttons.FirstOrDefault(x => string.Equals(x.Current.Name, "공유", StringComparison.OrdinalIgnoreCase) || string.Equals(x.Current.Name, "Share", StringComparison.OrdinalIgnoreCase));
        if (share is null || !TryGetBounds(share, out var shareBounds)) return false;

        System.Drawing.Rectangle? writeBounds = null;
        var write = buttons.FirstOrDefault(button =>
            string.IsNullOrWhiteSpace(button.Current.Name)
            && button.FindAll(TreeScope.Descendants, Condition.TrueCondition)
                .Cast<AutomationElement>()
                .Any(child => child.Current.ControlType == ControlType.Image));
        if (write is not null && TryGetBounds(write, out var detectedWriteBounds))
            writeBounds = detectedWriteBounds;

        bounds = OverlayBoundsCalculator.Calculate(
            new System.Drawing.Rectangle(left, top, width, height),
            shareBounds,
            writeBounds);
        if (bounds.Width < 80) return false;
        return true;
    }

    private static bool TryGetBounds(AutomationElement element, out System.Drawing.Rectangle bounds)
    {
        bounds = default;
        var current = element.GetType().GetProperty("Current")?.GetValue(element);
        var r = current?.GetType().GetProperty("BoundingRectangle")?.GetValue(current);
        if (r is null) return false;
        var t = r.GetType();
        var left = Convert.ToDouble(t.GetProperty("Left")?.GetValue(r));
        var top = Convert.ToDouble(t.GetProperty("Top")?.GetValue(r));
        var width = Convert.ToDouble(t.GetProperty("Width")?.GetValue(r));
        var height = Convert.ToDouble(t.GetProperty("Height")?.GetValue(r));
        if (width <= 0 || height <= 0) return false;
        bounds = new System.Drawing.Rectangle((int)left, (int)top, (int)width, (int)height);
        return true;
    }

    private static int GetDepth(AutomationElement document, AutomationElement element)
    {
        var depth = 0;
        var current = element;
        for (var i = 0; i < 12 && current is not null && !current.Equals(document); i++)
        {
            depth++;
            current = TreeWalker.ControlViewWalker.GetParent(current);
        }
        return depth;
    }

    private AutomationElement[] GetElements(nint hwnd, AutomationElement root)
    {
        lock (cacheLock)
        {
            if (cache.TryGetValue(hwnd, out var entry) && DateTime.UtcNow - entry.Refreshed < CacheLifetime)
                return entry.Elements;

            var collection = root.FindAll(TreeScope.Descendants, Condition.TrueCondition);
            var elements = collection.Cast<AutomationElement>().ToArray();
            cache[hwnd] = (elements, DateTime.UtcNow);
            return elements;
        }
    }

    private static string? ReadAriaProperties(AutomationElement element)
    {
        var arguments = new[] { RawNodeField.GetValue(element), (object)30102, null! };
        RawPropertyMethod.Invoke(null, arguments);
        return arguments[2] as string;
    }

    private static string Sanitize(string value)
    {
        var sanitized = value.Replace("\r", " ").Replace("\n", " ");
        return sanitized.Length <= 120 ? sanitized : sanitized[..120] + "…";
    }
}
