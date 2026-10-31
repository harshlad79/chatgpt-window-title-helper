// Read-only, standalone Mac diagnostic. Does not require Accessibility permission.
// CG layer-zero windows are NOT equivalent to native AXWindows or conversations.
// Never records titles, URLs, message contents, or changes application state.
import AppKit
import CoreGraphics
import Foundation

struct Window: Codable {
    let id: UInt32
    let onScreen: Bool
}
struct Sample: Codable {
    let layerZeroCount: Int
    let onScreenCount: Int
    let offScreenCount: Int
    let windows: [Window]
}
struct Report: Codable {
    let source: String
    let pid: Int32
    let samples: [Sample]
    let stableIDs: [UInt32]
    let transientIDs: [UInt32]
    let nativeAXWindowCountVerified: Bool
    let mutated: Bool
}

guard let app = NSWorkspace.shared.runningApplications.first(where: {
    $0.bundleIdentifier == "com.openai.codex" && !$0.isTerminated
}) else {
    fputs("ChatGPT not running\n", stderr)
    exit(2)
}
func capture(_ pid: Int32) -> Sample {
    let all = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    let filtered = all.filter {
        (($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? -1) == pid &&
        (($0[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -999) == 0
    }
    let windows = filtered.compactMap { item -> Window? in
        guard let number = item[kCGWindowNumber as String] as? NSNumber else { return nil }
        let onScreen = (item[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
        return Window(id: number.uint32Value, onScreen: onScreen)
    }.sorted { $0.id < $1.id }
    return Sample(layerZeroCount: windows.count,
                  onScreenCount: windows.filter { $0.onScreen }.count,
                  offScreenCount: windows.filter { !$0.onScreen }.count,
                  windows: windows)
}
let first = capture(app.processIdentifier)
Thread.sleep(forTimeInterval: 0.5)
let second = capture(app.processIdentifier)
let ids1 = Set(first.windows.map { $0.id })
let ids2 = Set(second.windows.map { $0.id })
let report = Report(source: "CGWindowListCopyWindowInfo",
                    pid: app.processIdentifier,
                    samples: [first, second],
                    stableIDs: Array(ids1.intersection(ids2)).sorted(),
                    transientIDs: Array(ids1.symmetricDifference(ids2)).sorted(),
                    nativeAXWindowCountVerified: false,
                    mutated: false)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let data = try encoder.encode(report)
print(String(data: data, encoding: .utf8)!)
