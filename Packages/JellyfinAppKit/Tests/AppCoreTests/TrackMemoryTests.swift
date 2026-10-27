import Foundation
import JellyfinAPI
import Testing
@testable import AppCore

/// A show remembers the subtitles and audio last chosen in it: the next
/// episode gets the closest match, or Off when they were switched off.
struct TrackMemoryTests {
    func stream(_ index: Int, _ type: MediaStreamType, _ language: String?, codec: String, title: String? = nil) -> MediaStream {
        var s = MediaStream(index: index, type: type, codec: codec)
        s.language = language
        s.displayTitle = title
        return s
    }

    @Test func theNextEpisodeGetsTheClosestSubtitleAndTheSameAudio() throws {
        let defaults = try #require(UserDefaults(suiteName: "tracks-\(UUID().uuidString)"))
        let memory = TrackMemory(defaults: defaults)
        memory.update(show: "s1") {
            $0.remember(subtitle: stream(5, .subtitle, "eng", codec: "subrip", title: "English SDH"))
            $0.audioLanguage = "jpn"
        }
        let next = [stream(2, .subtitle, "eng", codec: "ass", title: "English"),
                    stream(3, .subtitle, "eng", codec: "subrip", title: "English (SDH)"),
                    stream(4, .subtitle, "spa", codec: "subrip")]
        let audio = [stream(0, .audio, "eng", codec: "aac"), stream(1, .audio, "jpn", codec: "aac")]
        let preference = try #require(memory.preference(forShow: "s1"))
        #expect(preference.subtitle(in: next) == 3)
        #expect(preference.audio(in: audio) == 1)

        memory.update(show: "s1") { $0.remember(subtitle: nil) }
        #expect(memory.preference(forShow: "s1")?.subtitlesOff == true)
        #expect(memory.preference(forShow: "s1")?.subtitle(in: next) == nil)
        #expect(memory.preference(forShow: "other") == nil)
    }
}
