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

private let refreshInterval: TimeInterval = 0.5
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

func findWebArea(
    _ root: AXUIElement
) -> AXUIElement? {

    var queue: [AXUIElement] = [root]

    var index = 0
    var examined = 0

    while index < queue.count &&
          examined < 600 {

        let element = queue[index]

        index += 1
        examined += 1

        if axString(
            element,
            kAXRoleAttribute
        ) == "AXWebArea" {

            return element
        }

        queue.append(
            contentsOf:
                axChildren(element)
        )
    }

    return nil
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

                    return                }


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

    private var timer: Timer?

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

        loadPreferences()
        setupMenu()

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

        overlayPanel?.orderOut(nil)

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

    private func refresh() {

        guard AXIsProcessTrusted()
        else {

            overlayPanel?.orderOut(nil)

            overlayStatusItem.title =
                "오버레이: 손쉬운 사용 권한 필요"

            requestAccessibilityPermission()

            return
        }


        guard let targetApp =
            currentChatGPTApp()
        else {

            targetPID = 0
            targetAX = nil

            overlayPanel?.orderOut(nil)

            overlayStatusItem.title =
                "오버레이: ChatGPT 대기"

            nativeStatusItem.title =
                nativeTitleEnabled
                ? "Dock: ChatGPT 대기"
                : "Dock: 꺼짐"

            return        }


        let pid =
            targetApp.processIdentifier


        // ----------------------------------------------------
        // ChatGPT restarted
        // ----------------------------------------------------

        if pid != targetPID ||
           targetAX == nil {

            targetPID = pid

            targetAX =
                AXUIElementCreateApplication(
                    pid
                )

            nativeSync
                .resetForNewPID()

            lastNativeSync =
                Date.distantPast


            if let targetAX {

                _ =
                    AXUIElementSetAttributeValue(
                        targetAX,
                        "AXEnhancedUserInterface"
                            as CFString,
                        kCFBooleanTrue
                    )
            }
        }


        guard let targetAX else {
            return
        }


        // Chromium renderer가 새로 만들어졌을 때
        // AXWebArea 노출 유지.
        _ =
            AXUIElementSetAttributeValue(
                targetAX,
                "AXEnhancedUserInterface"
                    as CFString,
                kCFBooleanTrue
            )


        let windows =
            collectConversationWindows(
                axApp: targetAX
            )


        // ----------------------------------------------------
        // Overlay
        // ----------------------------------------------------

        updateOverlay(
            windows: windows
        )


        // ----------------------------------------------------
        // Native / Dock title
        // ----------------------------------------------------

        if nativeTitleEnabled {

            let now = Date()

            if now.timeIntervalSince(
                lastNativeSync
            ) >= nativeSyncInterval {

                lastNativeSync = now


                nativeSync.sync(
                    pid: pid,
                    windows: windows
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

        } else {

            nativeStatusItem.title =
                "Dock: 꺼짐"
        }
    }


    // ========================================================
    // Collect ChatGPT conversation windows
    // ========================================================

    private func collectConversationWindows(
        axApp: AXUIElement
    ) -> [ConversationWindow] {

        guard let windows =
            axGet(
                axApp,
                kAXWindowsAttribute
            ) as? [AXUIElement]
        else {
            return []
        }


        var result:
            [ConversationWindow] = []


        for window in windows {

            if axBool(
                window,
                kAXMinimizedAttribute
            ) == true {

                continue
            }


            guard let webArea =
                findWebArea(window)
            else {
                continue
            }


            let title =
                axString(
                    webArea,
                    kAXTitleAttribute
                )
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )


            // Pet / generic / 새 대화 등
            guard !title.isEmpty,
                  title != "ChatGPT"
            else {
                continue
            }


            guard let position =
                    axPoint(window),
                  let size =
                    axSize(window)
            else {
                continue
            }


            guard size.width > 100,
                  size.height > 100
            else {
                continue
            }


            let isMain =
                axBool(
                    window,
                    kAXMainAttribute
                ) ?? false


            result.append(
                ConversationWindow(
                    title: title,

                    x: position.x,
                    y: position.y,

                    width:
                        size.width,

                    height:
                        size.height,

                    isMain:
                        isMain
                )
            )
        }


        return result
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


// ============================================================
// Main
// ============================================================

let app =
    NSApplication.shared

let delegate =
    AppDelegate()

app.delegate =
    delegate

app.run()