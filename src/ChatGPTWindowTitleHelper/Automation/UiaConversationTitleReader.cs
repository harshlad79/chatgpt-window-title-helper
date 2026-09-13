using System.Windows.Automation;
using System.Runtime.InteropServices;
using ChatGPTWindowTitleHelper.Diagnostics;
using System.Collections.Concurrent;

namespace ChatGPTWindowTitleHelper.Automation;

public sealed class UiaConversationTitleReader : IConversationTitleReader
{
    private readonly Dictionary<nint, (AutomationElement[] Elements, DateTime Refreshed)> cache = [];
    private readonly object cacheLock = new();
    private readonly ConcurrentDictionary<nint, byte> structureDumped = [];
    private readonly ConcurrentDictionary<nint, byte> classificationDumped = [];
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

            var elements = GetElements(hwnd, root);
            var currentPageCount = 0;
            string? documentTitle = null;
            foreach (var element in elements)
            {
                var aria = ReadAriaProperties(element);
                var name = element.Current.Name;
                if (aria?.Contains("current=page", StringComparison.OrdinalIgnoreCase) == true
                    && !string.IsNullOrWhiteSpace(name))
                {
                    currentPageCount++;
                    DiagnosticLog.Info($"uia-detail hwnd=0x{hwnd.ToInt64():X} elements={elements.Length} currentPage={currentPageCount} result=found");
                    title = name.Trim();
                    return true;
                }

                if (documentTitle is null
                    && element.Current.ControlType == ControlType.Document
                    && !string.IsNullOrWhiteSpace(name))
                    documentTitle = name.Trim();
            }

            if (documentTitle is not null)
            {
                DiagnosticLog.Info($"uia-detail hwnd=0x{hwnd.ToInt64():X} elements={elements.Length} currentPage={currentPageCount} result=document-fallback title={Sanitize(documentTitle)}");
                title = documentTitle;
                return true;
            }

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
        var name = element.Current.Name.Replace("\r", " ").Replace("\n", " ");
        DiagnosticLog.Info($"uia-structure hwnd=0x{hwnd.ToInt64():X} depth={depth} type={element.Current.ControlType.ProgrammaticName.Replace("ControlType.", "")} name={Sanitize(name)}");
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
        var write = buttons.FirstOrDefault(x => string.IsNullOrWhiteSpace(x.Current.Name));
        if (share is null || write is null || !TryGetBounds(share, out var sr) || !TryGetBounds(write, out var wr)) return false;
        var overlayLeft = wr.Right + 8;
        var overlayRight = sr.Left - 8;
        if (overlayRight - overlayLeft < 80) return false;
        bounds = new System.Drawing.Rectangle(overlayLeft, top, overlayRight - overlayLeft, height);
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
