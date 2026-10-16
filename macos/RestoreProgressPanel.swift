import AppKit

// Separate self-owned status window because the Dock context menu is dismissed
// while opening new native ChatGPT windows. Does not capture user keyboard input.
final class RestoreProgressPanel: NSObject {
    private var panel: NSPanel?
    private var label: NSTextField?
    private var subtitle: NSTextField?
    var onCancel: (() -> Void)?

    func show(_ state: WindowSessionRestoreQueue.Progress) {
        if panel == nil {
            let frame = NSRect(x: 0, y: 0, width: 355, height: 118)
            let p = NSPanel(contentRect: frame,
                styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
                backing: .buffered, defer: false)
            p.title = "ChatGPT 마지막 창 복원"
            p.level = .floating
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = NSView(frame: frame)
            let top = NSTextField(labelWithString: "")
            top.font = NSFont.boldSystemFont(ofSize: 13)
            top.frame = NSRect(x: 15, y: 71, width: 326, height: 25)
            let detail = NSTextField(labelWithString: "")
            detail.lineBreakMode = .byTruncatingMiddle
            detail.font = NSFont.systemFont(ofSize: 11)
            detail.textColor = .secondaryLabelColor
            detail.frame = NSRect(x: 15, y: 43, width: 326, height: 22)
            let cancel = NSButton(title: "취소", target: self,
                                  action: #selector(cancelClicked))
            cancel.frame = NSRect(x: 264, y: 10, width: 80, height: 28)
            view.addSubview(top)
            view.addSubview(detail)
            view.addSubview(cancel)
            p.contentView = view
            p.center()
            panel = p
            label = top
            subtitle = detail
        }
        let remaining = max(0, state.total - state.finished)
        label?.stringValue = state.running
            ? "복원 중: \(state.finished)/\(state.total)"
            : "복원 종료: \(state.finished)/\(state.total)"
        let failure = state.failed > 0 ? " · 실패 \(state.failed)" : ""
        subtitle?.stringValue = state.running
            ? (state.cancelled ? "현재 창 처리 후 취소" :
                (state.activeTitle ?? "다음 창 대기")) + failure
            : (state.cancelled ? "사용자가 취소함" :
                remaining == 0 ? "처리 완료" : "일부 처리되지 않음") + failure
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    @objc private func cancelClicked() {
        onCancel?()
    }
}
