import AppKit
import SwiftUI

enum FullDiskAccess {
    /// The TCC database is only readable by processes that have Full Disk Access.
    static var isGranted: Bool {
        let probe = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        let fd = open(probe.path, O_RDONLY)
        guard fd >= 0 else { return false }
        close(fd)
        return true
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct OnboardingView: View {
    let onSkip: () -> Void

    private let steps = ["open System Settings", "Privacy & Security › Full Disk Access", "turn on MacOptimized"]

    var body: some View {
        VStack(alignment: .leading, spacing: 48) {
            VStack(alignment: .leading, spacing: 24) {
                Text("before you start").typeface(.mono, Theme.muted)
                Text("Let MacOptimized\nsee the whole disk.")
                    .font(Fonts.inter(72, .light)).tracking(-3).lineSpacing(-4)
                    .foregroundStyle(Theme.text)
                Text("Without Full Disk Access, the Trash, Mail and parts of ~/Library stay invisible, so sizes come out smaller than they are. Everything runs on this Mac; nothing is uploaded.")
                    .typeface(.body, Theme.muted)
                    .font(Fonts.inter(16, .medium))
                    .lineSpacing(6)
                    .frame(width: 620, alignment: .leading)
            }
            Spacer()
            VStack(spacing: 0) {
                Hairline()
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(format: "%02d", i + 1)).typeface(.mono, Theme.accent)
                            Text(step).typeface(.body)
                        }
                        .padding(.top, 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            HStack {
                PrimaryButton(title: "open settings") { FullDiskAccess.openSettings() }
                    .keyboardShortcut(.defaultAction)
                Spacer()
                GhostButton(title: "continue without", action: onSkip)
            }
        }
        .padding(EdgeInsets(top: 40, leading: 120, bottom: 72, trailing: 120))
    }
}
