import Foundation

/// A run of output audio that is continuous in the source: `sourceStart` is
/// where its first sample sits in the book (seconds).
public struct AudioChunk: Sendable {
    public var sourceStart: Double
    /// One array per channel, equal lengths.
    public var channels: [[Float]]
    public var frameCount: Int { channels.first?.count ?? 0 }
}

/// Smart Speed: shortens the silences in spoken audio, without touching the
/// speech — the way Overcast does. Pauses sound natural, just shorter, so a
/// book finishes sooner at the same voice speed.
///
/// How it works, per 10 ms frame:
/// 1. **Loudness** (RMS, dBFS) of the frame.
/// 2. **Adaptive threshold.** The last 8 s of frames give a noise floor (15th
///    percentile) and a speech level (85th). A frame is silent below
///    floor + 35 % of the gap between them — so a hissy tape and a clean
///    studio recording both work, and quiet words aren't mistaken for gaps.
/// 3. **Pauses.** A run of silent frames shorter than 0.3 s (between words,
///    a breath) passes untouched. A longer pause keeps its first 0.15 s and
///    a tail at the end, and loses the middle: a pause of length L becomes
///    0.3 s + 25 % of (L − 0.3 s), at most 0.9 s — 1 s → 0.48 s, 3 s → 0.9 s.
///    Longer pauses stay longer, so the rhythm survives.
/// 4. **Seams.** 10 ms fades either side of a cut, so room tone never clicks.
///
/// Streaming: a pause is held only until it is known to be long; after that
/// only the last 0.6 s (the possible tail) is kept in memory.
public struct SmartSpeedProcessor: Sendable {
    public var enabled: Bool
    public let sampleRate: Double
    public let channelCount: Int
    /// Seconds of silence removed so far.
    public private(set) var savedSeconds: Double = 0

    // Tuning (seconds).
    static let minPause = 0.30
    static let head = 0.15
    static let keepRatio = 0.25
    static let maxKeep = 0.90
    static let maxTail = maxKeep - head

    private let hop: Int                    // samples per 10 ms frame
    private var carry: [[Float]]            // < hop samples waiting for the next call
    private var carryStart: Double = 0
    private var levels: [Float] = []        // recent frame loudness (dB), ring
    private var levelIndex = 0
    private var framesSinceStats = 0
    private var threshold: Float = -45
    // The current pause.
    private var pause: [[Float]] = []       // held silent audio (all of it until it's long, then the tail)
    private var pauseStart: Double = 0      // source time of the pause's first sample
    private var pauseLength = 0             // samples in the pause so far
    private var cutting = false             // the head has gone out; the middle is being dropped
    private var output: [AudioChunk] = []

    public init(sampleRate: Double, channelCount: Int, enabled: Bool) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.enabled = enabled
        hop = max(1, Int(sampleRate / 100))
        carry = Array(repeating: [], count: channelCount)
    }

    /// Start over at `time` (after a seek): drops held audio, keeps the
    /// loudness history (same recording).
    public mutating func reset(at time: Double) {
        carry = Array(repeating: [], count: channelCount)
        carryStart = time
        pause = []
        pauseLength = 0
        cutting = false
        output = []
    }

    /// Feed decoded audio starting at `sourceStart`; returns what can be
    /// played now (a pause in progress is held back).
    public mutating func process(_ input: [[Float]], sourceStart: Double) -> [AudioChunk] {
        guard let count = input.first?.count, count > 0 else { return [] }
        guard enabled else { return [AudioChunk(sourceStart: sourceStart, channels: input)] }
        if carry[0].isEmpty { carryStart = sourceStart }
        for c in 0..<channelCount { carry[c] += input[c] }
        var offset = 0
        while carry[0].count - offset >= hop {
            let frame = (0..<channelCount).map { Array(carry[$0][offset..<(offset + hop)]) }
            handle(frame, at: carryStart + Double(offset) / sampleRate)
            offset += hop
        }
        if offset > 0 {
            for c in 0..<channelCount { carry[c].removeFirst(offset) }
            carryStart += Double(offset) / sampleRate
        }
        defer { output = [] }
        return output
    }

    /// End of the stream: release whatever is held.
    public mutating func flush() -> [AudioChunk] {
        if enabled {
            if pauseLength > 0 { endPause() }
            if !carry[0].isEmpty { emit(carry, at: carryStart) }
            carry = Array(repeating: [], count: channelCount)
        }
        defer { output = [] }
        return output
    }

    // MARK: Frames

    private mutating func handle(_ frame: [[Float]], at time: Double) {
        let level = Self.loudness(frame)
        track(level)
        if level < threshold {
            if pauseLength == 0 {
                pauseStart = time
                pause = Array(repeating: [], count: channelCount)
            }
            for c in 0..<channelCount { pause[c].append(contentsOf: frame[c]) }
            // Cutting: only the tail can still be played; trim now and then
            // (amortised), not every frame.
            let tailMax = Int(Self.maxTail * sampleRate)
            if cutting, pause[0].count > 2 * tailMax {
                for c in 0..<channelCount { pause[c].removeFirst(pause[c].count - tailMax) }
            }
            pauseLength += hop
            if !cutting, Double(pauseLength) / sampleRate > Self.minPause { startCutting() }
        } else {
            if pauseLength > 0 { endPause() }
            emit(frame, at: time)
        }
    }

    /// The pause is long: play its head (fading out), keep only a tail from now on.
    private mutating func startCutting() {
        let headCount = Int(Self.head * sampleRate)
        var head = pause.map { Array($0.prefix(headCount)) }
        Self.fade(&head, in: false, samples: hop)
        emit(head, at: pauseStart)
        pause = pause.map { Array($0.dropFirst(headCount).suffix(Int(Self.maxTail * sampleRate))) }
        cutting = true
    }

    private mutating func endPause() {
        defer { pause = []; pauseLength = 0; cutting = false }
        guard cutting else {
            emit(pause, at: pauseStart)                               // short: untouched
            return
        }
        let length = Double(pauseLength) / sampleRate
        let keep = min(Self.maxKeep, Self.minPause + Self.keepRatio * (length - Self.minPause))
        let tailCount = min(pause[0].count, Int((keep - Self.head) * sampleRate))
        var tail = pause.map { Array($0.suffix(tailCount)) }
        Self.fade(&tail, in: true, samples: hop)
        let tailStart = pauseStart + length - Double(tailCount) / sampleRate
        savedSeconds += length - Self.head - Double(tailCount) / sampleRate
        emit(tail, at: tailStart)
    }

    private mutating func emit(_ samples: [[Float]], at time: Double) {
        guard let n = samples.first?.count, n > 0 else { return }
        // Extend the last chunk when contiguous in the source.
        if let last = output.last, abs(last.sourceStart + Double(last.frameCount) / sampleRate - time) < 0.5 / sampleRate {
            for c in 0..<channelCount { output[output.count - 1].channels[c].append(contentsOf: samples[c]) }
        } else {
            output.append(AudioChunk(sourceStart: time, channels: samples))
        }
    }

    // MARK: Loudness

    private mutating func track(_ level: Float) {
        let window = 800                                               // 8 s of frames
        if levels.count < window { levels.append(level) } else { levels[levelIndex] = level }
        levelIndex = (levelIndex + 1) % window
        framesSinceStats += 1
        guard framesSinceStats >= 50, levels.count >= 200 else { return }   // every 0.5 s, after 2 s
        framesSinceStats = 0
        let sorted = levels.sorted()
        let floor = sorted[sorted.count * 15 / 100]
        let speech = sorted[sorted.count * 85 / 100]
        threshold = max(-60, min(speech - 6, max(floor + 6, floor + 0.35 * (speech - floor))))
    }

    static func loudness(_ frame: [[Float]]) -> Float {
        var sum: Float = 0
        var n = 0
        for channel in frame {
            for s in channel { sum += s * s }
            n += channel.count
        }
        let rms = (sum / Float(max(1, n))).squareRoot()
        return 20 * log10(max(rms, 1e-7))
    }

    static func fade(_ samples: inout [[Float]], in fadeIn: Bool, samples count: Int) {
        for c in samples.indices {
            let n = min(count, samples[c].count)
            guard n > 1 else { continue }
            for i in 0..<n {
                let g = Float(i) / Float(n - 1)
                let index = fadeIn ? i : samples[c].count - n + i
                samples[c][index] *= fadeIn ? g : 1 - g
            }
        }
    }
}
