import Foundation
import JellyfinAPI
@testable import PlaybackCore
import Synchronization
import Testing

/// The safety net under VLCKit's ASS rendering: when it trips, and for what.
@Suite("Memory guard")
struct MemoryGuardTests {
    static let mb = 1_048_576

    /// A reading that walks through `megabytes`, then stays on the last.
    final class Readings: Sendable {
        let megabytes: [Int?]
        let taken = Mutex(0)
        init(_ megabytes: [Int?]) { self.megabytes = megabytes }

        var reading: @Sendable () -> Int? {
            { [self] in
                let i = taken.withLock { n in defer { n += 1 }; return min(n, megabytes.count - 1) }
                return megabytes[i].map { $0 * MemoryGuardTests.mb }
            }
        }
    }

    static func stream(_ codec: String?) -> MediaStream { MediaStream(index: 2, type: .subtitle, codec: codec) }

    @Test func theThresholdIsAnEighthOfTheDevicesMemoryWithinBounds() {
        let gb: UInt64 = 1_073_741_824
        #expect(MemoryGuard.threshold(physicalMemory: 3 * gb) == 384 * Self.mb, "a 2017 Apple TV 4K: about 400 MB")
        #expect(MemoryGuard.threshold(physicalMemory: 1 * gb) == 256 * Self.mb)
        #expect(MemoryGuard.threshold(physicalMemory: 16 * gb) == 512 * Self.mb)
        #expect(MemoryGuard.threshold(physicalMemory: 3 * gb, override: 100_000) == 100_000 * Self.mb, "-memoryGuardAt")
        #expect(MemoryGuard.interval == .milliseconds(500), "twice a second")
    }

    @Test func itTripsOnceWhenWhatsLeftFallsUnderTheThreshold() {
        var memory = MemoryGuard(threshold: 400 * Self.mb, available: Readings([900, 500, 300, 100, 50]).reading)
        #expect(memory.sample() == nil)
        #expect(memory.sample() == nil)
        #expect(memory.sample() == 300 * Self.mb)
        #expect(memory.hasTripped)
        #expect(memory.sample() == nil && memory.sample() == nil, "once per item")
        #expect(memory.samples == 3, "no more readings once tripped")
    }

    @Test func noReadingNeverTrips() {
        var memory = MemoryGuard(threshold: 400 * Self.mb, available: { nil })
        for _ in 0..<5 { #expect(memory.sample() == nil) }
        #expect(!memory.hasTripped)
    }

    @Test func itCoversOnlyASSAndSSAThatVLCKitDraws() {
        #expect(MemoryGuard.covers(Self.stream("ass"), engine: .vlc, rendersSubtitles: true))
        #expect(MemoryGuard.covers(Self.stream("SSA"), engine: .vlc, rendersSubtitles: true))
        #expect(!MemoryGuard.covers(Self.stream("subrip"), engine: .vlc, rendersSubtitles: true), "plain text")
        #expect(!MemoryGuard.covers(Self.stream("pgssub"), engine: .vlc, rendersSubtitles: true), "bitmaps")
        #expect(!MemoryGuard.covers(Self.stream("ass"), engine: .native, rendersSubtitles: false), "AVPlayer: the overlay draws")
        #expect(!MemoryGuard.covers(Self.stream("ass"), engine: .vlc, rendersSubtitles: false))
        #expect(!MemoryGuard.covers(nil, engine: .vlc, rendersSubtitles: true), "subtitles off")
    }

    @Test func itSamplesOnlyWhileCoveredAndStopsAtTheTrip() async {
        let readings = Readings([900, 900, 100])
        var memory = MemoryGuard(threshold: 400 * Self.mb, available: readings.reading)
        var ticks = 0
        let left = await memory.watch(every: .milliseconds(1)) {
            ticks += 1
            return ticks > 3                       // another track for the first three ticks
        }
        #expect(left == 100 * Self.mb)
        #expect(readings.taken.withLock { $0 } == 3,"read only once covered, until it tripped")
        #expect(ticks == 6)
    }

    @Test func theWatchEndsWhenThePlayerHasGone() async {
        var memory = MemoryGuard(threshold: 400 * Self.mb, available: { 100 * Self.mb })
        #expect(await memory.watch(every: .milliseconds(1)) { nil } == nil)
        #expect(memory.samples == 0)
    }

    @Test func aCancelledWatchEndsWithoutTripping() async {
        let task = Task {
            var memory = MemoryGuard(threshold: 400 * Self.mb, available: { 900 * Self.mb })
            return await memory.watch(every: .milliseconds(1)) { true }
        }
        try? await Task.sleep(for: .milliseconds(20))
        task.cancel()
        #expect(await task.value == nil)
    }
}
