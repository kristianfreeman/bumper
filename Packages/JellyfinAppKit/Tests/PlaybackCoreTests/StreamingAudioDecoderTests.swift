import AVFoundation
import Foundation
@testable import PlaybackCore
import Testing

/// The audiobook decode path on a real file: TestMedia/books (synthesized
/// speech with scripted pauses; scripts/make-audiobook-media.sh).
@Suite("Audiobook decoding")
struct StreamingAudioDecoderTests {
    static let book = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appending(path: "TestMedia/books/the-old-pier.mp3")

    /// Fed in network-sized pieces, the whole book decodes to its full length;
    /// decoding can restart mid-stream (a seek); Smart Speed finds the
    /// scripted pauses in real speech.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: book.path)))
    func decodesStreamedMP3AndSmartSpeedFindsThePauses() throws {
        let data = try Data(contentsOf: Self.book)
        let decoder = StreamingAudioDecoder()
        var offset = 0
        while offset < data.count {                       // 7 KB at a time, like URLSession
            let end = min(data.count, offset + 7_000)
            decoder.parse(data.subdata(in: offset..<end))
            offset = end
        }
        let format = try #require(decoder.pcmFormat)
        #expect(decoder.packetCount > 2000)

        var smart = SmartSpeedProcessor(sampleRate: format.sampleRate, channelCount: Int(format.channelCount), enabled: true)
        var frames = 0, index = 0
        while let pcm = decoder.decode(from: index, count: 40) {
            let t = Double(index) * decoder.packetDuration
            frames += pcm[0].count
            _ = smart.process(pcm, sourceStart: t)
            index += 40
        }
        _ = smart.flush()
        let seconds = Double(frames) / format.sampleRate
        #expect(abs(seconds - 57.4) < 0.3, "decoded \(seconds) s of a 57.4 s book")
        // Scripted pauses: 1.8 0.7 2.5 1.2 3.0 0.6 2.0 0.9 4.0 s → ≈ 10.9 s saved, plus a little between sentences.
        #expect(smart.savedSeconds > 9.5 && smart.savedSeconds < 16, "Smart Speed saved \(smart.savedSeconds) s")

        decoder.resetDecoder()
        let middle = try #require(decoder.decode(from: 1000, count: 40))
        #expect(middle[0].count > 40 * 1000, "decoding mid-stream produced \(middle[0].count) frames")
    }
}
