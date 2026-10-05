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

    /// "Good evening, Kristian." — with the weekday where it colours the
    /// moment ("Friday night, Kristian."), and the odd holiday.
    public var greeting: String {
        let name = firstName.map { ", \($0)" } ?? ""
        let month = calendar.component(.month, from: now), day = calendar.component(.day, from: now)
        switch (month, day) {
        case (10, 31): return "Happy Halloween\(name)."
        case (12, 24), (12, 25): return "Merry Christmas\(name)."
        case (12, 31): return "Last night of the year\(name)."
        case (1, 1): return "Happy New Year\(name)."
        default: break
        }
        let weekdayNumber = calendar.component(.weekday, from: now)       // 1 = Sunday … 7 = Saturday
        switch timeOfDay {
        case .morning:
            return weekend ? "A slow \(weekday) morning\(name)." : pick(["Good morning\(name).", "Morning\(name).", "Rise and shine\(name)."], "greeting")
        case .afternoon:
            return weekend ? pick(["A lazy \(weekday) afternoon\(name).", "\(weekday) afternoon\(name)."], "greeting") : pick(["Good afternoon\(name).", "Afternoon\(name)."], "greeting")
        case .evening:
            if weekdayNumber == 6 { return "Friday night\(name)." }
            if weekdayNumber == 1 { return "Sunday night\(name)." }
            return pick(["Good evening\(name).", "Evening\(name).", "The evening's yours\(name)."], "greeting")
        case .late:
            return pick(["Up late\(name)?", "Still up\(name)?", "Burning the midnight oil\(name)?"], "greeting")
        }
    }

    /// One or two sentences under the greeting, from what's going on: what
    /// you're nearly done with, what's new, what's next.
    public var lede: String {
        var facts: [String] = []
        let resumable = inProgress.compactMap { item in minutesLeft(item).map { (item, $0) } }
        if let (item, left) = resumable.first {
            if left <= 30 {
                facts.append(timeOfDay == .late ? "Something short before bed? You're \(minutes(left)) from the end of \(seriesOrName(item))." : "You're \(minutes(left)) from the end of \(seriesOrName(item)).")
            } else {
                facts.append(pick(["\(seriesOrName(item)) is waiting where you left it.", "\(seriesOrName(item)) is right where you paused it.", "You left \(seriesOrName(item)) \(roughly(left)) from the end."], "lede.resume"))
            }
        }
        let newMovies = recentMovies.filter(addedThisWeek), newShows = recentShows.filter(addedThisWeek)
        if newMovies.count + newShows.count == 1, let only = (newMovies + newShows).first {
            facts.append("\(only.name ?? "Something new") arrived \(when(only.dateCreated))." )
        } else if newMovies.count + newShows.count > 1 {
            facts.append("\(countPhrase(newMovies.count, "film", "films", newShows.count, "show", "shows").capitalizedFirst) arrived this week.")
        } else if !nextUp.isEmpty {
            let shows = unique(nextUp.map(seriesOrName))
            facts.append(shows.count == 1 ? "A new episode of \(shows[0]) is ready." : "New episodes of \(list(Array(shows.prefix(2)))) are ready.")
        }
        if facts.isEmpty {
            switch timeOfDay {
            case .morning: return "Ease into the day with something light."
            case .afternoon: return weekend ? "No plans? Plenty here." : "Here's what's on your shelves."
            case .evening: return "Here's what's on your shelves tonight."
            case .late: return "Something short before bed?"
            }
        }
        return facts.prefix(2).joined(separator: " ")
    }

    // MARK: Collections

    public var resume: Copy {
        let left = inProgress.compactMap(minutesLeft)
        let total = left.reduce(0, +)
        let title = pick(["Pick up where you left off", "Still watching", "Unfinished business"], "resume")
        let subtitle: String?
        switch inProgress.count {
        case 0: subtitle = nil
        case 1: subtitle = "\(seriesOrName(inProgress[0])), \(minutes(total)) left."
        default: subtitle = "\(number(inProgress.count).capitalizedFirst) things on the go — \(roughly(total)) left between them."
        }
        return Copy(title: title, subtitle: subtitle)
    }

    public var upNext: Copy {
        let shows = unique(nextUp.map(seriesOrName))
        let named = shows.count > 3 ? "\(shows.prefix(2).joined(separator: ", ")) and \(number(shows.count - 2)) more" : list(shows)
        return Copy(title: pick(["What's next", "Next in your shows", "The next episode"], "nextup"),
                    subtitle: shows.isEmpty ? nil : "New episodes of \(named).")
    }

    /// A library's newest arrivals: "New this week" or "Recently added to Movies".
    public func recent(_ items: [BaseItem], library: String) -> Copy {
        let week = items.filter(addedThisWeek).count
        if week >= 2 { return Copy(title: "New this week", subtitle: "\(number(week).capitalizedFirst) additions to \(library) since last \(lastWeekday).") }
        if week == 1, let first = items.first { return Copy(title: "Just added", subtitle: "\(first.name ?? "Something new") arrived in \(library) \(when(first.dateCreated)).") }
        return Copy(title: "Recently added to \(library)", subtitle: items.first.map { "Most recently, \($0.name ?? "something new")\(addedClause($0.dateCreated))." })
    }

    /// "today", "yesterday", "on Tuesday", "last month", "in March".
    func when(_ date: Date?) -> String {
        guard let date else { return "recently" }
        if calendar.isDate(date, inSameDayAs: now) { return "today" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days == 1 { return "yesterday" }
        let style = Date.FormatStyle(timeZone: calendar.timeZone)
        if days < 7 { return "on \(date.formatted(style.weekday(.wide)))" }
        if days < 14 { return "last week" }
        if days < 45 { return "\(number(days / 7)) weeks ago" }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) { return "in \(date.formatted(style.month(.wide)))" }
        return "in \(date.formatted(style.month(.wide).year()))"
    }

    /// ", on Tuesday" — or nothing, when the server didn't say.
    func addedClause(_ date: Date?) -> String { date.map { ", \(when($0))" } ?? "" }

    private func unique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
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

    private func addedThisWeek(_ item: BaseItem) -> Bool {
        (item.dateCreated ?? .distantPast) > now.addingTimeInterval(-7 * 86_400)
    }

    private var weekday: String { now.formatted(Date.FormatStyle(timeZone: calendar.timeZone).weekday(.wide)) }
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
