import Companion
import Foundation
import Network
import Observation

/// The phone's side: finds Apple TVs running the app, connects to one, and
/// mirrors what it shows.
@MainActor
@Observable
final class CompanionModel {
    struct TV: Identifiable, Hashable {
        let name: String
        let endpoint: NWEndpoint
        var id: String { name }
    }

    private(set) var tvs: [TV] = []
    /// The TV the phone is linked to: it always watches one quietly (what's
    /// playing there shows above the tabs), whether or not it's casting.
    private(set) var connectedTo: String?
    /// Sending to the TV: what's played on the phone starts there. Only
    /// when asked (the TV button), never just from opening the app.
    private(set) var casting = false
    /// The service name of the TV linked to (its Bonjour name).
    private var linked: String?
    private(set) var state: CompanionState?

    private let queue = DispatchQueue(label: "companion.phone")
    private var browser: NWBrowser?
    private var connection: CompanionConnection?

    /// Settings → Apple TV Remote.
    private var enabled = false

    func startBrowsing() {
        enabled = true
        guard browser == nil else { return }
        let b = NWBrowser(for: .bonjour(type: CompanionService.type, domain: nil), using: .tcp)
        // A browser that stops (the local-network prompt on first use, the
        // network changing) starts again, or no TV would ever turn up.
        b.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .waiting:
                Task { @MainActor in
                    guard let self, self.browser === b else { return }
                    b.cancel()
                    self.browser = nil
                    try? await Task.sleep(for: .seconds(2))
                    if self.browser == nil, self.enabled { self.startBrowsing() }
                }
            default: break
            }
        }
        b.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.compactMap { r -> TV? in
                if case .service(let name, _, _, _) = r.endpoint { return TV(name: name, endpoint: r.endpoint) }
                return nil
            }
            Task { @MainActor in
                guard let self else { return }
                self.tvs = found.sorted { $0.name < $1.name }
                // One TV: watch it (what it plays shows on the phone). Casting
                // to it is the TV button's job.
                if self.connection == nil, let only = self.tvs.first, self.tvs.count == 1 { self.connect(only) }
            }
        }
        b.start(queue: queue)
        browser = b
    }

    /// Settings → Remote off: stop looking, and drop the TV.
    func stopBrowsing() {
        enabled = false
        browser?.cancel()
        browser = nil
        tvs = []
        casting = false
        let c = connection
        connection = nil
        linked = nil
        connectedTo = nil
        state = nil
        c?.cancel()
    }

    /// Back in the app: look again — the system may have stopped the search
    /// meanwhile, and a TV opened since should turn up.
    func refresh() {
        guard enabled, connection == nil else { return }
        browser?.cancel()
        browser = nil
        startBrowsing()
    }

    /// Casts to a TV by name (one the browser found): from now on Play goes there.
    func cast(to name: String) {
        if linked != name, let tv = tvs.first(where: { $0.name == name }) { connect(tv) }
        casting = true
    }

    /// Stops sending to the TV; the phone keeps watching what it plays.
    func stopCasting() { casting = false }

    func connect(_ tv: TV) {
        connection?.cancel()
        let c = CompanionConnection(to: tv.endpoint, queue: queue)
        c.onMessage = { [weak self] message in Task { @MainActor in self?.receive(message) } }
        c.onClose = { [weak self] in
            Task { @MainActor in
                guard let self, self.connection === c else { return }
                self.connection = nil
                self.linked = nil
                self.connectedTo = nil
                self.state = nil
                // Try again shortly (the TV may have gone to sleep, or restarted the app).
                try? await Task.sleep(for: .seconds(2))
                if let again = self.tvs.first(where: { $0.name == tv.name }) { self.connect(again) }
            }
        }
        c.onReady = { [weak self] in Task { @MainActor in if self?.connection === c { self?.connectedTo = tv.name } } }
        connection = c
        linked = tv.name
        c.start(timeout: .seconds(5))
    }

    func send(_ command: CompanionCommand) { connection?.send(.command(command)) }

    private func receive(_ message: CompanionMessage) {
        switch message {
        case .hello: break                          // the name found on the network (the room) stays
        case .state(let s): state = s
        case .results: break
        case .command: break
        }
    }
}
