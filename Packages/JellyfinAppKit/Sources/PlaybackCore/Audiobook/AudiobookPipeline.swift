public import AVFoundation
public import Foundation

/// Audiobook playback, end to end:
///
///     HTTP (MP3, from `streamURL(t)`) → packets → PCM → Smart Speed
///         → AVAudioPlayerNode → AVAudioUnitTimePitch (speed, pitch kept) → out
///
/// Everything runs on one serial queue; the owner gets state on the main
/// queue through `onUpdate`. Downloaded packets stay in memory (a window of
/// ~30 min), so seeks into them are instant; a seek outside starts a new
/// request at that time (the server's transcoder starts there).
public final class AudiobookPipeline: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    public struct State: Sendable, Equatable {
        public var position: Double = 0          // source seconds, what's audible now
        public var playing = false
        public var buffering = true
        public var ended = false
        public var savedSeconds: Double = 0      // by Smart Speed
        public var error: String?
    }

    /// Where a stream starting at `t` seconds comes from.
    public typealias StreamURL = @Sendable (Double) -> URL

    public var onUpdate: (@Sendable (State) -> Void)?

    private let queue = DispatchQueue(label: "audiobook.pipeline", qos: .userInitiated)
    private let streamURL: StreamURL
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private var session: URLSession!
    private var task: URLSessionDataTask?
    private var suspended = false

    // Stream (queue-confined).
    private var decoder = StreamingAudioDecoder()
    private var streamStart: Double = 0          // source time of stream packet 0
    private var streamFinished = false
    private var decodeIndex = 0                  // next stream packet to decode
    private var discardUntil: Double = 0         // after a seek: drop decoded audio before this
    private var smart: SmartSpeedProcessor?
    private var smartEnabled: Bool
    private var savedBefore: Double = 0          // Smart Speed savings from earlier processors

    // Output timeline (queue-confined): what's been handed to the player node.
    private struct Scheduled { var outStart: Int64; var frames: Int; var sourceStart: Double }
    private var scheduled: [Scheduled] = []
    private var outCursor: Int64 = 0
    private var connected = false
    private var wantsPlay = false
    private var state = State()
    private var ticker: (any DispatchSourceTimer)?
    private var generation = 0                   // bumps on every seek: stale callbacks are ignored

    /// Seconds of audio to keep scheduled ahead, and of packets to keep behind.
    static let lead = 8.0
    static let keepBehind = 15.0 * 60
    static let readAhead = 30.0 * 60

    public init(streamURL: @escaping StreamURL, smartSpeed: Bool) {
        self.streamURL = streamURL
        self.smartEnabled = smartSpeed
        super.init()
        let delegateQueue = OperationQueue()
        unsafe delegateQueue.underlyingQueue = queue
        delegateQueue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: .default, delegate: self, delegateQueue: delegateQueue)
        engine.attach(player)
        engine.attach(timePitch)
    }

    // MARK: Control (any thread)

    public func start(at time: Double, playing: Bool) {
        queue.async { [self] in
            wantsPlay = playing
            open(at: time)
            startTicker()
        }
    }

    public func play() { queue.async { [self] in wantsPlay = true; resumeOutput() } }
    public func pause() { queue.async { [self] in wantsPlay = false; player.pause(); engine.pause(); publish() } }

    public func seek(to time: Double) {
        queue.async { [self] in seekNow(to: max(0, time)) }
    }

    /// 0…1 (the sleep timer's fade).
    public func setVolume(_ volume: Float) {
        queue.async { [self] in engine.mainMixerNode.outputVolume = volume }
    }

    public func setRate(_ rate: Float) {
        queue.async { [self] in timePitch.rate = rate }
    }

    /// Takes effect at once: what's scheduled ahead is re-made from the playhead.
    public func setSmartSpeed(_ on: Bool) {
        queue.async { [self] in
            guard on != smartEnabled else { return }
            smartEnabled = on
            seekNow(to: currentPosition())
        }
    }

    public func stop() {
        queue.async { [self] in
            ticker?.cancel()
            task?.cancel()
            player.stop()
            engine.stop()
            session.invalidateAndCancel()
        }
    }

    // MARK: Stream

    private func open(at time: Double) {
        task?.cancel()
        decoder = StreamingAudioDecoder()
        streamStart = time
        streamFinished = false
        decodeIndex = 0
        discardUntil = time
        suspended = false
        state.buffering = true
        state.ended = false
        resetOutput(at: time)
        var request = URLRequest(url: streamURL(time))
        request.timeoutInterval = 30
        task = session.dataTask(with: request)
        task?.resume()
    }

    private func seekNow(to time: Double) {
        generation += 1
        let index = Int(((time - streamStart) / max(decoder.packetDuration, 1e-6)).rounded(.down))
        if decoder.packetDuration > 0, index >= decoder.firstPacket + 2, index < decoder.packetCount - 40 || (streamFinished && index < decoder.packetCount) {
            // Downloaded: restart decoding two packets early (MP3 frames lean
            // on the previous ones) and drop the audio before the target.
            decodeIndex = index - 2
            discardUntil = time
            decoder.resetDecoder()
            resetOutput(at: time)
            refill()
            resumeOutput()
        } else {
            open(at: time)
        }
        publish()
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard dataTask === task else { return }
        decoder.parse(data)
        if !connected, let format = decoder.pcmFormat { connect(format) }
        refill()
        // Far enough ahead: pause the download (memory), resume as playback catches up.
        if decoder.packetDuration > 0, Double(decoder.packetCount - decodeIndex) * decoder.packetDuration > Self.readAhead {
            dataTask.suspend()
            suspended = true
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard task === self.task else { return }
        if let error = error as? URLError, error.code == .cancelled { return }
        if let error {
            state.error = error.localizedDescription
            publish()
            return
        }
        streamFinished = true
        refill()
    }

    // MARK: Output

    private func connect(_ format: AVAudioFormat) {
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        connected = true
    }

    private func resetOutput(at time: Double) {
        player.stop()                                   // also drops what was scheduled
        scheduled = []
        outCursor = 0
        if let s = smart { savedBefore += s.savedSeconds }
        if let format = decoder.pcmFormat ?? (connected ? player.outputFormat(forBus: 0) : nil) {
            smart = SmartSpeedProcessor(sampleRate: format.sampleRate, channelCount: Int(format.channelCount), enabled: smartEnabled)
        } else {
            smart = nil
        }
        state.position = time
    }

    private func resumeOutput() {
        guard wantsPlay, connected, !scheduled.isEmpty else { publish(); return }
        if !engine.isRunning { try? engine.start() }
        if !player.isPlaying { player.play() }
        state.buffering = false
        publish()
    }

    /// Keep `lead` seconds scheduled: decode, Smart Speed, hand to the player.
    private func refill() {
        guard connected, let format = decoder.pcmFormat else { return }
        if smart == nil { smart = SmartSpeedProcessor(sampleRate: format.sampleRate, channelCount: Int(format.channelCount), enabled: smartEnabled) }
        while lead() < Self.lead {
            let available = decoder.packetCount - decodeIndex
            guard available > 0 else { break }
            if available < 40, !streamFinished { break }              // wait for a full batch
            let n = min(40, available)
            guard var pcm = decoder.decode(from: decodeIndex, count: n) else { break }
            var start = streamStart + Double(decodeIndex) * decoder.packetDuration
            decodeIndex += n
            if start < discardUntil {                                  // after a seek
                let drop = min(pcm[0].count, Int((discardUntil - start) * format.sampleRate))
                pcm = pcm.map { Array($0.dropFirst(drop)) }
                start += Double(drop) / format.sampleRate
            }
            guard !pcm[0].isEmpty else { continue }
            for chunk in smart!.process(pcm, sourceStart: start) { schedule(chunk, format: format) }
        }
        if streamFinished, decodeIndex >= decoder.packetCount {
            for chunk in smart!.flush() { schedule(chunk, format: format) }     // the held end of a final pause
        }
        // Memory: drop packets well behind, and pick the download back up.
        decoder.trim(before: decodeIndex - Int(Self.keepBehind / max(decoder.packetDuration, 1e-6)))
        if suspended, Double(decoder.packetCount - decodeIndex) * decoder.packetDuration < Self.readAhead / 2 {
            suspended = false
            task?.resume()
        }
        if state.buffering, lead() > 0.4 || (streamFinished && !scheduled.isEmpty) { resumeOutput() }      // decoding runs far ahead of real time
    }

    private func schedule(_ chunk: AudioChunk, format: AVAudioFormat) {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunk.frameCount)), let out = unsafe buffer.floatChannelData else { return }
        buffer.frameLength = AVAudioFrameCount(chunk.frameCount)
        for c in 0..<min(chunk.channels.count, Int(format.channelCount)) {
            chunk.channels[c].withUnsafeBufferPointer { unsafe out[c].update(from: $0.baseAddress!, count: chunk.frameCount) }
        }
        scheduled.append(Scheduled(outStart: outCursor, frames: chunk.frameCount, sourceStart: chunk.sourceStart))
        outCursor += Int64(chunk.frameCount)
        let generation = generation
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            self?.queue.async { [weak self] in
                guard let self, self.generation == generation else { return }
                self.refill()
            }
        }
    }

    /// The player node's frame being heard now (its timeline restarts at 0
    /// on every stop).
    private func playedFrame() -> Int64 {
        guard let nodeTime = player.lastRenderTime, let t = player.playerTime(forNodeTime: nodeTime) else { return 0 }
        return max(0, t.sampleTime)
    }

    private func lead() -> Double {
        guard let format = decoder.pcmFormat else { return 0 }
        return Double(outCursor - playedFrame()) / format.sampleRate
    }

    private func currentPosition() -> Double {
        guard let format = decoder.pcmFormat, !scheduled.isEmpty else { return state.position }
        let frame = playedFrame()
        // The last chunk that started at or before the playhead.
        var lo = 0, hi = scheduled.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if scheduled[mid].outStart <= frame { lo = mid } else { hi = mid - 1 }
        }
        let s = scheduled[lo]
        return s.sourceStart + Double(min(Int64(s.frames), max(0, frame - s.outStart))) / format.sampleRate
    }

    // MARK: State

    private func startTicker() {
        guard ticker == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(100))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        ticker = t
    }

    private func tick() {
        refill()
        if streamFinished, decodeIndex >= decoder.packetCount, connected, playedFrame() >= outCursor, !scheduled.isEmpty, !state.ended {
            state.ended = true
            wantsPlay = false
            player.stop()
        }
        if wantsPlay, !state.buffering, player.isPlaying, lead() < 0.05, !streamFinished {
            state.buffering = true                                     // ran dry: network
        }
        publish()
    }

    private func publish() {
        if !scheduled.isEmpty { state.position = currentPosition() }
        state.playing = wantsPlay && player.isPlaying
        state.savedSeconds = savedBefore + (smart?.savedSeconds ?? 0)
        let snapshot = state
        onUpdate?(snapshot)
    }
}
