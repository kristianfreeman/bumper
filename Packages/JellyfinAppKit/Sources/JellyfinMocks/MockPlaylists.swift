import Foundation
import JellyfinAPI

/// `-mockPlaylists`: a Playlists library — two video playlists (episodes and
/// films mixed, in a set order) and a music one the app leaves out.
enum MockPlaylists {
    static let viewId = "view-playlists"
    static var isConfigured: Bool { ProcessInfo.processInfo.arguments.contains("-mockPlaylists") }

    static var view: BaseItem {
        var v = BaseItem(id: viewId, name: "Playlists", kind: .collectionFolder)
        v.collectionType = "playlists"
        return v
    }

    static func playlists(_ catalog: MockCatalog) -> [BaseItem] {
        [playlist("playlist-marathon", "Weekend Marathon", entries(catalog, "playlist-marathon")),
         playlist("playlist-films", "Films to Rewatch", entries(catalog, "playlist-films")),
         { var p = playlist("playlist-music", "Road Trip", []); p.mediaType = "Audio"; return p }()]
    }

    static func entries(_ catalog: MockCatalog, _ id: String) -> [BaseItem] {
        switch id {
        case "playlist-marathon":
            let show = catalog.series.first.flatMap { catalog.seasons[$0.id]?.first }.flatMap { catalog.episodes[$0.id] } ?? []
            return Array(show.prefix(4)) + Array(catalog.movies.prefix(2))
        case "playlist-films":
            return Array(catalog.movies.dropFirst(10).prefix(5))
        default:
            return []
        }
    }

    private static func playlist(_ id: String, _ name: String, _ items: [BaseItem]) -> BaseItem {
        var p = BaseItem(id: id, name: name, kind: .playlist)
        p.mediaType = "Video"
        p.childCount = items.count
        p.runTimeTicks = items.compactMap(\.runTimeTicks).reduce(0, +)
        p.imageTags = items.first?.imageTags
        p.backdropImageTags = items.first?.backdropImageTags
        return p
    }
}
