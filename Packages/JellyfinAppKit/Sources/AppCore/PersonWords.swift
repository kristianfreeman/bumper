public import Foundation
public import JellyfinAPI

/// A person's page: what they're known for, when and where they were born,
/// and the line about what of theirs is in the library.
public enum PersonWords {
    /// The roles a page counts, in the words it uses, and the server's
    /// person types behind each (a guest star acts too).
    public static let roles: [(word: String, types: [String])] = [
        ("Actor", ["Actor", "GuestStar"]),
        ("Director", ["Director"]),
        ("Writer", ["Writer"]),
        ("Producer", ["Producer"]),
        ("Composer", ["Composer"]),
    ]

    /// "Actor · Director": the roles they have titles in, the most first.
    /// `counts`: titles per role word (missing: not asked, or the server
    /// didn't say). `fallback`: the role on the card that was opened, for
    /// when nothing was counted.
    public static func knownFor(counts: [String: Int], fallback: String? = nil) -> String? {
        let order = roles.map(\.word)
        let held = order.filter { (counts[$0] ?? 0) > 0 }
            .sorted { (counts[$0] ?? 0) != (counts[$1] ?? 0) ? (counts[$0] ?? 0) > (counts[$1] ?? 0) : order.firstIndex(of: $0)! < order.firstIndex(of: $1)! }
        if !held.isEmpty { return held.joined(separator: " · ") }
        return fallback.map(word(forType:))
    }

    /// The server's person type as the page says it ("GuestStar": "Actor").
    public static func word(forType type: String) -> String {
        roles.first { $0.types.contains(type) }?.word ?? type
    }

    /// "Born 4 May 1971 in Leeds, England" — or with a death, "4 May 1971 – 2 March 2016".
    /// Jellyfin keeps birth dates as midnight UTC: read in UTC, so they
    /// aren't a day early west of Greenwich.
    public static func life(born: Date?, died: Date?, place: String?) -> String? {
        var style = Date.FormatStyle(date: .long, time: .omitted)
        style.timeZone = TimeZone(identifier: "UTC")!
        style.locale = Locale(identifier: "en_GB")
        let at = place.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : " in \($0)" } ?? ""
        switch (born, died) {
        case let (born?, died?): return "\(born.formatted(style)) – \(died.formatted(style))"
        case let (born?, nil): return "Born \(born.formatted(style))\(at)"
        case let (nil, died?): return "Died \(died.formatted(style))"
        case (nil, nil): return place.flatMap { $0.isEmpty ? nil : "From \($0)" }
        }
    }

    /// "Twelve films and three shows in your library." (nil before anything's loaded).
    public static func lede(items: [BaseItem]) -> String? {
        guard !items.isEmpty else { return nil }
        let words = Editorial(userName: nil)
        let films = items.filter { $0.kind == .movie }.count
        let shows = items.filter { $0.kind == .series }.count
        let other = items.count - films - shows
        let parts = [(films, "film", "films"), (shows, "show", "shows"), (other, "title", "titles")]
            .filter { $0.0 > 0 }.map { "\(words.number($0.0)) \($0.0 == 1 ? $0.1 : $0.2)" }
        return (parts.joined(separator: " and ") + " in your library.").capitalizedFirst
    }

    /// Newest first, by year (a film without one goes by its premiere,
    /// and with neither, last); A to Z within a year. The server sorts
    /// too, but leaves undated titles wherever its database puts them.
    public static func filmography(_ items: [BaseItem]) -> [BaseItem] {
        func year(_ item: BaseItem) -> Int? {
            item.productionYear ?? item.premiereDate.map { Calendar(identifier: .gregorian).component(.year, from: $0) }
        }
        return items.sorted { a, b in
            switch (year(a), year(b)) {
            case let (x?, y?) where x != y: return x > y
            case (nil, _?): return false
            case (_?, nil): return true
            default:
                if let x = a.premiereDate, let y = b.premiereDate, x != y { return x > y }
                return (a.name ?? "").localizedStandardCompare(b.name ?? "") == .orderedAscending
            }
        }
    }
}
