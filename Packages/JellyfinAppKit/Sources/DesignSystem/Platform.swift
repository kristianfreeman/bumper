public import SwiftUI

/// What differs between the TV, the Mac and the phone/tablet, in one place.
public enum Platform {
    #if os(tvOS)
    public static let isTV = true
    #else
    public static let isTV = false
    #endif
    #if os(macOS)
    public static let isMac = true
    #else
    public static let isMac = false
    #endif
    #if os(iOS)
    public static let isTouch = true
    #else
    public static let isTouch = false
    #endif
}

extension View {
    /// A focus section where there's a focus engine (TV, Mac); nothing on touch.
    @ViewBuilder public func tvFocusSection() -> some View {
        #if os(tvOS) || os(macOS)
        focusSection()
        #else
        self
        #endif
    }

    /// Menu on the remote / Escape on the Mac; nothing on touch (Back is a button there).
    @ViewBuilder public func tvExitCommand(perform action: (() -> Void)?) -> some View {
        #if os(tvOS) || os(macOS)
        onExitCommand(perform: action)
        #else
        self
        #endif
    }
}

extension View {
    /// The system's card lift: focus on the TV, the pointer on iPad; on the
    /// Mac, a gentle grow under the pointer.
    @ViewBuilder public func cardHighlight() -> some View {
        #if os(macOS)
        modifier(MacHoverLift())
        #else
        hoverEffect(.highlight)
        #endif
    }
}

#if os(macOS)
private struct MacHoverLift: ViewModifier {
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? 1.03 : 1)
            .shadow(color: .black.opacity(hovering ? 0.3 : 0), radius: 14, y: 8)
            .animation(.spring(duration: 0.25), value: hovering)
            .onHover { hovering = $0 }
    }
}
#endif

extension Color {
    /// For CoreGraphics drawing (fixed RGB theme colours).
    public var cgColorValue: CGColor {
        #if os(macOS)
        NSColor(self).cgColor
        #else
        UIColor(self).cgColor
        #endif
    }
}
