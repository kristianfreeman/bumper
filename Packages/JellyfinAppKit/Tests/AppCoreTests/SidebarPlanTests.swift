@testable import AppCore
import JellyfinAPI
import Testing

/// The sidebar never grows past seven entries (Home + 4 libraries + Search + Settings).
@Suite("Sidebar plan")
struct SidebarPlanTests {
    static func lib(_ name: String, _ type: String?) -> BaseItem {
        var v = BaseItem(id: name.lowercased(), name: name, kind: .collectionFolder)
        v.collectionType = type
        return v
    }

    @Test func foldsARealServerIntoFourTabs() {
        // The library list that broke the sidebar on a real server.
        let views = [Self.lib("Audiobooks", "books"), Self.lib("Books", "books"), Self.lib("Collections", "boxsets"), Self.lib("Movies", "movies"),
                     Self.lib("Playlists", "playlists"), Self.lib("Shows", "tvshows"), Self.lib("Videos", "homevideos")]
        let plan = SidebarPlan(views: views) { $0.name == "Audiobooks" }      // "Books" holds e-books
        #expect(plan.entries == [.audiobooks([views[0]]), .library(views[3]), .library(views[5]), .library(views[6])])
        #expect(plan.collections == [views[2]])

        let many = (1...7).map { Self.lib("Lib \($0)", "movies") }
        let crowded = SidebarPlan(views: many) { _ in true }
        #expect(crowded.entries.count == SidebarPlan.maxLibraryTabs)
        #expect(crowded.entries.last == .more(Array(many[3...])))
    }
}
