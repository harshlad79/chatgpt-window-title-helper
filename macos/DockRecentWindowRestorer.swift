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
        // Do not act on the preflight item after closing/reopening menus.
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.6)
        let original = winList(root)
        let originalIDs = Set(original.map { String(CFHash($0)) })
        guard let newWindowMenu = fileNewWindow(root) else {
            completed(false, "파일 > 새 창 메뉴를 찾지 못함")
            return
        }
        busy = true
        // Activating ChatGPT allows its native menu to replace Dock's menu.
        _ = app.activate()
        guard press(newWindowMenu) else {
            busy = false
            completed(false, "새 창 메뉴 실행 실패")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            let after = self.winList(root)
            let created = after.filter {
                !originalIDs.contains(String(CFHash($0)))
            }
            guard after.count == original.count + 1, created.count == 1,
                  self.title(created[0]) == "ChatGPT" else {
                self.busy = false
                completed(false, "새 빈 창 생성 확인 실패; 기존 창 유지")
                return
            }
            // The Dock menu must be read again: prior AX handles can be stale.
            guard let choices = self.dockRecentMatches(title),
                  choices.count == 1, self.press(choices[0]) else {
                self.busy = false
                completed(false, "새 창은 열렸지만 Recent 항목 실행 실패")
                return
            }
            // The app can report an empty/generic AXWebArea for several
            // seconds after the native Dock action has already succeeded.
            // Poll without blocking the main run loop; never create another
            // window while a prior restore is awaiting verification.
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
                    return result.contains { String(CFHash($0)) == key }
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
                    // No conversation titles or messages in diagnostic reasons.
                    completed(false, "복원 확인 시간 초과 " +
                        "windows=\(result.count)/\(expectedCount) " +
                        "targetMatched=\(matched) originalsRetained=\(retained)")
                }
            }
            checkResult()
        }
    }
}
