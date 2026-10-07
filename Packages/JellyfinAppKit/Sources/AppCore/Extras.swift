public import Foundation
public import JellyfinAPI

/// A film or show's trailer: one in the library (played like the film
/// itself), or the server's link to one online (a YouTube page).
public enum Trailer: Sendable, Hashable {
    case local(BaseItem)
    case remote(URL)

    /// The library's own first; else the first online one that's a web
    /// link — where links can be opened (the TV has no browser or YouTube
    /// app to hand them to).
    public static func choose(local: [BaseItem], remote: [MediaURL]?, opensLinks: Bool) -> Trailer? {
        if let first = local.first(where: { $0.kind.isPlayable }) { return .local(first) }
        guard opensLinks else { return nil }
        let link = remote?.lazy.compactMap { $0.url.flatMap(URL.init(string:)) }.first { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
        return link.map(Trailer.remote)
    }
}

/// Behind the scenes, deleted scenes and the like.
public enum Extras {
    /// What a page shows of what the server lists as extras: not theme
    /// music or videos (Home plays those), nor trailers (the Trailer button's).
    public static func shown(_ items: [BaseItem]) -> [BaseItem] {
        let hidden: Set<String> = ["ThemeSong", "ThemeVideo", "Trailer"]
        return items.filter { !hidden.contains($0.extraType ?? "") && $0.kind != .audio }
    }

    /// Under an extra's card: "Behind the Scenes · 12 min".
    public static func caption(_ item: BaseItem) -> String? {
        let kind: String? = switch item.extraType {
        case "BehindTheScenes": "Behind the Scenes"
        case "DeletedScene": "Deleted Scene"
        case "Featurette": "Featurette"
        case "Interview": "Interview"
        case "Scene": "Scene"
        case "Short": "Short"
        case "Clip": "Clip"
        case "Sample": "Sample"
        default: nil
        }
        let minutes = item.runTimeTicks.map { max(1, Int(($0 / BaseItem.ticksPerSecond + 30) / 60)) }.map { "\($0) min" }
        let parts = [kind, minutes].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
