public import Foundation
public import JellyfinAPI
#if !os(macOS)
import os
#endif

/// The safety net under VLCKit's ASS/SSA rendering. Heavy typesetting and
/// karaoke make libass's caches grow without bound (an anime episode took
/// the Mac from ~380 MB to ~1.8 GB in two minutes), and on a 2017 Apple TV
/// 4K the system ended the app — no crash, no report. While VLCKit draws
/// ASS, memory is sampled twice a second; once what's left falls under
/// `threshold`, it trips (once per item) and the player swaps to plain
/// subtitles drawn by the app.
public struct MemoryGuard: Sendable {
    /// Two samples a second: libass grew ~12 MB/s on the Mac, so the
    /// headroom covers far more than half a second of it.
    public static let interval: Duration = .milliseconds(500)

    /// Bytes left before the system ends the app (nil: can't tell).
    public let available: @Sendable () -> Int?
    /// Trip when fewer bytes than this are left.
    public let threshold: Int
    public private(set) var hasTripped = false
    /// Readings taken (tests).
    public private(set) var samples = 0

    public init(threshold: Int = MemoryGuard.threshold(), available: @escaping @Sendable () -> Int? = AvailableMemory.now) {
        self.threshold = threshold
        self.available = available
    }

    /// ~400 MB of headroom on a 3 GB Apple TV 4K (an eighth of the device's
    /// memory): enough to swap subtitles before the jetsam limit, without
    /// tripping on a 2 GB phone that runs closer to it all the time; never
    /// under 256 MB nor over 512 MB. `override` is `-memoryGuardAt <MB>` (a
    /// very high one trips at once: for checking the swap on a device).
    public static func threshold(physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory,
                                 override megabytes: Int? = nil) -> Int {
        if let megabytes, megabytes > 0 { return megabytes * 1_048_576 }
        let eighth = Int(physicalMemory / 8)
        return min(max(eighth, 256 * 1_048_576), 512 * 1_048_576)
    }

    /// Only what libass draws: an ASS/SSA track VLCKit renders. Plain text
    /// (SRT, WebVTT) and bitmaps (PGS) don't grow like it.
    public static func covers(_ stream: MediaStream?, engine: EngineKind, rendersSubtitles: Bool) -> Bool {
        guard engine == .vlc, rendersSubtitles, let codec = stream?.codec?.lowercased() else { return false }
        return ["ass", "ssa"].contains(codec)
    }

    /// One reading. Returns what was left the one time it trips; nil
    /// otherwise (and every time after).
    public mutating func sample() -> Int? {
        guard !hasTripped else { return nil }
        samples += 1
        guard let left = available(), left < threshold else { return nil }
        hasTripped = true
        return left
    }

    /// Samples every `interval` while `covered()` says the item is drawing
    /// ASS through VLCKit, until it trips (returning what was left), the
    /// task is cancelled or `covered()` is nil (the player's gone). Runs on
    /// the caller's actor (`covered` reads the player).
    public mutating func watch(every interval: Duration = MemoryGuard.interval, isolation: isolated (any Actor)? = #isolation,
                               covered: () -> Bool?) async -> Int? {
        while !Task.isCancelled {
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled, let drawing = covered() else { return nil }
            if drawing, let left = sample() { return left }
        }
        return nil
    }
}

/// How much memory the app has left before the system ends it.
public enum AvailableMemory {
    /// The TV, iPhone and iPad: what jetsam allows, less what's in use. The
    /// Mac has no jetsam (it compresses and swaps): there, and where the
    /// system reports no limit (a simulator), a fixed 4 GB budget less the
    /// app's footprint — so the Mac keeps ASS until something runs away
    /// (the 1.8 GB episode doesn't trip it), and a forced threshold still
    /// works everywhere.
    public static let fallbackBudget = 4 * 1_073_741_824

    @Sendable public static func now() -> Int? {
        #if !os(macOS)
        let left = os_proc_available_memory()
        if left > 0 { return left }
        #endif
        return footprint().map { fallbackBudget - $0 }
    }

    /// The app's physical footprint (what jetsam and Activity Monitor count).
    public static func footprint() -> Int? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint) : nil
    }
}
