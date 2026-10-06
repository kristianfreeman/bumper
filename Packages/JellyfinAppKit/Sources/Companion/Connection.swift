public import Foundation
public import Network

/// One end of a companion connection: frames out, messages in.
public final class CompanionConnection: @unchecked Sendable {
    public let id = UUID()
    private let connection: NWConnection
    private let queue: DispatchQueue
    private var reader = Frames.Reader()
    public var onMessage: (@Sendable (CompanionMessage) -> Void)?
    public var onClose: (@Sendable () -> Void)?
    public var onReady: (@Sendable () -> Void)?

    public init(_ connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    public convenience init(to endpoint: NWEndpoint, queue: DispatchQueue) {
        self.init(NWConnection(to: endpoint, using: .tcp), queue: queue)
    }

    public func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.onReady?()
            case .failed, .cancelled: self?.onClose?()
            default: break
            }
        }
        connection.start(queue: queue)
        receive()
    }

    public func send(_ message: CompanionMessage) {
        guard let data = try? Frames.encode(message) else { return }
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    public func cancel() { connection.cancel() }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                do {
                    for message in try self.reader.append(data) { self.onMessage?(message) }
                } catch {
                    self.connection.cancel()
                    return
                }
            }
            if complete || error != nil { self.onClose?(); return }
            self.receive()
        }
    }
}

/// The TV side: advertises itself on the local network and keeps every
/// connected phone up to date.
public final class CompanionHost: @unchecked Sendable {
    private let queue = DispatchQueue(label: "companion.host")
    private var listener: NWListener?
    private var connections: [UUID: CompanionConnection] = [:]
    private var latest: CompanionState?
    /// nil: the system's name for this device (the room, "Living Room") —
    /// it fills that in when advertising, though apps can't read it.
    private let name: String?
    /// The name the service was registered under (the room, once advertised).
    private var advertised: String?
    /// A phone asked for something; reply through the connection if needed.
    public var onCommand: (@Sendable (CompanionCommand, CompanionConnection) -> Void)?
    public var onLog: (@Sendable (String) -> Void)?

    public init(name: String?) { self.name = name }

    public func start() {
        queue.async { [self] in
            guard listener == nil, let l = try? NWListener(using: .tcp) else { return }
            l.service = NWListener.Service(name: name, type: CompanionService.type)
            l.serviceRegistrationUpdateHandler = { [weak self] change in
                guard let self, case .add(let endpoint) = change, case .service(let registered, _, _, _) = endpoint else { return }
                self.advertised = registered
                self.onLog?("advertised as \(registered)")
            }
            l.newConnectionHandler = { [weak self] nw in self?.accept(nw) }
            l.stateUpdateHandler = { [weak self] state in self?.onLog?("listener \(state)") }
            l.start(queue: queue)
            listener = l
        }
    }

    public func stop() {
        queue.async { [self] in
            listener?.cancel()
            listener = nil
            connections.values.forEach { $0.cancel() }
            connections = [:]
        }
    }

    /// The TV's current state; sent now to every phone, and on connect.
    public func publish(_ state: CompanionState) {
        queue.async { [self] in
            guard state != latest else { return }
            latest = state
            connections.values.forEach { $0.send(.state(state)) }
        }
    }

    private func accept(_ nw: NWConnection) {
        let c = CompanionConnection(nw, queue: queue)
        connections[c.id] = c
        onLog?("phone connected (\(connections.count))")
        c.onMessage = { [weak self, weak c] message in
            guard let self, let c else { return }
            if case .command(let command) = message { self.onCommand?(command, c) }
        }
        c.onClose = { [weak self] in self?.queue.async { self?.connections[c.id] = nil } }
        c.onReady = { [weak self, weak c] in
            guard let self, let c else { return }
            c.send(.hello(name: self.advertised ?? self.name ?? "Apple TV", version: CompanionService.version))
            if let latest = self.latest { c.send(.state(latest)) }
        }
        c.start()
    }
}
