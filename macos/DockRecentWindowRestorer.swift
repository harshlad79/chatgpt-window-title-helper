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
        -> (buttons: [AXUIElement], inputs: Int, dialogs: Int, limited: Bool) {
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
        while index < queue.count && index < 800 &&
            ProcessInfo.processInfo.systemUptime - started < 3.0 {
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
            queue.append(contentsOf: next.prefix(48))
        }
        return (buttons, inputs, dialogs,
            index < queue.count || index >= 800)
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
                  let focused = self.read(root, kAXFocusedWindowAttribute)
                    as? AXUIElement else { return false }
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
}
