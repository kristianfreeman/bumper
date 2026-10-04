#if os(tvOS)
public import SwiftUI

/// The app's one button: a circle with an icon (or an image) at rest, that
/// opens into a capsule showing its title when focused.
///
///     Pill("Sleep Timer", systemImage: "moon.zzz", active: timer.isActive) { … }
///     Pill("Play", systemImage: "play.fill", prominent: true, size: .large) { … }
///     Pill("Kristian") { Avatar() } action: { … }        // an image instead of an icon
///
/// States: **active** (on — an accent ring and tint), **prominent** (the
/// page's main action — accent fill), **disabled** (dimmed, not focusable),
/// and **focused** (white, lifted, title showing).
public enum PillSize: Sendable {
    case small, regular, large
    public var diameter: CGFloat {
        switch self {
        case .small: 64
        case .regular: 80
        case .large: 112
        }
    }
}

public struct Pill<Icon: View>: View {
    public typealias Size = PillSize

    let title: String
    let detail: String?
    let size: Size
    let active: Bool
    let prominent: Bool
    let alwaysShowsTitle: Bool
    let icon: Icon
    let action: () -> Void

    public init(_ title: String, detail: String? = nil, size: Size = .regular, active: Bool = false, prominent: Bool = false,
                alwaysShowsTitle: Bool = false, @ViewBuilder icon: () -> Icon, action: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.size = size
        self.active = active
        self.prominent = prominent
        self.alwaysShowsTitle = alwaysShowsTitle
        self.icon = icon()
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            PillFace(title, detail: detail, size: size, active: active, prominent: prominent, alwaysShowsTitle: alwaysShowsTitle) { icon }
        }
        .buttonStyle(PillButtonStyle())
        .accessibilityLabel(title)
        .accessibilityValue(detail ?? "")
    }
}

extension Pill where Icon == PillSymbol {
    public init(_ title: String, systemImage: String, detail: String? = nil, size: Size = .regular, active: Bool = false, prominent: Bool = false,
                alwaysShowsTitle: Bool = false, action: @escaping () -> Void) {
        self.init(title, detail: detail, size: size, active: active, prominent: prominent, alwaysShowsTitle: alwaysShowsTitle,
                  icon: { PillSymbol(systemImage, size: size) }, action: action)
    }
}

/// An SF Symbol sized for a pill.
public struct PillSymbol: View {
    let name: String
    let size: PillSize
    public init(_ name: String, size: PillSize) {
        self.name = name
        self.size = size
    }
    public var body: some View {
        Image(systemName: name).font(.system(size: size.diameter * 0.38, weight: .semibold))
    }
}

/// The pill's look, for any label — use it for a `Menu` too:
///
///     Menu { … } label: { PillFace("Speed", …) { PillSymbol("speedometer", size: .regular) } }
///         .buttonStyle(PillButtonStyle())
public struct PillFace<Icon: View>: View {
    let title: String
    let detail: String?
    let size: PillSize
    let active: Bool
    let prominent: Bool
    let alwaysShowsTitle: Bool
    let icon: Icon
    @Environment(\.isFocused) private var focused
    @Environment(\.isEnabled) private var enabled
    @Environment(\.theme) private var theme

    public init(_ title: String, detail: String? = nil, size: PillSize = .regular, active: Bool = false, prominent: Bool = false,
                alwaysShowsTitle: Bool = false, @ViewBuilder icon: () -> Icon) {
        self.title = title
        self.detail = detail
        self.size = size
        self.active = active
        self.prominent = prominent
        self.alwaysShowsTitle = alwaysShowsTitle
        self.icon = icon()
    }

    private var open: Bool { focused || alwaysShowsTitle }

    public var body: some View {
        let d = size.diameter
        HStack(spacing: d * 0.16) {
            icon
                .frame(width: d * 0.62, height: d * 0.62)
                .clipShape(.circle)
            if open {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(size == .large ? .title3.weight(.semibold) : .callout.weight(.semibold))
                    if let detail { Text(detail).font(.caption2).opacity(0.7) }
                }
                .lineLimit(1)
                .fixedSize()
                .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .leading)))
            }
        }
        .foregroundStyle(foreground)
        .padding(.leading, d * 0.19)
        .padding(.trailing, open ? d * 0.38 : d * 0.19)
        .frame(minWidth: d, minHeight: d)
        .background(background, in: .capsule)
        .overlay {
            if active && !focused { Capsule().strokeBorder(theme.accent, lineWidth: 3) }
        }
        .scaleEffect(focused ? 1.08 : 1)
        .shadow(color: .black.opacity(focused ? 0.35 : 0), radius: 18, y: 8)
        .opacity(enabled ? 1 : 0.4)
        .animation(.spring(duration: 0.3, bounce: 0.2), value: focused)
        .animation(.easeOut(duration: 0.2), value: active)
    }

    private var foreground: Color {
        if focused { return .black }
        if prominent { return .black }
        return active ? theme.accent : .white
    }

    private var background: Color {
        if focused { return .white }
        if prominent { return theme.accent }
        return active ? theme.accent.opacity(0.22) : .white.opacity(0.14)
    }
}

/// No system focus effect: the face draws its own.
public struct PillButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.85 : 1)
    }
}
#endif
