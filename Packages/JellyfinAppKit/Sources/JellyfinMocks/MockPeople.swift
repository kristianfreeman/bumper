import Foundation
import JellyfinAPI

/// The mock library's people: a cast and crew for every film and show,
/// drawn from one pool, so each person's page has a filmography from the
/// library. Most have a photo, a bio and a birthplace; some don't, as on a
/// real server. Worked out from an item's number, nothing stored.
enum MockPeople {
    static let actors = 60, directors = 15, writers = 12, composers = 4

    private static let first = ["Ada", "Bram", "Celia", "Dev", "Elena", "Felix", "Greta", "Hugo", "Iris", "Jonah", "Kira", "Leo", "Mara",
                                "Nils", "Olive", "Pavel", "Quinn", "Rosa", "Silas", "Tess", "Uma", "Viktor", "Wren", "Yusuf", "Zoe"]
    private static let last = ["Abbott", "Brennan", "Castell", "Duarte", "Ellery", "Fontaine", "Garrow", "Halloran", "Ishikawa", "Jansen", "Kovac", "Lindqvist",
                               "Moreau", "Nakamura", "Okafor", "Pryce", "Quarles", "Reyes", "Sandoval", "Thorne", "Underhill", "Varga", "Whitlock", "Yates"]
    private static let places = ["Leeds, England", "Lyon, France", "Osaka, Japan", "Lagos, Nigeria", "Toronto, Canada", "Valparaíso, Chile",
                                 "Gothenburg, Sweden", "Kraków, Poland", "Melbourne, Australia", "Porto, Portugal", "Cork, Ireland", "Austin, Texas, USA"]
    private static let characters = ["The Keeper", "Detective Hale", "Nora", "Agent Cole", "Young Eli", "The Stranger", "Marta", "Dr. Ashby",
                                     "Sergeant Pike", "Lena", "Old Tom", "The Pilot", "Captain Reyes", "June", "The Narrator", "Abel"]

    /// One person: `role` a/d/w/c (actor, director, writer, composer), `n` their number in it.
    private struct Who {
        let role: Character
        let n: Int
        var id: String { "person-\(role)\(pad(n, 2))" }
        /// Across every pool, for names and the rest: no two people share a name.
        var k: Int {
            switch role {
            case "d": actors + n
            case "w": actors + directors + n
            case "c": actors + directors + writers + n
            default: n
            }
        }
        var name: String { "\(MockPeople.first[(k * 7) % MockPeople.first.count]) \(MockPeople.last[(k * 11) % MockPeople.last.count])" }
        var type: String {
            switch role { case "d": "Director"; case "w": "Writer"; case "c": "Composer"; default: "Actor" }
        }
    }

    private static func who(_ id: String) -> Who? {
        guard id.hasPrefix("person-"), id.count == 10 else { return nil }
        let role = id[id.index(id.startIndex, offsetBy: 7)]
        guard let n = Int(id.suffix(2)) else { return nil }
        let count = switch role { case "a": actors; case "d": directors; case "w": writers; case "c": composers; default: 0 }
        return n < count ? Who(role: role, n: n) : nil
    }

    private static func credit(_ who: Who, as type: String? = nil, role: String? = nil) -> Person {
        Person(id: who.id, name: who.name, role: role ?? (who.role == "a" ? nil : who.type), type: type ?? who.type,
               primaryImageTag: hasPhoto(who) ? "pp-\(who.id)" : nil)
    }

    private static func hasPhoto(_ who: Who) -> Bool { who.k % 6 != 5 }

    /// The director of film `i`. One of them is also an actor (person-a02):
    /// their page says "Actor · Director".
    private static func director(_ i: Int) -> Who {
        let d = i % directors
        return d == 7 ? Who(role: "a", n: 2) : Who(role: "d", n: d)
    }

    /// An item's cast and crew, in the server's order: the cast, then the crew.
    static func people(for itemId: String) -> [Person] {
        if itemId.hasPrefix("movie-"), let i = Int(itemId.dropFirst(6)) {
            let cast = [i % 7, 7 + (i * 3) % 13, 20 + (i * 7) % 17, 37 + (i * 5) % 23]
            var out = cast.enumerated().map { k, a in credit(Who(role: "a", n: a), role: characters[(i + k * 5) % characters.count]) }
            let director = director(i)
            out.append(credit(director, as: "Director", role: "Director"))
            // Every fifteenth film's director wrote it too.
            out.append(i % directors == 3 ? credit(director, as: "Writer", role: "Writer") : credit(Who(role: "w", n: (i * 7) % writers)))
            if i % 4 == 0 { out.append(credit(Who(role: "c", n: (i / 4) % composers))) }
            return out
        }
        if itemId.hasPrefix("series-"), let i = Int(itemId.dropFirst(7)) {
            let cast = [(i * 2) % 7, 7 + (i * 5) % 13, 20 + (i * 3) % 17]
            var out = cast.enumerated().map { k, a in credit(Who(role: "a", n: a), role: characters[(i * 3 + k * 7) % characters.count]) }
            out.append(credit(Who(role: "w", n: i % writers), role: "Creator"))
            return out
        }
        return []
    }

    /// Whether `itemId` credits any of `ids` (in one of `types`, if any are given).
    static func credits(_ itemId: String, anyOf ids: Set<String>, types: Set<String>) -> Bool {
        people(for: itemId).contains { ids.contains($0.id) && (types.isEmpty || types.contains($0.type ?? "")) }
    }

    /// A person's own item (`/Items/person-…`): photo, bio, birth and birthplace.
    static func person(id: String) -> BaseItem? {
        guard let who = who(id) else { return nil }
        let k = who.k
        var p = BaseItem(id: id, name: who.name, kind: .person)
        if hasPhoto(who) { p.imageTags = ["Primary": "pp-\(id)"] }
        let place = k % 3 == 2 ? nil : places[k % places.count]
        p.productionLocations = place.map { [$0] }
        let born = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(identifier: "UTC"),
                                  year: 1940 + (k * 13) % 60, month: 1 + k % 12, day: 1 + (k * 7) % 28)
        p.premiereDate = born.date
        if k == 9 || k == 33 {
            p.endDate = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(identifier: "UTC"), year: 2019 + k % 5, month: 3, day: 2).date
        }
        if k % 5 != 4 { p.overview = bio(who, place: place) }
        return p
    }

    private static func bio(_ who: Who, place: String?) -> String {
        let name = String(who.name.split(separator: " ").first ?? "")
        let city = place.map { String($0.split(separator: ",").first ?? "") } ?? "a small town on the coast"
        switch who.role {
        case "d":
            return "\(name) made short films and music videos in \(city) before a first feature. Writes most of their own films, and works with the same small crew each time."
        case "w":
            return "\(name) wrote for the stage and for radio before television. Their scripts are known for long scenes, few cuts and very good arguments."
        case "c":
            return "\(name) writes for small orchestras and old synthesisers, and records most scores in a single room in \(city)."
        default:
            switch who.n % 3 {
            case 0: return "\(name) grew up in \(city) and started out on stage, moving to film in their twenties. Known for quiet, precise performances that move easily between drama and comedy."
            case 1: return "Trained at a drama school in \(city), \(name) spent a decade in repertory theatre before a breakout role on television, and has worked with several of the directors here more than once."
            default: return "\(name) came to acting late, after years as a session musician in \(city). Often cast as the one person in the room who knows more than they say."
            }
        }
    }
}

/// Trailers and extras for some of the mock library's titles. Film 1 has
/// them all (a trailer in the library, one online, four extras); film 2
/// has none; film 3 only a trailer online (none on the TV).
enum MockExtras {
    private static func number(_ id: String) -> (movie: Bool, n: Int)? {
        if id.hasPrefix("movie-"), let n = Int(id.dropFirst(6)) { return (true, n) }
        if id.hasPrefix("series-"), let n = Int(id.dropFirst(7)) { return (false, n) }
        return nil
    }

    static func localTrailers(for id: String) -> [BaseItem] {
        guard let (movie, n) = number(id), movie ? n % 3 == 1 : n % 4 == 0, let owner = MockCatalog.shared.item(id: id) else { return [] }
        var t = BaseItem(id: "\(id)-trailer", name: "\(owner.name ?? "Trailer") — Trailer", kind: .trailer)
        t.runTimeTicks = 150 * BaseItem.ticksPerSecond
        t.productionYear = owner.productionYear
        t.parentId = id
        t.imageTags = ["Primary": "tr-\(id)"]
        t.parentBackdropItemId = id
        t.parentBackdropImageTags = owner.backdropImageTags
        t.userData = UserItemData()
        return [t]
    }

    /// Big Buck Bunny (Blender's open film) on YouTube: a link that opens to something.
    static func remoteTrailers(for id: String) -> [MediaURL]? {
        guard let (movie, n) = number(id), movie ? n % 2 == 1 : n % 2 == 0 else { return nil }
        return [MediaURL(url: "https://www.youtube.com/watch?v=YE7VzlLtp-4", name: "Official Trailer")]
    }

    static func specialFeatures(for id: String) -> [BaseItem] {
        guard let (movie, n) = number(id), movie ? n % 5 == 1 : n % 6 == 0, let owner = MockCatalog.shared.item(id: id) else { return [] }
        let title = owner.name ?? "It"
        let extras: [(String, String, Int)] = [
            ("Making \(title)", "BehindTheScenes", 14),
            ("Deleted Scenes", "DeletedScene", 9),
            ("The Sound of \(title)", "Featurette", 6),
            ("Cast Interviews", "Interview", 11),
        ]
        return extras.enumerated().map { k, extra in
            var x = BaseItem(id: "\(id)-extra-\(k + 1)", name: extra.0, kind: .video)
            x.extraType = extra.1
            x.runTimeTicks = Int64(extra.2) * 60 * BaseItem.ticksPerSecond
            x.parentId = id
            x.imageTags = ["Primary": "x\(k + 1)-\(id)"]
            x.parentBackdropItemId = id
            x.parentBackdropImageTags = owner.backdropImageTags
            x.userData = UserItemData()
            return x
        }
    }

    /// A trailer's or an extra's own item (`/Items/movie-0001-trailer`).
    static func item(id: String) -> BaseItem? {
        if id.hasSuffix("-trailer") { return localTrailers(for: String(id.dropLast(8))).first }
        if let r = id.range(of: "-extra-") { return specialFeatures(for: String(id[..<r.lowerBound])).first { $0.id == id } }
        return nil
    }

    /// A film or show as the detail page asks for it: with its cast and crew,
    /// and its trailers online (lists leave both out, as the server does
    /// unless asked).
    static func detailed(_ item: BaseItem) -> BaseItem {
        guard item.kind == .movie || item.kind == .series else { return item }
        var out = item
        let people = MockPeople.people(for: item.id)
        if !people.isEmpty { out.people = people }
        out.remoteTrailers = remoteTrailers(for: item.id)
        return out
    }
}
