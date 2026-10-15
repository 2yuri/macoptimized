import AppKit
import SwiftUI

@main
struct MacOptimizedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        Fonts.register()
    }

    var body: some Scene {
        WindowGroup("MacOptimized") {
            RootView()
                .frame(minWidth: 1100, minHeight: 720)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare SwiftPM executable (no .app bundle).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            for window in NSApp.windows {
                window.isMovableByWindowBackground = true
                window.backgroundColor = NSColor(Theme.bg)
            }
        }
        #if DEBUG
        DebugSnapshot.scheduleIfRequested()
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

enum Tab: String, CaseIterable, Identifiable {
    case care, free, lens
    var id: String { rawValue }
}

struct RootView: View {
    @State private var tab: Tab = {
        #if DEBUG
        if let t = DebugSnapshot.env["MACOPT_TAB"].flatMap(Tab.init(rawValue:)) { return t }
        #endif
        return .care
    }()
    @State private var hasFullDiskAccess = FullDiskAccess.isGranted
    @AppStorage("onboarding.skipped") private var skippedOnboarding = false
    @StateObject private var disk = DiskStatus()
    @StateObject private var care = CareModel()
    @StateObject private var free = FreeModel()
    @StateObject private var lens = LensModel()

    private var showsOnboarding: Bool { !hasFullDiskAccess && !skippedOnboarding }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(tab: $tab, freeSpace: disk.freeText, showsNav: !showsOnboarding)
            ZStack {
                if showsOnboarding {
                    OnboardingView { skippedOnboarding = true }
                } else {
                    // Models live here, so a scan keeps running while another tab is shown.
                    switch tab {
                    case .care: CareView(model: care)
                    case .free: FreeView(model: free)
                    case .lens: LensView(model: lens)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg)
        .ignoresSafeArea(.container, edges: .top)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasFullDiskAccess = FullDiskAccess.isGranted
            disk.refresh()
        }
    }
}

/// Window controls sit on the left (native), tabs in the middle, free space on the right.
private struct TopBar: View {
    @Binding var tab: Tab
    let freeSpace: String
    let showsNav: Bool

    var body: some View {
        ZStack {
            if showsNav {
                HStack(spacing: 40) {
                    ForEach(Array(Tab.allCases.enumerated()), id: \.element) { i, t in
                        Button { tab = t } label: {
                            VStack(spacing: 6) {
                                Text(t.rawValue).typeface(.mono, tab == t ? Theme.text : Theme.muted)
                                Circle().fill(tab == t ? Theme.accent : .clear).frame(width: 4, height: 4)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                    }
                }
                .padding(.top, 8)
            }
            HStack {
                Spacer()
                Text(freeSpace).typeface(.monoSmall, Theme.muted)
            }
            .padding(.trailing, 24)
        }
        .frame(height: 56)
    }
}

@MainActor
final class DiskStatus: ObservableObject {
    @Published var freeText = ""
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        freeText = "\(Bytes.format(Volumes.available())) free"
    }
}
