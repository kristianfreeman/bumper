public import Foundation
public import JellyfinAPI

/// The app's written voice: titles and lines of copy for Home and the
/// libraries, from what we know — the time, what you're in the middle of,
/// what's new. Templates, not a language model (there's none on tvOS), but
/// they change with the day and the library, so the page reads as written.
///
/// Deterministic for a given context (a day's phrasing is stable), and pure,
/// so it's unit-tested.
public struct Editorial: Sendable {
    public struct Copy: Sendable, Equatable {
        public var title: String
        public var subtitle: String?
    }

    public var now: Date
    public var calendar: Calendar
    public var userName: String?
    public var inProgress: [BaseItem]
    public var nextUp: [BaseItem]
    public var recentMovies: [BaseItem]
    public var recentShows: [BaseItem]

    public init(now: Date = .now, calendar: Calendar = .current, userName: String?, inProgress: [BaseItem] = [], nextUp: [BaseItem] = [],
                recentMovies: [BaseItem] = [], recentShows: [BaseItem] = []) {
        self.now = now
        self.calendar = calendar
        self.userName = userName
        self.inProgress = inProgress
        self.nextUp = nextUp
        self.recentMovies = recentMovies
        self.recentShows = recentShows
    }

    // MARK: Page

    public enum TimeOfDay: Sendable { case morning, afternoon, evening, late }

    public var timeOfDay: TimeOfDay {
        switch calendar.component(.hour, from: now) {
        case 5..<12: .morning
        case 12..<17: .afternoon
        case 17..<22: .evening
        default: .late
        }
    }

    private var weekend: Bool { calendar.isDateInWeekend(now) }
    /// Account names are often lower-case ("kristian"); greet a person.
    private var firstName: String? { userName?.split(separator: " ").first.map { String($0).capitalizedFirst } }

    /// "Good evening, Kristian."
    public var greeting: String {
        let name = firstName.map { ", \($0)" } ?? ""
        switch timeOfDay {
        case .morning: return pick(["Good morning\(name).", "Morning\(name)."], "greeting")
        case .afternoon: return weekend ? "A slow \(weekday) afternoon\(name)." : "Good afternoon\(name)."
        case .evening: return pick(["Good evening\(name).", "Evening\(name)."], "greeting")
        case .late: return pick(["Up late\(name)?", "Still up\(name)?"], "greeting")
        }
    }

    /// One or two sentences under the greeting.
    public var lede: String {
        var facts: [String] = []
        if let item = inProgress.first, let left = minutesLeft(item) {
            facts.append(left <= 30 ? "You're \(minutes(left)) from the end of \(seriesOrName(item))." : "\(seriesOrName(item)) is waiting where you left it.")
        }
        let movies = addedThisWeek(recentMovies), shows = addedThisWeek(recentShows)
        if movies + shows > 0 {
            facts.append("\(countPhrase(movies, "film", "films", shows, "show", "shows").capitalizedFirst) arrived this week.")
        } else if !nextUp.isEmpty {
            facts.append("New episodes of \(list(nextUp.prefix(2).map(seriesOrName))) are ready.")
        }
        if facts.isEmpty {
            return timeOfDay == .late ? "Something short before bed?" : "Here's what's on your shelves."
        }
        return facts.prefix(2).joined(separator: " ")
    }

    // MARK: Collections

    public var resume: Copy {
        let total = inProgress.compactMap(minutesLeft).reduce(0, +)
        let title = pick(["Pick up where you left off", "Still watching", "Unfinished business"], "resume")
        let subtitle: String
        switch inProgress.count {
        case 0: subtitle = ""
        case 1: subtitle = "\(minutes(total)) left."
        default: subtitle = "\(number(inProgress.count).capitalizedFirst) things in progress — \(roughly(total)) in all."
        }
        return Copy(title: title, subtitle: subtitle.isEmpty ? nil : subtitle)
    }

    public var upNext: Copy {
        let shows = list(nextUp.prefix(3).map(seriesOrName))
        return Copy(title: pick(["What's next", "Next in your shows", "The next episode"], "nextup"),
                    subtitle: nextUp.isEmpty ? nil : "Continuing \(shows).")
    }

    /// A library's newest arrivals: "New this week" or "Recently added to Movies".
    public func recent(_ items: [BaseItem], library: String) -> Copy {
        let week = addedThisWeek(items)
        if week >= 2 { return Copy(title: "New this week", subtitle: "\(number(week).capitalizedFirst) additions to \(library) since last \(lastWeekday).") }
        if week == 1, let first = items.first { return Copy(title: "Just added", subtitle: "\(first.name ?? "Something new") arrived in \(library) this week.") }
        return Copy(title: "Recently added to \(library)", subtitle: items.first.map { "Most recently, \($0.name ?? "something new")." })
    }

    // MARK: Words

    private func pick(_ options: [String], _ salt: String) -> String {
        // Stable through a day, different the next.
        let day = calendar.ordinality(of: .day, in: .era, for: now) ?? 0
        let h = salt.unicodeScalars.reduce(day) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        return options[h % options.count]
    }

    private func minutesLeft(_ item: BaseItem) -> Int? {
        guard let total = item.runTimeTicks, let pos = item.userData?.playbackPositionTicks, total > pos else { return nil }
        return Int(Double(total - pos) / Double(BaseItem.ticksPerSecond) / 60)
    }

    private func addedThisWeek(_ items: [BaseItem]) -> Int {
        let start = now.addingTimeInterval(-7 * 86_400)
        return items.filter { ($0.dateCreated ?? .distantPast) > start }.count
    }

    private var weekday: String { now.formatted(.dateTime.weekday(.wide)) }
    private var lastWeekday: String { now.addingTimeInterval(-7 * 86_400).formatted(.dateTime.weekday(.wide)) }

    private func seriesOrName(_ item: BaseItem) -> String { item.seriesName ?? item.name ?? "it" }

    func minutes(_ m: Int) -> String {
        m < 60 ? "\(m) minute\(m == 1 ? "" : "s")" : hours(m)
    }

    func hours(_ m: Int) -> String {
        if m < 60 { return minutes(m) }
        let h = m / 60, r = m % 60
        if r < 10 { return "\(number(h)) hour\(h == 1 ? "" : "s")" }
        return "\(h) h \(r) min"
    }

    /// To the nearest quarter hour, in words: "an hour and a quarter", "nearly three hours".
    /// "about an hour and a quarter", "nearly three hours", "over 29 hours".
    func roughly(_ m: Int) -> String {
        if m < 50 { return "about " + minutes(Int((Double(m) / 5).rounded()) * 5) }
        if m >= 4 * 60 { return "over \(number(m / 60)) hours" }
        let quarters = Int((Double(m) / 15).rounded())
        let h = quarters / 4, q = quarters % 4
        let whole = h == 1 ? "an hour" : "\(number(h)) hours"
        switch q {
        case 0: return "about " + whole
        case 1: return h == 1 ? "about an hour and a quarter" : "about \(number(h)) and a quarter hours"
        case 2: return h == 1 ? "about an hour and a half" : "about \(number(h)) and a half hours"
        default: return "nearly \(number(h + 1)) hours"
        }
    }

    func number(_ n: Int) -> String {
        let words = ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        return n < words.count ? words[n] : String(n)
    }

    func countPhrase(_ a: Int, _ aOne: String, _ aMany: String, _ b: Int, _ bOne: String, _ bMany: String) -> String {
        let parts = [(a, aOne, aMany), (b, bOne, bMany)].filter { $0.0 > 0 }.map { "\(number($0.0)) \($0.0 == 1 ? $0.1 : $0.2)" }
        return parts.joined(separator: " and ")
    }

    func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " and " + names.last!
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
