import DesignSystem
public import Observation
public import SwiftUI


/// The iPhone/iPad's link to an Apple TV running the app (the companion):
/// the TV button in the corner (like a cast button), and Play on the TV.
/// The app sets it from its companion model; nil where there's none (the
/// TV itself, the Mac).
@MainActor
@Observable
public final class CastLink {
    /// The TV it's connected to, by name.
    public var connectedTo: String?
    /// Whether any TV has been seen on the network.
    public var available = false
    /// Plays an item on the connected TV.
    @ObservationIgnored public var play: (String) -> Void = { _ in }

    public init() {}
}

extension EnvironmentValues {
    @Entry var castLink: CastLink? = nil
    /// What the TV button opens: finding the TV, then steering it.
    @Entry var castPanel: AnyView? = nil
}

/// The corner's TV button: lit while connected; opens the panel.
struct CastButton: View {
    @Environment(\.castLink) private var cast
    @Environment(\.castPanel) private var panel
    @State private var showing = false

    var body: some View {
        if let cast, let panel {
            let connected = cast.connectedTo != nil
            Pill(connected ? "Connected to \(cast.connectedTo!)" : "Apple TV", systemImage: connected ? "tv.fill" : "tv", size: .small, active: connected) {
                showing = true
            }
            .accessibilityIdentifier("cast.button")
            .sheet(isPresented: $showing) {
                panel
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}
