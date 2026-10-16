import AppKit
import ApplicationServices

// A self-owned panel beside Dock's existing ChatGPT context menu. It never
// changes Dock/ChatGPT titles and never assumes a correlation between the
// ambiguous, identically named native menu items and AXWindows order.
final class DockMenuSidecar: NSObject {
    struct Entry {
        let id: String
        let title: String
        let axWindow: AXUIElement
    }

    private var entries: [Entry] = []
    private var recoverableTitles: [String] = []
    private var dockPID: pid_t = 0
    private var dockAX: AXUIElement?
    private var chatGPTDockItem: AXUIElement?
    private var timer: Timer?
    private var panel: NSPanel?
    private var lastIdentity = ""
    private var visible = false
    private var lastDiscovery = Date.distantPast
    private let width: CGFloat = 320
    private let maxRows = 10

    var onSelect: ((Entry) -> Void)?
    var onRestore: ((String) -> Void)?
    var onRestoreAll: (() -> Void)?

    func start() {
        guard timer == nil else { return }
        let newTimer = Timer(timeInterval: 0.3, repeats: true) {
            [weak self] _ in self?.tick()
        }
        timer = newTimer
        RunLoop.main.add(newTimer, forMode: .common)
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        hide()
        entries.removeAll()
        recoverableTitles.removeAll()
    }

    func update(_ next: [Entry]) {
        // Retain AX window identity to ensure a sidecar row raises the actual
        // selected ChatGPT window, regardless of Dock's menu item order.
        entries = Array(next.prefix(maxRows))
        if visible { tick() }
    }

    func updateHistory(_ titles: [String]) {
        let open = Set(entries.map { $0.title })
        recoverableTitles = Array(titles.filter { !open.contains($0) }.prefix(8))
        if visible { tick() }
    }

    private func get(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, attribute as CFString, &value
        ) == .success else { return nil }
        return value
    }

    private func children(_ element: AXUIElement) -> [AXUIElement] {
        (get(element, kAXChildrenAttribute) as? [AXUIElement]) ??
            (get(element, kAXVisibleChildrenAttribute) as? [AXUIElement]) ?? []
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String {
        get(element, attribute) as? String ?? ""
    }

    private func rectangle(_ element: AXUIElement) -> CGRect? {
        guard let p = get(element, kAXPositionAttribute),
              let s = get(element, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(),
              CFGetTypeID(s) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &origin),
              AXValueGetValue(s as! AXValue, .cgSize, &size),
              size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private func findDockItem() -> AXUIElement? {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.dock"
        }) else { return nil }
        if dockPID != app.processIdentifier {
            dockPID = app.processIdentifier
            dockAX = AXUIElementCreateApplication(dockPID)
            if let dockAX {
                AXUIElementSetMessagingTimeout(dockAX, 0.25)
            }
            chatGPTDockItem = nil
        }
        guard let dockAX else { return nil }
        let lists = children(dockAX)
        let candidates = lists.flatMap { children($0) }.filter {
            string($0, kAXRoleAttribute) == "AXDockItem" &&
                string($0, kAXTitleAttribute) == "ChatGPT" &&
                string($0, kAXSubroleAttribute) == "AXApplicationDockItem"
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    private func dockMenu() -> CGRect? {
        let now = Date()
        if chatGPTDockItem == nil ||
           now.timeIntervalSince(lastDiscovery) >= 5.0 {
            lastDiscovery = now
            chatGPTDockItem = findDockItem()
        }
        guard let icon = chatGPTDockItem else { return nil }
        for candidate in children(icon) {
            guard string(candidate, kAXRoleAttribute) == "AXMenu",
                  let bounds = rectangle(candidate) else { continue }
            // Only react to the actual ChatGPT application menu. Do not
            // overlay when Dock is merely hovered or another menu is open.
            let menuItems = children(candidate)
            guard menuItems.contains(where: {
                string($0, kAXRoleAttribute) == "AXMenuItem" &&
                string($0, kAXTitleAttribute) == "ChatGPT"
            }) else { continue }
            return bounds
        }
        return nil
    }

    private func panelFrame(menu: CGRect, height: CGFloat) -> NSRect? {
        guard let primary = NSScreen.screens.first else { return nil }
        // Dock AX coordinates use the primary screen's top-left origin.
        let menuLeft = menu.minX
        let menuTop = primary.frame.maxY - menu.minY
        let menuCenter = NSPoint(x: menu.midX, y: menuTop - menu.height / 2)
        let screen = NSScreen.screens.first(where: {
            $0.frame.contains(menuCenter)
        }) ?? primary
        let available = screen.visibleFrame
        let gap: CGFloat = 10
        let x: CGFloat
        if menuLeft - available.minX >= width + gap {
            x = menuLeft - width - gap
        } else if available.maxX - menu.maxX >= width + gap {
            x = menu.maxX + gap
        } else { return nil } // Fail closed rather than overlap Dock's menu.
        let y = max(available.minY,
                    min(available.maxY - height, menuTop - height))
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func tick() {
        guard AXIsProcessTrusted(), let menu = dockMenu(),
              !(entries.isEmpty && recoverableTitles.isEmpty) else {
            hide()
            return
        }
        let historyCount = recoverableTitles.count
        let height: CGFloat = 42 + CGFloat(entries.count) * 34 + 8 +
            (historyCount == 0 ? 0 : 72 + CGFloat(historyCount) * 34)
        guard let frame = panelFrame(menu: menu, height: height) else {
            hide()
            return
        }
        let signature = (entries.map { $0.id + ":" + $0.title } +
            recoverableTitles.map { "history:" + $0 })
            .joined(separator: "\u{1f}")
        if !visible || lastIdentity != signature {
            render(height: height)
            lastIdentity = signature
        }
        panel?.setFrame(frame, display: true)
        if !visible {
            panel?.orderFrontRegardless()
            visible = true
            TitleHelperDiagnostics.shared.record(
                "dock-sidecar-visible rows=\(entries.count) history=\(recoverableTitles.count)")
        }
    }

    private func render(height: CGFloat) {
        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false
            )
            p.isOpaque = false
            p.backgroundColor = .clear
            p.level = .screenSaver
            p.isFloatingPanel = true
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            p.hasShadow = true
            p.animationBehavior = .none
            p.collectionBehavior = [
                .canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle
            ]
            panel = p
        }
        guard let p = panel else { return }
        let container = NSView(frame: NSRect(
            x: 0, y: 0, width: width, height: height))
        container.wantsLayer = true
        container.layer?.backgroundColor =
            NSColor.windowBackgroundColor.withAlphaComponent(0.97).cgColor
        container.layer?.cornerRadius = 9
        container.layer?.borderColor = NSColor.separatorColor.cgColor
        container.layer?.borderWidth = 0.5

        let heading = NSTextField(labelWithString: "ChatGPT 대화 창")
        heading.font = NSFont.boldSystemFont(ofSize: 12)
        heading.textColor = .secondaryLabelColor
        heading.frame = NSRect(x: 12, y: height - 31,
                               width: width - 24, height: 20)
        container.addSubview(heading)

        for (i, item) in entries.enumerated() {
            let button = DockConversationButton(
                title: item.title, target: self,
                action: #selector(selectWindow(_:)))
            button.windowID = item.id
            button.bezelStyle = .rounded
            button.alignment = .left
            button.lineBreakMode = .byTruncatingMiddle
            button.font = NSFont.systemFont(ofSize: 12)
            button.toolTip = item.title
            button.frame = NSRect(x: 10,
                                  y: height - 39 - CGFloat(i + 1) * 34,
                                  width: width - 20, height: 29)
            container.addSubview(button)
        }
        if !recoverableTitles.isEmpty {
            let top = height - 42 - CGFloat(entries.count) * 34
            let separator = NSBox(frame: NSRect(x: 10, y: top - 6,
                                                  width: width - 20, height: 1))
            separator.boxType = .separator
            container.addSubview(separator)

            let section = NSTextField(labelWithString: "이전에 열었던 대화")
            section.font = NSFont.boldSystemFont(ofSize: 11)
            section.textColor = .secondaryLabelColor
            section.frame = NSRect(x: 12, y: top - 26,
                                   width: width - 24, height: 17)
            container.addSubview(section)

            for (idx, title) in recoverableTitles.enumerated() {
                let button = DockConversationButton(
                    title: "↗ " + title, target: self,
                    action: #selector(restoreWindow(_:)))
                button.windowID = title
                button.bezelStyle = .rounded
                button.alignment = .left
                button.lineBreakMode = .byTruncatingMiddle
                button.font = NSFont.systemFont(ofSize: 12)
                button.toolTip = "새 창으로 복원: " + title
                button.frame = NSRect(
                    x: 10,
                    y: top - 29 - CGFloat(idx + 1) * 34,
                    width: width - 20, height: 29)
                container.addSubview(button)
            }
            let allButton = NSButton(
                title: "마지막 창 모두 복원 (\(recoverableTitles.count))",
                target: self, action: #selector(restoreAllWindows(_:)))
            allButton.bezelStyle = .rounded
            allButton.font = NSFont.boldSystemFont(ofSize: 12)
            allButton.frame = NSRect(x: 10, y: 10,
                                      width: width - 20, height: 30)
            container.addSubview(allButton)
        }
        p.contentView = container
    }

    @objc private func restoreAllWindows(_ sender: NSButton) {
        guard !recoverableTitles.isEmpty else { return }
        hide()
        onRestoreAll?()
    }

    @objc private func restoreWindow(_ sender: DockConversationButton) {
        guard recoverableTitles.contains(sender.windowID) else { return }
        let selected = sender.windowID
        hide()
        onRestore?(selected)
    }

    @objc private func selectWindow(_ sender: DockConversationButton) {
        guard let entry = entries.first(where: {
            $0.id == sender.windowID
        }) else { return }
        hide()
        onSelect?(entry)
    }

    private func hide() {
        if visible {
            panel?.orderOut(nil)
            visible = false
            lastIdentity = ""
            TitleHelperDiagnostics.shared.record("dock-sidecar-hidden")
        }
    }
}

private final class DockConversationButton: NSButton {
    var windowID = ""
}
