#if os(tvOS)
import AppCore
import DesignSystem
import JellyfinAPI
import SwiftUI

/// Server → user → signed in. Auto-discovers servers on the LAN so most
/// people never type an address; Quick Connect means most never type a
/// password with the Siri Remote either.
struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var server: ServerRecord?

    var body: some View {
        NavigationStack {
            Group {
                if let server {
                    SignInView(server: server) { self.server = nil }
                } else {
                    ServerConnectView { self.server = $0 }
                }
            }
            .background(theme.backgroundGradient.ignoresSafeArea())
        }
    }
}

struct ServerConnectView: View {
    let onConnected: (ServerRecord) -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var discovered: [DiscoveredServer] = []
    @State private var address = ""
    @State private var error: String?
    @State private var connecting = false

    var body: some View {
        HStack(alignment: .top, spacing: 120) {
            VStack(alignment: .leading, spacing: 24) {
                Text("Welcome to \(Brand.displayName)").font(.largeTitle.bold()).foregroundStyle(theme.primaryText)
                Text("Your Jellyfin library on Apple TV.")
                    .font(.title3).foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: 700, alignment: .leading)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 30) {
                if !app.accounts.servers.isEmpty {
                    Text("Recent").font(.headline).foregroundStyle(theme.secondaryText)
                    ForEach(app.accounts.servers) { s in
                        Button { onConnected(s) } label: { serverRow(s.name, s.url.absoluteString) }
                    }
                }
                Text("On Your Network").font(.headline).foregroundStyle(theme.secondaryText)
                if discovered.isEmpty {
                    HStack(spacing: 16) { ProgressView(); Text("Looking for servers…").foregroundStyle(theme.secondaryText) }
                }
                ForEach(discovered) { d in
                    Button { connect(d.address) } label: { serverRow(d.name, d.address) }
                }
                Text("Server Address").font(.headline).foregroundStyle(theme.secondaryText)
                TextField("http://192.168.1.10:8096", text: $address)
                    .textContentType(.URL)
                    .onSubmit { connect(address) }
                if connecting { ProgressView() }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .frame(width: 760)
        }
        .padding(100)
        .task {
            while !Task.isCancelled {
                let found = await ServerDiscovery.discover()
                if !found.isEmpty { discovered = found }
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    private func serverRow(_ name: String, _ detail: String) -> some View {
        HStack(spacing: 20) {
            Image(systemName: "server.rack").font(.title2)
            VStack(alignment: .leading) {
                Text(name).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private func connect(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if !text.contains("://") { text = "http://" + text }
        if URLComponents(string: text)?.port == nil, !text.hasPrefix("https"), text.filter({ $0 == ":" }).count == 1 { text += ":8096" }
        guard let url = URL(string: text) else { error = JellyfinError.invalidURL.localizedDescription; return }
        connecting = true
        error = nil
        Task {
            defer { connecting = false }
            do {
                let info = try await app.accounts.anonymousClient(for: url).publicSystemInfo()
                guard info.isSupported else { throw JellyfinError.unsupportedServer(version: info.version ?? "?") }
                let record = ServerRecord(id: info.id ?? url.absoluteString, name: info.serverName ?? url.host() ?? "Jellyfin", url: url, version: info.version)
                app.accounts.upsert(server: record)
                onConnected(record)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

struct SignInView: View {
    let server: ServerRecord
    let onBack: () -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var users: [UserDto] = []
    @State private var quickConnectCode: String?
    @State private var username = ""
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        HStack(alignment: .top, spacing: 100) {
            VStack(alignment: .leading, spacing: 30) {
                Text(server.name).font(.largeTitle.bold()).foregroundStyle(theme.primaryText)
                if let code = quickConnectCode {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Quick Connect").font(.headline).foregroundStyle(theme.secondaryText)
                        Text(code).font(.system(size: 96, weight: .heavy, design: .monospaced)).foregroundStyle(theme.accent)
                            .accessibilityIdentifier("quickconnect.code")
                        Text("Enter this code under Quick Connect in any signed-in Jellyfin app.")
                            .font(.callout).foregroundStyle(theme.secondaryText).frame(maxWidth: 640, alignment: .leading)
                    }
                }
                if !users.isEmpty {
                    Text("Who's watching?").font(.headline).foregroundStyle(theme.secondaryText)
                    HStack(spacing: 30) {
                        ForEach(users) { user in
                            Button { username = user.name ?? "" } label: {
                                VStack {
                                    Image(systemName: "person.crop.circle.fill").font(.system(size: 90))
                                    Text(user.name ?? "").font(.caption)
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                Button("Other Server", action: onBack)
            }
            VStack(alignment: .leading, spacing: 24) {
                Text("Password").font(.headline).foregroundStyle(theme.secondaryText)
                TextField("Username", text: $username).textContentType(.username)
                SecureField("Password", text: $password).textContentType(.password).onSubmit(signIn)
                Button(action: signIn) {
                    HStack { if busy { ProgressView() }; Text("Sign In") }.frame(maxWidth: .infinity)
                }
                .disabled(username.isEmpty || busy)
                if let error { Text(error).foregroundStyle(.red) }
            }
            .frame(width: 640)
        }
        .padding(100)
        .task { await loadUsers() }
        .task { await runQuickConnect() }
    }

    private func loadUsers() async {
        users = (try? await app.accounts.client(for: server).publicUsers()) ?? []
    }

    /// Initiates Quick Connect and polls until approved on another device.
    private func runQuickConnect() async {
        let client = app.accounts.client(for: server)
        guard (try? await client.quickConnectEnabled()) == true, let state = try? await client.quickConnectInitiate() else { return }
        quickConnectCode = state.code
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            guard let s = try? await client.quickConnectState(secret: state.secret) else { continue }
            if s.authenticated {
                if let result = try? await client.authenticate(quickConnectSecret: state.secret) {
                    app.didSignIn(app.accounts.signIn(server: server, result: result))
                }
                return
            }
        }
    }

    private func signIn() {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                let result = try await app.accounts.client(for: server).authenticate(username: username, password: password)
                app.didSignIn(app.accounts.signIn(server: server, result: result))
            } catch JellyfinError.unauthorized {
                error = "Wrong username or password."
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
#endif
