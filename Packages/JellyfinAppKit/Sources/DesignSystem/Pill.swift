public import SwiftUI

/// The app's one button: a circle with an icon (or an image) at rest, that
/// opens into a capsule showing its title when focused.
///
///     Pill("Sleep Timer", systemImage: "moon.zzz", active: timer.isActive) { … }
///     Pill("Play", systemImage: "play.fill", prominent: true, size: .large) { … }
///     Pill("Sam") { Avatar() } action: { … }        // an image instead of an icon
///
/// States: **active** (on — an accent ring and tint), **prominent** (the
/// page's main action — accent fill), **disabled** (dimmed, not focusable),
/// and **focused** (white, lifted, title showing).
public enum PillSize: Sendable {
    case small, regular, large
    /// The TV's sizes, scaled for nearer screens.
    public var diameter: CGFloat {
        let tv: CGFloat = switch self {
        case .small: 64
        case .regular: 80
        case .large: 112
        }
        return (tv * Layout.pillScale).rounded()
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
    let fillsIcon: Bool
    let icon: Icon
    let action: () -> Void

    public init(_ title: String, detail: String? = nil, size: Size = .regular, active: Bool = false, prominent: Bool = false,
                alwaysShowsTitle: Bool = false, fillsIcon: Bool = false, @ViewBuilder icon: () -> Icon, action: @escaping () -> Void) {
        self.fillsIcon = fillsIcon
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
            PillFace(title, detail: detail, size: size, active: active, prominent: prominent, alwaysShowsTitle: alwaysShowsTitle, fillsIcon: fillsIcon) { icon }
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
    /// An image (a profile picture) fills the circle instead of sitting in it like a symbol.
    var fillsIcon = false
    let icon: Icon
    @Environment(\.isFocused) private var focused
    @Environment(\.isEnabled) private var enabled
    @Environment(\.theme) private var theme

    public init(_ title: String, detail: String? = nil, size: PillSize = .regular, active: Bool = false, prominent: Bool = false,
                alwaysShowsTitle: Bool = false, fillsIcon: Bool = false, @ViewBuilder icon: () -> Icon) {
        self.fillsIcon = fillsIcon
        self.title = title
        self.detail = detail
        self.size = size
        self.active = active
        self.prominent = prominent
        self.alwaysShowsTitle = alwaysShowsTitle
        self.icon = icon()
    }

    private var open: Bool { focused || alwaysShowsTitle }
    /// `open`, changed inside an animation: tvOS moves focus outside any
    /// transaction, so the label (and every neighbour making room for it)
    /// jumped. Changed here with a spring, the pill grows and shrinks and the
    /// row around it moves with it — every pill in the app.
    @State private var shown: Bool?
    @Environment(\.pillCaptions) private var captions
    @Environment(\.pillCaption) private var caption

    public var body: some View {
        // Touch and the Mac have no focus to open a pill and say what it
        // is: where asked (a detail page's actions), its name sits beneath.
        if captions && !alwaysShowsTitle && !Platform.isTV {
            VStack(spacing: 6) {
                face
                Text(caption ?? title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
            }
        } else {
            face
        }
    }

    @ViewBuilder private var face: some View {
        let d = size.diameter
        let open = shown ?? self.open
        HStack(spacing: d * 0.16) {
            icon
                .frame(width: d * (fillsIcon ? 0.9 : 0.62), height: d * (fillsIcon ? 0.9 : 0.62))
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
        .padding(.leading, d * (fillsIcon ? 0.05 : 0.19))
        .padding(.trailing, open ? d * 0.38 : d * 0.19)
        .frame(minWidth: d, minHeight: d)
        .background(background, in: .capsule)
        .overlay {
            if active && !focused { Capsule().strokeBorder(theme.accent, lineWidth: 3) }
        }
        .scaleEffect(focused ? 1.08 : 1)
        .shadowWhen(focused, color: .black.opacity(0.35), radius: 18, y: 8)
        .opacity(enabled ? 1 : 0.4)
        .animation(.spring(duration: 0.3, bounce: 0.2), value: focused)
        .animation(.easeOut(duration: 0.2), value: active)
        .onChange(of: self.open, initial: true) { was, now in
            if shown == nil || was == now { shown = now; return }
            withAnimation(.spring(duration: 0.34, bounce: 0.16)) { shown = now }
        }
    }

    private var foreground: Color {
        if focused { return .black }
        if prominent { return theme.colorScheme == .light ? .white : .black }
        return active ? theme.accent : theme.primaryText
    }

    private var background: Color {
        if focused { return .white }
        if prominent { return theme.accent }
        return active ? theme.accent.opacity(0.22) : theme.primaryText.opacity(0.12)
    }
}

extension EnvironmentValues {
    /// Pills show their name beneath them (off the TV, where focus would).
    @Entry public var pillCaptions = false
    /// A pill's short name for its caption ("Restart" for Play from Beginning).
    @Entry public var pillCaption: String? = nil
}

extension View {
    /// The short name a pill shows beneath it, where pills show one.
    public func pillCaption(_ text: String) -> some View { environment(\.pillCaption, text) }
}

/// No system focus effect: the face draws its own.
public struct PillButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.85 : 1)
    }
}
