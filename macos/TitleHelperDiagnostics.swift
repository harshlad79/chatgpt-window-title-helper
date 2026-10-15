import Foundation

// Diagnostics intentionally exclude raw conversation titles and message text.
// Only runtime state, window counts, and timing are persisted.
final class TitleHelperDiagnostics {
    static let shared = TitleHelperDiagnostics()
    private let writer: FileHandle?
    private let lock = NSLock()

    private init() {
        let folder = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Logs/ChatGPTTitleHelper", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("title-helper-event-current.log")
        try? Data().write(to: file, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: file.path)
        writer = try? FileHandle(forWritingTo: file)
    }

    func record(_ summary: String) {
        lock.lock()
        defer { lock.unlock() }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        if let payload = (timestamp + " " + summary + "\n").data(using: .utf8) {
            try? writer?.write(contentsOf: payload)
        }
    }
}
