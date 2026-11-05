import Foundation
import JellyfinAPI

/// The line under a row's title, written from what's in the row, so a row
/// reads as a shelf someone put together rather than a filter:
///
///   Thriller     142 films, from Heat to Prisoners · mostly the 90s
///   The 80s      61 films, from Alien to Akira
///   Alien        6 films, 1979 to 2017 · 2 you haven't seen
///
/// How many and two you'd know, then (a genre) when they're from. Something
/// that doesn't stand out (no decade has most of them) is left out, not said
/// weakly. How many of a genre you haven't seen isn't said: in a big library
/// it's a big number that tells you nothing. A collection's is (a few films).
nonisolated enum RowLine {
    enum Kind: String, Codable, Sendable, Hashable { case genre, decade, collection }

    /// `items`: the row's cards (a genre's are a few at random from it);
    /// `total`: how many there are in all.
    static func make(_ kind: Kind, items: [BaseItem], total: Int?) -> String? {
        guard !items.isEmpty else { return nil }
        let noun = Noun(items)
                var parts: [String] = []
        switch kind {
        case .genre, .decade:
            let anchors = Self.anchors(items).map { "from \($0.0) to \($0.1)" }
            parts.append([total.map { noun.count($0) }, anchors].compactMap { $0 }.joined(separator: ", "))
            // A decade's row already says when.
            if kind == .genre, let era = Self.era(items) { parts.append(era) }
        case .collection:
            // In the order they came out: first to last.
            let years = items.compactMap(\.productionYear)
            var lead = noun.count(total ?? items.count)
            if let first = years.min(), let last = years.max() {
                lead += first == last ? ", all from \(first)" : ", \(first) to \(last)"
            }
            parts.append(lead)
            let notSeen = items.filter { !$0.isPlayed }.count
            if let more = Self.unseen(notSeen, of: items.count, noun: noun) { parts.append(more) }
        }
        let line = parts.filter { !$0.isEmpty }.joined(separator: " · ")
        return line.isEmpty ? nil : line.prefix(1).uppercased() + line.dropFirst()
    }

    /// Two in the row you'd know (the best rated), the older first: "Heat"
    /// and "Prisoners". Only short names with no punctuation — "from Star
    /// Wars: Episode IV – A New Hope to Dr. Strangelove" reads as junk. Nil
    /// with fewer than two.
    static func anchors(_ items: [BaseItem]) -> (String, String)? {
        let rated = items.filter { $0.communityRating != nil && plain($0.name ?? "") }
            .sorted { ($0.communityRating ?? 0, $1.name ?? "") > ($1.communityRating ?? 0, $0.name ?? "") }
        guard rated.count >= 2 else { return nil }
        let two = rated.prefix(2).sorted { ($0.productionYear ?? 0) < ($1.productionYear ?? 0) }
        return (two[0].name ?? "", two[1].name ?? "")
    }

    /// Short, and only letters, digits and spaces: "Heat", "Blade Runner",
    /// "Alien 3" — not "Dr. No", "Léon: The Professional" or "The Lord of
    /// the Rings".
    static func plain(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 18 && name.split(separator: " ").count <= 3
            && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == " " }
    }

    /// "mostly the 90s": when one decade has at least half of them (of six
    /// or more with a year). Nil when they're spread out.
    static func era(_ items: [BaseItem]) -> String? {
        let years = items.compactMap(\.productionYear)
        guard years.count >= 6 else { return nil }
        let decades = Dictionary(grouping: years) { $0 / 10 * 10 }
        guard let (decade, inIt) = decades.max(by: { ($0.value.count, $1.key) < ($1.value.count, $0.key) }),
              Double(inIt.count) / Double(years.count) >= 0.5 else { return nil }
        return "mostly the \(decade >= 2000 ? String(decade) : String(String(decade).suffix(2)))s"
    }

    /// What you haven't seen of `count`: nothing when that's none of it
    /// (nothing to say) — "all seen" or how many are left otherwise.
    static func unseen(_ unseen: Int, of count: Int, noun: Noun) -> String? {
        guard count > 0 else { return nil }
        if unseen <= 0 { return "you've seen \(count == 1 ? "it" : count == 2 ? "both" : "them all")" }
        if unseen >= count { return nil }
        return "\(unseen) you haven't \(noun.seen)"
    }

    /// Films, shows, or both — from what's in the row.
    struct Noun {
        let one: String, many: String, seen: String

        init(_ items: [BaseItem]) {
            let kinds = Set(items.map(\.kind))
            if kinds == [.series] { (one, many, seen) = ("show", "shows", "finished") }
            else if kinds.contains(.series) { (one, many, seen) = ("film or show", "films and shows", "seen") }
            else { (one, many, seen) = ("film", "films", "seen") }
        }

        func count(_ n: Int) -> String { "\(n) \(n == 1 ? one : many)" }
    }
}
