import AppKit
import ApplicationServices
import Foundation

// Independent, opt-in sampling cadence: short-lived menus must not depend
// on the 2-second full-window refresh or its 2.5-second diagnostic throttle.
// Only inspect when the target ChatGPT app is foreground and AX is trusted.
enum FocusedMenuProbeCadence {
    static let timerInterval: TimeInterval = 0.35
    static let minimumSpacing: TimeInterval = 0.30

    static func shouldSample(
        trusted: Bool,
        frontmostPID: pid_t?,
        targetPID: pid_t,
        inFlight: Bool,
        elapsed: TimeInterval
    ) -> Bool {
        trusted && targetPID > 0 && frontmostPID == targetPID &&
            !inFlight && elapsed >= minimumSpacing
    }
}

// Opt-in, read-only diagnostic for an ALREADY OPEN ChatGPT context menu.
// Never opens a menu, invokes AXPress, changes focus, or logs titles/URLs/IDs.
// It is not a conversation restorer and is not enabled in the installed Helper.
enum FocusedMenuURLProbe {
    enum LinkEvidence: Equatable {
        case unrelated
        case missingURL
        case invalidURL
        case conversationURL
    }

    struct Result {
        let menuFound: Bool
        let menuItems: Int
        let labeledItems: Int
        let validConversationURLs: Int
        let invalidURLs: Int
        let limited: Bool
        let elapsedMilliseconds: Int
    }

    static func classify(label: String, url: String?) -> LinkEvidence {
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let allowed: Set<String> = [
            "open on chatgpt.com",
            "chatgpt.com에서 열기",
            "chatgpt.com에서 열기…",
            "chatgpt.com에서 열기..."
        ]
        guard allowed.contains(normalized) else { return .unrelated }
        guard let url, !url.isEmpty else { return .missingURL }
        return ConversationRouteIdentity.parse(url) == nil
            ? .invalidURL : .conversationURL
    }

    private static func read(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, key as CFString, &value)
            == .success ? value : nil
    }

    private static func string(_ element: AXUIElement, _ key: String) -> String {
        (read(element, key) as? String) ?? ""
    }

    private static func url(_ element: AXUIElement) -> String? {
        guard let raw = read(element, "AXURL") else { return nil }
        if let text = raw as? String { return text }
        if let value = raw as? URL { return value.absoluteString }
        return nil
    }

    static func inspect(app: AXUIElement) -> Result {
        let start = ProcessInfo.processInfo.systemUptime
        func result(_ found: Bool, _ items: Int, _ labels: Int,
                    _ valid: Int, _ invalid: Int, _ limited: Bool) -> Result {
            Result(menuFound: found, menuItems: items,
                   labeledItems: labels, validConversationURLs: valid,
                   invalidURLs: invalid, limited: limited,
                   elapsedMilliseconds: Int(
                       (ProcessInfo.processInfo.systemUptime - start) * 1000))
        }
        _ = AXUIElementSetMessagingTimeout(app, 0.12)
        guard let focusedRaw = read(app, kAXFocusedUIElementAttribute),
              CFGetTypeID(focusedRaw) == AXUIElementGetTypeID()
        else { return result(false, 0, 0, 0, 0, false) }
        let focused = focusedRaw as! AXUIElement

        // The focused item may be nested inside an AXMenu. Inspect ancestors,
        // not unrelated conversation content or the entire application tree.
        var current = focused
        var ancestors = Set<String>()
        var menu: AXUIElement?
        for _ in 0..<12 {
            guard ancestors.insert(String(CFHash(current))).inserted else { break }
            _ = AXUIElementSetMessagingTimeout(current, 0.12)
            if string(current, kAXRoleAttribute) == "AXMenu" {
                menu = current
                break
            }
            guard let parentRaw = read(current, kAXParentAttribute),
                  CFGetTypeID(parentRaw) == AXUIElementGetTypeID()
            else { break }
            current = parentRaw as! AXUIElement
        }
        guard let menu else { return result(false, 0, 0, 0, 0, false) }

        var queue: [(AXUIElement, Int)] = [(menu, 0)]
        var seen = Set<String>()
        var index = 0
        var items = 0
        var labeled = 0
        var valid = 0
        var invalid = 0
        while index < queue.count && index < 160 &&
              ProcessInfo.processInfo.systemUptime - start < 0.9 {
            let (node, depth) = queue[index]
            index += 1
            guard seen.insert(String(CFHash(node))).inserted else { continue }
            _ = AXUIElementSetMessagingTimeout(node, 0.12)
            let role = string(node, kAXRoleAttribute)
            if role == "AXMenuItem" || role == "AXLink" {
                items += 1
                let label = [
                    string(node, kAXTitleAttribute),
                    string(node, kAXDescriptionAttribute),
                    string(node, kAXHelpAttribute)
                ]
                // Attributes can differ by host; count the same element once.
                let candidateURL = url(node)
                let evidence = label.map { classify(label: $0, url: candidateURL) }
                if evidence.contains(where: { $0 != .unrelated }) {
                    labeled += 1
                    if evidence.contains(.conversationURL) { valid += 1 }
                    else if evidence.contains(.invalidURL) { invalid += 1 }
                }
            }
            if depth < 3 {
                let children = (read(node, kAXChildrenAttribute)
                    as? [AXUIElement]) ?? []
                for child in children.prefix(60) where queue.count < 180 {
                    queue.append((child, depth + 1))
                }
            }
        }
        return result(true, items, labeled, valid, invalid,
                      index < queue.count || index >= 160)
    }
}
