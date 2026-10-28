import Cocoa
import ApplicationServices
import QuartzCore
import Foundation
import Darwin

// ============================================================
// Configuration
// ============================================================

private let targetBundleID = "com.openai.codex"

private let overlayHeight: CGFloat = 28
private let overlayGap: CGFloat = 3

private let minimumOverlayWidth: CGFloat = 180
private let maximumOverlayWidth: CGFloat = 520

// Windows parity: small discovery tick, event-driven title reads.
private let refreshInterval: TimeInterval = 2.0
private let nativeSyncInterval: TimeInterval = 1.0

private let prefOverlayEnabled = "overlayEnabled"
private let prefNativeTitleEnabled = "nativeTitleEnabled"

private let inspectorListURL =
    URL(string: "http://127.0.0.1:9229/json/list")!


// ============================================================
// AX Helpers
// ============================================================

func axGet(
    _ element: AXUIElement,
    _ attribute: String
) -> CFTypeRef? {

    var value: CFTypeRef?

    let result = AXUIElementCopyAttributeValue(
        element,
        attribute as CFString,
        &value
    )

    return result == .success ? value : nil
}


func axString(
    _ element: AXUIElement,
    _ attribute: String
) -> String {

    axGet(element, attribute) as? String ?? ""
}


func axBool(
    _ element: AXUIElement,
    _ attribute: String
) -> Bool? {

    (axGet(element, attribute) as? NSNumber)?.boolValue
}


func axChildren(
    _ element: AXUIElement
) -> [AXUIElement] {

    axGet(
        element,
        kAXChildrenAttribute
    ) as? [AXUIElement] ?? []
}


func axPoint(
    _ element: AXUIElement
) -> CGPoint? {

    guard let value =
            axGet(element, kAXPositionAttribute),
          CFGetTypeID(value) == AXValueGetTypeID()
    else {
        return nil
    }

    let axValue =
        unsafeBitCast(
            value,
            to: AXValue.self
        )

    var point = CGPoint.zero

    guard AXValueGetValue(
        axValue,
        .cgPoint,
        &point
    ) else {
        return nil
    }

    return point
}


func axSize(
    _ element: AXUIElement
) -> CGSize? {

    guard let value =
            axGet(element, kAXSizeAttribute),
          CFGetTypeID(value) == AXValueGetTypeID()
    else {
        return nil
    }

    let axValue =
        unsafeBitCast(
            value,
            to: AXValue.self
        )

    var size = CGSize.zero

    guard AXValueGetValue(
        axValue,
        .cgSize,
        &size
    ) else {
        return nil
    }

    return size
}


// ============================================================
// Find Chromium WebArea
// ============================================================

// The v3-v7 TitleProbe proved AXWebArea.Title is the conversation title.
// Walk by role (NOT text length), avoid cycles and fall back to the visible
// AX subtree when Chromium omits ordinary AXChildren.
func findWebArea(_ root: AXUIElement) -> AXUIElement? {
    var queue = [root]
    var visited: Set<String> = []
    var index = 0
    while index < queue.count && index < 1600 {
        let e = queue[index]
        index += 1
        let id = String(CFHash(e))
        guard visited.insert(id).inserted else { continue }
        if axString(e, kAXRoleAttribute) == "AXWebArea" {
            return e
        }
        let ordinary = axChildren(e)
        let children: [AXUIElement]
        if !ordinary.isEmpty {
            children = ordinary
        } else {
            children = (axGet(e, kAXVisibleChildrenAttribute)
                as? [AXUIElement]) ??
                ((axGet(e, kAXContentsAttribute) as? [AXUIElement]) ?? [])
        }
        for child in children.prefix(150) where queue.count < 1600 {
            queue.append(child)
        }
    }
    return nil
}

// Diagnostic only: bounded, read-only AXWebArea discovery for minimized windows.
// This does not inspect AXValue/message text or change any window state.
private func boundedMinimizedWebAreaTitle(
    _ window: AXUIElement
) -> (found: Bool, title: String, limited: Bool) {
    let started = ProcessInfo.processInfo.systemUptime
    var queue = [window]
    var seen: Set<String> = []
    var index = 0
    while index < queue.count && index < 48 &&
          ProcessInfo.processInfo.systemUptime - started < 2.5 {
        let element = queue[index]
        index += 1
        let id = String(CFHash(element))
        guard seen.insert(id).inserted else { continue }
        _ = AXUIElementSetMessagingTimeout(element, 0.2)
        if axString(element, kAXRoleAttribute) == "AXWebArea" {
            let title = axString(element, kAXTitleAttribute)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (true, title, false)
        }
        let ordinary = axChildren(element)
        let children: [AXUIElement]
        if !ordinary.isEmpty {
            children = ordinary
        } else {
            children = (axGet(element, kAXVisibleChildrenAttribute)
                as? [AXUIElement]) ??
                ((axGet(element, kAXContentsAttribute) as? [AXUIElement]) ?? [])
        }
        for child in children.prefix(12) where queue.count < 48 {
            queue.append(child)
        }
    }
    return (false, "", index < queue.count || index >= 48)
}

// Metadata-only probe: read documented AXWindow attributes without logging
// their contents. Some hosts return CFURL rather than CFString for AXURL.
private func axWindowMetadataText(_ window: AXUIElement, _ key: String) -> String {
    guard let raw = axGet(window, key) else { return "" }
    if let value = raw as? String {
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let value = raw as? URL { return value.absoluteString }
    return ""
}

// Read-only, time-bounded census of user-facing share/copy-link controls in an
// ALREADY VISIBLE conversation AXWebArea. No AXPress, AXValue or raw labels.
private func boundedShareControlCensus(
    _ root: AXUIElement
) -> (visited: Int, share: Int, copyLink: Int,
      shareEnabled: Int, sharePressable: Int, shareActionable: Int,
      shareMenuRole: Int, copyLinkEnabled: Int, copyLinkPressable: Int,
      openOnChatGPTControls: Int, openOnChatGPTConversationURLs: Int,
      elapsedMs: Int, remaining: Int, limited: Bool) {
    let started = ProcessInfo.processInfo.systemUptime
    var queue = [root]
    var seen: Set<String> = []
    var index = 0
    var share = 0
    var copyLink = 0
    var shareEnabled = 0
    var sharePressable = 0
    var shareActionable = 0
    var shareMenuRole = 0
    var copyLinkEnabled = 0
    var copyLinkPressable = 0
    var openOnChatGPTControls = 0
    var openOnChatGPTConversationURLs = 0
    while index < queue.count &&
          ProcessInfo.processInfo.systemUptime - started < 2.0 {
        let element = queue[index]
        index += 1
        let id = String(CFHash(element))
        guard seen.insert(id).inserted else { continue }
        _ = AXUIElementSetMessagingTimeout(element, 0.15)
        let role = axString(element, kAXRoleAttribute)
        // The installed ChatGPT app offers a non-public-share navigation
        // item "Open on chatgpt.com" for a known conversation ID. Inspect
        // only link/menu metadata; never press it or log the URL/ID.
        if role == "AXLink" || role == "AXMenuItem" {
            let label = [
                axString(element, kAXTitleAttribute),
                axString(element, kAXDescriptionAttribute),
                axString(element, kAXHelpAttribute)
            ].joined(separator: " ").localizedLowercase
            if label.contains("open on chatgpt.com") ||
               label.contains("chatgpt.com에서 열기") {
                openOnChatGPTControls += 1
                let value = axWindowMetadataText(element, "AXURL")
                if let parsed = URLComponents(string: value),
                   parsed.scheme?.lowercased() == "https",
                   parsed.host?.lowercased() == "chatgpt.com",
                   parsed.path.hasPrefix("/c/") {
                    openOnChatGPTConversationURLs += 1
                }
            }
        }
        if role == "AXButton" || role == "AXMenuButton" ||
           role == "AXPopUpButton" {
            // Inspect only button metadata, never conversation message text.
            let labels = [
                axString(element, kAXTitleAttribute),
                axString(element, kAXDescriptionAttribute),
                axString(element, kAXHelpAttribute)
            ].joined(separator: " ").localizedLowercase
            let isShare = labels.contains("share") || labels.contains("공유")
            let isCopyLink = labels.contains("copy link") ||
                labels.contains("링크 복사") || labels.contains("링크복사")
            if isShare || isCopyLink {
                // Read-only AX action metadata: do NOT invoke AXPress.
                var rawActions: CFArray?
                let hasPress = AXUIElementCopyActionNames(element, &rawActions) == .success &&
                    ((rawActions as? [String]) ?? []).contains(kAXPressAction as String)
                let enabled = axBool(element, kAXEnabledAttribute) == true
                if isShare {
                    share += 1
                    if enabled { shareEnabled += 1 }
                    if hasPress { sharePressable += 1 }
                    if enabled && hasPress { shareActionable += 1 }
                    if role != "AXButton" { shareMenuRole += 1 }
                }
                if isCopyLink {
                    copyLink += 1
                    if enabled { copyLinkEnabled += 1 }
                    if hasPress { copyLinkPressable += 1 }
                }
            }
        }
        let ordinary = axChildren(element)
        let children: [AXUIElement]
        if !ordinary.isEmpty {
            children = ordinary
        } else {
            children = (axGet(element, kAXVisibleChildrenAttribute)
                as? [AXUIElement]) ??
                ((axGet(element, kAXContentsAttribute)
                    as? [AXUIElement]) ?? [])
        }
        queue.append(contentsOf: children)
    }
    return (seen.count, share, copyLink,
            shareEnabled, sharePressable, shareActionable,
            shareMenuRole, copyLinkEnabled, copyLinkPressable,
            openOnChatGPTControls, openOnChatGPTConversationURLs,
            Int((ProcessInfo.processInfo.systemUptime - started) * 1000),
            queue.count - index, index < queue.count)
}

// Read-only observation can safely subscribe to multiple title buttons.
// The current ChatGPT AX tree exposes two AXButtons with the conversation
// title. Uniqueness is essential for *pressing* buttons, but would incorrectly
// disable event observation. Keep the search bounded to a few exact matches.
func findConversationTitleButtons(_ webArea: AXUIElement,
                                  title: String) -> [AXUIElement] {
    var queue = [webArea]
    var seen: Set<String> = []
    var matches: [AXUIElement] = []
    var index = 0
    while index < queue.count && index < 1600 {
        let e = queue[index]
        index += 1
        let id = String(CFHash(e))
        guard seen.insert(id).inserted else { continue }
        if axString(e, kAXRoleAttribute) == "AXButton" &&
            axString(e, kAXTitleAttribute) == title {
            matches.append(e)
            if matches.count >= 4 { break }
        }
        // Try all known AX hierarchy paths. Chromium often omits a title
        // button from conventional AXChildren while exposing it elsewhere.
        for source in [kAXChildrenAttribute, kAXVisibleChildrenAttribute,
                       kAXContentsAttribute, "AXChildrenInNavigationOrder"] {
            let children = (axGet(e, source) as? [AXUIElement]) ?? []
            for child in children.prefix(150) where queue.count < 1600 {
                queue.append(child)
            }
        }
    }
    return matches
}


// ============================================================
// Conversation Window
// ============================================================

struct ConversationWindow {

    let title: String

    // AX / Electron coordinate system:
    // top-left global desktop coordinates
    let x: CGFloat
    let y: CGFloat

    let width: CGFloat
    let height: CGFloat

    let isMain: Bool
}


// ============================================================
// Screen mapping
// ============================================================

struct ScreenMapping {

    let screen: NSScreen
    let displayID: CGDirectDisplayID
    let cgBounds: CGRect
}


func getScreenMappings()
-> [ScreenMapping] {

    var result: [ScreenMapping] = []

    let key =
        NSDeviceDescriptionKey(
            "NSScreenNumber"
        )

    for screen in NSScreen.screens {

        guard let number =
                screen.deviceDescription[key]
                as? NSNumber
        else {
            continue
        }

        let displayID =
            CGDirectDisplayID(
                number.uint32Value
            )

        result.append(
            ScreenMapping(
                screen: screen,
                displayID: displayID,
                cgBounds:
                    CGDisplayBounds(displayID)
            )
        )
    }

    return result
}


// ============================================================
// Overlay Panel
// ============================================================

final class TitleOverlayPanel: NSPanel {

    private let label =
        NSTextField(
            labelWithString: ""
        )


    init() {

        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: 400,
                height: overlayHeight
            ),
            styleMask: [
                .borderless,
                .nonactivatingPanel
            ],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear

        // 실제 표시가 잘 됐던 기존 값 유지.
        level = .screenSaver

        isFloatingPanel = true
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false

        hasShadow = true
        animationBehavior = .none

        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]

        guard let contentView else {
            return
        }

        let background =
            NSView(
                frame: contentView.bounds
            )

        background.autoresizingMask = [
            .width,
            .height
        ]

        background.wantsLayer = true

        background.layer?.backgroundColor =
            NSColor.windowBackgroundColor
                .withAlphaComponent(0.96)
                .cgColor

        background.layer?.cornerRadius = 7
        background.layer?.borderWidth = 0.5

        background.layer?.borderColor =
            NSColor.separatorColor.cgColor

        contentView.addSubview(background)

        label.frame =
            NSRect(
                x: 10,
                y: 3,
                width:
                    contentView.bounds.width - 20,
                height:
                    contentView.bounds.height - 6
            )

        label.autoresizingMask = [
            .width,
            .height
        ]

        label.alignment = .center

        label.font =
            NSFont.systemFont(
                ofSize: 13,
                weight: .semibold
            )

        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1

        background.addSubview(label)
    }


    func setTitle(
        _ title: String
    ) {

        label.stringValue = title
    }
}


// ============================================================
// Inspector Target
// ============================================================

struct InspectorTarget: Decodable {

    let description: String?
    let title: String?
    let type: String?
    let url: String?
    let webSocketDebuggerUrl: String?
}


// ============================================================
// Native Title Sync
// ============================================================

final class NativeTitleSync {

    private var signalSentPID: pid_t = 0
    private var requestInFlight = false

    private let session: URLSession


    init() {

        let config =
            URLSessionConfiguration.ephemeral

        config.timeoutIntervalForRequest = 0.5
        config.timeoutIntervalForResource = 1.0

        session =
            URLSession(
                configuration: config
            )
    }


    func resetForNewPID() {

        signalSentPID = 0
        requestInFlight = false
    }


    // --------------------------------------------------------
    // Sync titles
    // --------------------------------------------------------

    func sync(
        pid: pid_t,
        windows: [ConversationWindow],
        completion:
            @escaping (String) -> Void
    ) {

        guard !requestInFlight else {
            return
        }

        guard !windows.isEmpty else {

            completion(
                "Dock: 제목 대상 없음"
            )

            return
        }

        requestInFlight = true

        getInspectorTarget(
            pid: pid
        ) { [weak self] target in

            guard let self else {
                return
            }

            guard let target,
                  let wsText =
                    target.webSocketDebuggerUrl,
                  let wsURL =
                    URL(string: wsText)
            else {

                self.requestInFlight = false

                completion(
                    "Dock: inspector 시작 중"
                )

                return
            }

            let expression =
                self.makeSyncExpression(
                    windows
                )

            self.evaluate(
                wsURL: wsURL,
                expression: expression
            ) { result in

                self.requestInFlight = false

                switch result {

                case .success(let value):

                    if let data =
                        value.data(
                            using: .utf8
                        ),
                       let object =
                        try? JSONSerialization
                            .jsonObject(
                                with: data
                            ) as? [String: Any] {

                        if let updated =
                            object["updated"]
                            as? Int {

                            completion(
                                "Dock: \(updated)개 동기화"
                            )

                            return
                        }

                        if let error =
                            object["error"]
                            as? String {

                            completion(
                                "Dock 오류: \(error)"
                            )

                            return
                        }
                    }

                    completion(
                        "Dock: 동기화 완료"
                    )


                case .failure(let error):

                    completion(
                        "Dock 연결 오류: \(error.localizedDescription)"
                    )
                }
            }
        }
    }


    // --------------------------------------------------------
    // Restore original native titles
    // --------------------------------------------------------

    func restore(
        pid: pid_t,
        completion:
            @escaping (String) -> Void
    ) {

        guard !requestInFlight else {

            completion(
                "Dock: 작업 중"
            )

            return
        }

        requestInFlight = true

        getInspectorTarget(
            pid: pid
        ) { [weak self] target in

            guard let self else {
                return
            }

            guard let target,
                  let wsText =
                    target.webSocketDebuggerUrl,
                  let wsURL =
                    URL(string: wsText)
            else {

                self.requestInFlight = false

                completion(
                    "Dock: inspector 없음"
                )

                return
            }

            let expression = #"""
(() => {
    try {
        const electron =
            process.mainModule.require("electron");

        const {
            BrowserWindow,
            app
        } = electron;

        if (app.getName() !== "ChatGPT") {
            return JSON.stringify({
                error: "not ChatGPT main process"
            });
        }

        const store =
            globalThis.__chatgptTitleHelperOriginalTitles;

        if (!store) {
            return JSON.stringify({
                restored: 0
            });
        }

        let restored = 0;

        for (const [id, originalTitle] of store) {

            const w =
                BrowserWindow.fromId(id);

            if (!w || w.isDestroyed()) {
                continue;
            }

            w.setTitle(originalTitle);
            restored++;
        }

        store.clear();

        return JSON.stringify({
            restored
        });

    } catch (e) {

        return JSON.stringify({
            error: String(e)
        });
    }
})()
"""#

            self.evaluate(
                wsURL: wsURL,
                expression: expression
            ) { result in

                self.requestInFlight = false

                switch result {

                case .success(let value):

                    var restored = 0

                    if let data =
                        value.data(
                            using: .utf8
                        ),
                       let object =
                        try? JSONSerialization
                            .jsonObject(
                                with: data
                            ) as? [String: Any] {

                        restored =
                            object["restored"]
                            as? Int ?? 0
                    }

                    completion(
                        "Dock: \(restored)개 복원"
                    )


                case .failure:

                    completion(
                        "Dock: 복원 실패"
                    )
                }
            }
        }
    }


    // ========================================================
    // Inspector discovery
    // ========================================================

    private func getInspectorTarget(
        pid: pid_t,
        completion:
            @escaping (InspectorTarget?) -> Void
    ) {

        var request =
            URLRequest(
                url: inspectorListURL
            )

        request.cachePolicy =
            .reloadIgnoringLocalCacheData

        request.timeoutInterval =
            0.35


        session.dataTask(
            with: request
        ) {
            [weak self]
            data,
            response,
            error
            in

            guard let self else {
                return
            }


            // Inspector already open
            if let data,
               let targets =
                try? JSONDecoder()
                    .decode(
                        [InspectorTarget].self,
                        from: data
                    ) {

                if let target =
                    targets.first(
                        where: {
                            $0.type == "node" &&
                            $0.webSocketDebuggerUrl != nil
                        }
                    ) {

                    completion(target)
                    return
                }
            }


            // Not open:
            // Dock에서 평소처럼 실행한 ChatGPT에도
            // SIGUSR1으로 inspector 활성화.
            if self.signalSentPID != pid {

                self.signalSentPID = pid

                _ = Darwin.kill(
                    pid,
                    SIGUSR1
                )
            }

            completion(nil)

        }.resume()
    }


    // ========================================================
    // Build BrowserWindow.setTitle expression
    // ========================================================

    private func makeSyncExpression(
        _ windows: [ConversationWindow]
    ) -> String {

        let payload:
            [[String: Any]] =
            windows.map {

                [
                    "title": $0.title,
                    "x": Double($0.x),
                    "y": Double($0.y),
                    "width": Double($0.width),
                    "height": Double($0.height)
                ]
            }


        guard let data =
                try? JSONSerialization.data(
                    withJSONObject: payload
                ),
              let json =
                String(
                    data: data,
                    encoding: .utf8
                )
        else {

            return
                #"JSON.stringify({"error":"payload encode failed"})"#
        }


        return """
(() => {
    try {

        const electron =
            process.mainModule.require("electron");

        const {
            BrowserWindow,
            app
        } = electron;


        if (app.getName() !== "ChatGPT") {

            return JSON.stringify({
                error:
                    "not ChatGPT main process"
            });
        }


        const wanted = \(json);


        if (
            !globalThis
                .__chatgptTitleHelperOriginalTitles
        ) {

            globalThis
                .__chatgptTitleHelperOriginalTitles =
                new Map();
        }


        const originals =
            globalThis
                .__chatgptTitleHelperOriginalTitles;


        const browserWindows =
            BrowserWindow
                .getAllWindows()
                .filter(
                    w =>
                        !w.isDestroyed() &&
                        w.isVisible()
                );


        const used =
            new Set();


        const changes = [];


        for (const item of wanted) {

            let best = null;
            let bestScore = Infinity;


            for (const w of browserWindows) {

                if (used.has(w.id)) {
                    continue;
                }


                const b =
                    w.getBounds();


                const dx =
                    Math.abs(
                        b.x - item.x
                    );

                const dy =
                    Math.abs(
                        b.y - item.y
                    );

                const dw =
                    Math.abs(
                        b.width - item.width
                    );

                const dh =
                    Math.abs(
                        b.height - item.height
                    );


                // 실제 관찰:
                // AX ↔ Electron bounds는
                // 몇 px ~ 수십 px 정도 차이가 날 수 있음.
                if (
                    dx > 120 ||
                    dy > 120 ||
                    dw > 80 ||
                    dh > 80
                ) {

                    continue;
                }


                const score =
                    dx +
                    dy +
                    dw * 2 +
                    dh * 2;


                if (score < bestScore) {

                    bestScore = score;
                    best = w;
                }
            }


            if (!best) {
                continue;
            }


            used.add(best.id);


            if (!originals.has(best.id)) {

                originals.set(
                    best.id,
                    best.getTitle()
                );
            }


            if (
                best.getTitle()
                !== item.title
            ) {

                best.setTitle(
                    item.title
                );
            }


            changes.push({
                id: best.id,
                title: item.title,
                bounds:
                    best.getBounds(),
                score:
                    bestScore
            });
        }


        return JSON.stringify({
            updated: changes.length,
            changes
        });


    } catch (e) {

        return JSON.stringify({
            error: String(e),
            stack: e?.stack
        });
    }
})()
"""
    }


    // ========================================================
    // V8 Inspector Runtime.evaluate
    // ========================================================

    private func evaluate(
        wsURL: URL,
        expression: String,
        completion:
            @escaping (
                Result<String, Error>
            ) -> Void
    ) {

        var request =
            URLRequest(
                url: wsURL
            )

        request.timeoutInterval = 1.0


        let task =
            session.webSocketTask(
                with: request
            )

        task.resume()


        let messageObject:
            [String: Any] = [

                "id": 1,

                "method":
                    "Runtime.evaluate",

                "params": [

                    "expression":
                        expression,

                    "returnByValue":
                        true
                ]
            ]


        guard let data =
                try? JSONSerialization.data(
                    withJSONObject:
                        messageObject
                ),
              let message =
                String(
                    data: data,
                    encoding: .utf8
                )
        else {

            task.cancel(
                with: .goingAway,
                reason: nil
            )

            completion(
                .failure(
                    NSError(
                        domain:
                            "ChatGPTTitleOverlay",
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "CDP message encode failed"
                        ]
                    )
                )
            )

            return
        }


        task.send(
            .string(message)
        ) {
            error in

            if let error {

                task.cancel(
                    with: .goingAway,
                    reason: nil
                )

                completion(
                    .failure(error)
                )

                return
            }


            self.receiveResponse(
                task: task,
                expectedID: 1,
                completion: completion
            )
        }
    }


    private func receiveResponse(
        task: URLSessionWebSocketTask,
        expectedID: Int,
        completion:
            @escaping (
                Result<String, Error>
            ) -> Void
    ) {

        task.receive {
            result in

            switch result {

            case .failure(let error):

                task.cancel(
                    with: .goingAway,
                    reason: nil
                )

                completion(
                    .failure(error)
                )


            case .success(let message):

                let text: String

                switch message {

                case .string(let value):

                    text = value


                case .data(let data):

                    text =
                        String(
                            data: data,
                            encoding: .utf8
                        ) ?? ""
                @unknown default:

                    text = ""
                }


                guard let data =
                        text.data(
                            using: .utf8
                        ),
                      let object =
                        try? JSONSerialization
                            .jsonObject(
                                with: data
                            ) as? [String: Any]
                else {

                    self.receiveResponse(
                        task: task,
                        expectedID:
                            expectedID,
                        completion:
                            completion
                    )

                    return
                }


                // Inspector notifications may arrive
                // before our result.
                guard let id =
                        object["id"] as? Int,
                      id == expectedID
                else {

                    self.receiveResponse(
                        task: task,
                        expectedID:
                            expectedID,
                        completion:
                            completion
                    )

                    return
                }


                if let errorObject =
                    object["error"] {

                    task.cancel(
                        with: .normalClosure,
                        reason: nil
                    )

                    completion(
                        .failure(
                            NSError(
                                domain:
                                    "ChatGPTTitleOverlay",
                                code: 2,
                                userInfo: [
                                    NSLocalizedDescriptionKey:
                                        "\(errorObject)"
                                ]
                            )
                        )
                    )

                    return
                }


                let value =
                    (
                        (
                            object["result"]
                            as? [String: Any]
                        )?["result"]
                        as? [String: Any]
                    )?["value"]
                    as? String
                    ?? ""


                task.cancel(
                    with: .normalClosure,
                    reason: nil
                )


                completion(
                    .success(value)
                )
            }
        }
    }
}


// ============================================================
// Controller
// ============================================================

final class OverlayController:
    NSObject {

    private var targetPID: pid_t = 0
    private var targetAX: AXUIElement?

    private var overlayPanel:
        TitleOverlayPanel?

    private let dockSidecar = DockMenuSidecar()
    private let sessionHistory = WindowSessionHistoryStore()
    private let recentRestorer = DockRecentWindowRestorer()
    private let restoreQueue = WindowSessionRestoreQueue()
    private let restoreProgress = RestoreProgressPanel()
    private var restoreRunID = 0
    private var restorePreflightPending = false
    private var sidecarWindows: [String: AXUIElement] = [:]
    private var sidecarWindowOrder: [String] = []
    private var lastAXWindowCensusSucceeded = false
    // Counts only, emitted on changes; never logs conversation titles.
    private var lastAXCensusLogState: String?
    private var lastAXCensusShape: String?
    private var lastAXCensusCheckedAt = Date.distantPast
    private var minimizedAXProbePID: pid_t = 0
    // One bounded read-only identity census per visible conversation count.
    private var lastVisibleIdentityProbeCount = 0

    private var timer: Timer?

    // TitleProbe-derived event subscriptions + one-window priority queue.
    // The legacy NativeTitleSync implementation below is unchanged.
    private var titleObserver: MacAXTitleObserver?
    private var titleScheduler = TitleWorkScheduler()
    private struct CachedConversation {
        let value: ConversationWindow
        let webArea: AXUIElement
        let buttons: [AXUIElement]
    }
    private var titleCache: [String: CachedConversation] = [:]
    private var pendingEventTick = false
    private var lastFocusedID: String?
    private var pendingAXTitleEvents: Set<String> = []
    private var titleRetryPlan = TitleRevisionRetryPlan()
    private var processingRefresh = false
    private var retryRefresh = false

    private let nativeSync =
        NativeTitleSync()

    private var permissionPromptRequested =
        false


    // --------------------------------------------------------
    // Preferences
    // --------------------------------------------------------

    private var overlayEnabled =
        true

    private var nativeTitleEnabled =
        false


    // --------------------------------------------------------
    // Native sync timing
    // --------------------------------------------------------

    private var lastNativeSync =
        Date.distantPast


    // --------------------------------------------------------
    // Menu
    // --------------------------------------------------------

    private var statusItem:
        NSStatusItem!

    private var overlayToggleItem:
        NSMenuItem!

    private var nativeToggleItem:
        NSMenuItem!

    private var overlayStatusItem:
        NSMenuItem!

    private var nativeStatusItem:
        NSMenuItem!


    // ========================================================
    // Start
    // ========================================================

    func start() {
        TitleHelperDiagnostics.shared.record(
            "helper-start pid=\(ProcessInfo.processInfo.processIdentifier)")
        loadPreferences()
        setupMenu()

        // Poll one Dock AX item only; never alter ChatGPT or Dock menu labels.
        dockSidecar.onSelect = { [weak self] entry in
            guard let self, let app = self.currentChatGPTApp(),
                  app.processIdentifier == self.targetPID else { return }
            _ = app.activate()
            _ = AXUIElementPerformAction(
                entry.axWindow, kAXRaiseAction as CFString)
            TitleHelperDiagnostics.shared.record("dock-sidecar-window-selected")
        }
        dockSidecar.onRestore = { [weak self] title in
            guard let self else { return }
            self.prepareForegroundRestore { [weak self] open in
                guard let self else { return }
                guard !open.contains(title) else {
                    TitleHelperDiagnostics.shared.record(
                        "history-reopen-skipped already-open=true")
                    self.refresh()
                    return
                }
                TitleHelperDiagnostics.shared.record(
                    "history-restore-request title=\(TitleHelperDiagnostics.fingerprint(title))")
                self.recentRestorer.restore(title: title) { [weak self] ok, reason in
                    TitleHelperDiagnostics.shared.record(
                        "history-restore-result ok=\(ok) reason=\(reason)")
                    self?.refresh()
                    if !ok { self?.showRestoreError(reason) }
                }
            }
        }
        restoreProgress.onCancel = { [weak self] in
            self?.restoreQueue.cancel()
            TitleHelperDiagnostics.shared.record("history-bulk-cancel-requested")
        }
        restoreQueue.onResult = { title, success, reason in
            TitleHelperDiagnostics.shared.record(
                "history-bulk-item ok=\(success) " +
                "title=\(TitleHelperDiagnostics.fingerprint(title)) " +
                "reason=\(reason)")
        }
        restoreQueue.onProgress = { [weak self] progress in
            self?.restoreProgress.show(progress)
            TitleHelperDiagnostics.shared.record(
                "history-bulk-progress finished=\(progress.finished) " +
                "total=\(progress.total) failed=\(progress.failed) " +
                "running=\(progress.running) cancelled=\(progress.cancelled)")
        }
        restoreQueue.onComplete = { [weak self] progress in
            guard let self else { return }
            self.refresh()
            self.restoreRunID &+= 1
            let runID = self.restoreRunID
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self, self.restoreRunID == runID,
                      !self.restoreQueue.isRunning else { return }
                self.restoreProgress.hide()
            }
            TitleHelperDiagnostics.shared.record(
                "history-bulk-finished completed=\(progress.finished) " +
                "total=\(progress.total) failed=\(progress.failed) " +
                "cancelled=\(progress.cancelled)")
        }
        dockSidecar.onRestoreAll = { [weak self] in
            guard let self else { return }
            self.prepareForegroundRestore { [weak self] currentlyOpen in
                guard let self else { return }
                // The saved last session is authoritative. Never bulk open
                // the unrelated lifetime history.
                guard let currentPID = self.currentChatGPTPID(),
                      currentPID == self.targetPID else {
                    self.showRestoreError("ChatGPT 프로세스가 변경되었습니다.")
                    return
                }
                let targets = self.sessionHistory.lastSessionTargets(pid: currentPID)
                self.restoreRunID &+= 1
                let started = self.restoreQueue.start(
                    titles: targets, alreadyOpen: currentlyOpen
                ) { [weak self] title, callback in
                    guard let self else {
                        callback(false, "TitleHelper 종료")
                        return
                    }
                    self.recentRestorer.restore(title: title, completed: callback)
                }
                TitleHelperDiagnostics.shared.record(
                    "history-bulk-request accepted=\(started) total=\(targets.count)")
                if !started && !self.restoreQueue.isRunning {
                    self.showRestoreError("복원할 누락된 창이 없습니다.")
                }
            }
        }
        dockSidecar.start()
        requestAccessibilityPermission()

        timer =
            Timer.scheduledTimer(
                withTimeInterval:
                    refreshInterval,
                repeats: true
            ) {
                [weak self] _
                in

                self?.refresh()
            }

        if let timer {

            RunLoop.main.add(
                timer,
                forMode: .common
            )
        }

        refresh()
        // Opt-in smoke test for a single independent generic native window.
        // Never run on ordinary launch or restore; no conversation navigation.
        if ProcessInfo.processInfo.environment["TITLEHELPER_SAFE_BLANK_PROBE"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self else { return }
                self.recentRestorer.probeBlankWindow { success, detail in
                    TitleHelperDiagnostics.shared.record(
                        "blank-probe success=\(success) \(detail)")
                    self.refresh()
                }
            }
        }
        // One-shot, identity-fenced read-only scan of the eighth blank window.
        // Both environment variables must be explicitly supplied; ordinary
        // launch never scans the isolated window.
        if let isolatedID = ProcessInfo.processInfo.environment[
            "TITLEHELPER_SAFE_ISOLATED_WINDOW_ID"],
           let baseline = ProcessInfo.processInfo.environment[
            "TITLEHELPER_SAFE_ISOLATED_WINDOW_BASELINE"],
           ProcessInfo.processInfo.environment["TITLEHELPER_SAFE_ISOLATED_SEARCH_PRESS"] != "1",
           ProcessInfo.processInfo.environment["TITLEHELPER_SAFE_ISOLATED_FOCUS_DIAG"] != "1",
           ProcessInfo.processInfo.environment["TITLEHELPER_SAFE_ISOLATED_FOREGROUND_SEARCH"] != "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self else { return }
                self.recentRestorer.probeIsolatedWindowMetrics(
                    expectedID: isolatedID, expectedSnapshot: baseline
                ) { success, detail in
                    TitleHelperDiagnostics.shared.record(
                        "isolated-window-metrics success=\(success) \(detail)")
                }
            }
        }
        // One-shot read-only focus/baseline diagnosis for the isolated window.
        // This path never invokes AXPress, activation or window mutation.
        if ProcessInfo.processInfo.environment["TITLEHELPER_SAFE_ISOLATED_FOCUS_DIAG"] == "1",
           ProcessInfo.processInfo.environment["TITLEHELPER_SAFE_ISOLATED_SEARCH_PRESS"] != "1",
           let isolatedID = ProcessInfo.processInfo.environment[
               "TITLEHELPER_SAFE_ISOLATED_WINDOW_ID"],
           let baseline = ProcessInfo.processInfo.environment[
               "TITLEHELPER_SAFE_ISOLATED_WINDOW_BASELINE"],
           let pidText = ProcessInfo.processInfo.environment[
               "TITLEHELPER_SAFE_ISOLATED_SEARCH_PID"],
           let expectedPID = Int32(pidText), expectedPID > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self else { return }
                self.recentRestorer.probeIsolatedFocusGate(
                    expectedID: isolatedID, expectedSnapshot: baseline,
                    expectedPID: expectedPID
                ) { success, detail in
                    TitleHelperDiagnostics.shared.record(
                        "isolated-focus-gate success=\(success) \(detail)")
                }
            }
        }
        // A separate one-shot mutation of the isolated eighth window only.
        // Requires the exact prior census, fixed ChatGPT PID, and focused target.
        if ProcessInfo.processInfo.environment["TITLEHELPER_SAFE_ISOLATED_SEARCH_PRESS"] == "1",
           let isolatedID = ProcessInfo.processInfo.environment[
               "TITLEHELPER_SAFE_ISOLATED_WINDOW_ID"],
           let baseline = ProcessInfo.processInfo.environment[
               "TITLEHELPER_SAFE_ISOLATED_WINDOW_BASELINE"],
           let pidText = ProcessInfo.processInfo.environment[
               "TITLEHELPER_SAFE_ISOLATED_SEARCH_PID"],
           let expectedPID = Int32(pidText), expectedPID > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self else { return }
                self.recentRestorer.probeIsolatedSearchPress(
                    expectedID: isolatedID, expectedSnapshot: baseline,
                    expectedPID: expectedPID
                ) { success, detail in
                    TitleHelperDiagnostics.shared.record(
                        "isolated-search-press success=\(success) \(detail)")
                }
            }
        }
        // Explicit isolated-window-only foreground activation, Search press,
        // and prior app focus restoration. Never enabled on ordinary launch.
        if ProcessInfo.processInfo.environment["TITLEHELPER_SAFE_ISOLATED_FOREGROUND_SEARCH"] == "1",
           ProcessInfo.processInfo.environment["TITLEHELPER_SAFE_ISOLATED_SEARCH_PRESS"] != "1",
           ProcessInfo.processInfo.environment["TITLEHELPER_SAFE_ISOLATED_FOCUS_DIAG"] != "1",
           let isolatedID = ProcessInfo.processInfo.environment[
               "TITLEHELPER_SAFE_ISOLATED_WINDOW_ID"],
           let baseline = ProcessInfo.processInfo.environment[
               "TITLEHELPER_SAFE_ISOLATED_WINDOW_BASELINE"],
           let pidText = ProcessInfo.processInfo.environment[
               "TITLEHELPER_SAFE_ISOLATED_SEARCH_PID"],
           let expectedPID = Int32(pidText), expectedPID > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self else { return }
                self.recentRestorer.probeIsolatedForegroundSearch(
                    expectedID: isolatedID, expectedSnapshot: baseline,
                    expectedPID: expectedPID
                ) { success, detail in
                    TitleHelperDiagnostics.shared.record(
                        "isolated-foreground-search success=\(success) \(detail)")
                }
            }
        }
        // Explicit read-only census of the currently focused ChatGPT window.
        // Never create a window, activate ChatGPT, or press any control.
        if ProcessInfo.processInfo.environment["TITLEHELPER_SAFE_FOCUSED_SEARCH_METRICS"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self else { return }
                self.recentRestorer.probeFocusedSearchMetrics { success, detail in
                    TitleHelperDiagnostics.shared.record(
                        "focused-search-metrics success=\(success) \(detail)")
                }
            }
        }
        // Separate explicit one-shot. Only a newly created blank native
        // window receives the sidebar Search AXPress; never type/select.
        if ProcessInfo.processInfo.environment["TITLEHELPER_SAFE_SEARCH_UI_PROBE"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self else { return }
                self.recentRestorer.probeSearchUI { success, detail in
                    TitleHelperDiagnostics.shared.record(
                        "search-ui-probe success=\(success) \(detail)")
                    self.refresh()
                }
            }
        }
    }


    // ========================================================
    // Preferences
    // ========================================================

    private func loadPreferences() {

        let defaults =
            UserDefaults.standard


        if defaults.object(
            forKey:
                prefOverlayEnabled
        ) == nil {

            overlayEnabled = true

        } else {

            overlayEnabled =
                defaults.bool(
                    forKey:
                        prefOverlayEnabled
                )
        }


        if defaults.object(
            forKey:
                prefNativeTitleEnabled
        ) == nil {

            // 처음 설치 시에는
            // native 변경을 자동 실행하지 않음.
            nativeTitleEnabled = false

        } else {

            nativeTitleEnabled =
                defaults.bool(
                    forKey:
                        prefNativeTitleEnabled
                )
        }
    }


    private func savePreferences() {

        let defaults =
            UserDefaults.standard

        defaults.set(
            overlayEnabled,
            forKey:
                prefOverlayEnabled
        )

        defaults.set(
            nativeTitleEnabled,
            forKey:
                prefNativeTitleEnabled
        )
    }


    // ========================================================
    // Menu
    // ========================================================

    private func setupMenu() {

        statusItem =
            NSStatusBar.system
                .statusItem(
                    withLength:
                        NSStatusItem
                            .variableLength
                )

        statusItem.button?.title =
            "T"

        statusItem.button?.toolTip =
            "ChatGPT Window Title"


        let menu = NSMenu()


        // ----------------------------------------------------
        // Overlay toggle
        // ----------------------------------------------------

        overlayToggleItem =
            NSMenuItem(
                title:
                    "화면 오버레이",
                action:
                    #selector(
                        toggleOverlay
                    ),
                keyEquivalent:
                    ""
            )

        overlayToggleItem.target = self

        menu.addItem(
            overlayToggleItem
        )


        // ----------------------------------------------------
        // Native/Dock toggle
        // ----------------------------------------------------

        nativeToggleItem =
            NSMenuItem(
                title:
                    "Dock/네이티브 제목",
                action:
                    #selector(
                        toggleNativeTitle
                    ),
                keyEquivalent:
                    ""
            )

        nativeToggleItem.target = self

        menu.addItem(
            nativeToggleItem
        )


        menu.addItem(.separator())


        // ----------------------------------------------------
        // Status
        // ----------------------------------------------------

        overlayStatusItem =
            NSMenuItem(
                title:
                    "오버레이: 시작",
                action: nil,
                keyEquivalent: ""
            )

        overlayStatusItem.isEnabled = false

        menu.addItem(
            overlayStatusItem
        )


        nativeStatusItem =
            NSMenuItem(
                title:
                    "Dock: 꺼짐",
                action: nil,
                keyEquivalent: ""
            )

        nativeStatusItem.isEnabled = false

        menu.addItem(
            nativeStatusItem
        )


        menu.addItem(.separator())


        // ----------------------------------------------------
        // Accessibility
        // ----------------------------------------------------

        let permissionItem =
            NSMenuItem(
                title:
                    "손쉬운 사용 설정 열기",
                action:
                    #selector(
                        openAccessibilitySettings
                    ),
                keyEquivalent: ""
            )

        permissionItem.target = self

        menu.addItem(
            permissionItem
        )


        // ----------------------------------------------------
        // Quit
        // ----------------------------------------------------

        let quitItem =
            NSMenuItem(
                title: "종료",
                action:
                    #selector(quitApp),
                keyEquivalent: "q"
            )

        quitItem.target = self

        menu.addItem(quitItem)

        statusItem.menu = menu

        updateMenuChecks()
    }


    private func updateMenuChecks() {

        overlayToggleItem.state =
            overlayEnabled
            ? .on
            : .off

        nativeToggleItem.state =
            nativeTitleEnabled
            ? .on
            : .off
    }


    @objc
    private func toggleOverlay() {

        overlayEnabled.toggle()

        savePreferences()
        updateMenuChecks()

        if !overlayEnabled {

            overlayPanel?.orderOut(nil)

            overlayStatusItem.title =
                "오버레이: 꺼짐"

        } else {

            refresh()
        }
    }


    @objc
    private func toggleNativeTitle() {

        nativeTitleEnabled.toggle()

        savePreferences()
        updateMenuChecks()


        guard let pid =
            currentChatGPTPID()
        else {

            nativeStatusItem.title =
                nativeTitleEnabled
                ? "Dock: ChatGPT 대기"
                : "Dock: 꺼짐"

            return
        }


        // The verified production app never sends SIGUSR1.  The legacy
        // NativeTitleSync is preserved as-is, but its calls are compile-time
        // excluded until a separately audited safe Inspector transport exists.
        #if TITLEHELPER_NATIVE_WRITER_VERIFIED
        if nativeTitleEnabled {

            nativeStatusItem.title =
                "Dock: 시작 중"

            lastNativeSync =
                Date.distantPast

            refresh()

        } else {

            nativeStatusItem.title =
                "Dock: 복원 중"

            nativeSync.restore(
                pid: pid
            ) {
                [weak self] text in

                DispatchQueue.main.async {

                    self?
                        .nativeStatusItem
                        .title =
                        text
                }
            }
        }
        #else
        nativeStatusItem.title =
            "Dock: 안전 중지 (Inspector 미검증)"
        TitleHelperDiagnostics.shared.record(
            "native-sync-blocked source=menu enabled=\(nativeTitleEnabled)")
        #endif
    }


    // ========================================================
    // Accessibility permission
    // ========================================================

    private func requestAccessibilityPermission() {

        if AXIsProcessTrusted() {
            return
        }

        guard !permissionPromptRequested
        else {
            return
        }

        permissionPromptRequested = true

        let options = [
            kAXTrustedCheckOptionPrompt
                .takeUnretainedValue()
                as String:
                true
        ] as CFDictionary

        _ =
            AXIsProcessTrustedWithOptions(
                options
            )
    }


    @objc
    private func openAccessibilitySettings() {

        guard let url =
            URL(
                string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )
        else {
            return
        }

        NSWorkspace.shared.open(url)
    }


    // ========================================================
    // Quit
    // ========================================================

    @objc
    private func quitApp() {

        restoreQueue.cancel()
        restoreProgress.hide()
        dockSidecar.stop()
        overlayPanel?.orderOut(nil)

        #if !TITLEHELPER_NATIVE_WRITER_VERIFIED
        // Do not call NativeTitleSync.restore() when the Inspector transport
        // is unverified: its fallback can signal/terminate ChatGPT.
        TitleHelperDiagnostics.shared.record(
            "native-sync-blocked source=quit")
        NSApp.terminate(nil)
        return
        #else
        guard nativeTitleEnabled,
              let pid =
                currentChatGPTPID()
        else {

            NSApp.terminate(nil)
            return
        }

        var terminated = false

        nativeSync.restore(
            pid: pid
        ) {
            _ in

            DispatchQueue.main.async {

                guard !terminated else {
                    return
                }

                terminated = true

                NSApp.terminate(nil)
            }
        }


        // 복원 요청 자체가 실패해도
        // 앱 종료가 막히지 않도록 fallback.
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.8
        ) {

            guard !terminated else {
                return
            }

            terminated = true

            NSApp.terminate(nil)
        }
        #endif
    }


    // A restarted app often exposes no AXWebArea while a generic initial
    // ChatGPT window is loading. Validate on a fresh AX app handle *after*
    // foreground activation, not on stale or incomplete event caches.
    private func freshOpenConversationTitles(pid: pid_t) -> [String]? {
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.75)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            root, kAXWindowsAttribute as CFString, &raw) == .success,
              let windows = raw as? [AXUIElement], windows.count < 40 else {
            return nil
        }
        var result: [String] = []
        var unresolved = 0
        for window in windows {
            let id = String(CFHash(window))
            if let known = titleCache[id]?.value.title {
                result.append(known)
                continue
            }
            if let area = findWebArea(window) {
                let title = axString(area, kAXTitleAttribute)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty && title != "ChatGPT" {
                    result.append(title)
                    continue
                }
            }
            let native = axString(window, kAXTitleAttribute)
            if !native.isEmpty && native != "ChatGPT" {
                result.append(native)
            } else if native == "ChatGPT" {
                unresolved += 1
            } else {
                return nil
            }
        }
        // At most one generic initial window is acceptable. If multiple
        // unknown native windows exist, refuse rather than duplicate them.
        guard unresolved <= 1 else { return nil }
        return result
    }

    private func showRestoreError(_ reason: String) {
        let alert = NSAlert()
        alert.messageText = "대화 복원 불가"
        alert.informativeText = reason
        alert.runModal()
    }

    private func prepareForegroundRestore(
        _ callback: @escaping ([String]) -> Void
    ) {
        guard !restorePreflightPending, !restoreQueue.isRunning,
              let app = currentChatGPTApp(),
              app.processIdentifier == targetPID else { return }
        restorePreflightPending = true
        let pid = app.processIdentifier
        _ = app.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { [weak self] in
            guard let self else { return }
            self.restorePreflightPending = false
            guard self.currentChatGPTPID() == pid else {
                self.showRestoreError("ChatGPT 프로세스가 변경되었습니다.")
                return
            }
            self.refresh()
            guard let open = self.freshOpenConversationTitles(pid: pid) else {
                TitleHelperDiagnostics.shared.record(
                    "history-restore-blocked reason=foreground-AX-incomplete")
                self.showRestoreError(
                    "현재 ChatGPT 창 상태를 확인하지 못했습니다. " +
                    "앱을 전면에 표시한 뒤 다시 시도해 주세요.")
                return
            }
            callback(open)
        }
    }

    // ========================================================
    // Targeted event scheduling
    // ========================================================

    private func receivedAXEvent(windowID: String?, titleRelated: Bool) {
        if let windowID {
            pendingAXTitleEvents.insert(windowID)
            titleScheduler.request(windowID, priority: .immediate)

            // Chromium often sends AXValueChanged while the old web-area
            // title is still visible. Observe just this window with bounded
            // follow-up reads; no foreground focus, clicks, or fast polling.
            if titleRelated, let ticket = titleRetryPlan.begin(
                windowID, hasCachedTitle: titleCache[windowID] != nil
            ) {
                for delay in TitleRevisionRetryPlan.delays {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        [weak self] in
                        guard let self, self.titleRetryPlan.isActive(
                            windowID, generation: ticket
                        ) else { return }
                        self.pendingAXTitleEvents.insert(windowID)
                        self.titleScheduler.request(windowID, priority: .immediate)
                        self.schedulePendingWork()
                    }
                }
                TitleHelperDiagnostics.shared.record(
                    "ax-title-retry-scheduled checks=\(TitleRevisionRetryPlan.delays.count)")
            }
        }
        // Coalesce AXTitleChanged/AXValueChanged bursts; callback itself is
        // intentionally free of any AX remote reads or window traversal.
        guard !pendingEventTick else { return }
        pendingEventTick = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            self.pendingEventTick = false
            self.refresh(allowBackgroundFallback: false)
        }
    }

    private func schedulePendingWork() {
        guard titleScheduler.hasPending, !pendingEventTick else { return }
        pendingEventTick = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
            guard let self else { return }
            self.pendingEventTick = false
            self.refresh(allowBackgroundFallback: false)
        }
    }

    // ========================================================
    // ChatGPT process
    // ========================================================

    private func currentChatGPTApp()
    -> NSRunningApplication? {

        NSWorkspace.shared
            .runningApplications
            .first {
                $0.bundleIdentifier
                    == targetBundleID
            }
    }


    private func currentChatGPTPID()
    -> pid_t? {

        currentChatGPTApp()?
            .processIdentifier
    }


    // ========================================================
    // Refresh
    // ========================================================

    private func refresh(allowBackgroundFallback: Bool = true) {
        // Protect against re-entrancy from AppKit / AX runloop events.
        guard !processingRefresh else {
            retryRefresh = true
            return
        }
        processingRefresh = true
        defer {
            processingRefresh = false
            if retryRefresh {
                retryRefresh = false
                schedulePendingWork()
            }
        }

        guard AXIsProcessTrusted() else {
            TitleHelperDiagnostics.shared.record("ax-trusted=false")
            overlayPanel?.orderOut(nil)
            overlayStatusItem.title = "오버레이: 손쉬운 사용 권한 필요"
            requestAccessibilityPermission()
            return
        }

        guard let targetApp = currentChatGPTApp() else {
            TitleHelperDiagnostics.shared.record("chatgpt-running=false")
            titleObserver?.stop()
            titleObserver = nil
            titleCache.removeAll()
            sidecarWindows.removeAll()
            sidecarWindowOrder.removeAll()
            lastAXWindowCensusSucceeded = false
            lastAXCensusLogState = nil
            lastAXCensusShape = nil
            lastAXCensusCheckedAt = .distantPast
            minimizedAXProbePID = 0
            lastVisibleIdentityProbeCount = 0
            dockSidecar.update([])
            pendingAXTitleEvents.removeAll()
            titleScheduler = TitleWorkScheduler()
            titleRetryPlan = TitleRevisionRetryPlan()
            targetPID = 0
            targetAX = nil
            lastFocusedID = nil
            overlayPanel?.orderOut(nil)
            overlayStatusItem.title = "오버레이: ChatGPT 대기"
            nativeStatusItem.title = nativeTitleEnabled
                ? "Dock: ChatGPT 대기" : "Dock: 꺼짐"
            return
        }

        let pid = targetApp.processIdentifier
        if targetPID != pid || targetAX == nil {
            titleObserver?.stop()
            titleObserver = nil
            titleCache.removeAll()
            sidecarWindows.removeAll()
            sidecarWindowOrder.removeAll()
            lastAXWindowCensusSucceeded = false
            lastAXCensusLogState = nil
            lastAXCensusShape = nil
            lastAXCensusCheckedAt = .distantPast
            minimizedAXProbePID = 0
            lastVisibleIdentityProbeCount = 0
            dockSidecar.update([])
            pendingAXTitleEvents.removeAll()
            titleScheduler = TitleWorkScheduler()
            titleRetryPlan = TitleRevisionRetryPlan()
            lastFocusedID = nil
            targetPID = pid
            targetAX = AXUIElementCreateApplication(pid)
            nativeSync.resetForNewPID()
            lastNativeSync = .distantPast
            if let appAX = targetAX {
                AXUIElementSetMessagingTimeout(appAX, 0.6)
                _ = AXUIElementSetAttributeValue(
                    appAX, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue
                )
                titleObserver = MacAXTitleObserver(pid: pid, app: appAX) {
                    [weak self] windowID, titleRelated in
                    self?.receivedAXEvent(
                        windowID: windowID, titleRelated: titleRelated)
                }
                TitleHelperDiagnostics.shared.record(
                    "ax-observer-created=\(titleObserver != nil) pid=\(pid)")
            }
        }

        guard let appAX = targetAX else { return }
        let windows = collectConversationWindows(
            axApp: appAX,
            allowBackgroundFallback: allowBackgroundFallback
        )
        // Distinguish raw native AX windows from loaded conversation titles.
        // A generic ChatGPT starter window is still a real window.
        let censusState = lastAXWindowCensusSucceeded
            ? "available raw=\(sidecarWindowOrder.count) recognized=\(windows.count)"
            : "unavailable"
        // Refresh aggregate window identity periodically even if the number of
        // recognized chats stays constant. Minimize/restore can change while
        // raw/recognized counts do not, so count-only log gating goes stale.
        let censusNow = Date()
        let censusDue = censusState != lastAXCensusShape ||
            censusNow.timeIntervalSince(lastAXCensusCheckedAt) >= 30
        if censusDue {
            lastAXCensusShape = censusState
            lastAXCensusCheckedAt = censusNow
            if lastAXWindowCensusSucceeded {
                var nativeGeneric = 0
                var nativeNamed = 0
                var nativeEmpty = 0
                var standard = 0
                var minimized = 0
                var matchedSaved = 0
                var minimizedSaved = 0
                var matchedPrevious = 0
                var matchedRecent = 0
                let savedTargets = Set(sessionHistory.lastSessionTargets(pid: pid))
                let previousTargets = Set(sessionHistory.snapshot.previousSessionOpen)
                let recentTargets = Set(sessionHistory.snapshot.recentTitles)
                // Only aggregate native AX attributes; never log raw titles.
                for id in sidecarWindowOrder {
                    guard let window = sidecarWindows[id] else { continue }
                    let nativeTitle = axString(window, kAXTitleAttribute)
                    if nativeTitle == "ChatGPT" {
                        nativeGeneric += 1
                    } else if nativeTitle.isEmpty {
                        nativeEmpty += 1
                    } else {
                        nativeNamed += 1
                    }
                    if axString(window, kAXSubroleAttribute) == "AXStandardWindow" {
                        standard += 1
                    }
                    let isMinimized = axBool(window, kAXMinimizedAttribute) == true
                    if isMinimized { minimized += 1 }
                    if savedTargets.contains(nativeTitle) {
                        matchedSaved += 1
                        if isMinimized { minimizedSaved += 1 }
                    }
                    if previousTargets.contains(nativeTitle) { matchedPrevious += 1 }
                    if recentTargets.contains(nativeTitle) { matchedRecent += 1 }
                }
                let censusDetail = [
                    censusState,
                    "nativeGeneric=\(nativeGeneric) nativeNamed=\(nativeNamed)",
                    "nativeEmpty=\(nativeEmpty) standard=\(standard) minimized=\(minimized)",
                    "matchedSaved=\(matchedSaved)/\(savedTargets.count)",
                    "minimizedSaved=\(minimizedSaved)",
                    "matchedPrevious=\(matchedPrevious)/\(previousTargets.count)",
                    "matchedRecent=\(matchedRecent)/\(recentTargets.count)"
                ].joined(separator: " ")
                if censusDetail != lastAXCensusLogState {
                    TitleHelperDiagnostics.shared.record(
                        "ax-window-census \(censusDetail)")
                    lastAXCensusLogState = censusDetail
                }
                // Opt-in, read-only, process-local native AX identity snapshot.
                // Never log conversation titles, URLs, message text or stable
                // account identifiers. AX element hashes are only meaningful
                // within this running helper process and ChatGPT PID.
                if ProcessInfo.processInfo.environment["TITLEHELPER_SAFE_AX_WINDOW_SNAPSHOT"] == "1" {
                    let entries = sidecarWindowOrder.prefix(39).enumerated().compactMap {
                        index, id -> String? in
                        guard let window = sidecarWindows[id] else { return nil }
                        let minimized = axBool(window, kAXMinimizedAttribute) == true
                        let generic = axString(window, kAXTitleAttribute) == "ChatGPT"
                        let recognized = titleCache[id] != nil
                        return "\(index):\(id):min=\(minimized ? 1 : 0):generic=\(generic ? 1 : 0):known=\(recognized ? 1 : 0)"
                    }
                    TitleHelperDiagnostics.shared.record(
                        "ax-window-identity-snapshot pid=\(pid) raw=\(sidecarWindowOrder.count) " +
                        "entries=\(entries.joined(separator: ";"))")
                }
            } else if lastAXCensusLogState != "unavailable" {
                TitleHelperDiagnostics.shared.record("ax-window-census unavailable")
                lastAXCensusLogState = "unavailable"
            }
        }
        // One bounded background census per ChatGPT PID. The normal refresh
        // deliberately skips minimized AX trees; do not mistake that for no chats.
        if lastAXWindowCensusSucceeded && minimizedAXProbePID != pid {
            minimizedAXProbePID = pid
            let saved = Set(sessionHistory.lastSessionTargets(pid: pid))
            let previous = Set(sessionHistory.snapshot.previousSessionOpen)
            let recent = Set(sessionHistory.snapshot.recentTitles)
            DispatchQueue.global(qos: .utility).async {
                let root = AXUIElementCreateApplication(pid)
                _ = AXUIElementSetMessagingTimeout(root, 0.2)
                guard let raw = axGet(root, kAXWindowsAttribute)
                    as? [AXUIElement], raw.count < 40 else {
                    TitleHelperDiagnostics.shared.record(
                        "ax-minimized-webarea unavailable pid=\(pid)")
                    return
                }
                var minimized = 0
                var found = 0
                var named = 0
                var generic = 0
                var limited = 0
                var matchedSaved = 0
                var matchedPrevious = 0
                var matchedRecent = 0
                var documents = Set<String>()
                var urls = Set<String>()
                var identifiers = Set<String>()
                var documentCount = 0
                var urlCount = 0
                var identifierCount = 0
                for window in raw.prefix(8) {
                    guard axBool(window, kAXMinimizedAttribute) == true else {
                        continue
                    }
                    minimized += 1
                    // Read only the window itself; never traverse message values.
                    // Retain values only transiently for aggregate uniqueness.
                    let document = axWindowMetadataText(window, "AXDocument")
                    let url = axWindowMetadataText(window, "AXURL")
                    let identifier = axWindowMetadataText(window, "AXIdentifier")
                    if !document.isEmpty {
                        documentCount += 1
                        documents.insert(document)
                    }
                    if !url.isEmpty {
                        urlCount += 1
                        urls.insert(url)
                    }
                    if !identifier.isEmpty {
                        identifierCount += 1
                        identifiers.insert(identifier)
                    }
                    let result = boundedMinimizedWebAreaTitle(window)
                    if result.limited { limited += 1 }
                    guard result.found else { continue }
                    found += 1
                    let title = result.title
                    if title.isEmpty || title == "ChatGPT" {
                        generic += 1
                    } else {
                        named += 1
                    }
                    if saved.contains(title) { matchedSaved += 1 }
                    if previous.contains(title) { matchedPrevious += 1 }
                    if recent.contains(title) { matchedRecent += 1 }
                }
                TitleHelperDiagnostics.shared.record(
                    "ax-minimized-webarea pid=\(pid) raw=\(raw.count) " +
                    "minimized=\(minimized) found=\(found) named=\(named) " +
                    "generic=\(generic) limited=\(limited) " +
                    "matchedSaved=\(matchedSaved)/\(saved.count) " +
                    "matchedPrevious=\(matchedPrevious)/\(previous.count) " +
                    "matchedRecent=\(matchedRecent)/\(recent.count)")
                TitleHelperDiagnostics.shared.record(
                    "ax-minimized-metadata pid=\(pid) checked=\(minimized) " +
                    "document=\(documentCount) uniqueDocument=\(documents.count) " +
                    "url=\(urlCount) uniqueURL=\(urls.count) " +
                    "identifier=\(identifierCount) uniqueIdentifier=\(identifiers.count)")
            }
        }
        TitleHelperDiagnostics.shared.record(
            "refresh-success knownWindows=\(windows.count) backgroundTick=\(allowBackgroundFallback) nativeEnabled=\(nativeTitleEnabled)")
        updateOverlay(windows: windows)
        // Independent selectable titles; never guess native Dock item order.
        let sidecarEntries: [DockMenuSidecar.Entry] =
            sidecarWindowOrder.compactMap { id in
                guard let ax = sidecarWindows[id],
                      let cached = titleCache[id] else { return nil }
                return DockMenuSidecar.Entry(
                    id: id, title: cached.value.title, axWindow: ax)
            }
        dockSidecar.update(sidecarEntries)
        // Probe already-visible, cached conversation web areas only. This is
        // aggregate-only and never changes owner windows or reads messages.
        // A new count triggers at most one bounded background scan per PID.
        if !sidecarEntries.isEmpty &&
           lastVisibleIdentityProbeCount != sidecarEntries.count {
            lastVisibleIdentityProbeCount = sidecarEntries.count
            let samples: [(String, AXUIElement, AXUIElement)] =
                sidecarEntries.prefix(8).compactMap { entry in
                    guard axBool(entry.axWindow, kAXMinimizedAttribute) != true,
                          let cached = titleCache[entry.id] else { return nil }
                    return (cached.value.title, cached.webArea, entry.axWindow)
                }
            let saved = Set(sessionHistory.lastSessionTargets(pid: pid))
            let previous = Set(sessionHistory.snapshot.previousSessionOpen)
            let recent = Set(sessionHistory.snapshot.recentTitles)
            DispatchQueue.global(qos: .utility).async {
                var shareCandidates = 0
                var copyLinkCandidates = 0
                var shareEnabled = 0
                var sharePressable = 0
                var shareActionable = 0
                var shareMenuRole = 0
                var copyLinkEnabled = 0
                var copyLinkPressable = 0
                var openOnChatGPTControls = 0
                var openOnChatGPTConversationURLs = 0
                var shareNodesVisited = 0
                var shareScanLimited = 0
                var shareScanElapsedMs = 0
                var shareScanRemaining = 0
                var webURLs = Set<String>()
                var webURLPresent = 0
                var webURLChatGPTHost = 0
                var webURLChatGPTRoot = 0
                var webURLChatGPTConversationPath = 0
                var webURLOtherHTTPHost = 0
                var webURLNonHTTP = 0
                var webURLAppScheme = 0
                var webURLChatGPTScheme = 0
                var webURLNonHTTPConversationPath = 0
                var webURLUnparsed = 0
                var webDocuments = Set<String>()
                var webIdentifiers = Set<String>()
                var webDOMIdentifiers = Set<String>()
                var windowURLs = Set<String>()
                var matchedSaved = 0
                var matchedPrevious = 0
                var matchedRecent = 0
                var nativeTitleEqualsWeb = 0
                var chatPath = 0
                for (title, area, window) in samples {
                    let controls = boundedShareControlCensus(area)
                    shareCandidates += controls.share
                    copyLinkCandidates += controls.copyLink
                    shareEnabled += controls.shareEnabled
                    sharePressable += controls.sharePressable
                    shareActionable += controls.shareActionable
                    shareMenuRole += controls.shareMenuRole
                    copyLinkEnabled += controls.copyLinkEnabled
                    copyLinkPressable += controls.copyLinkPressable
                    openOnChatGPTControls += controls.openOnChatGPTControls
                    openOnChatGPTConversationURLs += controls.openOnChatGPTConversationURLs
                    shareNodesVisited += controls.visited
                    if controls.limited { shareScanLimited += 1 }
                    shareScanElapsedMs += controls.elapsedMs
                    shareScanRemaining += controls.remaining
                    _ = AXUIElementSetMessagingTimeout(area, 0.2)
                    _ = AXUIElementSetMessagingTimeout(window, 0.2)
                    let webURL = axWindowMetadataText(area, "AXURL")
                    let webDocument = axWindowMetadataText(area, "AXDocument")
                    let webIdentifier = axWindowMetadataText(area, "AXIdentifier")
                    let webDOMIdentifier = axWindowMetadataText(area, "AXDOMIdentifier")
                    let windowURL = axWindowMetadataText(window, "AXURL")
                    if !webURL.isEmpty {
                        webURLPresent += 1
                        webURLs.insert(webURL)
                        // Classify only aggregate URL shape. Never log a URL,
                        // path, host, query, token or per-window identity.
                        if let parsed = URLComponents(string: webURL),
                           let scheme = parsed.scheme?.lowercased() {
                            if scheme == "https" || scheme == "http" {
                                if let host = parsed.host?.lowercased() {
                                    if host == "chatgpt.com" ||
                                       host == "www.chatgpt.com" {
                                        webURLChatGPTHost += 1
                                        if parsed.path.isEmpty || parsed.path == "/" {
                                            webURLChatGPTRoot += 1
                                        }
                                        if parsed.path.contains("/c/") {
                                            webURLChatGPTConversationPath += 1
                                        }
                                    } else {
                                        webURLOtherHTTPHost += 1
                                    }
                                } else {
                                    webURLUnparsed += 1
                                }
                            } else {
                                webURLNonHTTP += 1
                                // Do not log the URL or any path/ID. Classify
                                // non-HTTP schemes and conversation-shaped paths.
                                if scheme == "app" { webURLAppScheme += 1 }
                                if scheme == "chatgpt" { webURLChatGPTScheme += 1 }
                                if parsed.path.contains("/c/") {
                                    webURLNonHTTPConversationPath += 1
                                }
                            }
                        } else {
                            webURLUnparsed += 1
                        }
                    }
                    if !webDocument.isEmpty { webDocuments.insert(webDocument) }
                    if !webIdentifier.isEmpty { webIdentifiers.insert(webIdentifier) }
                    if !webDOMIdentifier.isEmpty { webDOMIdentifiers.insert(webDOMIdentifier) }
                    if !windowURL.isEmpty { windowURLs.insert(windowURL) }
                    if saved.contains(title) { matchedSaved += 1 }
                    if previous.contains(title) { matchedPrevious += 1 }
                    if recent.contains(title) { matchedRecent += 1 }
                    if axString(window, kAXTitleAttribute) == title {
                        nativeTitleEqualsWeb += 1
                    }
                    if [webURL, webDocument].contains(where: { value in
                        guard let url = URLComponents(string: value),
                              let host = url.host?.lowercased(),
                              host == "chatgpt.com" || host == "www.chatgpt.com"
                        else { return false }
                        return url.path.contains("/c/")
                    }) { chatPath += 1 }
                }
                TitleHelperDiagnostics.shared.record(
                    "ax-visible-identity pid=\(pid) checked=\(samples.count) " +
                    "shareCandidates=\(shareCandidates) " +
                    "copyLinkCandidates=\(copyLinkCandidates) " +
                    "shareEnabled=\(shareEnabled) " +
                    "sharePressable=\(sharePressable) " +
                    "shareActionable=\(shareActionable) " +
                    "shareMenuRole=\(shareMenuRole) " +
                    "copyLinkEnabled=\(copyLinkEnabled) " +
                    "copyLinkPressable=\(copyLinkPressable) " +
                    "openOnChatGPTControls=\(openOnChatGPTControls) " +
                    "openOnChatGPTConversationURLs=\(openOnChatGPTConversationURLs) " +
                    "shareNodesVisited=\(shareNodesVisited) " +
                    "shareScanLimited=\(shareScanLimited) " +
                    "shareScanElapsedMs=\(shareScanElapsedMs) " +
                    "shareScanRemaining=\(shareScanRemaining) " +
                    "webURL=\(webURLs.count) webURLPresent=\(webURLPresent) " +
                    "webURLChatGPTHost=\(webURLChatGPTHost) " +
                    "webURLChatGPTRoot=\(webURLChatGPTRoot) " +
                    "webURLChatGPTConversationPath=\(webURLChatGPTConversationPath) " +
                    "webURLOtherHTTPHost=\(webURLOtherHTTPHost) " +
                    "webURLNonHTTP=\(webURLNonHTTP) " +
                    "webURLAppScheme=\(webURLAppScheme) " +
                    "webURLChatGPTScheme=\(webURLChatGPTScheme) " +
                    "webURLNonHTTPConversationPath=\(webURLNonHTTPConversationPath) " +
                    "webURLUnparsed=\(webURLUnparsed) " +
                    "webDocument=\(webDocuments.count) " +
                    "webIdentifier=\(webIdentifiers.count) " +
                    "webDOMIdentifier=\(webDOMIdentifiers.count) " +
                    "windowURL=\(windowURLs.count) chatPath=\(chatPath) " +
                    "nativeEqualsWeb=\(nativeTitleEqualsWeb) " +
                    "matchedSaved=\(matchedSaved)/\(saved.count) " +
                    "matchedPrevious=\(matchedPrevious)/\(previous.count) " +
                    "matchedRecent=\(matchedRecent)/\(recent.count)")
                // Explicit one-shot diagnostic of the common, static app: AXURL.
                // Only reveal it when every sampled conversation has the same
                // URL and it contains no query, fragment, ID-shaped path or
                // characters outside the expected static app-origin alphabet.
                // Never log per-conversation URLs or message content.
                if ProcessInfo.processInfo.environment["TITLEHELPER_SAFE_COMMON_APP_AXURL"] == "1" {
                    if webURLPresent == samples.count, samples.count >= 2,
                       webURLs.count == 1, let common = webURLs.first,
                       common.count <= 160,
                       common.range(of: "^[A-Za-z0-9._:/-]+$", options: .regularExpression) != nil,
                       let parsed = URLComponents(string: common),
                       parsed.scheme?.lowercased() == "app",
                       parsed.query == nil, parsed.fragment == nil,
                       !parsed.path.contains("/c/"),
                       common.range(of: "(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", options: .regularExpression) == nil {
                        TitleHelperDiagnostics.shared.record("ax-common-app-url verified=\(samples.count) value=\(common)")
                    } else {
                        TitleHelperDiagnostics.shared.record("ax-common-app-url blocked=not-static-common")
                    }
                }
            }
        }
        // Save only a complete known title census, never transient missing
        // AX windows. Across ChatGPT PID changes, retain last session state.
        let complete = lastAXWindowCensusSucceeded &&
            sidecarEntries.count == sidecarWindowOrder.count
        if complete {
            _ = sessionHistory.observe(
                pid: pid,
                titles: sidecarEntries.map { $0.title },
                windowCount: sidecarWindowOrder.count)
            dockSidecar.updateHistory(sessionHistory.recoverable(
                excluding: sidecarEntries.map { $0.title }, pid: pid))
        } else if sessionHistory.hasPendingRestart(pid: pid) {
            // A restarted ChatGPT process may expose ZERO AX windows until
            // its renderer has initialized or is foreground. Last session
            // titles are durable and must remain visible in the Dock panel.
            // Do NOT create windows until a fresh foreground AX preflight
            // confirms whether any conversations are already open.
            dockSidecar.updateHistory(
                sessionHistory.recoverable(excluding: [], pid: pid))
            TitleHelperDiagnostics.shared.record(
                "history-restart-pending pid=\(pid) " +
                "saved=\(sessionHistory.snapshot.lastCompleteOpen.count)")
        } else {
            // An incomplete AX read in an already tracked process should
            // never be interpreted as newly missing conversations.
            dockSidecar.updateHistory([])
        }

        // Preserve the legacy NativeTitleSync unchanged: it still updates
        // BrowserWindow.setTitle and restores saved native titles.
        // The cached title list is event-driven; one stale title per tick is
        // refreshed as a 20-second fallback.
        #if TITLEHELPER_NATIVE_WRITER_VERIFIED
        if nativeTitleEnabled {
            let now = Date()
            if now.timeIntervalSince(lastNativeSync) >= nativeSyncInterval {
                lastNativeSync = now
                nativeSync.sync(pid: pid, windows: windows) { [weak self] text in
                    DispatchQueue.main.async {
                        self?.nativeStatusItem.title = text
                        // Preserve NativeTitleSync behavior, but never
                        // mistake a pending inspector for an actual sync.
                        // Do not persist conversation titles.
                        let nativeState: String
                        if text == "Dock: 제목 대상 없음" {
                            nativeState = "no-title"
                        } else if text == "Dock: inspector 시작 중" {
                            nativeState = "inspector-pending"
                        } else if text.hasPrefix("Dock: ") &&
                                  text.contains("개 동기화") {
                            nativeState = "sync-returned-count"
                        } else if text.hasPrefix("Dock 오류: ") ||
                                  text.hasPrefix("Dock 연결 오류: ") {
                            nativeState = "error"
                        } else {
                            nativeState = "other"
                        }
                        TitleHelperDiagnostics.shared.record(
                            "native-sync-result state=\(nativeState)")
                    }
                }
            }
        } else {
            nativeStatusItem.title = "Dock: 꺼짐"
        }
        #else
        nativeStatusItem.title = nativeTitleEnabled
            ? "Dock: 안전 중지 (Inspector 미검증)" : "Dock: 꺼짐"
        #endif
    }

    // Read ONE eligible AX window each tick, with title events prioritized.
    // Only cheap AXWindows / AXMain attributes are read for other windows.
    private func collectConversationWindows(
        axApp: AXUIElement,
        allowBackgroundFallback: Bool
    ) -> [ConversationWindow] {
        guard let windows = axGet(axApp, kAXWindowsAttribute)
            as? [AXUIElement] else {
            lastAXWindowCensusSucceeded = false
            return titleCache.values.map { $0.value }
        }
        lastAXWindowCensusSucceeded = true
        let ids = Set(windows.map { String(CFHash($0)) })
        sidecarWindowOrder = windows.map { String(CFHash($0)) }
        sidecarWindows = Dictionary(
            uniqueKeysWithValues: windows.map {
                (String(CFHash($0)), $0)
            })
        titleCache = titleCache.filter { ids.contains($0.key) }
        pendingAXTitleEvents = pendingAXTitleEvents.intersection(ids)
        titleRetryPlan.retainOnly(ids)

        titleObserver?.beginDiscovery()
        var windowsByID: [String: AXUIElement] = [:]
        var visibleIDs: Set<String> = []
        for w in windows {
            let id = String(CFHash(w))
            windowsByID[id] = w
            titleObserver?.watchWindow(w, id: id)
            if axBool(w, kAXMinimizedAttribute) != true {
                visibleIDs.insert(id)
            }
        }
        // Minimized windows are not queued for AX tree reads. An unminimized
        // window is considered new and becomes immediate-priority work.
        titleScheduler.reconcile(visibleIDs)
        // Changes of foreground window are high priority, but generic
        // AXFocusedUIElement events do not trigger full-tree reads.
        let focused = axGet(axApp, kAXFocusedWindowAttribute)
        if let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
            let focusedID = String(CFHash(focused))
            if focusedID != lastFocusedID {
                lastFocusedID = focusedID
                titleScheduler.request(focusedID, priority: .active)
            }
        }

        // Windows parity: background due work is queued once per discovery
        // timer tick, not during every event burst or backlog drain.
        if allowBackgroundFallback {
            titleScheduler.requestOneOverdue(visibleIDs, now: Date())
        }
        if let selectedID = titleScheduler.pop(),
           let window = windowsByID[selectedID] {
            let fromEvent = pendingAXTitleEvents.remove(selectedID) != nil
            let started = Date()
            let result = readConversationWindow(window)
            // No conversation content is printed. These metrics distinguish
            // actual AX-event work from periodic one-window fallback.
            TitleHelperDiagnostics.shared.record(
                "ax-title-read source=\(fromEvent ? "event" : "discovery-or-due") " +
                "ok=\(result != nil) durationMs=\(Int(Date().timeIntervalSince(started) * 1000)) " +
                "fingerprint=\(result.map { TitleHelperDiagnostics.fingerprint($0.value.title) } ?? "-")")
            if let result {
                let old = titleCache[selectedID]?.value.title
                titleCache[selectedID] = result
                if old != result.value.title {
                    titleRetryPlan.complete(selectedID)
                    // An event can occur within the 1s legacy sync throttle.
                    // Force the unchanged synchronizer to receive this title.
                    lastNativeSync = .distantPast
                }
            } else {
                titleCache.removeValue(forKey: selectedID)
            }
            titleScheduler.complete(selectedID, success: result != nil, now: Date())
        }

        for (id, cache) in titleCache {
            if visibleIDs.contains(id) {
                titleObserver?.watchTitle(
                    cache.webArea, buttons: cache.buttons, id: id
                )
            }
        }
        titleObserver?.finishDiscovery()
        schedulePendingWork()

        var result: [ConversationWindow] = []
        for window in windows {
            let id = String(CFHash(window))
            guard visibleIDs.contains(id), let cached = titleCache[id] else {
                continue
            }
            // AXMain may change without a title event; keep UI selection fresh.
            let main = axBool(window, kAXMainAttribute) ?? false
            let v = cached.value
            result.append(ConversationWindow(
                title: v.title, x: v.x, y: v.y,
                width: v.width, height: v.height, isMain: main
            ))
        }
        return result
    }

    private func readConversationWindow(
        _ window: AXUIElement
    ) -> CachedConversation? {
        guard axBool(window, kAXMinimizedAttribute) != true,
              let webArea = findWebArea(window) else { return nil }

        let title = axString(webArea, kAXTitleAttribute)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != "ChatGPT",
              let position = axPoint(window), let size = axSize(window),
              size.width > 100, size.height > 100 else { return nil }

        let v = ConversationWindow(
            title: title, x: position.x, y: position.y,
            width: size.width, height: size.height,
            isMain: axBool(window, kAXMainAttribute) ?? false
        )
        let buttons = findConversationTitleButtons(webArea, title: title)
        TitleHelperDiagnostics.shared.record(
            "title-elements webArea=1 exactButtons=\(buttons.count)")
        return CachedConversation(
            value: v,
            webArea: webArea,
            buttons: buttons
        )
    }


    // ========================================================
    // Overlay
    //
    // 현재 ChatGPT가 frontmost일 때,
    // AXMain 창 하나에만 표시.
    // ========================================================

    private func updateOverlay(
        windows: [ConversationWindow]
    ) {

        guard overlayEnabled
        else {

            overlayPanel?.orderOut(nil)

            overlayStatusItem.title =
                "오버레이: 꺼짐"

            return
        }


        guard NSWorkspace.shared
            .frontmostApplication?
            .bundleIdentifier
            == targetBundleID
        else {

            overlayPanel?.orderOut(nil)

            overlayStatusItem.title =
                "오버레이: ChatGPT 비활성"

            return
        }


        guard let active =
            windows.first(
                where: {
                    $0.isMain
                }
            )
            ?? windows.first
        else {

            overlayPanel?.orderOut(nil)

            overlayStatusItem.title =
                "오버레이: 제목창 없음"

            return
        }


        if overlayPanel == nil {

            overlayPanel =
                TitleOverlayPanel()
        }


        guard let overlayPanel,
              let placement =
                overlayFrame(
                    for: active
                )
        else {

            self.overlayPanel?
                .orderOut(nil)

            overlayStatusItem.title =
                "오버레이: 외부 공간 없음"

            return
        }


        overlayPanel.setTitle(
            active.title
        )


        overlayPanel.setFrame(
            placement,
            display: true
        )


        overlayPanel
            .orderFrontRegardless()


        overlayStatusItem.title =
            "오버레이: 표시 중"
    }


    // ========================================================
    // AX coordinates -> Cocoa coordinates
    // ========================================================

    private func cocoaWindowRect(
        _ window: ConversationWindow
    ) -> (
        rect: NSRect,
        screen: NSScreen
    )? {

        let mappings =
            getScreenMappings()


        let axCenter =
            CGPoint(
                x:
                    window.x +
                    window.width / 2,

                y:
                    window.y +
                    window.height / 2
            )


        var selected:
            ScreenMapping?


        for mapping in mappings {

            if mapping
                .cgBounds
                .contains(axCenter) {

                selected = mapping
                break
            }
        }


        if selected == nil {

            let axRect =
                CGRect(
                    x: window.x,
                    y: window.y,

                    width:
                        window.width,

                    height:
                        window.height
                )


            var bestArea:
                CGFloat = 0


            for mapping in mappings {

                let intersection =
                    axRect.intersection(
                        mapping.cgBounds
                    )

                if intersection.isNull {
                    continue
                }


                let area =
                    intersection.width *
                    intersection.height


                if area > bestArea {

                    bestArea = area
                    selected = mapping
                }
            }
        }


        guard let mapping =
            selected
        else {
            return nil
        }


        let cg =
            mapping.cgBounds

        let cocoa =
            mapping.screen.frame


        let localX =
            window.x - cg.minX

        let localYFromTop =
            window.y - cg.minY


        let cocoaX =
            cocoa.minX + localX


        let cocoaY =
            cocoa.maxY
            - localYFromTop
            - window.height


        return (
            NSRect(
                x: cocoaX,
                y: cocoaY,

                width:
                    window.width,

                height:
                    window.height
            ),

            mapping.screen
        )
    }


    // ========================================================
    // Overlay frame
    // ========================================================

    private func overlayFrame(
        for window:
            ConversationWindow
    ) -> NSRect? {

        guard let converted =
            cocoaWindowRect(window)
        else {
            return nil
        }


        let rect =
            converted.rect

        let visible =
            converted.screen.visibleFrame


        var width =
            min(
                maximumOverlayWidth,

                max(
                    minimumOverlayWidth,
                    rect.width * 0.55
                )
            )


        width =
            min(
                width,
                visible.width
            )


        var x =
            rect.midX -
            width / 2


        x =
            max(
                visible.minX,

                min(
                    x,
                    visible.maxX - width
                )
            )


        // ----------------------------------------------------
        // Above
        // ----------------------------------------------------

        let aboveY =
            rect.maxY +
            overlayGap


        if aboveY +
            overlayHeight
            <= visible.maxY {

            return NSRect(
                x: x,
                y: aboveY,

                width: width,
                height:
                    overlayHeight
            )
        }


        // ----------------------------------------------------
        // Below
        // ----------------------------------------------------

        let belowY =
            rect.minY
            - overlayGap
            - overlayHeight


        if belowY >=
            visible.minY {

            return NSRect(
                x: x,
                y: belowY,

                width: width,
                height:
                    overlayHeight
            )
        }


        return nil
    }
}


// ============================================================
// App Delegate
// ============================================================

final class AppDelegate:
    NSObject,
    NSApplicationDelegate {

    private let controller =
        OverlayController()


    func applicationDidFinishLaunching(
        _ notification:
            Notification
    ) {

        NSApp.setActivationPolicy(
            .accessory
        )

        controller.start()
    }
}
