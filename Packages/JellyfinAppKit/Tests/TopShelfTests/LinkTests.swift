import Foundation
import Testing
import TopShelf

struct LinkTests {
    @Test func readsTheShelfsLinks() {
        let item = TopShelfSnapshot.Item(id: "episode-42", title: "Lost")
        #expect(TopShelfSnapshot.Link(item.playURL) == .play("episode-42"))
        #expect(TopShelfSnapshot.Link(item.displayURL) == .item("episode-42"))
        #expect(TopShelfSnapshot.Link(URL(string: "https://example.com/play/x")!) == nil)
        #expect(TopShelfSnapshot.Link(URL(string: "bumper://play")!) == nil)
        for link in [TopShelfSnapshot.Link.library("view-1"), .queue, .search] { #expect(TopShelfSnapshot.Link(link.url) == link) }
        let tile = TopShelfSnapshot.Item(id: "movies", title: "Movies", link: TopShelfSnapshot.Link.library("view-1").url)
        #expect(TopShelfSnapshot.Link(tile.playURL) == .library("view-1"))
    }
}
