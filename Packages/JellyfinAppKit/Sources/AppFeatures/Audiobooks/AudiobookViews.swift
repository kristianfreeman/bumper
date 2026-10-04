#if os(tvOS)
import AppCore
import DesignSystem
import Instrumentation
import JellyfinAPI
import Observation
import PlaybackCore
import SwiftUI

// MARK: - Library

@MainActor
@Observable
final class AudiobookLibraryModel {
    private(set) var sections: [BrowseSection] = []
    private(set) var lede: String?

    /// Every books library's audiobooks, as one collection.
    func load(libraries: [BaseItem], client: JellyfinClient, app: AppModel) async {
        func query(_ library: BaseItem, _ sort: [String], _ order: ItemSortOrder = .ascending) -> ItemQuery {
            var q = ItemQuery(parentId: library.id, includeItemTypes: [.audioBook], sortBy: sort, sortOrder: order, limit: 2000)
            q.fields = ItemField.card + [.chapters, .overview]
            return q
        }
        var books: [Audiobook] = []
        var recent: [(Date, Audiobook)] = []
        for library in libraries {
            guard let files = try? await client.items(query(library, ["SortName"])).items else { continue }
            books += Audiobook.group(files, libraryId: library.id)
            if let newest = try? await client.items(query(library, ["DateCreated", "SortName"], .descending)).items {
                // Interleave libraries by their files' order; keep each library's newest first.
                recent += Audiobook.group(newest, libraryId: library.id).enumerated().map { (Date(timeIntervalSince1970: -Double($0.offset)), $0.element) }
            }
        }
        guard !books.isEmpty else { sections = []; return }
        for book in books { app.audiobooks[book.id] = book }
        let recentBooks = recent.sorted { $0.0 > $1.0 }.map(\.1)

        var out: [BrowseSection] = []
        let listening = books.filter { $0.resumePosition != nil && !$0.isFinished }
        let hours = Int(books.reduce(0) { $0 + $1.duration } / 3600)
        lede = "\(books.count) book\(books.count == 1 ? "" : "s"), \(hours > 0 ? "\(hours) hours of listening" : "under an hour of listening")" + (listening.isEmpty ? "." : " — \(listening.count) in progress.")
        if !listening.isEmpty { out.append(BrowseSection(id: "listening", title: "Still listening", items: listening.map(\.card), style: .square, subtitle: listening.first.map { "Back to \($0.title)." })) }
        if !recentBooks.isEmpty { out.append(BrowseSection(id: "recent", title: "Recently added", items: Array(recentBooks.prefix(20)).map(\.card), style: .square, subtitle: recentBooks.first.map { "Most recently, \($0.title)." })) }
        out.append(BrowseSection(id: "all", title: "All audiobooks", items: books.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }.map(\.card), style: .square, subtitle: "A to Z."))
        // Authors with several books get a row each.
        let byAuthor = Dictionary(grouping: books.filter { $0.author != nil }, by: { $0.author! })
        for (author, theirs) in byAuthor.filter({ $0.value.count >= 2 }).sorted(by: { $0.value.count > $1.value.count }).prefix(6) {
            out.append(BrowseSection(id: "author-\(author)", title: "By \(author)", items: theirs.map(\.card), style: .square, subtitle: "\(theirs.count) of their books."))
        }
        sections = out
    }
}

struct AudiobookLibraryView: View {
    let libraries: [BaseItem]
    @Environment(AppModel.self) private var app
    @State private var model = AudiobookLibraryModel()
    @State private var tracker = FocusTracker()
    @FocusState private var firstCardFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            TrackedBackdrop(tracker: tracker)
            CollectionList(sections: model.sections, firstCardFocus: $firstCardFocused) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Audiobooks").font(.system(size: 64, weight: .bold)).foregroundStyle(.white)
                    if let lede = model.lede { Text(lede).font(.title3).foregroundStyle(.white.opacity(0.75)) }
                }
                .padding(.top, 110)
            }
            if let player = app.audiobook {
                NowPlayingPill(player: player) { app.showsAudiobook = true }
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
                    .padding(.trailing, Layout.horizontalMargin)
                    .padding(.top, 20)
            }
        }
        .environment(\.focusTracker, tracker)
        .task {
            guard let client = app.session?.client else { return }
            await model.load(libraries: libraries, client: client, app: app)
            tracker.seed(model.sections.first?.items.first)
        }
        .claimsLaunchFocus($firstCardFocused, ready: !model.sections.isEmpty, key: "books")
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// "Now Playing: The Old Pier" — back to the player while browsing.
struct NowPlayingPill: View {
    let player: AudiobookPlayer
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(player.book.title).lineLimit(1)
            } icon: {
                Image(systemName: player.isPlaying ? "waveform" : "pause.fill")
                    .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
            }
            .font(.callout.weight(.semibold))
        }
        .accessibilityIdentifier("audiobook.nowPlaying")
    }
}

// MARK: - Book

struct AudiobookDetailView: View {
    let bookId: String
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var book: Audiobook?
    @FocusState private var playFocused: Bool

    var body: some View {
        ZStack {
            theme.backgroundGradient.ignoresSafeArea()
            if let book {
                HStack(alignment: .top, spacing: 80) {
                    Artwork(item: book.card, kind: .poster, width: 520)
                        .frame(width: 520, height: 520)
                        .clipShape(.rect(cornerRadius: 24))
                        .shadow(color: .black.opacity(0.4), radius: 30, y: 16)
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(book.title).font(.title.bold()).foregroundStyle(theme.primaryText).lineLimit(2)
                            if let author = book.author { Text(author).font(.title3).foregroundStyle(theme.secondaryText) }
                            Text(facts(book)).font(.callout).foregroundStyle(theme.secondaryText)
                        }
                        HStack(spacing: 24) {
                            Button { app.listen(book) } label: {
                                Label(primaryTitle(book), systemImage: "play.fill").padding(.horizontal, 20)
                            }
                            .focused($playFocused)
                            .accessibilityIdentifier("audiobook.play")
                            if book.resumePosition != nil {
                                Button { app.listen(book, from: 0) } label: { Label("Start Over", systemImage: "gobackward") }
                            }
                        }
                        if let overview = book.overview {
                            Text(overview).font(.callout).foregroundStyle(theme.secondaryText).lineLimit(3).frame(maxWidth: 1000, alignment: .leading)
                        }
                        if !book.chapters.isEmpty { ChapterList(book: book, current: nil) { app.listen(book, from: $0.start) } }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, Layout.horizontalMargin)
                .padding(.top, 60)
            } else {
                ProgressView()
            }
        }
        .task {
            book = await app.audiobook(id: bookId)
            playFocused = true
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func primaryTitle(_ book: Audiobook) -> String {
        if app.audiobook?.book.id == book.id { return "Now Playing" }
        return book.resumePosition != nil ? "Resume" : "Play"
    }

    private func facts(_ book: Audiobook) -> String {
        var parts = [hoursMinutes(book.duration)]
        if !book.chapters.isEmpty { parts.append("\(book.chapters.count) chapters") }
        if let t = book.resumePosition { parts.append("\(hoursMinutes(book.duration - t)) left") }
        if let year = book.year { parts.append(String(year)) }
        return parts.joined(separator: " · ")
    }
}

func hoursMinutes(_ seconds: Double) -> String {
    let minutes = Int((seconds / 60).rounded())
    if minutes < 1 { return "\(Int(seconds)) s" }
    return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
}

func clock(_ seconds: Double) -> String {
    let s = Int(max(0, seconds))
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
}

/// Chapters: title, start, length. Select one to listen from there.
struct ChapterList: View {
    let book: Audiobook
    let current: Int?
    let select: (Audiobook.Chapter) -> Void
    @Environment(\.theme) private var theme
    @FocusState private var focused: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(book.chapters.enumerated()), id: \.offset) { i, chapter in
                    Button { select(chapter) } label: {
                        ChapterRow(index: i, title: chapter.title, range: book.chapterRange(i), current: i == current)
                    }
                    .buttonStyle(BareButtonStyle())
                    .focused($focused, equals: i)
                    .accessibilityIdentifier("chapter.\(i)")
                }
            }
            .padding(.vertical, 10)
        }
        .scrollClipDisabled()
        .frame(maxHeight: 420, alignment: .top)
        .defaultFocus($focused, current ?? 0)
        .task { if let current { focused = current } }     // opened over the player: start on the chapter playing
    }
}

private struct ChapterRow: View {
    let index: Int
    let title: String
    let range: ClosedRange<Double>
    let current: Bool
    @Environment(\.isFocused) private var focused
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 20) {
            Group {
                if current { Image(systemName: "speaker.wave.2.fill") } else { Text("\(index + 1)").monospacedDigit() }
            }
            .frame(width: 36)
            .foregroundStyle(focused ? .black : current ? theme.accent : .secondary)
            Text(title).lineLimit(1).fontWeight(current ? .semibold : .regular)
            Spacer()
            Text(clock(range.lowerBound)).monospacedDigit().opacity(0.6)
            Text(hoursMinutes(range.upperBound - range.lowerBound)).opacity(0.6).frame(width: 130, alignment: .trailing)
        }
        .font(.callout)
        .foregroundStyle(focused ? .black : .primary)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(focused ? Color.white : Color.white.opacity(0.06), in: .rect(cornerRadius: 16))
        .scaleEffect(focused ? 1.02 : 1)
        .animation(.spring(duration: 0.18), value: focused)
    }
}

// MARK: - Now Playing

struct AudiobookNowPlayingView: View {
    let player: AudiobookPlayer
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var showsChapters = false
    @FocusState private var focus: Control?

    enum Control: Hashable { case previous, back, playPause, forward, next, chapters }

    var body: some View {
        let book = player.book
        ZStack {
            Color.black.ignoresSafeArea()
            Artwork(item: book.card, kind: .poster, width: 600)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(1.6)
                .opacity(0.25)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            LinearGradient(colors: [.black.opacity(0.3), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            HStack(alignment: .center, spacing: 90) {
                Artwork(item: book.card, kind: .poster, width: 600)
                    .frame(width: 600, height: 600)
                    .clipShape(.rect(cornerRadius: 28))
                    .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
                    .scaleEffect(player.isPlaying ? 1 : 0.94)
                    .animation(.spring(duration: 0.4), value: player.isPlaying)
                VStack(alignment: .leading, spacing: 34) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(book.title).font(.title2.bold()).foregroundStyle(.white).lineLimit(2)
                        if let author = book.author { Text(author).font(.title3).foregroundStyle(.white.opacity(0.7)) }
                    }
                    progress
                    transport
                    options
                }
                .frame(maxWidth: 900, alignment: .leading)
            }
            .padding(.horizontal, 100)
            if showsChapters {
                chapterPanel.transition(.move(edge: .trailing).combined(with: .opacity))
            }
            status
        }
        .defaultFocus($focus, .playPause)
        .onPlayPauseCommand { player.togglePlayPause() }
        .onExitCommand {
            if showsChapters { showsChapters = false; focus = .chapters } else { app.showsAudiobook = false }
        }
        .animation(.spring(duration: 0.3), value: showsChapters)
    }

    private var progress: some View {
        let range = player.chapterRange
        let within = max(0, player.position - range.lowerBound)
        let length = max(1, range.upperBound - range.lowerBound)
        return VStack(alignment: .leading, spacing: 12) {
            if let chapter = player.chapter, let i = player.chapterIndex {
                Text("Chapter \(i + 1) of \(player.book.chapters.count) · \(chapter.title)")
                    .font(.headline).foregroundStyle(theme.accent).lineLimit(1)
                    .accessibilityIdentifier("audiobook.chapter")
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(.white).frame(width: max(10, geo.size.width * within / length))
                }
            }
            .frame(height: 10)
            HStack {
                Text(clock(within))
                Spacer()
                Text("\(hoursMinutes(player.remainingAtSpeed)) left" + (player.rate == 1 ? "" : " at \(speedLabel(player.rate))"))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text("−" + clock(length - within))
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(.white.opacity(0.85))
        }
    }

    private var transport: some View {
        HStack(spacing: 26) {
            Pill("Previous Chapter", systemImage: "backward.end.fill", size: .small) { player.previousChapter() }
                .focused($focus, equals: .previous)
            Pill("Back 15 Seconds", systemImage: "gobackward.15") { player.skip(by: -15) }
                .focused($focus, equals: .back)
            Pill(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.fill" : "play.fill", size: .large) { player.togglePlayPause() }
                .focused($focus, equals: .playPause)
                .accessibilityIdentifier("audiobook.playPause")
            Pill("Forward 30 Seconds", systemImage: "goforward.30") { player.skip(by: 30) }
                .focused($focus, equals: .forward)
                .accessibilityIdentifier("audiobook.forward")
            Pill("Next Chapter", systemImage: "forward.end.fill", size: .small) { player.nextChapter() }
                .focused($focus, equals: .next)
                .accessibilityIdentifier("audiobook.nextChapter")
        }
        // Full-width focus areas: pills are narrow at rest, and without this
        // Down from the right of one row finds nothing beneath it.
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    private var options: some View {
        HStack(spacing: 22) {
            Menu {
                ForEach(AudiobookPlayer.speeds, id: \.self) { speed in
                    Button { player.rate = speed } label: {
                        if speed == player.rate { Label(speedLabel(speed), systemImage: "checkmark") } else { Text(speedLabel(speed)) }
                    }
                }
            } label: {
                PillFace("Speed", detail: speedLabel(player.rate), size: .small, active: player.rate != 1) { PillSymbol("speedometer", size: .small) }
            }
            .buttonStyle(PillButtonStyle())
            .accessibilityIdentifier("audiobook.speed")
            Pill("Smart Speed", systemImage: player.smartSpeed ? "waveform.badge.minus" : "waveform", detail: smartSpeedDetail, size: .small, active: player.smartSpeed) {
                player.smartSpeed.toggle()
            }
            .accessibilityIdentifier("audiobook.smartSpeed")
            Menu {
                Button("Off") { app.sleepTimer.reset() }
                Button("End of Chapter") { app.sleepTimer.set(.endOfItem) }
                ForEach(SleepTimer.presets, id: \.self) { m in Button("\(m) Minutes") { app.sleepTimer.set(.minutes(m)) } }
            } label: {
                PillFace("Sleep Timer", detail: sleepDetail, size: .small, active: app.sleepTimer.isActive) {
                    PillSymbol(app.sleepTimer.isActive ? "moon.zzz.fill" : "moon.zzz", size: .small)
                }
            }
            .buttonStyle(PillButtonStyle())
            if !player.book.chapters.isEmpty {
                Pill("Chapters", systemImage: "list.bullet", size: .small) { showsChapters = true }
                    .focused($focus, equals: .chapters)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    private var smartSpeedDetail: String? {
        guard player.smartSpeed else { return "Off" }
        let saved = player.savedSeconds
        return saved < 60 ? "\(Int(saved)) s saved" : "\(Int(saved / 60)) min saved"
    }

    private var sleepDetail: String? {
        switch app.sleepTimer.mode {
        case .off: nil
        case .endOfItem: "End of chapter"
        case .minutes: app.sleepTimer.shortLabel
        }
    }



    private var chapterPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Chapters").font(.headline).foregroundStyle(.white.opacity(0.7)).padding(.horizontal, 20)
            ChapterList(book: player.book, current: player.chapterIndex) { chapter in
                player.seek(to: chapter.start)
                if !player.isPlaying { player.play() }
                showsChapters = false
                focus = .playPause
            }
            .frame(maxHeight: 800, alignment: .top)
        }
        .padding(30)
        .frame(width: 760, alignment: .leading)
        .overVideoPanel(cornerRadius: 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .padding(60)
        .focusSection()
    }

    /// Buffering, errors — and invisible values UI tests read.
    private var status: some View {
        VStack {
            if let error = player.error {
                Label(error, systemImage: "exclamationmark.triangle").font(.callout).padding(20).overVideoPanel(cornerRadius: 18)
            } else if player.isBuffering {
                ProgressView().padding(20)
            }
            Spacer()
            HStack {
                Text(verbatim: String(Int(player.position * 1000))).accessibilityIdentifier("audiobook.position")
                Text(verbatim: String(Int(player.savedSeconds * 1000))).accessibilityIdentifier("audiobook.saved")
                Text(verbatim: player.isPlaying ? "playing" : "paused").accessibilityIdentifier("audiobook.state")
            }
            .foregroundStyle(.clear)
            .allowsHitTesting(false)
        }
        .padding(.top, 40)
    }
}

func speedLabel(_ rate: Double) -> String {
    rate.formatted(.number.precision(.fractionLength(rate * 10 == (rate * 10).rounded() ? 1 : 2))) + "×"
}

#endif
