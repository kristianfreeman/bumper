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

    /// Keeps `width` at this view's width minus the page margins — once a
    /// resize settles (a window drag, the Mac's sidebar opening), not on
    /// every frame of it: each update re-lays out the whole page.
    public func tracksPageWidth(_ width: Binding<CGFloat>) -> some View {
        modifier(PageWidth(width: width))
    }
}

private struct PageWidth: ViewModifier {
    @Binding var width: CGFloat
    @Environment(\.pageViewportWidth) private var viewport
    @State private var pending: Task<Void, Never>?
    @State private var measured = false

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width - $0.safeAreaInsets.trailing } action: { w in
                // The Mac measures in its shell instead: measured here, the
                // page's width followed its own content while the sidebar
                // opened, and never settled.
                guard viewport == nil else { return }
                apply(w)
            }
            .onChange(of: viewport, initial: true) { _, w in
                if let w { apply(w) }
            }
    }

    private func apply(_ page: CGFloat) {
        let new = page - 2 * Layout.horizontalMargin
        guard abs(new - width) > 0.5 else { return }
        pending?.cancel()
        if Platform.isTV || !measured {
            measured = true
            width = new                                   // the first measure (and the TV, which never resizes): at once
            return
        }
        pending = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.2)) { width = new }
        }
    }
}

extension EnvironmentValues {
    /// The Mac's page width, measured once by the window's shell (its size
    /// already leaves out what the sidebar covers).
    @Entry public var pageViewportWidth: CGFloat? = nil
}

extension View {
    /// Measures this (a page column whose size doesn't follow its content)
    /// and gives pages inside it that width.
    public func measuresPageViewport() -> some View { modifier(ViewportMeasure()) }
}

private struct ViewportMeasure: ViewModifier {
    @State private var width: CGFloat?

    func body(content: Content) -> some View {
        content
            .environment(\.pageViewportWidth, width)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}
