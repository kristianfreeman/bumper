public import Foundation
public import JellyfinAPI

/// A library page's words: the line under its name, each row's subtitle,
/// and a line for each genre — specific to what's in it ("Rated 7.5 and up;
/// Severance leads at 8.7.") rather than a label ("Highest rated").
public enum LibraryWords {
    public typealias Noun = (singular: String, plural: String)

    /// "48 shows, 36 with episodes you haven't seen. The newest is Severance."
    public static func lede(all: Int?, unwatched: Int?, noun: Noun, newest: BaseItem?, isShows: Bool) -> String? {
        guard let all else { return nil }
        let words = Editorial(userName: nil)
        var line = "\(all.formatted()) \(all == 1 ? noun.singular : noun.plural)"
        if let unwatched, unwatched > 0 {
            if unwatched == all { line += all == 1 ? ", not yet watched" : ", none of them watched yet" }
            else { line += isShows ? ", \(unwatched.formatted()) with episodes you haven't seen" : ", \(unwatched.formatted()) you haven't seen" }
        } else if unwatched == 0 {
            line += isShows ? ", every episode watched" : ", every one of them watched"
        }
        line += "."
        if let name = newest?.name {
            line += " The newest is \(name)" + (newest?.dateCreated.map { ", added \(words.when($0))" } ?? "") + "."
        }
        return line
    }

    /// A row's subtitle. `first`: the row's first item (in the row's order).
    public static func subtitle(_ id: String, total: Int, noun: Noun, first: BaseItem?, minRating: Double? = nil, decade: Int? = nil, now: Date = .now) -> String? {
        let words = Editorial(now: now, userName: nil)
        let n = total == 1 ? "one \(noun.singular)" : "\(total.formatted()) \(noun.plural)"
        switch id {
        case "recent": return first.map { "Most recently, \($0.name ?? "something new")\(words.addedClause($0.dateCreated))." }
        case "all": return "Every one of them, A to Z — \(n)."
        case "unwatched": return "\(n.capitalizedFirst) you haven't watched, shuffled."
        case "favorites": return total == 1 ? "Just the one you've starred." : "The \(total.formatted()) you've starred."
        case "top":
            let floor = minRating.map { "Rated \(CollectionWords.rating($0)) and up" } ?? "Rated highest"
            if let first, let name = first.name, let score = first.communityRating { return "\(floor); \(name) leads at \(CollectionWords.rating(score))." }
            return "\(floor)."
        case "released":
            if let decade { return "Premieres from the \(decade)s, newest first." }
            return "The latest premieres first."
        case "collections": return "\(n.capitalizedFirst) that belong together."
        default: return nil
        }
    }

    /// "23 comedies, for when you need a laugh." — a line in the genre's own
    /// key where there is one.
    public static func genre(_ genre: String, count: Int, noun: Noun) -> String {
        let key = genre.lowercased()
        let n = count.formatted()
        let flavour: String? = switch true {
        case key.contains("comedy"): "for when you need a laugh"
        case key.contains("horror"): "best with the lights off"
        case key.contains("documentary"): "all of it true"
        case key.contains("thriller"): "for the edge of your seat"
        case key.contains("mystery"): "for the armchair detective"
        case key.contains("crime"): "heists, cons and whodunits"
        case key.contains("romance"): "for the hopeless romantic"
        case key.contains("animation"): "drawn, painted and rendered"
        case key.contains("family"), key.contains("kids"): "for the whole couch"
        case key.contains("sci-fi"), key.contains("science fiction"): "for somewhere far away"
        case key.contains("fantasy"): "dragons optional"
        case key.contains("western"): "dust, horses and long silences"
        case key.contains("war"): "on the front lines"
        case key.contains("history"): "from the history books"
        case key.contains("music"): "turn it up"
        case key.contains("action"), key.contains("adventure"): "explosions very much included"
        case key.contains("drama"): "the serious stuff"
        case key.contains("reality"): "nothing scripted (supposedly)"
        case key.contains("sport"): "no spoilers for the score"
        default: nil
        }
        let what = count == 1 ? "\(genre.lowercased()) \(noun.singular)" : "\(genre.lowercased()) \(noun.plural)"
        return flavour.map { "\(n) \(what), \($0)." } ?? "\(n) \(what), a few picked at random."
    }
}

extension LibraryWords {
    /// What a library's count counts (nil: nothing worth counting).
    public static func countedKinds(_ type: String?) -> [ItemKind]? {
        switch type {
        case "movies": [.movie]
        case "tvshows": [.series]
        case "boxsets": [.boxSet]
        case "books": [.audioBook]
        case "homevideos": [.video]
        case "musicvideos": [.musicVideo]
        case "playlists": [.playlist]
        default: nil
        }
    }

    /// "612 films", "1 show", "34 audiobooks".
    public static func count(_ n: Int, of type: String?) -> String {
        let (one, many): (String, String) = switch type {
        case "movies": ("film", "films")
        case "tvshows": ("show", "shows")
        case "boxsets": ("collection", "collections")
        case "books": ("audiobook", "audiobooks")
        case "homevideos", "musicvideos": ("video", "videos")
        case "playlists": ("playlist", "playlists")
        default: ("title", "titles")
        }
        return "\(n.formatted()) \(n == 1 ? one : many)"
    }
}
