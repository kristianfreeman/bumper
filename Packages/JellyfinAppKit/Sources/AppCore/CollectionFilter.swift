public import Foundation
public import JellyfinAPI

/// What a collection page shows, as something you can read and change:
/// *Movies · added in the last month · unwatched · comedy · under 90 minutes*.
/// Each part is a pill on the page; words ("something funny from the 80s,
/// under an hour and a half") set them through `apply(words:)`.
public struct CollectionFilter: Sendable, Hashable, Codable {
    public enum Added: String, Sendable, Codable, CaseIterable { case any, week, month, year }
    public enum Watched: String, Sendable, Codable, CaseIterable { case any, unwatched, watched }
    public enum Sort: String, Sendable, Codable, CaseIterable { case name, added, released, rating }

    /// The library (or collection) it's drawn from: its query's parent and types.
    public var base: ItemQuery
    public var libraryName: String
    public var added: Added = .any
    public var watched: Watched = .any
    public var favourites = false
    public var genre: String?
    /// 1990 = the 1990s.
    public var decade: Int?
    public var maxMinutes: Int?
    public var minRating: Double?
    public var sort: Sort = .name

    /// Starts from a collection's own query: its filters, genre and order
    /// become parts of the sentence you can change.
    public init(base: ItemQuery, libraryName: String) {
        var b = base
        if b.filters.contains("IsUnplayed") { watched = .unwatched }
        if b.filters.contains("IsPlayed") { watched = .watched }
        favourites = b.filters.contains("IsFavorite")
        b.filters.removeAll { ["IsUnplayed", "IsPlayed", "IsFavorite"].contains($0) }
        genre = b.genres.first
        b.genres = []
        switch b.sortBy.first {
        case "DateCreated": sort = .added
        case "PremiereDate": sort = .released
        case "CommunityRating": sort = .rating
        default: sort = .name
        }
        b.startIndex = 0
        self.base = b
        self.libraryName = libraryName
    }

    public var sortTitle: String {
        switch sort {
        case .name: "A–Z"
        case .added: "Recently added"
        case .released: "Release date"
        case .rating: "Rating"
        }
    }

    // MARK: The sentence

    public enum Part: String, Sendable, CaseIterable { case added, watched, favourites, genre, decade, length, rating }

    /// The set parts, in reading order.
    public var parts: [Part] {
        Part.allCases.filter { part in
            switch part {
            case .added: added != .any
            case .watched: watched != .any
            case .favourites: favourites
            case .genre: genre != nil
            case .decade: decade != nil
            case .length: maxMinutes != nil
            case .rating: minRating != nil
            }
        }
    }

    public func text(_ part: Part) -> String {
        switch part {
        case .added:
            switch added {
            case .any: "added any time"
            case .week: "added this week"
            case .month: "added in the last month"
            case .year: "added this year"
            }
        case .watched: watched == .unwatched ? "unwatched" : "watched"
        case .favourites: "favourites"
        case .genre: genre?.lowercased() ?? ""
        case .decade: decade.map { "from the \($0)s" } ?? ""
        case .length: maxMinutes.map { $0 % 60 == 0 ? "under \($0 / 60) hour\($0 == 60 ? "" : "s")" : "under \($0) minutes" } ?? ""
        case .rating: minRating.map { "rated \($0.formatted(.number.precision(.fractionLength(0...1))))+" } ?? ""
        }
    }

    /// "Movies · added in the last month · unwatched"
    public var sentence: String { ([libraryName] + parts.map(text)).joined(separator: " · ") }

    public mutating func clear(_ part: Part) {
        switch part {
        case .added: added = .any
        case .watched: watched = .any
        case .favourites: favourites = false
        case .genre: genre = nil
        case .decade: decade = nil
        case .length: maxMinutes = nil
        case .rating: minRating = nil
        }
    }

    // MARK: The query

    /// The server's half of the filter (the rest — when added, length — is
    /// checked on the items, since /Items can't filter on them).
    public var query: ItemQuery {
        var q = base
        q.filters = base.filters.filter { $0 != "IsUnplayed" && $0 != "IsPlayed" && $0 != "IsFavorite" }
        if watched == .unwatched { q.filters.append("IsUnplayed") }
        if watched == .watched { q.filters.append("IsPlayed") }
        if favourites { q.filters.append("IsFavorite") }
        if let genre { q.genres = [genre] }
        if let decade { q.years = Array(decade..<(decade + 10)) }
        if let minRating { q.minCommunityRating = minRating }
        // "Added recently" pages newest-first so we can stop at the cutoff.
        let effective: Sort = added != .any ? .added : sort
        switch effective {
        case .name: q.sortBy = ["SortName"]; q.sortOrder = .ascending
        case .added: q.sortBy = ["DateCreated", "SortName"]; q.sortOrder = .descending
        case .released: q.sortBy = ["PremiereDate", "SortName"]; q.sortOrder = .descending
        case .rating: q.sortBy = ["CommunityRating", "SortName"]; q.sortOrder = .descending
        }
        q.fields = q.fields.contains(.dateCreated) ? q.fields : q.fields + [.dateCreated]
        return q
    }

    public func addedCutoff(now: Date = .now) -> Date? {
        switch added {
        case .any: nil
        case .week: now.addingTimeInterval(-7 * 86_400)
        case .month: now.addingTimeInterval(-31 * 86_400)
        case .year: now.addingTimeInterval(-365 * 86_400)
        }
    }

    /// The client-side half.
    public func matches(_ item: BaseItem, now: Date = .now) -> Bool {
        if let cutoff = addedCutoff(now: now), (item.dateCreated ?? .distantPast) < cutoff { return false }
        if let maxMinutes, let ticks = item.runTimeTicks, Double(ticks) / Double(BaseItem.ticksPerSecond) / 60 > Double(maxMinutes) { return false }
        return true
    }

    // MARK: Words

    /// Moods → genres, for "something funny", "scary", "lighter"…
    static let moods: [(words: [String], genre: String)] = [
        (["funny", "comedy", "comedies", "laugh", "lighter", "light"], "Comedy"),
        (["scary", "horror", "frightening"], "Horror"),
        (["action", "exciting", "explosions"], "Action"),
        (["romantic", "romance", "love story"], "Romance"),
        (["sad", "drama", "dramas", "cry", "serious"], "Drama"),
        (["mystery", "whodunit", "detective"], "Mystery"),
        (["thriller", "tense", "suspense"], "Thriller"),
        (["sci-fi", "science fiction", "space"], "Science Fiction"),
        (["animated", "animation", "cartoon"], "Animation"),
        (["documentary", "documentaries", "true story", "real"], "Documentary"),
        (["family", "kids", "children"], "Family"),
        (["western", "westerns"], "Western"),
    ]

    /// Reads a request and sets what it asks for. Returns the parts it
    /// changed (so the page can show what it understood). `genres`: the
    /// library's own genre names, matched before the mood words.
    @discardableResult
    public mutating func apply(words raw: String, genres: [String] = []) -> [Part] {
        let text = " " + raw.lowercased().replacingOccurrences(of: "[^a-z0-9' ]", with: " ", options: .regularExpression) + " "
        var changed: [Part] = []
        func has(_ phrase: String) -> Bool { text.contains(" \(phrase) ") }

        if has("unwatched") || has("haven't seen") || has("havent seen") || has("not seen") || has("new to me") { watched = .unwatched; changed.append(.watched) }
        else if has("seen") || has("watched") || has("rewatch") { watched = .watched; changed.append(.watched) }
        if has("favourite") || has("favorite") || has("favourites") || has("favorites") { favourites = true; changed.append(.favourites) }

        if has("this week") || has("new this week") { added = .week; changed.append(.added) }
        else if has("this month") || has("last month") || has("recent") || has("recently added") || has("new") { added = .month; changed.append(.added) }
        else if has("this year") { added = .year; changed.append(.added) }

        if let match = text.range(of: #" (?:the )?(19|20)?([0-9])0'?s "#, options: .regularExpression) {
            let digits = text[match].filter(\.isNumber)
            let century = digits.count >= 3 ? Int(digits.prefix(2))! * 100 : (Int(digits.prefix(1))! >= 3 ? 1900 : 2000)
            let tens = Int(String(digits.dropLast().last!))! * 10
            decade = century + tens
            changed.append(.decade)
        } else {
            for (word, value) in [("twenties", 1920), ("thirties", 1930), ("forties", 1940), ("fifties", 1950), ("sixties", 1960),
                                  ("seventies", 1970), ("eighties", 1980), ("nineties", 1990)] where has(word) {
                decade = value
                changed.append(.decade)
            }
        }

        if let m = text.range(of: #"under (an? )?([0-9]+|an?|one|two|three) (hours?|minutes?|mins?)"#, options: .regularExpression) {
            let phrase = String(text[m])
            let numbers = ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3]
            let n = phrase.split(separator: " ").compactMap { Int($0) ?? numbers[String($0)] }.first ?? 1
            var minutes = phrase.contains("hour") ? n * 60 : n
            if text[m.upperBound...].hasPrefix(" and a half") || text[m.upperBound...].hasPrefix("and a half") { minutes += 30 }
            maxMinutes = minutes
            changed.append(.length)
        } else if has("short") || has("quick") {
            maxMinutes = 90
            changed.append(.length)
        }

        if has("highly rated") || has("best") || has("top rated") || has("good") || has("acclaimed") { minRating = 7.5; changed.append(.rating) }

        if let named = genres.first(where: { text.contains(" \($0.lowercased()) ") }) {
            genre = named
            changed.append(.genre)
        } else if let mood = Self.moods.first(where: { $0.words.contains(where: has) }) {
            genre = genres.first { $0.caseInsensitiveCompare(mood.genre) == .orderedSame } ?? mood.genre
            changed.append(.genre)
        }
        return changed
    }
}
