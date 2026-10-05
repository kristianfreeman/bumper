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
            .shadowWhen(hovering, color: .black.opacity(0.3), radius: 14, y: 8)
            .animation(.spring(duration: 0.25), value: hovering)
            .onHover { hovering = $0 }
    }
}
#endif

extension View {
    /// A shadow only while `on`: an invisible one (opacity 0) is still drawn,
    /// an offscreen pass per view — dozens of cards made scrolling janky.
    @ViewBuilder public func shadowWhen(_ on: Bool, color: Color, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View {
        if on { shadow(color: color, radius: radius, x: x, y: y) } else { self }
    }
}

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

#if os(tvOS) || os(macOS)
public typealias PlatformMoveDirection = MoveCommandDirection
#else
public enum PlatformMoveDirection { case up, down, left, right }
#endif

extension View {
    /// Arrow presses (remote / keyboard); nothing on touch.
    @ViewBuilder public func tvMoveCommand(perform action: ((PlatformMoveDirection) -> Void)?) -> some View {
        #if os(tvOS) || os(macOS)
        onMoveCommand(perform: action)
        #else
        self
        #endif
    }

    /// The remote's Play/Pause button; nothing elsewhere (Space on the Mac is a key command).
    @ViewBuilder public func tvPlayPauseCommand(perform action: (() -> Void)?) -> some View {
        #if os(tvOS)
        onPlayPauseCommand(perform: action)
        #else
        self
        #endif
    }
}

extension View {
    /// Pages draw their own titles. The TV: no navigation bar (Menu goes
    /// back). iPhone/iPad: a clear bar, so a page opened from another keeps
    /// the system's Back button and swipe back (hiding the bar took both).
    /// The Mac's window keeps its toolbar (with its own Back).
    @ViewBuilder public func hidesNavigationBar() -> some View {
        #if os(tvOS)
        toolbar(.hidden, for: .navigationBar)
        #elseif os(iOS)
        toolbarBackground(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// The bottom of the stack (the tabs themselves): no bar at all.
    @ViewBuilder public func hidesNavigationBarEntirely() -> some View {
        #if os(macOS)
        self
        #else
        toolbar(.hidden, for: .navigationBar)
        #endif
    }
}

extension View {
    /// Full screen over everything: a cover on TV/iPhone/iPad; on the Mac,
    /// the whole window (a window can't be covered; the player fills it).
    @ViewBuilder public func fullScreen<Item: Identifiable, Content: View>(item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        #if os(macOS)
        overlay {
            if let value = item.wrappedValue {
                content(value)
                    .transition(.opacity)
                    .onExitCommand { item.wrappedValue = nil }
            }
        }
        .animation(.easeOut(duration: 0.2), value: item.wrappedValue?.id)
        #else
        fullScreenCover(item: item, content: content)
        #endif
    }

    @ViewBuilder public func fullScreen<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(macOS)
        overlay {
            if isPresented.wrappedValue {
                content()
                    .transition(.opacity)
                    .onExitCommand { isPresented.wrappedValue = false }
            }
        }
        .animation(.easeOut(duration: 0.2), value: isPresented.wrappedValue)
        #else
        fullScreenCover(isPresented: isPresented, content: content)
        #endif
    }
}

extension View {
    /// No home indicator / system overlays over the video (none on the Mac).
    @ViewBuilder public func hidesSystemOverlays() -> some View {
        #if os(macOS)
        self
        #else
        persistentSystemOverlays(.hidden)
        #endif
    }
}

extension View {
    /// Focused cards lift past a scroll view's edge on the TV; elsewhere
    /// content stays inside (on the Mac it drew over the sidebar).
    @ViewBuilder public func tvScrollClipDisabled() -> some View {
        #if os(tvOS)
        scrollClipDisabled()
        #else
        self
        #endif
    }

    /// Gives the pages inside this the width they're offered, as
    /// `\.pageWidth` (the shared navigation stack wraps every page in it).
    public func readsPageWidth() -> some View { modifier(PageWidthReader()) }
}

extension EnvironmentValues {
    /// The page's usable width: what it's offered, inside the safe area (on
    /// the Mac that leaves out the sidebar) and the page margins. Pages size
    /// their cards from it.
    @Entry public var pageWidth: CGFloat = 1600
}

/// Read during layout from a GeometryReader, which takes exactly the space
/// it's offered whatever its content asks for. Pages used to measure
/// themselves and keep the width as state: a beat behind every resize, so a
/// window resize or the Mac's sidebar opening laid out the page twice (or,
/// when the content widened the column, never settled).
private struct PageWidthReader: ViewModifier {
    func body(content: Content) -> some View {
        GeometryReader { geo in
            content.environment(\.pageWidth, Self.usable(geo))
        }
    }

    private static func usable(_ geo: GeometryProxy) -> CGFloat {
        // The TV's scroll views run under its sideways safe area (the
        // screen's overscan), so its pages lay out from the full width.
        let width = Platform.isTV ? geo.size.width + geo.safeAreaInsets.leading : geo.size.width
        return max(0, (width - 2 * Layout.horizontalMargin).rounded(.down))
    }
}
