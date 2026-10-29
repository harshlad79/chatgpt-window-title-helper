import AppKit
import ApplicationServices

// Uses only verified native UI actions: ChatGPT File > New Window,
// followed by ChatGPT Dock Recent > second More > unique exact title.
// No Electron Inspector, binary patching, or message submission.
final class DockRecentWindowRestorer {
    private var busy = false

    private func read(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &result)
                == .success else { return nil }
        return result
    }
    private func children(_ element: AXUIElement) -> [AXUIElement] {
        (read(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }
    private func str(_ element: AXUIElement, _ key: String) -> String {
        (read(element, key) as? String) ?? ""
    }
    private func winList(_ root: AXUIElement) -> [AXUIElement] {
        (read(root, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    }
    private func title(_ win: AXUIElement) -> String {
        str(win, kAXTitleAttribute)
    }
    private func press(_ item: AXUIElement) -> Bool {
        var raw: CFArray?
        guard AXUIElementCopyActionNames(item, &raw) == .success,
              ((raw as? [String]) ?? []).contains(kAXPressAction as String)
        else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString)
            == .success
    }

    private func dockRecentMatches(_ desired: String) -> [AXUIElement]? {
        guard let dock = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.dock"
        }) else { return nil }
        let root = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.6)
        let icons = children(root).flatMap { children($0) }.filter {
            str($0, kAXRoleAttribute) == "AXDockItem" &&
                str($0, kAXSubroleAttribute) == "AXApplicationDockItem" &&
                str($0, kAXTitleAttribute) == "ChatGPT"
        }
        guard icons.count == 1 else { return nil }
        var menu = children(icons[0]).first {
            str($0, kAXRoleAttribute) == "AXMenu"
        }
        if menu == nil {
            guard AXUIElementPerformAction(
                icons[0], kAXShowMenuAction as CFString) == .success
            else { return nil }
            // Dock adds the menu as a child asynchronously.
            Thread.sleep(forTimeInterval: 0.35)
            menu = children(icons[0]).first {
                str($0, kAXRoleAttribute) == "AXMenu"
            }
        }
        guard let menu else { return nil }
        let more = children(menu).filter {
            str($0, kAXRoleAttribute) == "AXMenuItem" &&
                str($0, kAXTitleAttribute) == "More"
        }
        guard more.count == 2 else { return nil }
        let nested = children(more[1]).filter {
            str($0, kAXRoleAttribute) == "AXMenu"
        }
        guard nested.count == 1 else { return nil }
        return children(nested[0]).filter {
            str($0, kAXRoleAttribute) == "AXMenuItem" &&
                str($0, kAXTitleAttribute) == desired
        }
    }

    private func fileNewWindow(_ root: AXUIElement) -> AXUIElement? {
        guard let bar = read(root, kAXMenuBarAttribute),
              CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
        let top = children(bar as! AXUIElement).filter {
            str($0, kAXTitleAttribute) == "파일"
        }
        guard top.count == 1 else { return nil }
        let items = children(top[0]).flatMap { children($0) }.filter {
            str($0, kAXRoleAttribute) == "AXMenuItem" &&
                str($0, kAXTitleAttribute) == "새 창"
        }
        guard items.count == 1,
              (read(items[0], kAXEnabledAttribute) as? NSNumber)?.boolValue == true
        else { return nil }
        return items[0]
    }

    // Explicit one-shot, non-navigating diagnostic. Invoked only by the
    // signed helper with TITLEHELPER_SAFE_BLANK_PROBE=1 at launch.
    // Never closes, unminimizes, navigates or edits an existing conversation.
    func probeBlankWindow(completed: @escaping (Bool, String) -> Void) {
        guard !busy, AXIsProcessTrusted(),
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == "com.openai.codex"
              }) else { completed(false, "busy-or-no-AX-permission"); return }

        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.6)
        let original = winList(root)
        let originalIDs = Set(original.map { String(CFHash($0)) })
        guard !original.isEmpty, original.count <= 12,
              originalIDs.count == original.count,
              fileNewWindow(root) != nil
        else { completed(false, "preflight-window-or-menu-unsafe"); return }

        // Fail closed if any original window cannot report minimized state.
        var originalMinimized: [String: Bool] = [:]
        for win in original {
            guard str(win, kAXRoleAttribute) == "AXWindow",
                  let minimized = read(win, kAXMinimizedAttribute) as? NSNumber
            else { completed(false, "preflight-minimized-unavailable"); return }
            originalMinimized[String(CFHash(win))] = minimized.boolValue
        }
        let priorFrontmost = NSWorkspace.shared.frontmostApplication
        busy = true
        guard app.activate() else {
            busy = false
            completed(false, "activation-request-rejected")
            return
        }

        // The previous test pressed File > New Window immediately after
        // activation and saw AXPress success but no new window. Wait for
        // confirmed focus, then resolve the menu item again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier ==
                    app.processIdentifier else {
                self.busy = false
                priorFrontmost?.activate()
                completed(false, "focus-not-confirmed")
                return
            }
            guard let newWindowMenu = self.fileNewWindow(root),
                  self.press(newWindowMenu) else {
                self.busy = false
                priorFrontmost?.activate()
                completed(false, "focused-menu-or-AXPress-failed")
                return
            }
            let startedAt = ProcessInfo.processInfo.systemUptime
            func poll() {
                let after = self.winList(root)
                let created = after.filter {
                    !originalIDs.contains(String(CFHash($0)))
                }
                let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
                if after.count == original.count && created.isEmpty &&
                    elapsed < 8.0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        poll()
                    }
                    return
                }
                let originalsRetained = original.allSatisfy { old in
                    let key = String(CFHash(old))
                    guard let live = after.first(where: {
                        String(CFHash($0)) == key
                    }), let minimized = self.read(
                        live, kAXMinimizedAttribute) as? NSNumber
                    else { return false }
                    return minimized.boolValue == originalMinimized[key]
                }
                let newGeneric = created.count == 1 &&
                    self.title(created[0]) == "ChatGPT"
                let success = after.count == original.count + 1 &&
                    created.count == 1 && originalsRetained && newGeneric
                self.busy = false
                // Restore the prior app focus, never close any window.
                if let priorFrontmost,
                   priorFrontmost.processIdentifier != app.processIdentifier {
                    _ = priorFrontmost.activate()
                }
                completed(success, "before=\(original.count) after=\(after.count) " +
                    "created=\(created.count) originalsRetained=\(originalsRetained) " +
                    "newGeneric=\(newGeneric) elapsed=\(Int(elapsed))s")
            }
            poll()
        }
    }


    // Search Chats is a hidden native accelerator in the installed ChatGPT
    // build (visible=false), not a File-menu AXMenuItem. Probe the visible
    // sidebar Search AXButton on an independently verified new window only.
    private func searchUIScan(_ window: AXUIElement)
        -> (buttons: [AXUIElement], inputs: Int, dialogs: Int, limited: Bool,
            visitedCount: Int, elapsedMs: Int, remainingCount: Int) {
        let allowed: Set<String> = [
            "search", "search chats", "search chats…", "search conversations",
            "검색", "채팅 검색", "채팅 검색…", "대화 검색", "대화 검색…"
        ]
        var queue: [AXUIElement] = [window]
        var visited: Set<String> = []
        var buttons: [AXUIElement] = []
        var inputs = 0
        var dialogs = 0
        var index = 0
        let started = ProcessInfo.processInfo.systemUptime
        // Search the full AX subtree. Stop only on the monotonic time budget,
        // never on an arbitrary element count or per-parent child cap.
        while index < queue.count &&
            ProcessInfo.processInfo.systemUptime - started < 5.0 {
            let element = queue[index]
            index += 1
            let key = String(CFHash(element))
            guard visited.insert(key).inserted else { continue }
            let role = str(element, kAXRoleAttribute)
            if role == "AXTextField" || role == "AXSearchField" ||
                role == "AXComboBox" { inputs += 1 }
            if role == "AXDialog" || role == "AXSheet" { dialogs += 1 }
            if role == "AXButton" {
                let labels = [
                    str(element, kAXTitleAttribute),
                    str(element, kAXDescriptionAttribute),
                    str(element, kAXHelpAttribute)
                ].map { $0.trimmingCharacters(in: .whitespacesAndNewlines)
                          .lowercased() }
                if labels.contains(where: { allowed.contains($0) }) {
                    buttons.append(element)
                }
            }
            var next = children(element)
            if next.isEmpty {
                next = (read(element, kAXVisibleChildrenAttribute)
                    as? [AXUIElement]) ?? []
            }
            queue.append(contentsOf: next)
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        let timedOut = index < queue.count && elapsed >= 5.0
        return (buttons, inputs, dialogs, timedOut,
            visited.count, Int(elapsed * 1000), queue.count - index)
    }

    // Opt-in read-only probe of one previously identity-verified blank window.
    // The caller supplies the exact complete native AX census (hash:minimized).
    // Fail closed on any changed window, missing identity or unexpected state.
    func probeIsolatedWindowMetrics(
        expectedID: String, expectedSnapshot: String,
        completed: @escaping (Bool, String) -> Void
    ) {
        guard !busy, AXIsProcessTrusted(),
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == "com.openai.codex"
              }) else { completed(false, "no-AX-or-app"); return }
        var expected: [String: Bool] = [:]
        for entry in expectedSnapshot.split(separator: ",") {
            let fields = entry.split(separator: ":")
            guard fields.count == 2,
                  (fields[1] == "0" || fields[1] == "1"),
                  expected[String(fields[0])] == nil else {
                completed(false, "invalid-expected-snapshot"); return
            }
            expected[String(fields[0])] = fields[1] == "1"
        }
        guard expected.count == 8, expected[expectedID] == false,
              expected.values.filter({ $0 }).count == 3 else {
            completed(false, "expected-baseline-not-eight-or-three"); return
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.35)
        let windows = winList(root)
        guard windows.count == expected.count else {
            completed(false, "window-count-changed"); return
        }
        var actual: [String: Bool] = [:]
        for window in windows {
            let id = String(CFHash(window))
            guard actual[id] == nil,
                  let minimized = (read(window, kAXMinimizedAttribute) as? NSNumber)?.boolValue,
                  str(window, kAXRoleAttribute) == "AXWindow" else {
                completed(false, "window-identity-or-state-unavailable"); return
            }
            actual[id] = minimized
        }
        guard actual == expected,
              let target = windows.first(where: {
                  String(CFHash($0)) == expectedID
              }),
              title(target) == "ChatGPT" else {
            completed(false, "baseline-changed-or-target-not-generic"); return
        }
        // Read only the isolated AX subtree. Never log labels, titles, IDs,
        // message text, query text, or URL. No AXPress or app activation.
        let scan = searchUIScan(target)
        let after = winList(root)
        var afterStates: [String: Bool] = [:]
        for window in after {
            let id = String(CFHash(window))
            guard afterStates[id] == nil,
                  let minimized = (read(window, kAXMinimizedAttribute) as? NSNumber)?.boolValue else {
                completed(false, "postscan-window-state-unavailable"); return
            }
            afterStates[id] = minimized
        }
        let preserved = afterStates == expected
        completed(preserved && !scan.limited,
            "isolated=true count=\(windows.count) minimized=3 " +
            "visited=\(scan.visitedCount) elapsedMs=\(scan.elapsedMs) " +
            "remaining=\(scan.remainingCount) limited=\(scan.limited) " +
            "searchButtons=\(scan.buttons.count) inputs=\(scan.inputs) " +
            "dialogs=\(scan.dialogs) originalsPreserved=\(preserved)")
    }

    // One-shot privacy-safe AX attribute-shape probe for the isolated eighth window.
    // Never logs private AX values, titles, IDs, URLs, queries or message text.
    // No AXPress, focus activation, text entry, selection or window creation.
    func probeIsolatedSearchResultMetadata(
        expectedID: String, expectedSnapshot: String, expectedPID: pid_t,
        completed: @escaping (Bool, String) -> Void
    ) {
        guard !busy, AXIsProcessTrusted(),
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == "com.openai.codex"
              }), app.processIdentifier == expectedPID else {
            completed(false, "metadata-AX-or-pid-unavailable"); return
        }
        var expected: [String: Bool] = [:]
        for entry in expectedSnapshot.split(separator: ",") {
            let fields = entry.split(separator: ":")
            guard fields.count == 2,
                  (fields[1] == "0" || fields[1] == "1"),
                  expected[String(fields[0])] == nil else {
                completed(false, "metadata-invalid-baseline"); return
            }
            expected[String(fields[0])] = fields[1] == "1"
        }
        guard expected.count == 8, expected[expectedID] == false,
              expected.values.filter({ $0 }).count == 3 else {
            completed(false, "metadata-unexpected-baseline"); return
        }
        let root = AXUIElementCreateApplication(expectedPID)
        AXUIElementSetMessagingTimeout(root, 0.35)
        func snapshot() -> ([String: Bool]?, AXUIElement?) {
            let windows = winList(root)
            guard windows.count == 8 else { return (nil, nil) }
            var actual: [String: Bool] = [:]
            for window in windows {
                let id = String(CFHash(window))
                guard actual[id] == nil,
                      str(window, kAXRoleAttribute) == "AXWindow",
                      let minimized = (read(window, kAXMinimizedAttribute)
                          as? NSNumber)?.boolValue else { return (nil, nil) }
                actual[id] = minimized
            }
            return (actual, windows.first(where: {
                String(CFHash($0)) == expectedID
            }))
        }
        let (before, target) = snapshot()
        guard before == expected, let target, title(target) == "ChatGPT" else {
            completed(false, "metadata-baseline-or-target-changed"); return
        }
        let search = searchUIScan(target)
        guard !search.limited else {
            completed(false, "metadata-search-scan-limited"); return
        }
        let candidateRoles: Set<String> = [
            "AXRow", "AXCell", "AXMenuItem", "AXButton", "AXGroup"
        ]
        let uuidPattern = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
        var queue: [AXUIElement] = [target]
        var seen: Set<String> = []
        var index = 0
        var candidates = 0
        var values = 0
        var identifiers = 0
        var urls = 0
        var uuidShaped = 0
        var chatURLShaped = 0
        let started = ProcessInfo.processInfo.systemUptime
        while index < queue.count &&
            ProcessInfo.processInfo.systemUptime - started < 5.0 {
            let element = queue[index]
            index += 1
            guard seen.insert(String(CFHash(element))).inserted else { continue }
            if candidateRoles.contains(str(element, kAXRoleAttribute)) {
                candidates += 1
                var rawNames: CFArray?
                if AXUIElementCopyAttributeNames(element, &rawNames) == .success,
                   let names = rawNames as? [String] {
                    for key in ["AXValue", "AXIdentifier", "AXURL"] {
                        guard names.contains(key) else { continue }
                        if key == "AXValue" { values += 1 }
                        if key == "AXIdentifier" { identifiers += 1 }
                        if key == "AXURL" { urls += 1 }
                        // Shape-only classification: raw content never leaves memory.
                        let raw = read(element, key)
                        let value: String
                        if let s = raw as? String {
                            value = s
                        } else if let u = raw as? URL {
                            value = u.absoluteString
                        } else {
                            value = ""
                        }
                        if value.range(of: uuidPattern,
                            options: .regularExpression) != nil {
                            uuidShaped += 1
                        }
                        if value.hasPrefix("https://chatgpt.com/c/") {
                            chatURLShaped += 1
                        }
                    }
                }
            }
            var next = children(element)
            if next.isEmpty {
                next = (read(element, kAXVisibleChildrenAttribute)
                    as? [AXUIElement]) ?? []
            }
            queue.append(contentsOf: next)
        }
        let limited = index < queue.count
        let (after, _) = snapshot()
        let preserved = after == expected
        completed(preserved && !limited,
            "count=8 minimized=3 inputs=\(search.inputs) " +
            "candidateElements=\(candidates) AXValuePresent=\(values) " +
            "AXIdentifierPresent=\(identifiers) AXURLPresent=\(urls) " +
            "uuidShaped=\(uuidShaped) chatURLShaped=\(chatURLShaped) " +
            "visited=\(seen.count) limited=\(limited) " +
            "originalsPreserved=\(preserved)")
    }

    // Read-only AX role/action census for the already queried isolated window.
    // Never reveal titles, result values, IDs, URLs or message text.
    func probeIsolatedSearchResultActions(
        expectedID: String, expectedSnapshot: String, expectedPID: pid_t,
        completed: @escaping (Bool, String) -> Void
    ) {
        guard !busy, AXIsProcessTrusted(),
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == "com.openai.codex"
              }), app.processIdentifier == expectedPID else {
            completed(false, "result-actions-AX-or-pid-unavailable"); return
        }
        var expected: [String: Bool] = [:]
        for entry in expectedSnapshot.split(separator: ",") {
            let fields = entry.split(separator: ":")
            guard fields.count == 2,
                  (fields[1] == "0" || fields[1] == "1"),
                  expected[String(fields[0])] == nil else {
                completed(false, "result-actions-invalid-baseline"); return
            }
            expected[String(fields[0])] = fields[1] == "1"
        }
        guard expected.count == 8, expected[expectedID] == false,
              expected.values.filter({ $0 }).count == 3 else {
            completed(false, "result-actions-unexpected-baseline"); return
        }
        let root = AXUIElementCreateApplication(expectedPID)
        AXUIElementSetMessagingTimeout(root, 0.35)
        func snapshot() -> ([String: Bool]?, AXUIElement?) {
            let windows = winList(root)
            guard windows.count == 8 else { return (nil, nil) }
            var actual: [String: Bool] = [:]
            for window in windows {
                let id = String(CFHash(window))
                guard actual[id] == nil,
                      str(window, kAXRoleAttribute) == "AXWindow",
                      let minimized = (read(window, kAXMinimizedAttribute)
                          as? NSNumber)?.boolValue else { return (nil, nil) }
                actual[id] = minimized
            }
            return (actual, windows.first(where: {
                String(CFHash($0)) == expectedID
            }))
        }
        let (before, target) = snapshot()
        guard before == expected, let target, title(target) == "ChatGPT" else {
            completed(false, "result-actions-baseline-or-target-changed"); return
        }
        // Track fixed AX roles, per-list ancestry and aggregate query-match counts.
        // Never emit any text, IDs, URLs, hashes, or raw accessibility values.
        var queue: [(element: AXUIElement, parentRole: String, listIndex: Int?, candidateAncestors: [Int])] = [
            (element: target, parentRole: "root", listIndex: nil, candidateAncestors: [])
        ]
        var seen: Set<String> = []
        var index = 0
        var inputs = 0
        var queryMatches = 0
        var rows = 0
        var cells = 0
        var menuItems = 0
        var buttons = 0
        var links = 0
        var groups = 0
        var pressable = 0
        var menuActions = 0
        var nonemptyIDs = 0
        var chatURLs = 0
        // Only fixed AX role names are emitted; never log UI labels or values.
        let safeRoles: Set<String> = ["AXWindow", "AXWebArea", "AXGroup", "AXButton", "AXStaticText", "AXList", "AXListBox", "AXOption", "AXRow", "AXCell", "AXMenuItem", "AXLink", "AXScrollArea", "AXTextField", "AXSearchField", "AXComboBox", "AXImage", "AXCheckBox", "AXHeading", "AXTextArea", "AXToolbar", "AXSplitGroup"]
        var roleCounts: [String: Int] = [:]
        var listParentRoles: [String: Int] = [:]
        var listDirectChildren: [Int] = []
        var listDirectRoles: [Int: [String: Int]] = [:]
        var listPressGroups: [Int: Int] = [:]
        var listTextNodes: [Int: Int] = [:]
        var listQueryTextNodes: [Int: Int] = [:]
        var listPressParentRoles: [Int: [String: Int]] = [:]
        var groupParentRoles: [String: Int] = [:]
        var groupsInsideList = 0
        var pressGroupsInsideList = 0
        var menuGroupsInsideList = 0
        var pressRoles: [String: Int] = [:]
        var menuRoles: [String: Int] = [:]
        // Per-AXPress Group structural census. Never collect titles, text or IDs.
        var candidateParents: [String] = []
        var candidateChildCounts: [Int] = []
        var candidateTextCounts: [Int] = []
        var candidateQueryCounts: [Int] = []
        var candidateGroupCounts: [Int] = []
        var candidateHasMenu: [Bool] = []
        // Read only AX metadata keys/action names, never attribute values.
        // These names are fixed platform identifiers, not user-visible text.
        let safeCandidateAttributes: Set<String> = [
            "AXRole", "AXSubrole", "AXTitle", "AXValue", "AXDescription",
            "AXHelp", "AXIdentifier", "AXDOMIdentifier", "AXURL",
            "AXDocument", "AXSelected", "AXFocused", "AXEnabled",
            "AXChildren", "AXVisibleChildren", "AXParent", "AXWindow",
            "AXPosition", "AXSize", "AXLinkUIElements"
        ]
        let safeCandidateActions: Set<String> = [
            "AXPress", "AXShowMenu", "AXCancel", "AXConfirm",
            "AXPick", "AXRaise", "AXScrollToVisible"
        ]
        var candidateAttributeKeys: [String] = []
        var candidateActionKeys: [String] = []
        var candidateDescendantIDKeys: [Int] = []
        var candidateDescendantURLKeys: [Int] = []
        var candidateDescendantDOMKeys: [Int] = []
        let started = ProcessInfo.processInfo.systemUptime
        while index < queue.count &&
            ProcessInfo.processInfo.systemUptime - started < 5.0 {
            let node = queue[index]
            let element = node.element
            index += 1
            guard seen.insert(String(CFHash(element))).inserted else { continue }
            let role = str(element, kAXRoleAttribute)
            let safeRole = safeRoles.contains(role) ? role : "other"
            roleCounts[safeRole, default: 0] += 1
            if role == "AXList" {
                listParentRoles[node.parentRole, default: 0] += 1
            }
            // Aggregate only counts under pressable result candidates, never values.
            for candidate in node.candidateAncestors {
                // Presence-only attribute census on candidate descendants.
                var rawDescendantKeys: CFArray?
                if AXUIElementCopyAttributeNames(element, &rawDescendantKeys) == .success,
                   let keys = rawDescendantKeys as? [String] {
                    if keys.contains("AXIdentifier") { candidateDescendantIDKeys[candidate] += 1 }
                    if keys.contains("AXURL") { candidateDescendantURLKeys[candidate] += 1 }
                    if keys.contains("AXDOMIdentifier") { candidateDescendantDOMKeys[candidate] += 1 }
                }
                if role == "AXGroup" { candidateGroupCounts[candidate] += 1 }
                if role == "AXStaticText" {
                    candidateTextCounts[candidate] += 1
                    if let value = read(element, kAXValueAttribute) as? String,
                       value.range(of: "ChatGPT", options: .caseInsensitive) != nil {
                        candidateQueryCounts[candidate] += 1
                    }
                }
            }
            if let listIndex = node.listIndex {
                if node.parentRole == "AXList" {
                    listDirectRoles[listIndex, default: [:]][safeRole, default: 0] += 1
                }
                if role == "AXStaticText" {
                    listTextNodes[listIndex, default: 0] += 1
                    // Match count only. Never store or log the underlying text.
                    if let value = read(element, kAXValueAttribute) as? String,
                       value.range(of: "ChatGPT", options: .caseInsensitive) != nil {
                        listQueryTextNodes[listIndex, default: 0] += 1
                    }
                }
            }
            if role == "AXGroup" && node.listIndex != nil {
                groupsInsideList += 1
            }
            if ["AXTextField", "AXSearchField", "AXComboBox"].contains(role) {
                inputs += 1
                if (read(element, kAXValueAttribute) as? String) == "ChatGPT" {
                    queryMatches += 1
                }
            }
            if role == "AXRow" { rows += 1 }
            if role == "AXCell" { cells += 1 }
            if role == "AXMenuItem" { menuItems += 1 }
            if role == "AXButton" { buttons += 1 }
            if role == "AXLink" { links += 1 }
            if role == "AXGroup" { groups += 1 }
            var isCandidate = false
            var candidateMenu = false
            var candidateActions = ""
            if ["AXRow", "AXCell", "AXMenuItem", "AXButton", "AXLink", "AXGroup", "AXOption", "AXList", "AXListBox"].contains(role) {
                var rawActions: CFArray?
                if AXUIElementCopyActionNames(element, &rawActions) == .success,
                   let actions = rawActions as? [String] {
                    if actions.contains("AXPress") {
                        pressable += 1
                        pressRoles[safeRole, default: 0] += 1
                        if role == "AXGroup" {
                            groupParentRoles[node.parentRole, default: 0] += 1
                            if let listIndex = node.listIndex {
                                isCandidate = true
                                candidateActions = actions.filter {
                                    safeCandidateActions.contains($0)
                                }.sorted().joined(separator: "|")
                                pressGroupsInsideList += 1
                                listPressGroups[listIndex, default: 0] += 1
                                listPressParentRoles[listIndex, default: [:]][node.parentRole, default: 0] += 1
                            }
                        }
                    }
                    if actions.contains("AXShowMenu") {
                        if isCandidate { candidateMenu = true }
                        menuActions += 1
                        menuRoles[safeRole, default: 0] += 1
                        if role == "AXGroup" && node.listIndex != nil {
                            menuGroupsInsideList += 1
                        }
                    }
                }
                if let identifier = read(element, kAXIdentifierAttribute) as? String,
                   !identifier.isEmpty { nonemptyIDs += 1 }
                if let rawURL = read(element, kAXURLAttribute) {
                    let value: String
                    if let url = rawURL as? URL { value = url.absoluteString }
                    else { value = rawURL as? String ?? "" }
                    if value.hasPrefix("https://chatgpt.com/c/") {
                        chatURLs += 1
                    }
                }
            }
            var next = children(element)
            if next.isEmpty {
                next = (read(element, kAXVisibleChildrenAttribute)
                    as? [AXUIElement]) ?? []
            }
            let childListIndex: Int?
            if role == "AXList" {
                childListIndex = listDirectChildren.count
                listDirectChildren.append(next.count)
            } else {
                childListIndex = node.listIndex
            }
            var childAncestors = node.candidateAncestors
            if isCandidate {
                let candidate = candidateParents.count
                candidateParents.append(node.parentRole)
                candidateChildCounts.append(next.count)
                candidateTextCounts.append(0)
                candidateQueryCounts.append(0)
                candidateGroupCounts.append(0)
                candidateHasMenu.append(candidateMenu)
                candidateActionKeys.append(candidateActions)
                var rawCandidateKeys: CFArray?
                var candidateKeys = ""
                if AXUIElementCopyAttributeNames(element, &rawCandidateKeys) == .success,
                   let keys = rawCandidateKeys as? [String] {
                    candidateKeys = keys.filter {
                        safeCandidateAttributes.contains($0)
                    }.sorted().joined(separator: "|")
                }
                candidateAttributeKeys.append(candidateKeys)
                candidateDescendantIDKeys.append(0)
                candidateDescendantURLKeys.append(0)
                candidateDescendantDOMKeys.append(0)
                childAncestors.append(candidate)
            }
            queue.append(contentsOf: next.map {
                (element: $0, parentRole: safeRole, listIndex: childListIndex,
                 candidateAncestors: childAncestors)
            })
        }
        let limited = index < queue.count
        let (after, _) = snapshot()
        let preserved = after == expected
        let queryValid = inputs == 1 && queryMatches == 1
        func summary(_ counts: [String: Int]) -> String {
            counts.keys.sorted().map { "\($0):\(counts[$0] ?? 0)" }.joined(separator: ",")
        }
        let listDetails = listDirectChildren.indices.map { listIndex in
            "\(listIndex):children=\(listDirectChildren[listIndex])" +
            ":press=\(listPressGroups[listIndex, default: 0])" +
            ":text=\(listTextNodes[listIndex, default: 0])" +
            ":queryText=\(listQueryTextNodes[listIndex, default: 0])" +
            ":directRoles=\(summary(listDirectRoles[listIndex, default: [:]]))" +
            ":pressParents=\(summary(listPressParentRoles[listIndex, default: [:]]))"
        }.joined(separator: ";")
        let candidateDetails = candidateParents.indices.prefix(20).map { candidate in
            "\(candidate):parent=\(candidateParents[candidate])" +
            ":children=\(candidateChildCounts[candidate])" +
            ":groups=\(candidateGroupCounts[candidate])" +
            ":text=\(candidateTextCounts[candidate])" +
            ":queryText=\(candidateQueryCounts[candidate])" +
            ":menu=\(candidateHasMenu[candidate] ? 1 : 0)" +
            ":attrs=\(candidateAttributeKeys[candidate])" +
            ":actions=\(candidateActionKeys[candidate])" +
            ":descID=\(candidateDescendantIDKeys[candidate])" +
            ":descURL=\(candidateDescendantURLKeys[candidate])" +
            ":descDOM=\(candidateDescendantDOMKeys[candidate])"
        }.joined(separator: ";")
        completed(preserved && !limited && queryValid,
            "count=8 minimized=3 queryValid=\(queryValid) " +
            "rows=\(rows) cells=\(cells) menuItems=\(menuItems) " +
            "buttons=\(buttons) links=\(links) groups=\(groups) " +
            "pressable=\(pressable) menuActions=\(menuActions) " +
            "nonemptyIDs=\(nonemptyIDs) chatURLs=\(chatURLs) " +
            "listParents=\(summary(listParentRoles)) " +
            "listChildren=\(listDirectChildren.map(String.init).joined(separator: ",")) " +
            "groupsInsideList=\(groupsInsideList) " +
            "pressGroupsInsideList=\(pressGroupsInsideList) " +
            "menuGroupsInsideList=\(menuGroupsInsideList) " +
            "pressGroupParents=\(summary(groupParentRoles)) " +
            "listDetails=\(listDetails) " +
            "candidateCount=\(candidateParents.count) candidateDetails=\(candidateDetails) " +
            "roleCounts=\(summary(roleCounts)) " +
            "pressRoles=\(summary(pressRoles)) menuRoles=\(summary(menuRoles)) " +
            "visited=\(seen.count) limited=\(limited) " +
            "originalsPreserved=\(preserved)")
    }

    // Opt-in reversible contrast ONLY on the pre-existing isolated eighth window.
    // Input is restored to its exact known baseline; no results are pressed.
    // Logs only aggregate AX role counts, never text, titles, IDs or URLs.
    func probeIsolatedSearchContrast(
        expectedID: String, expectedSnapshot: String, expectedPID: pid_t,
        completed: @escaping (Bool, String) -> Void
    ) {
        guard !busy, AXIsProcessTrusted(),
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == "com.openai.codex"
              }), app.processIdentifier == expectedPID else {
            completed(false, "contrast-AX-or-pid-unavailable"); return
        }
        var expected: [String: Bool] = [:]
        for entry in expectedSnapshot.split(separator: ",") {
            let fields = entry.split(separator: ":")
            guard fields.count == 2,
                  (fields[1] == "0" || fields[1] == "1"),
                  expected[String(fields[0])] == nil else {
                completed(false, "contrast-invalid-baseline"); return
            }
            expected[String(fields[0])] = fields[1] == "1"
        }
        guard expected.count == 8, expected[expectedID] == false,
              expected.values.filter({ $0 }).count == 3 else {
            completed(false, "contrast-unexpected-baseline"); return
        }
        let root = AXUIElementCreateApplication(expectedPID)
        AXUIElementSetMessagingTimeout(root, 0.35)
        func snapshot() -> ([String: Bool]?, AXUIElement?) {
            let windows = winList(root)
            guard windows.count == 8 else { return (nil, nil) }
            var actual: [String: Bool] = [:]
            for window in windows {
                let id = String(CFHash(window))
                guard actual[id] == nil,
                      str(window, kAXRoleAttribute) == "AXWindow",
                      let minimized = (read(window, kAXMinimizedAttribute)
                          as? NSNumber)?.boolValue else { return (nil, nil) }
                actual[id] = minimized
            }
            return (actual, windows.first(where: {
                String(CFHash($0)) == expectedID
            }))
        }
        // Identity-only restoration fence: a focus change must not strand the
        // temporary query. Never restore if the user edited its value.
        func targetIdentitySafe() -> Bool {
            let (actual, target) = snapshot()
            return app.processIdentifier == expectedPID &&
                actual == expected && target.map { title($0) == "ChatGPT" } == true
        }
        func targetSafe() -> Bool {
            guard targetIdentitySafe(),
                  let rawFocused = read(root, kAXFocusedWindowAttribute),
                  CFGetTypeID(rawFocused) == AXUIElementGetTypeID() else {
                return false
            }
            return String(CFHash(rawFocused as! AXUIElement)) == expectedID
        }
        guard targetSafe(), let target = snapshot().1 else {
            completed(false, "contrast-baseline-or-focus-changed"); return
        }
        var queue: [AXUIElement] = [target]
        var seen: Set<String> = []
        var inputs: [AXUIElement] = []
        var index = 0
        let started = ProcessInfo.processInfo.systemUptime
        while index < queue.count &&
            ProcessInfo.processInfo.systemUptime - started < 5.0 {
            let element = queue[index]
            index += 1
            guard seen.insert(String(CFHash(element))).inserted else { continue }
            if ["AXTextField", "AXSearchField", "AXComboBox"].contains(
                str(element, kAXRoleAttribute)
            ) { inputs.append(element) }
            var next = children(element)
            if next.isEmpty {
                next = (read(element, kAXVisibleChildrenAttribute)
                    as? [AXUIElement]) ?? []
            }
            queue.append(contentsOf: next)
        }
        guard index == queue.count, inputs.count == 1,
              (read(inputs[0], kAXValueAttribute) as? String) == "ChatGPT",
              targetSafe() else {
            completed(false, "contrast-query-not-unique-or-unexpected"); return
        }
        let input = inputs[0]
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            input, kAXValueAttribute as CFString, &settable
        ) == .success, settable.boolValue else {
            completed(false, "contrast-input-not-settable"); return
        }
        func listCounts(_ detail: String) -> String {
            let parts = detail.components(separatedBy: "listDetails=")
            guard parts.count > 1 else { return "unavailable" }
            return parts[1].components(separatedBy: " roleCounts=")[0]
        }
        probeIsolatedSearchResultActions(
            expectedID: expectedID, expectedSnapshot: expectedSnapshot,
            expectedPID: expectedPID
        ) { baselineOK, baselineDetail in
            guard baselineOK, targetSafe() else {
                completed(false, "contrast-initial-census-failed"); return
            }
            let noMatch = "zzqv_noresults_20261029_isolated8"
            let first = AXUIElementSetAttributeValue(
                input, kAXValueAttribute as CFString, noMatch as NSString
            )
            guard first == .success else {
                completed(false, "contrast-no-match-set-failed status=\(first.rawValue)")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                let noMatchReadback = (self.read(input, kAXValueAttribute)
                    as? String) == noMatch
                self.probeIsolatedSearchResultActions(
                    expectedID: expectedID, expectedSnapshot: expectedSnapshot,
                    expectedPID: expectedPID
                ) { _, noMatchDetail in
                    // Restore only the same input in the same unchanged window.
                    // If the guard fails, do not risk writing to another window.
                    guard targetIdentitySafe(),
                          (self.read(input, kAXValueAttribute) as? String) == noMatch else {
                        completed(false, "contrast-restore-identity-or-query-changed")
                        return
                    }
                    let restore = AXUIElementSetAttributeValue(
                        input, kAXValueAttribute as CFString, "ChatGPT" as NSString
                    )
                    guard restore == .success else {
                        completed(false, "contrast-restore-write-failed status=\(restore.rawValue)")
                        return
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                        let restored = targetIdentitySafe() &&
                            (self.read(input, kAXValueAttribute) as? String) == "ChatGPT"
                        self.probeIsolatedSearchResultActions(
                            expectedID: expectedID,
                            expectedSnapshot: expectedSnapshot,
                            expectedPID: expectedPID
                        ) { finalOK, finalDetail in
                            let before = listCounts(baselineDetail)
                            let changed = listCounts(noMatchDetail)
                            let after = listCounts(finalDetail)
                            let contrastObserved = before != changed
                            completed(restored && finalOK,
                                "count=8 minimized=3 noMatchReadback=\(noMatchReadback) " +
                                "restored=\(restored) contrastObserved=\(contrastObserved) " +
                                "before=\(before) noMatch=\(changed) after=\(after) " +
                                "originalsPreserved=\(targetSafe())")
                        }
                    }
                }
            }
        }
    }

    // Read-only capability check for the existing isolated Search input.
    // No AXSetValue, AXPress, activation, query, selection or navigation.
    func probeIsolatedSearchInputCapabilities(
        expectedID: String, expectedSnapshot: String, expectedPID: pid_t,
        completed: @escaping (Bool, String) -> Void
    ) {
        guard !busy, AXIsProcessTrusted(),
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == "com.openai.codex"
              }), app.processIdentifier == expectedPID else {
            completed(false, "input-capabilities-AX-or-pid-unavailable"); return
        }
        var expected: [String: Bool] = [:]
        for entry in expectedSnapshot.split(separator: ",") {
            let fields = entry.split(separator: ":")
            guard fields.count == 2,
                  (fields[1] == "0" || fields[1] == "1"),
                  expected[String(fields[0])] == nil else {
                completed(false, "input-capabilities-invalid-baseline"); return
            }
            expected[String(fields[0])] = fields[1] == "1"
        }
        guard expected.count == 8, expected[expectedID] == false,
              expected.values.filter({ $0 }).count == 3 else {
            completed(false, "input-capabilities-unexpected-baseline"); return
        }
        let root = AXUIElementCreateApplication(expectedPID)
        AXUIElementSetMessagingTimeout(root, 0.35)
        func snapshot() -> ([String: Bool]?, AXUIElement?) {
            let windows = winList(root)
            guard windows.count == 8 else { return (nil, nil) }
            var actual: [String: Bool] = [:]
            for window in windows {
                let id = String(CFHash(window))
                guard actual[id] == nil,
                      str(window, kAXRoleAttribute) == "AXWindow",
                      let minimized = (read(window, kAXMinimizedAttribute)
                          as? NSNumber)?.boolValue else { return (nil, nil) }
                actual[id] = minimized
            }
            return (actual, windows.first(where: {
                String(CFHash($0)) == expectedID
            }))
        }
        let (before, target) = snapshot()
        guard before == expected, let target, title(target) == "ChatGPT" else {
            completed(false, "input-capabilities-baseline-or-target-changed"); return
        }
        let search = searchUIScan(target)
        guard !search.limited, search.inputs == 1 else {
            completed(false, "input-capabilities-search-not-unique"); return
        }
        var queue: [AXUIElement] = [target]
        var seen: Set<String> = []
        var index = 0
        var inputCount = 0
        var settableCount = 0
        var emptyCount = 0
        var roleTextField = 0
        let started = ProcessInfo.processInfo.systemUptime
        while index < queue.count &&
            ProcessInfo.processInfo.systemUptime - started < 5.0 {
            let element = queue[index]
            index += 1
            guard seen.insert(String(CFHash(element))).inserted else { continue }
            let role = str(element, kAXRoleAttribute)
            if ["AXTextField", "AXSearchField", "AXComboBox"].contains(role) {
                inputCount += 1
                if role == "AXTextField" { roleTextField += 1 }
                var settable = DarwinBoolean(false)
                if AXUIElementIsAttributeSettable(
                    element, kAXValueAttribute as CFString, &settable
                ) == .success && settable.boolValue {
                    settableCount += 1
                }
                // Only report whether empty. Never log the actual input value.
                if (read(element, kAXValueAttribute) as? String) == "" {
                    emptyCount += 1
                }
            }
            var next = children(element)
            if next.isEmpty {
                next = (read(element, kAXVisibleChildrenAttribute)
                    as? [AXUIElement]) ?? []
            }
            queue.append(contentsOf: next)
        }
        let limited = index < queue.count
        let (after, _) = snapshot()
        let preserved = after == expected
        completed(preserved && !limited && inputCount == 1,
            "count=8 minimized=3 inputs=\(inputCount) " +
            "settable=\(settableCount) empty=\(emptyCount) " +
            "textField=\(roleTextField) visited=\(seen.count) " +
            "limited=\(limited) originalsPreserved=\(preserved)")
    }

    // Explicit one-shot Search query on the *existing isolated eighth window*.
    // The fixed, non-sensitive word is never sent as a chat message. No result
    // selection, owner-window navigation, new window, or application activation.
    func probeIsolatedSearchQuery(
        expectedID: String, expectedSnapshot: String, expectedPID: pid_t,
        completed: @escaping (Bool, String) -> Void
    ) {
        guard !busy, AXIsProcessTrusted(),
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == "com.openai.codex"
              }), app.processIdentifier == expectedPID else {
            completed(false, "query-AX-or-pid-unavailable"); return
        }
        var expected: [String: Bool] = [:]
        for entry in expectedSnapshot.split(separator: ",") {
            let fields = entry.split(separator: ":")
            guard fields.count == 2,
                  (fields[1] == "0" || fields[1] == "1"),
                  expected[String(fields[0])] == nil else {
                completed(false, "query-invalid-baseline"); return
            }
            expected[String(fields[0])] = fields[1] == "1"
        }
        guard expected.count == 8, expected[expectedID] == false,
              expected.values.filter({ $0 }).count == 3 else {
            completed(false, "query-unexpected-baseline"); return
        }
        let root = AXUIElementCreateApplication(expectedPID)
        AXUIElementSetMessagingTimeout(root, 0.35)
        func snapshot() -> ([String: Bool]?, AXUIElement?) {
            let windows = winList(root)
            guard windows.count == 8 else { return (nil, nil) }
            var actual: [String: Bool] = [:]
            for window in windows {
                let id = String(CFHash(window))
                guard actual[id] == nil,
                      str(window, kAXRoleAttribute) == "AXWindow",
                      let minimized = (read(window, kAXMinimizedAttribute)
                          as? NSNumber)?.boolValue else { return (nil, nil) }
                actual[id] = minimized
            }
            return (actual, windows.first(where: {
                String(CFHash($0)) == expectedID
            }))
        }
        let (before, target) = snapshot()
        guard before == expected, let target, title(target) == "ChatGPT",
              let focused = read(root, kAXFocusedWindowAttribute),
              CFGetTypeID(focused) == AXUIElementGetTypeID(),
              String(CFHash(focused as! AXUIElement)) == expectedID else {
            completed(false, "query-baseline-or-target-focus-changed"); return
        }
        let scan = searchUIScan(target)
        guard !scan.limited, scan.inputs == 1 else {
            completed(false, "query-search-input-not-unique"); return
        }
        var queue: [AXUIElement] = [target]
        var seen: Set<String> = []
        var inputs: [AXUIElement] = []
        var index = 0
        let started = ProcessInfo.processInfo.systemUptime
        while index < queue.count &&
            ProcessInfo.processInfo.systemUptime - started < 5.0 {
            let element = queue[index]
            index += 1
            guard seen.insert(String(CFHash(element))).inserted else { continue }
            if ["AXTextField", "AXSearchField", "AXComboBox"].contains(
                str(element, kAXRoleAttribute)
            ) {
                inputs.append(element)
            }
            var next = children(element)
            if next.isEmpty {
                next = (read(element, kAXVisibleChildrenAttribute)
                    as? [AXUIElement]) ?? []
            }
            queue.append(contentsOf: next)
        }
        guard index == queue.count, inputs.count == 1,
              (read(inputs[0], kAXValueAttribute) as? String) == "" else {
            completed(false, "query-input-not-empty-or-scan-limited"); return
        }
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            inputs[0], kAXValueAttribute as CFString, &settable
        ) == .success, settable.boolValue,
              snapshot().0 == expected else {
            completed(false, "query-input-not-settable-or-baseline-changed"); return
        }
        let query = "ChatGPT" as NSString
        let status = AXUIElementSetAttributeValue(
            inputs[0], kAXValueAttribute as CFString, query
        )
        guard status == .success else {
            completed(false, "query-AXSetValue-failed status=\(status.rawValue)")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            let (after, afterTarget) = snapshot()
            let preserved = after == expected &&
                afterTarget.map { self.title($0) == "ChatGPT" } == true
            let readback = (self.read(inputs[0], kAXValueAttribute)
                as? String) == "ChatGPT"
            guard preserved else {
                completed(false, "query-postwrite-window-baseline-changed")
                return
            }
            self.probeIsolatedSearchResultMetadata(
                expectedID: expectedID, expectedSnapshot: expectedSnapshot,
                expectedPID: expectedPID
            ) { metadataOK, detail in
                completed(readback && metadataOK,
                    "AXSetValue=true AXValueReadback=\(readback) " +
                    "originalsPreserved=\(preserved) metadataOK=\(metadataOK) " +
                    detail)
            }
        }
    }

    // One-shot, strictly read-only diagnosis of the isolated window's focus gate.
    // No AX actions, activation, titles, content, or other-window hashes logged.
    func probeIsolatedFocusGate(
        expectedID: String, expectedSnapshot: String, expectedPID: pid_t,
        completed: @escaping (Bool, String) -> Void
    ) {
        guard !busy, AXIsProcessTrusted(),
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == "com.openai.codex"
              }), app.processIdentifier == expectedPID else {
            completed(false, "busy-AX-or-pid-changed"); return
        }
        var expected: [String: Bool] = [:]
        for entry in expectedSnapshot.split(separator: ",") {
            let fields = entry.split(separator: ":")
            guard fields.count == 2,
                  (fields[1] == "0" || fields[1] == "1"),
                  expected[String(fields[0])] == nil else {
                completed(false, "invalid-baseline"); return
            }
            expected[String(fields[0])] = fields[1] == "1"
        }
        guard expected.count == 8, expected[expectedID] == false,
              expected.values.filter({ $0 }).count == 3 else {
            completed(false, "unexpected-baseline"); return
        }
        let root = AXUIElementCreateApplication(expectedPID)
        AXUIElementSetMessagingTimeout(root, 0.35)
        func snapshot() -> ([String: Bool]?, [AXUIElement]) {
            let windows = winList(root)
            guard windows.count == 8 else { return (nil, windows) }
            var actual: [String: Bool] = [:]
            for window in windows {
                let id = String(CFHash(window))
                guard actual[id] == nil,
                      str(window, kAXRoleAttribute) == "AXWindow",
                      let minimized = (read(window, kAXMinimizedAttribute)
                          as? NSNumber)?.boolValue else {
                    return (nil, windows)
                }
                actual[id] = minimized
            }
            return (actual, windows)
        }
        let (before, windows) = snapshot()
        guard before == expected,
              let target = windows.first(where: {
                  String(CFHash($0)) == expectedID
              }), title(target) == "ChatGPT" else {
            completed(false, "baseline-changed-or-target-not-generic"); return
        }
        let chatgptFrontmost =
            NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedPID
        let focusedRaw = read(root, kAXFocusedWindowAttribute)
        let focusAvailable = focusedRaw.map {
            CFGetTypeID($0) == AXUIElementGetTypeID()
        } ?? false
        let isolatedTargetFocused = focusAvailable &&
            String(CFHash(focusedRaw as! AXUIElement)) == expectedID
        let (after, _) = snapshot()
        guard after == expected else {
            completed(false, "postdiagnostic-baseline-changed"); return
        }
        completed(true,
            "baseline=true count=8 minimized=3 " +
            "chatgptFrontmost=\(chatgptFrontmost) " +
            "focusedWindowAvailable=\(focusAvailable) " +
            "isolatedTargetFocused=\(isolatedTargetFocused) " +
            "originalsPreserved=true")
    }

    // Explicit one-shot Search UI press on the previously verified eighth window.
    // Requires an exact eight-window census, a fixed ChatGPT PID and the target
    // already focused. No activation, AXRaise, text input or result selection.
    func probeIsolatedSearchPress(
        expectedID: String, expectedSnapshot: String, expectedPID: pid_t,
        completed: @escaping (Bool, String) -> Void
    ) {
        guard !busy, AXIsProcessTrusted(),
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == "com.openai.codex"
              }), app.processIdentifier == expectedPID else {
            completed(false, "busy-AX-or-pid-changed"); return
        }
        var expected: [String: Bool] = [:]
        for entry in expectedSnapshot.split(separator: ",") {
            let fields = entry.split(separator: ":")
            guard fields.count == 2,
                  (fields[1] == "0" || fields[1] == "1"),
                  expected[String(fields[0])] == nil else {
                completed(false, "invalid-baseline"); return
            }
            expected[String(fields[0])] = fields[1] == "1"
        }
        guard expected.count == 8, expected[expectedID] == false,
              expected.values.filter({ $0 }).count == 3 else {
            completed(false, "unexpected-baseline"); return
        }
        let root = AXUIElementCreateApplication(expectedPID)
        AXUIElementSetMessagingTimeout(root, 0.35)
        func baselineSafe() -> (Bool, AXUIElement?) {
            let windows = self.winList(root)
            guard windows.count == 8 else { return (false, nil) }
            var actual: [String: Bool] = [:]
            for window in windows {
                let id = String(CFHash(window))
                guard actual[id] == nil,
                      self.str(window, kAXRoleAttribute) == "AXWindow",
                      let minimized = (self.read(window, kAXMinimizedAttribute)
                          as? NSNumber)?.boolValue else { return (false, nil) }
                actual[id] = minimized
            }
            guard actual == expected,
                  let target = windows.first(where: {
                      String(CFHash($0)) == expectedID
                  }), self.title(target) == "ChatGPT" else {
                return (false, nil)
            }
            return (true, target)
        }
        guard baselineSafe().0,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedPID,
              let rawFocused = read(root, kAXFocusedWindowAttribute),
              CFGetTypeID(rawFocused) == AXUIElementGetTypeID(),
              String(CFHash(rawFocused as! AXUIElement)) == expectedID,
              let target = baselineSafe().1 else {
            completed(false, "baseline-or-target-focus-changed"); return
        }
        let scan = searchUIScan(target)
        guard !scan.limited, scan.buttons.count == 1,
              scan.inputs == 0, scan.dialogs == 0,
              baselineSafe().0,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedPID,
              let rawFocusAgain = read(root, kAXFocusedWindowAttribute),
              CFGetTypeID(rawFocusAgain) == AXUIElementGetTypeID(),
              String(CFHash(rawFocusAgain as! AXUIElement)) == expectedID else {
            completed(false, "search-button-or-prepress-guard-failed"); return
        }
        busy = true
        guard press(scan.buttons[0]) else {
            busy = false
            completed(false, "isolated-search-AXPress-failed"); return
        }
        let started = ProcessInfo.processInfo.systemUptime
        func poll() {
            let safe = baselineSafe().0
            guard safe else {
                self.busy = false
                completed(false, "postpress-window-census-changed"); return
            }
            let after = self.searchUIScan(target)
            let opened = !after.limited &&
                (after.inputs > scan.inputs || after.dialogs > scan.dialogs)
            if !opened && !after.limited &&
                ProcessInfo.processInfo.systemUptime - started < 6.0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { poll() }
                return
            }
            self.busy = false
            completed(opened,
                "isolatedSearchPressed=true opened=\(opened) " +
                "beforeInputs=\(scan.inputs) afterInputs=\(after.inputs) " +
                "beforeDialogs=\(scan.dialogs) afterDialogs=\(after.dialogs) " +
                "AXLimited=\(after.limited) originalsPreserved=\(safe)")
        }
        poll()
    }

    // One-shot, identity-fenced activation of the already focused isolated eighth
    // window. Restore the previously frontmost application after the Search probe.
    // No AXRaise, new window, text entry, chat selection or owner-window navigation.
    func probeIsolatedForegroundSearch(
        expectedID: String, expectedSnapshot: String, expectedPID: pid_t,
        completed: @escaping (Bool, String) -> Void
    ) {
        guard !busy, AXIsProcessTrusted(),
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == "com.openai.codex"
              }), app.processIdentifier == expectedPID,
              let prior = NSWorkspace.shared.frontmostApplication,
              prior.processIdentifier != expectedPID, !prior.isTerminated else {
            completed(false, "foreground-preflight-app-unavailable"); return
        }
        var expected: [String: Bool] = [:]
        for entry in expectedSnapshot.split(separator: ",") {
            let fields = entry.split(separator: ":")
            guard fields.count == 2,
                  (fields[1] == "0" || fields[1] == "1"),
                  expected[String(fields[0])] == nil else {
                completed(false, "foreground-invalid-baseline"); return
            }
            expected[String(fields[0])] = fields[1] == "1"
        }
        guard expected.count == 8, expected[expectedID] == false,
              expected.values.filter({ $0 }).count == 3 else {
            completed(false, "foreground-unexpected-baseline"); return
        }
        let root = AXUIElementCreateApplication(expectedPID)
        AXUIElementSetMessagingTimeout(root, 0.35)
        func baselineSafe() -> Bool {
            let windows = self.winList(root)
            guard windows.count == 8 else { return false }
            var actual: [String: Bool] = [:]
            for window in windows {
                let id = String(CFHash(window))
                guard actual[id] == nil,
                      self.str(window, kAXRoleAttribute) == "AXWindow",
                      let minimized = (self.read(window, kAXMinimizedAttribute)
                          as? NSNumber)?.boolValue else { return false }
                actual[id] = minimized
            }
            guard actual == expected,
                  let target = windows.first(where: {
                      String(CFHash($0)) == expectedID
                  }), self.title(target) == "ChatGPT" else { return false }
            return true
        }
        func targetFocused() -> Bool {
            guard let raw = self.read(root, kAXFocusedWindowAttribute),
                  CFGetTypeID(raw) == AXUIElementGetTypeID() else { return false }
            return String(CFHash(raw as! AXUIElement)) == expectedID
        }
        guard baselineSafe(), targetFocused(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier ==
                  prior.processIdentifier else {
            completed(false, "foreground-baseline-or-target-changed"); return
        }
        // App activation raises its *already focused* window. No AXRaise on
        // any window and no request to change the ChatGPT focused AXWindow.
        guard app.activate(options: [.activateIgnoringOtherApps]) else {
            completed(false, "foreground-activation-denied"); return
        }
        func restorePriorFocus() -> Bool {
            // Never steal focus back if the user switched to a third app.
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier ==
                    expectedPID, !prior.isTerminated else { return false }
            return prior.activate(options: [.activateIgnoringOtherApps])
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard baselineSafe(), targetFocused(),
                  NSWorkspace.shared.frontmostApplication?.processIdentifier ==
                      expectedPID else {
                let restored = restorePriorFocus()
                completed(false,
                    "foreground-postactivation-guard-failed restored=\(restored)")
                return
            }
            self.probeIsolatedSearchPress(
                expectedID: expectedID, expectedSnapshot: expectedSnapshot,
                expectedPID: expectedPID
            ) { success, detail in
                let preserved = baselineSafe()
                let restored = restorePriorFocus()
                completed(success && preserved && restored,
                    "search=\(success) originalsPreserved=\(preserved) " +
                    "priorFocusRestored=\(restored) \(detail)")
            }
        }
    }

    // Explicit opt-in, read-only measurement of the *currently focused*
    // ChatGPT AXWindow. It never creates/navigates/raises/closes a window,
    // enters a search query, or logs private titles, IDs, or contents.
    func probeFocusedSearchMetrics(completed: @escaping (Bool, String) -> Void) {
        guard !busy, AXIsProcessTrusted(),
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == "com.openai.codex"
              }) else { completed(false, "no-AX-or-app"); return }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier ==
                app.processIdentifier else {
            completed(false, "ChatGPT-not-frontmost"); return
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.35)
        let originals = winList(root)
        let ids = originals.map { String(CFHash($0)) }
        guard !originals.isEmpty, Set(ids).count == originals.count,
              let rawFocused = read(root, kAXFocusedWindowAttribute),
              CFGetTypeID(rawFocused) == AXUIElementGetTypeID() else {
            completed(false, "window-census-or-focus-unavailable"); return
        }
        let focused = rawFocused as! AXUIElement
        let focusedID = String(CFHash(focused))
        guard ids.contains(focusedID),
              (read(focused, kAXMinimizedAttribute) as? NSNumber)?.boolValue == false
        else { completed(false, "focused-window-not-eligible"); return }
        let beforeMinimized = originals.map {
            (read($0, kAXMinimizedAttribute) as? NSNumber)?.boolValue
        }
        guard beforeMinimized.allSatisfy({ $0 != nil }) else {
            completed(false, "minimized-state-unavailable"); return
        }
        let focusedRole: String
        if let rawFocus = read(root, kAXFocusedUIElementAttribute),
           CFGetTypeID(rawFocus) == AXUIElementGetTypeID() {
            focusedRole = str(rawFocus as! AXUIElement, kAXRoleAttribute)
        } else {
            focusedRole = "unavailable"
        }
        // The focused palette can be in a different native window than the
        // historical test window. Inspect only AX roles/ownership; no labels.
        let nativeKind = title(focused) == "ChatGPT" ? "generic" :
            (title(focused).isEmpty ? "empty" : "named")
        let genericWindows = originals.filter { title($0) == "ChatGPT" }.count
        let focusedIndex = ids.firstIndex(of: focusedID) ?? -1
        var focusedUIWindowMatched = false
        var focusedParentWindowMatched = false
        var focusedParentDepth = 0
        if let rawUI = read(root, kAXFocusedUIElementAttribute),
           CFGetTypeID(rawUI) == AXUIElementGetTypeID() {
            let ui = rawUI as! AXUIElement
            if let rawOwner = read(ui, kAXWindowAttribute),
               CFGetTypeID(rawOwner) == AXUIElementGetTypeID() {
                focusedUIWindowMatched = String(CFHash(rawOwner)) == focusedID
            }
            var current = ui
            var seen = Set<String>()
            // Parent-only chain: never enumerate private message descendants.
            while focusedParentDepth < 24 {
                let key = String(CFHash(current))
                guard seen.insert(key).inserted else { break }
                if key == focusedID {
                    focusedParentWindowMatched = true
                    break
                }
                AXUIElementSetMessagingTimeout(current, 0.2)
                guard let rawParent = read(current, kAXParentAttribute),
                      CFGetTypeID(rawParent) == AXUIElementGetTypeID()
                else { break }
                current = rawParent as! AXUIElement
                focusedParentDepth += 1
            }
        }
        let scan = searchUIScan(focused)
        let after = winList(root)
        let statesPreserved = after.count == originals.count &&
            after.map({ String(CFHash($0)) }) == ids &&
            after.enumerated().allSatisfy { i, item in
                (read(item, kAXMinimizedAttribute) as? NSNumber)?.boolValue ==
                    beforeMinimized[i]
            }
        completed(statesPreserved,
            "windowCount=\(originals.count) focusedRole=\(focusedRole) " +
            "visited=\(scan.visitedCount) elapsedMs=\(scan.elapsedMs) " +
            "remaining=\(scan.remainingCount) timedOut=\(scan.limited) " +
            "searchButtons=\(scan.buttons.count) inputs=\(scan.inputs) " +
            "dialogs=\(scan.dialogs) windowsPreserved=\(statesPreserved) " +
            "nativeKind=\(nativeKind) genericWindows=\(genericWindows) " +
            "focusedIndex=\(focusedIndex) minimizedWindows=\(beforeMinimized.filter { $0 == true }.count) " +
            "uiWindowMatched=\(focusedUIWindowMatched) " +
            "parentWindowMatched=\(focusedParentWindowMatched) " +
            "parentDepth=\(focusedParentDepth)")
    }

    private func probeSearchOnNewWindow(
        root: AXUIElement, app: NSRunningApplication,
        created: AXUIElement, originals: [AXUIElement],
        originalMinimized: [String: Bool],
        priorFrontmost: NSRunningApplication?,
        completed: @escaping (Bool, String) -> Void
    ) {
        let newID = String(CFHash(created))
        func finish(_ success: Bool, _ reason: String) {
            self.busy = false
            if let priorFrontmost,
               priorFrontmost.processIdentifier != app.processIdentifier {
                _ = priorFrontmost.activate()
            }
            completed(success, reason)
        }
        func originalsSafe() -> Bool {
            let after = self.winList(root)
            guard after.count == originals.count + 1,
                  after.contains(where: { String(CFHash($0)) == newID })
            else { return false }
            return originals.allSatisfy { old in
                let key = String(CFHash(old))
                guard let live = after.first(where: {
                    String(CFHash($0)) == key
                }), let minimized = self.read(
                    live, kAXMinimizedAttribute) as? NSNumber
                else { return false }
                return minimized.boolValue == originalMinimized[key]
            }
        }
        func newWindowFocused() -> Bool {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier ==
                    app.processIdentifier,
                  let raw = self.read(root, kAXFocusedWindowAttribute),
                  CFGetTypeID(raw) == AXUIElementGetTypeID()
            else { return false }
            let focused = raw as! AXUIElement
            return String(CFHash(focused)) == newID
        }
        let started = ProcessInfo.processInfo.systemUptime
        func waitForSearchButton() {
            guard originalsSafe(), self.title(created) == "ChatGPT",
                  newWindowFocused() else {
                finish(false, "search-preflight-window-focus-or-originals-changed")
                return
            }
            let scan = self.searchUIScan(created)
            guard !scan.limited else {
                finish(false, "search-button-AX-scan-limited")
                return
            }
            if scan.buttons.isEmpty &&
               ProcessInfo.processInfo.systemUptime - started < 6.0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    waitForSearchButton()
                }
                return
            }
            guard scan.buttons.count == 1 else {
                finish(false, "search-button-count=\(scan.buttons.count)")
                return
            }
            guard self.press(scan.buttons[0]) else {
                finish(false, "search-button-AXPress-failed")
                return
            }
            let pressedAt = ProcessInfo.processInfo.systemUptime
            func verifySearchUI() {
                guard originalsSafe(), newWindowFocused() else {
                    finish(false, "search-after-press-window-or-focus-changed")
                    return
                }
                let after = self.searchUIScan(created)
                let visible = after.inputs > scan.inputs ||
                    after.dialogs > scan.dialogs
                if !visible && !after.limited &&
                   ProcessInfo.processInfo.systemUptime - pressedAt < 6.0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        verifySearchUI()
                    }
                    return
                }
                finish(visible && !after.limited,
                    "search-UI-only opened=\(visible) " +
                    "inputsBefore=\(scan.inputs) inputsAfter=\(after.inputs) " +
                    "dialogsBefore=\(scan.dialogs) dialogsAfter=\(after.dialogs) " +
                    "originalsRetained=true AXLimited=\(after.limited)")
            }
            verifySearchUI()
        }
        // Give the new blank window's renderer time to expose its sidebar.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            waitForSearchButton()
        }
    }

    // Explicit one-shot Search UI-only probe; no query or result selection.
    func probeSearchUI(completed: @escaping (Bool, String) -> Void) {
        guard !busy, AXIsProcessTrusted(),
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == "com.openai.codex"
              }) else { completed(false, "busy-or-no-AX-permission"); return }

        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.6)
        let original = winList(root)
        let originalIDs = Set(original.map { String(CFHash($0)) })
        guard !original.isEmpty, original.count <= 12,
              originalIDs.count == original.count,
              fileNewWindow(root) != nil
        else { completed(false, "preflight-window-or-menu-unsafe"); return }

        // Fail closed if any original window cannot report minimized state.
        var originalMinimized: [String: Bool] = [:]
        for win in original {
            guard str(win, kAXRoleAttribute) == "AXWindow",
                  let minimized = read(win, kAXMinimizedAttribute) as? NSNumber
            else { completed(false, "preflight-minimized-unavailable"); return }
            originalMinimized[String(CFHash(win))] = minimized.boolValue
        }
        let priorFrontmost = NSWorkspace.shared.frontmostApplication
        busy = true
        guard app.activate() else {
            busy = false
            completed(false, "activation-request-rejected")
            return
        }

        // The previous test pressed File > New Window immediately after
        // activation and saw AXPress success but no new window. Wait for
        // confirmed focus, then resolve the menu item again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier ==
                    app.processIdentifier else {
                self.busy = false
                priorFrontmost?.activate()
                completed(false, "focus-not-confirmed")
                return
            }
            guard let newWindowMenu = self.fileNewWindow(root),
                  self.press(newWindowMenu) else {
                self.busy = false
                priorFrontmost?.activate()
                completed(false, "focused-menu-or-AXPress-failed")
                return
            }
            let startedAt = ProcessInfo.processInfo.systemUptime
            func poll() {
                let after = self.winList(root)
                let created = after.filter {
                    !originalIDs.contains(String(CFHash($0)))
                }
                let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
                if after.count == original.count && created.isEmpty &&
                    elapsed < 8.0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        poll()
                    }
                    return
                }
                let originalsRetained = original.allSatisfy { old in
                    let key = String(CFHash(old))
                    guard let live = after.first(where: {
                        String(CFHash($0)) == key
                    }), let minimized = self.read(
                        live, kAXMinimizedAttribute) as? NSNumber
                    else { return false }
                    return minimized.boolValue == originalMinimized[key]
                }
                let newGeneric = created.count == 1 &&
                    self.title(created[0]) == "ChatGPT"
                let success = after.count == original.count + 1 &&
                    created.count == 1 && originalsRetained && newGeneric
                guard success else {
                    self.busy = false
                    if let priorFrontmost,
                       priorFrontmost.processIdentifier != app.processIdentifier {
                        _ = priorFrontmost.activate()
                    }
                    completed(false, "new-window-failed before=\(original.count) " +
                        "after=\(after.count) created=\(created.count) " +
                        "retained=\(originalsRetained) generic=\(newGeneric)")
                    return
                }
                // Only the exact newly created generic window may receive Search.
                // No query, selection, clipboard, or owner conversation navigation.
                self.probeSearchOnNewWindow(root: root, app: app,
                    created: created[0], originals: original,
                    originalMinimized: originalMinimized,
                    priorFrontmost: priorFrontmost, completed: completed)
            }
            poll()
        }
    }

    func restore(title: String, completed: @escaping (Bool, String) -> Void) {
        guard !busy else { completed(false, "복원 작업 진행 중"); return }
        guard !title.isEmpty, AXIsProcessTrusted(),
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == "com.openai.codex"
              }) else { completed(false, "ChatGPT 또는 접근성 권한 없음"); return }
        // Duplicate titles are ambiguous. Preflight before creating a window.
        guard let matches = dockRecentMatches(title), matches.count == 1 else {
            completed(false, "Recent에 없거나 같은 제목이 여러 개임")
            return
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.6)
        let original = winList(root)
        let originalIDs = Set(original.map { String(CFHash($0)) })
        guard !original.isEmpty, original.count <= 12,
              originalIDs.count == original.count,
              fileNewWindow(root) != nil else {
            completed(false, "복원 전 창/파일 메뉴 식별 실패")
            return
        }
        // Never navigate a new window if an existing window disappeared or
        // changed its minimized state during the creation preflight.
        var originalMinimized: [String: Bool] = [:]
        for win in original {
            guard str(win, kAXRoleAttribute) == "AXWindow",
                  let minimized = read(win, kAXMinimizedAttribute) as? NSNumber
            else { completed(false, "기존 창 상태 식별 실패"); return }
            originalMinimized[String(CFHash(win))] = minimized.boolValue
        }

        busy = true
        guard app.activate() else {
            busy = false
            completed(false, "ChatGPT 활성화 실패")
            return
        }
        // The live blank-window probe proved immediate AXPress after activate
        // can return success without creating a window. Wait for focus and
        // resolve a fresh menu item; press exactly once.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier ==
                    app.processIdentifier else {
                self.busy = false
                completed(false, "ChatGPT 포커스 확인 실패")
                return
            }
            guard let newWindowMenu = self.fileNewWindow(root),
                  self.press(newWindowMenu) else {
                self.busy = false
                completed(false, "새 창 메뉴 실행 실패")
                return
            }

            let createdAt = ProcessInfo.processInfo.systemUptime
            func waitForNewWindow() {
                let after = self.winList(root)
                let created = after.filter {
                    !originalIDs.contains(String(CFHash($0)))
                }
                let elapsed = ProcessInfo.processInfo.systemUptime - createdAt
                if after.count == original.count && created.isEmpty &&
                    elapsed < 8.0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        waitForNewWindow()
                    }
                    return
                }
                let originalsRetained = original.allSatisfy { old in
                    let key = String(CFHash(old))
                    guard let live = after.first(where: {
                        String(CFHash($0)) == key
                    }), let minimized = self.read(
                        live, kAXMinimizedAttribute) as? NSNumber
                    else { return false }
                    return minimized.boolValue == originalMinimized[key]
                }
                guard after.count == original.count + 1,
                      created.count == 1, originalsRetained,
                      self.title(created[0]) == "ChatGPT" else {
                    self.busy = false
                    completed(false, "새 빈 창/기존 창 보존 확인 실패")
                    return
                }

                // Re-read the Dock menu: preflight handles may be stale.
                guard let choices = self.dockRecentMatches(title),
                      choices.count == 1, self.press(choices[0]) else {
                    self.busy = false
                    completed(false, "새 창은 열렸지만 Recent 항목 실행 실패")
                    return
                }
                // Loading a native conversation title can take many seconds.
                let startedAt = ProcessInfo.processInfo.systemUptime
                let expectedCount = original.count + 1
                let newID = String(CFHash(created[0]))
                func checkResult() {
                    let result = self.winList(root)
                    let matched = result.contains {
                        String(CFHash($0)) == newID && self.title($0) == title
                    }
                    let retained = original.allSatisfy { old in
                        let key = String(CFHash(old))
                        guard let live = result.first(where: {
                            String(CFHash($0)) == key
                        }), let minimized = self.read(
                            live, kAXMinimizedAttribute) as? NSNumber
                        else { return false }
                        return minimized.boolValue == originalMinimized[key]
                    }
                    let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
                    let decision = WindowRestoreVerificationPolicy.decide(
                        elapsed: elapsed, expectedCount: expectedCount,
                        actualCount: result.count, newWindowTitleMatched: matched,
                        originalsRetained: retained)
                    switch decision {
                    case .pending:
                        DispatchQueue.main.asyncAfter(
                            deadline: .now() + WindowRestoreVerificationPolicy.pollSeconds
                        ) { checkResult() }
                    case .success:
                        self.busy = false
                        completed(true, "새 창으로 복원됨")
                    case .failure:
                        self.busy = false
                        completed(false, "복원 확인 시간 초과 " +
                            "windows=\(result.count)/\(expectedCount) " +
                            "targetMatched=\(matched) originalsRetained=\(retained)")
                    }
                }
                checkResult()
            }
            waitForNewWindow()
        }
    }

    // Single-process opt-in: raise only the isolated eighth window, contrast
    // its Search results, restore its exact input, then restore owner focus.
    // A foreground/focus change never causes us to steal focus back.
    func probeIsolatedFocusAndSearchContrast(
        expectedID: String, expectedSnapshot: String, expectedPID: pid_t,
        completed: @escaping (Bool, String) -> Void
    ) {
        guard !busy, AXIsProcessTrusted(),
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == "com.openai.codex"
              }), app.processIdentifier == expectedPID,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedPID else {
            completed(false, "focus-contrast-app-or-AX-unavailable"); return
        }
        var expected: [String: Bool] = [:]
        for entry in expectedSnapshot.split(separator: ",") {
            let fields = entry.split(separator: ":")
            guard fields.count == 2,
                  (fields[1] == "0" || fields[1] == "1"),
                  expected[String(fields[0])] == nil else {
                completed(false, "focus-contrast-invalid-baseline"); return
            }
            expected[String(fields[0])] = fields[1] == "1"
        }
        guard expected.count == 8, expected[expectedID] == false,
              expected.values.filter({ $0 }).count == 3 else {
            completed(false, "focus-contrast-unexpected-baseline"); return
        }
        let root = AXUIElementCreateApplication(expectedPID)
        AXUIElementSetMessagingTimeout(root, 0.35)
        func snapshot() -> ([String: Bool]?, [AXUIElement]) {
            let windows = winList(root)
            guard windows.count == 8 else { return (nil, windows) }
            var actual: [String: Bool] = [:]
            for window in windows {
                let id = String(CFHash(window))
                guard actual[id] == nil,
                      str(window, kAXRoleAttribute) == "AXWindow",
                      let minimized = (read(window, kAXMinimizedAttribute)
                          as? NSNumber)?.boolValue else {
                    return (nil, windows)
                }
                actual[id] = minimized
            }
            return (actual, windows)
        }
        func focusedID() -> String? {
            guard let raw = read(root, kAXFocusedWindowAttribute),
                  CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
            return String(CFHash(raw as! AXUIElement))
        }
        let (before, windows) = snapshot()
        guard before == expected,
              let target = windows.first(where: {
                  String(CFHash($0)) == expectedID
              }), title(target) == "ChatGPT",
              let originalID = focusedID(), originalID != expectedID,
              let original = windows.first(where: {
                  String(CFHash($0)) == originalID
              }), expected[originalID] == false else {
            completed(false, "focus-contrast-target-or-owner-focus-changed"); return
        }
        let raise = AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        guard raise == .success else {
            completed(false, "focus-contrast-isolated-raise-failed status=\(raise.rawValue)")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            guard snapshot().0 == expected, focusedID() == expectedID,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedPID else {
                completed(false, "focus-contrast-isolated-focus-not-confirmed")
                return
            }
            self.probeIsolatedSearchContrast(
                expectedID: expectedID, expectedSnapshot: expectedSnapshot,
                expectedPID: expectedPID
            ) { contrastOK, detail in
                let preserved = snapshot().0 == expected
                let stillFrontmost =
                    NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedPID
                let mayRestoreFocus = preserved && stillFrontmost &&
                    focusedID() == expectedID
                let restoreStatus: AXError? = mayRestoreFocus
                    ? AXUIElementPerformAction(original, kAXRaiseAction as CFString)
                    : nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    let finalPreserved = snapshot().0 == expected
                    let originalFocusRestored = focusedID() == originalID
                    completed(contrastOK && mayRestoreFocus &&
                        restoreStatus == .success &&
                        finalPreserved && originalFocusRestored,
                        "contrastOK=\(contrastOK) " +
                        "originalFocusRestored=\(originalFocusRestored) " +
                        "restoreAXSuccess=\(restoreStatus == .success) " +
                        "originalsPreserved=\(finalPreserved) " + detail)
                }
            }
        }
    }

    // One-shot isolated-window AXRaise/restore preflight. Opt-in only.
    // The owner's focused native window is never closed, minimized or navigated.
    // Do not run while a different application is foreground.
    func probeIsolatedFocusPreflight(
        expectedID: String, expectedSnapshot: String, expectedPID: pid_t,
        completed: @escaping (Bool, String) -> Void
    ) {
        guard !busy, AXIsProcessTrusted(),
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == "com.openai.codex"
              }), app.processIdentifier == expectedPID,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedPID else {
            completed(false, "focus-preflight-app-or-AX-unavailable"); return
        }
        var expected: [String: Bool] = [:]
        for entry in expectedSnapshot.split(separator: ",") {
            let fields = entry.split(separator: ":")
            guard fields.count == 2,
                  (fields[1] == "0" || fields[1] == "1"),
                  expected[String(fields[0])] == nil else {
                completed(false, "focus-preflight-invalid-baseline"); return
            }
            expected[String(fields[0])] = fields[1] == "1"
        }
        guard expected.count == 8, expected[expectedID] == false,
              expected.values.filter({ $0 }).count == 3 else {
            completed(false, "focus-preflight-unexpected-baseline"); return
        }
        let root = AXUIElementCreateApplication(expectedPID)
        AXUIElementSetMessagingTimeout(root, 0.35)
        func snapshot() -> ([String: Bool]?, [AXUIElement]) {
            let windows = winList(root)
            guard windows.count == 8 else { return (nil, windows) }
            var actual: [String: Bool] = [:]
            for window in windows {
                let id = String(CFHash(window))
                guard actual[id] == nil,
                      str(window, kAXRoleAttribute) == "AXWindow",
                      let minimized = (read(window, kAXMinimizedAttribute)
                          as? NSNumber)?.boolValue else {
                    return (nil, windows)
                }
                actual[id] = minimized
            }
            return (actual, windows)
        }
        func focusedID() -> String? {
            guard let raw = read(root, kAXFocusedWindowAttribute),
                  CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
            return String(CFHash(raw as! AXUIElement))
        }
        let (before, windows) = snapshot()
        guard before == expected,
              let target = windows.first(where: {
                  String(CFHash($0)) == expectedID
              }), title(target) == "ChatGPT",
              let originalID = focusedID(), originalID != expectedID,
              let original = windows.first(where: {
                  String(CFHash($0)) == originalID
              }), expected[originalID] == false else {
            completed(false, "focus-preflight-target-or-owner-focus-changed"); return
        }
        // Raise ONLY the known isolated generic window. Restore only the
        // original focused window, and only if this preflight still owns focus.
        busy = true
        let raiseStatus = AXUIElementPerformAction(
            target, kAXRaiseAction as CFString
        )
        guard raiseStatus == .success else {
            busy = false
            completed(false, "focus-preflight-isolated-raise-failed status=\(raiseStatus.rawValue)")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            let targetFocused = focusedID() == expectedID
            let preserved = snapshot().0 == expected
            let stillFrontmost =
                NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedPID
            // Never steal focus back if the owner moved to another window/app.
            let canRestore = targetFocused && preserved && stillFrontmost
            let restoreStatus: AXError? = canRestore
                ? AXUIElementPerformAction(original, kAXRaiseAction as CFString)
                : nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                let finalPreserved = snapshot().0 == expected
                let originalFocused = focusedID() == originalID
                self.busy = false
                completed(canRestore && restoreStatus == .success &&
                    finalPreserved && originalFocused,
                    "baseline=true count=8 minimized=3 " +
                    "isolatedFocused=\(targetFocused) " +
                    "originalFocusRestored=\(originalFocused) " +
                    "restoreAttempted=\(canRestore) " +
                    "restoreAXSuccess=\(restoreStatus == .success) " +
                    "originalsPreserved=\(finalPreserved)")
            }
        }
    }
}
