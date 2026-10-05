#if os(tvOS)
import AppCore
import DesignSystem
import Instrumentation
import JellyfinAPI
import SwiftUI

/// Server → who's watching → signed in. Servers on the network are found on
/// their own, so most people never type an address; Quick Connect and
/// password-less profiles mean most never type a password with the remote.
struct OnboardingView: View {
    @Environment(\.theme) private var theme
    @State private var server: ServerRecord?

    var body: some View {
        NavigationStack {
            ZStack {
                theme.backgroundGradient.ignoresSafeArea()
                if let server {
                    SignInView(server: server) { self.server = nil }
                        .transition(.opacity)
                } else {
                    ServerConnectView { self.server = $0 }
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.25), value: server)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// The page's words: a small eyebrow, a headline, a line of lede — the
/// same voice as Home and the collection pages.
private struct OnboardingHeader: View {
    var eyebrow: String? = nil
    /// The boiling wordmark in place of the eyebrow (the welcome page).
    var showsMark = false
    let title: String
    let lede: String
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if showsMark {
                BrandMark(.wordmark, height: 84).padding(.bottom, 14)
            }
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.caption.weight(.bold)).tracking(2)
                    .foregroundStyle(theme.secondaryText)
            }
            Text(title)
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(theme.primaryText)
            Text(lede)
                .font(.title3)
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: 820, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A server to pick: one wide row that lifts and turns white when focused,
/// like a pill opened all the way.
private struct ServerRow: View {
    let name: String
    let detail: String
    let symbol: String
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) { ServerRowFace(name: name, detail: detail, symbol: symbol, busy: busy) }
            .buttonStyle(PillButtonStyle())
    }
}

private struct ServerRowFace: View {
    let name: String
    let detail: String
    let symbol: String
    let busy: Bool
    @Environment(\.isFocused) private var focused
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 24) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .frame(width: 72, height: 72)
                .background(focused ? Color.black.opacity(0.08) : theme.primaryText.opacity(0.08), in: .circle)
                .foregroundStyle(focused ? .black : theme.primaryText)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.headline)
                Text(detail).font(.callout).opacity(0.65)
            }
            .lineLimit(1)
            Spacer(minLength: 20)
            if busy {
                ProgressView()
            } else {
                Image(systemName: "arrow.right").font(.headline).opacity(focused ? 1 : 0)
            }
        }
        .foregroundStyle(focused ? .black : theme.primaryText)
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(width: 820)
        .background(focused ? Color.white : theme.primaryText.opacity(0.08), in: .rect(cornerRadius: 28))
        .scaleEffect(focused ? 1.04 : 1)
        .shadow(color: .black.opacity(focused ? 0.35 : 0), radius: 20, y: 10)
        .animation(.spring(duration: 0.3, bounce: 0.2), value: focused)
    }
}

struct ServerConnectView: View {
    let onConnected: (ServerRecord) -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var discovered: [DiscoveredServer] = []
    @State private var searched = false
    @State private var address = ""
    @State private var typing = false
    @State private var error: String?
    @State private var connecting: String?

    /// Found on the network and not already listed as used before.
    private var fresh: [DiscoveredServer] {
        discovered.filter { d in !app.accounts.servers.contains { $0.url.absoluteString == d.address || $0.id == d.id } }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 40) {
                OnboardingHeader(
                    showsMark: true,
                    title: "Let's find your library.",
                    lede: "\(Brand.displayName) plays straight from your Jellyfin server. It's usually right here on your network — pick it below."
                )
                VStack(alignment: .leading, spacing: 18) {
                    if !app.accounts.servers.isEmpty {
                        SectionLabel("Used before")
                        ForEach(app.accounts.servers) { s in
                            ServerRow(name: s.name, detail: s.url.absoluteString, symbol: "clock.arrow.circlepath", busy: false) { onConnected(s) }
                                .accessibilityIdentifier("onboarding.server.\(s.id)")
                        }
                    }
                    SectionLabel("On your network")
                        .accessibilityIdentifier("onboarding.network")
                    ForEach(fresh) { d in
                        ServerRow(name: d.name, detail: d.address, symbol: "server.rack", busy: connecting == d.address) { connect(d.address) }
                            .accessibilityIdentifier("onboarding.server.\(d.id)")
                    }
                    if fresh.isEmpty {
                        HStack(spacing: 16) {
                            if !searched || discovered.isEmpty { ProgressView() }
                            Text(searched ? "Still looking. If it's on another network, type its address." : "Looking…")
                                .font(.callout).foregroundStyle(theme.secondaryText)
                        }
                        .frame(height: 72)
                    }
                }
                .tvFocusSection()
                HStack(spacing: 18) {
                    Pill("Type an Address", systemImage: "keyboard", size: .small, alwaysShowsTitle: true) { typing = true }
                        .accessibilityIdentifier("onboarding.address")
                    if connecting != nil && fresh.allSatisfy({ $0.address != connecting }) { ProgressView() }
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.red)
                        .frame(maxWidth: 820, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Layout.horizontalMargin)
        .padding(.top, 90)
        .alert("Server address", isPresented: $typing) {
            TextField("192.168.1.10:8096", text: $address)
                .textContentType(.URL)
                .onSubmit { connect(address); typing = false }
            Button("Connect") { connect(address) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The address you'd open in a browser to reach Jellyfin.")
        }
        .task {
            while !Task.isCancelled {
                let found = await ServerDiscovery.discover()
                if !found.isEmpty { discovered = found }
                searched = true
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    private func connect(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, connecting == nil else { return }
        if !text.contains("://") { text = "http://" + text }
        if URLComponents(string: text)?.port == nil, !text.hasPrefix("https"), text.filter({ $0 == ":" }).count == 1 { text += ":8096" }
        guard let url = URL(string: text) else { error = JellyfinError.invalidURL.localizedDescription; return }
        connecting = raw
        error = nil
        Task {
            defer { connecting = nil }
            do {
                let info = try await app.accounts.anonymousClient(for: url).publicSystemInfo()
                guard info.isSupported else { throw JellyfinError.unsupportedServer(version: info.version ?? "?") }
                let record = ServerRecord(id: info.id ?? url.absoluteString, name: info.serverName ?? url.host() ?? "Jellyfin", url: url, version: info.version)
                app.accounts.upsert(server: record)
                onConnected(record)
            } catch {
                self.error = "Couldn't reach \(url.host() ?? text). \(error.localizedDescription)"
            }
        }
    }
}

private struct SectionLabel: View {
    let text: String
    @Environment(\.theme) private var theme
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.headline).foregroundStyle(theme.secondaryText).padding(.top, 6)
    }
}

struct SignInView: View {
    let server: ServerRecord
    let onBack: () -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var users: [UserDto] = []
    @State private var loadedUsers = false
    @State private var quickConnectCode: String?
    @State private var username = ""
    @State private var password = ""
    @State private var askingPassword = false
    @State private var error: String?
    @State private var busy: String?

    var body: some View {
        HStack(alignment: .top, spacing: 90) {
            VStack(alignment: .leading, spacing: 44) {
                OnboardingHeader(
                    eyebrow: server.name,
                    title: "Who's watching?",
                    lede: users.isEmpty && loadedUsers
                        ? "Sign in with your Jellyfin name and password\(quickConnectCode == nil ? "" : ", or approve this TV from your phone")."
                        : "Pick your profile\(quickConnectCode == nil ? "" : ", or approve this TV from your phone"). \(Brand.displayName) remembers you after this."
                )
                if !users.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 40) {
                            ForEach(users) { user in
                                ProfileButton(user: user, server: server, busy: busy == user.name) { pick(user) }
                                    .accessibilityIdentifier("onboarding.user.\(user.name ?? user.id)")
                            }
                        }
                        .padding(.vertical, 30)
                        .padding(.horizontal, 10)
                    }
                    .scrollClipDisabled()
                    .tvFocusSection()
                }
                HStack(spacing: 18) {
                    Pill(users.isEmpty ? "Sign In" : "Someone Else", systemImage: "person.badge.key", size: .small,
                         prominent: users.isEmpty && loadedUsers, alwaysShowsTitle: true) {
                        username = ""
                        askingPassword = true
                    }
                    .accessibilityIdentifier("onboarding.signIn")
                    Pill("Other Server", systemImage: "arrow.left", size: .small, alwaysShowsTitle: true, action: onBack)
                        .accessibilityIdentifier("onboarding.back")
                }
                .tvFocusSection()
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.red)
                }
                Spacer(minLength: 0)
            }
            if let code = quickConnectCode {
                QuickConnectCard(code: code)
            }
        }
        .padding(.horizontal, Layout.horizontalMargin)
        .padding(.top, 90)
        .alert(username.isEmpty ? "Sign in to \(server.name)" : "Password for \(username)", isPresented: $askingPassword) {
            if users.first(where: { $0.name == username }) == nil {
                TextField("Name", text: $username).textContentType(.username)
            }
            SecureField("Password", text: $password).textContentType(.password)
                .onSubmit { signIn(); askingPassword = false }
            Button("Sign In") { signIn() }
            Button("Cancel", role: .cancel) { password = "" }
        }
        .task { await loadUsers() }
        .task { await runQuickConnect() }
    }

    private func pick(_ user: UserDto) {
        username = user.name ?? ""
        password = ""
        if user.hasPassword == false { signIn() } else { askingPassword = true }
    }

    private func loadUsers() async {
        users = (try? await app.accounts.client(for: server).publicUsers()) ?? []
        loadedUsers = true
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
                    TraceFile.write("onboarding", "signed in with Quick Connect")
                    app.didSignIn(app.accounts.signIn(server: server, result: result))
                }
                return
            }
        }
    }

    private func signIn() {
        guard !username.isEmpty, busy == nil else { return }
        busy = username
        error = nil
        let name = username, secret = password
        password = ""
        Task {
            defer { busy = nil }
            do {
                let result = try await app.accounts.client(for: server).authenticate(username: name, password: secret)
                TraceFile.write("onboarding", "signed in with a profile")
                app.didSignIn(app.accounts.signIn(server: server, result: result))
            } catch JellyfinError.unauthorized {
                error = "That password didn't work for \(name)."
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// A profile: its picture (or initials) in a circle, the name beneath; the
/// circle lifts and rings white when focused.
private struct ProfileButton: View {
    let user: UserDto
    let server: ServerRecord
    let busy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) { ProfileFace(user: user, server: server, busy: busy) }
            .buttonStyle(PillButtonStyle())
            .accessibilityLabel(user.name ?? "")
    }
}

private struct ProfileFace: View {
    let user: UserDto
    let server: ServerRecord
    let busy: Bool
    @Environment(AppModel.self) private var app
    @Environment(\.isFocused) private var focused
    @Environment(\.theme) private var theme
    @Environment(\.displayScale) private var scale

    private let size: CGFloat = 170

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Monogram(user.name ?? "?", size: size)
                if let tag = user.primaryImageTag {
                    let px = Int(size * scale)
                    RemoteImage(request: ImageRequest(url: app.accounts.client(for: server).userImageURL(userId: user.id, tag: tag, size: px), maxPixelSize: px))
                }
                if busy { Circle().fill(.black.opacity(0.4)); ProgressView() }
            }
            .frame(width: size, height: size)
            .clipShape(.circle)
            .overlay { Circle().strokeBorder(theme.colorScheme == .light ? theme.primaryText : .white, lineWidth: focused ? 6 : 0) }
            .scaleEffect(focused ? 1.1 : 1)
            .shadow(color: .black.opacity(focused ? 0.4 : 0), radius: 24, y: 12)
            Text(user.name ?? "")
                .font(.headline)
                .foregroundStyle(focused ? theme.primaryText : theme.secondaryText)
                .lineLimit(1)
            Text(user.hasPassword == false ? " " : "Password")
                .font(.caption2).foregroundStyle(theme.secondaryText.opacity(0.7))
        }
        .frame(width: size + 40)
        .animation(.spring(duration: 0.3, bounce: 0.2), value: focused)
    }

}

/// The code, big, with where to enter it.
private struct QuickConnectCard: View {
    let code: String
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Label("Quick Connect", systemImage: "iphone.radiowaves.left.and.right")
                .font(.headline).foregroundStyle(theme.primaryText)
            HStack(spacing: 10) {
                ForEach(Array(code.enumerated()), id: \.offset) { _, c in
                    if c == " " { Color.clear.frame(width: 14, height: 1) } else {
                    Text(String(c))
                        .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(theme.primaryText)
                        .frame(width: 64, height: 92)
                        .background(theme.primaryText.opacity(0.08), in: .rect(cornerRadius: 16))
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(code)
            .accessibilityIdentifier("quickconnect.code")
            Text("On your phone or computer, open Jellyfin, go to your profile, choose Quick Connect and enter this code. This TV signs in on its own.")
                .font(.callout).foregroundStyle(theme.secondaryText)
                .frame(width: 520, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(40)
        .background(theme.surface.opacity(0.55), in: .rect(cornerRadius: 36))
        .padding(.top, 60)
    }
}
#endif
