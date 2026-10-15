import SwiftUI

/// The one call to action per screen: accent mono text, an arrow and an underline.
struct ActionLink: View {
    let title: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title).font(Fonts.mono(14, .semibold)).tracking(0.3)
                Image(systemName: "arrow.right").font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Theme.accent)
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.accent).frame(height: Theme.hairline) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}

/// Plain mono text button ("cancel  esc", "stop  esc").
struct TextButton: View {
    let title: String
    var hint: String?
    var color = Theme.text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title).typeface(.mono, color)
                if let hint { Text(hint).typeface(.monoSmall, Theme.muted) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Selected = filled accent dot, unselected = empty ring.
struct Dot: View {
    let isOn: Bool

    var body: some View {
        Circle()
            .fill(isOn ? Theme.accent : .clear)
            .overlay(Circle().strokeBorder(isOn ? .clear : Theme.muted, lineWidth: Theme.hairline))
            .frame(width: 10, height: 10)
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.line).frame(height: Theme.hairline) }
}

struct VerticalHairline: View {
    var body: some View { Rectangle().fill(Theme.line).frame(width: Theme.hairline) }
}

struct GroupHeader: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).typeface(.monoSmall, Theme.muted)
            Hairline()
        }
    }
}

/// A selectable list row: dot, label, optional note and a mono value on the right.
struct SelectRow: View {
    let label: String
    let value: String
    let isOn: Bool
    var note: String?
    var showsDot = true
    var onToggle: (() -> Void)?
    var onOpen: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                if showsDot { Dot(isOn: isOn) }
                Text(label)
                    .typeface(.body, isOn ? Theme.text : Theme.muted)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let note { Text(note).typeface(.monoSmall, Theme.muted) }
                Text(value).typeface(.mono, isOn ? Theme.text : Theme.muted).monospacedDigit()
                if onOpen != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(hovering ? Theme.text : Theme.muted)
                }
            }
            .padding(.vertical, 12)
            Hairline()
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onToggle?() }
        .simultaneousGesture(TapGesture(count: 2).onEnded { onOpen?() })
    }
}

/// Key/value line used inside modals.
struct FactRow: View {
    let key: String
    let value: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(key).typeface(.mono).frame(width: 110, alignment: .leading)
                Text(value).typeface(.body, Theme.muted).frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 12)
            Hairline()
        }
    }
}

/// Big thin number with a small unit, e.g. "37.6 GB".
struct BigNumber: View {
    let value: String
    let unit: String
    var size: CGFloat = 168
    var unitSize: CGFloat = 40
    var unitIsMono = false

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: unitIsMono ? 8 : 12) {
            Text(value)
                .font(Fonts.inter(size, .light))
                .tracking(size >= 160 ? -8 : -size / 19)
                .foregroundStyle(Theme.text)
                .monospacedDigit()
            Text(unit)
                .font(unitIsMono ? Fonts.mono(unitSize, .medium) : Fonts.inter(unitSize, .light))
                .tracking(unitIsMono ? 0.3 : -1)
                .foregroundStyle(Theme.muted)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}

// MARK: - Overlays

/// Scrim + dark panel with a hairline. Content gets 28 pt between blocks.
struct ModalSheet<Content: View>: View {
    var width: CGFloat = 520
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Theme.scrim.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 28) { content }
                .padding(36)
                .frame(width: width)
                .background(Theme.sheet, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line, lineWidth: Theme.hairline))
        }
        .transition(.opacity)
    }
}

struct ModalHeader: View {
    var eyebrow = "confirm"
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow).typeface(.monoSmall, Theme.muted)
            Text(title).font(Fonts.inter(44, .light)).tracking(-1.5).foregroundStyle(Theme.text)
        }
    }
}

struct ModalActions: View {
    let primary: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        HStack(spacing: 32) {
            Spacer()
            TextButton(title: "cancel", hint: "esc", color: Theme.muted, action: onCancel)
                .keyboardShortcut(.cancelAction)
            ActionLink(title: primary, action: onConfirm)
                .keyboardShortcut(.defaultAction)
        }
    }
}

struct Toast: Equatable {
    var text: String
    var isError = false
}

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(toast.isError ? Theme.danger : Theme.accent).frame(width: 8, height: 8)
            Text(toast.text).typeface(.mono)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .background(Theme.toast, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: Theme.hairline))
        .shadow(color: .black.opacity(0.6), radius: 16, y: 12)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

extension View {
    /// Shows a toast pill under the top bar and hides it after a few seconds.
    func toast(_ toast: Binding<Toast?>) -> some View {
        overlay(alignment: .top) {
            if let t = toast.wrappedValue {
                ToastView(toast: t)
                    .padding(.top, 8)
                    .task(id: t) {
                        try? await Task.sleep(nanoseconds: 3_500_000_000)
                        withAnimation { toast.wrappedValue = nil }
                    }
            }
        }
        .animation(.easeOut(duration: 0.25), value: toast.wrappedValue)
    }
}

// MARK: - Ring and bubble

/// Thin ring with an accent arc. Angles are degrees clockwise from 12 o'clock.
struct Ring: View {
    var start: Double = 0
    var sweep: Double
    /// Where the round head sits: at the arc's start or its end.
    var headAtEnd = true
    var diameter: CGFloat = 320

    var body: some View {
        let r = diameter / 2 - 2
        let headAngle = (headAtEnd ? start + sweep : start) * .pi / 180
        ZStack {
            Circle().strokeBorder(Theme.line, lineWidth: 2)
            Circle()
                .inset(by: 2)
                .trim(from: 0, to: max(0.0001, min(1, sweep / 360)))
                .stroke(Theme.accent, lineWidth: 4)
                .rotationEffect(.degrees(start - 90))
            Circle().fill(Theme.accent).frame(width: 10, height: 10)
                .offset(x: r * sin(headAngle), y: -r * cos(headAngle))
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeInOut(duration: 0.4), value: sweep)
    }
}

/// A sphere: soft light from the top left, two inner shadows and a translucent rim.
struct BubbleShape: View {
    let diameter: CGFloat
    var selected = false

    var body: some View {
        let k = max(0.35, min(1, diameter / 300))
        let light = selected ? Theme.accent : Color.white
        Circle()
            .fill(
                RadialGradient(
                    stops: [
                        .init(color: light.opacity(selected ? 0.09 : 0.08), location: 0),
                        .init(color: light.opacity(0.02), location: 0.55),
                        .init(color: .clear, location: 1),
                    ],
                    center: UnitPoint(x: 0.35, y: 0.28), startRadius: 0, endRadius: diameter * 0.65
                )
                .shadow(.inner(color: selected ? Theme.accent.opacity(0.25) : .white.opacity(0.15), radius: 11 * k, x: 6 * k, y: 8 * k))
                .shadow(.inner(color: .black.opacity(0.7), radius: 15 * k, x: -10 * k, y: -14 * k))
            )
            .overlay(Circle().strokeBorder(selected ? Theme.accent : .white.opacity(0.12), lineWidth: Theme.hairline))
            .shadow(color: selected ? Theme.accent.opacity(0.15) : .clear, radius: 12)
            .frame(width: diameter, height: diameter)
    }
}
