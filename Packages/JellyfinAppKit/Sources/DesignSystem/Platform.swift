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
    /// Pages draw their own titles: no navigation bar (the Mac's window keeps its toolbar).
    @ViewBuilder public func hidesNavigationBar() -> some View {
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
