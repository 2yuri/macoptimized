#if DEBUG
import AppKit

/// Development aid: `MACOPT_SNAPSHOT=/tmp/shot.png` renders the window to a PNG after
/// `MACOPT_SNAPSHOT_DELAY` seconds (default 2) and quits. Lets you check the UI without screen recording.
enum DebugSnapshot {
    static let env = ProcessInfo.processInfo.environment

    static func scheduleIfRequested() {
        guard let path = env["MACOPT_SNAPSHOT"] else { return }
        let delay = Double(env["MACOPT_SNAPSHOT_DELAY"] ?? "") ?? 2
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let view = NSApp.windows.first?.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            exit(0)
        }
    }
}
#endif
