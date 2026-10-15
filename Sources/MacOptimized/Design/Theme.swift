import AppKit
import CoreText
import SwiftUI

/// Design tokens. Dark-first: the app always renders in its dark palette.
enum Theme {
    static let bg = Color(hex: 0x0A0A0B)
    static let text = Color(hex: 0xEDEDEC)
    static let muted = Color(hex: 0xA3A3A9)
    static let line = Color(hex: 0x3A3A40)
    static let accent = Color(hex: 0x6FD6FF)
    static let danger = Color(hex: 0xFF6B6B)
    static let sheet = Color(hex: 0x111113)
    static let toast = Color(hex: 0x151517)
    static let scrim = Color.black.opacity(0.72)

    static let hairline: CGFloat = 1.5
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

// MARK: - Type

enum Typeface {
    case display, big, body, mono, monoSmall

    var font: Font {
        switch self {
        case .display: Fonts.inter(168, .light)
        case .big: Fonts.inter(72, .light)
        case .body: Fonts.inter(15, .medium)
        case .mono: Fonts.mono(13, .medium)
        case .monoSmall: Fonts.mono(12, .medium)
        }
    }

    var tracking: CGFloat {
        switch self {
        case .display: -8
        case .big: -3
        case .body: 0
        case .mono: 0.3
        case .monoSmall: 0.4
        }
    }
}

extension View {
    func typeface(_ t: Typeface, _ color: Color = Theme.text) -> some View {
        font(t.font).tracking(t.tracking).foregroundStyle(color)
    }
}

/// Inter and JetBrains Mono ship in Resources/Fonts and are registered at launch.
/// If they can't be found the system fonts are used instead.
enum Fonts {
    enum Weight { case light, regular, medium, semibold }

    static func inter(_ size: CGFloat, _ weight: Weight) -> Font {
        let name = switch weight {
        case .light: "Inter-Light"
        case .regular: "Inter-Regular"
        case .medium: "Inter-Medium"
        case .semibold: "Inter-SemiBold"
        }
        return available ? .custom(name, fixedSize: size) : .system(size: size, weight: weight.system)
    }

    static func mono(_ size: CGFloat, _ weight: Weight) -> Font {
        let name = switch weight {
        case .light, .regular: "JetBrainsMono-Regular"
        case .medium: "JetBrainsMono-Medium"
        case .semibold: "JetBrainsMono-SemiBold"
        }
        return available ? .custom(name, fixedSize: size) : .system(size: size, weight: weight.system, design: .monospaced)
    }

    private(set) static var available = false

    static func register() {
        guard let dir = fontDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        let fonts = files.filter { $0.pathExtension == "ttf" }
        for url in fonts { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        available = NSFont(name: "Inter-Light", size: 12) != nil && NSFont(name: "JetBrainsMono-Medium", size: 12) != nil
    }

    /// Inside the .app bundle, or next to the sources when run with `swift run`.
    private static func fontDirectory() -> URL? {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Fonts")
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Fonts")
        return [bundled, source].compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

private extension Fonts.Weight {
    var system: Font.Weight {
        switch self {
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        }
    }
}
