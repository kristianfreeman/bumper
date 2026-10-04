public import AVFoundation
import AudioToolbox

/// Turns a compressed audio byte stream (MP3 from Jellyfin's transcoder, as
/// it arrives over HTTP) into packets, and packets into PCM on demand.
///
/// Packets are kept (compressed, ~12 KB per second at 96 kb/s) so seeking
/// anywhere already downloaded is instant: decoding restarts at a packet.
/// Not thread-safe: the owner calls it from one queue.
@safe public final class StreamingAudioDecoder {
    /// Decoded audio: float32, one buffer per channel.
    public private(set) var pcmFormat: AVAudioFormat?
    /// Source seconds per packet (1152 / 44100 for MP3).
    public private(set) var packetDuration: Double = 0
    /// Index of `packets[0]` in the stream (old packets get trimmed).
    public private(set) var firstPacket = 0
    public var packetCount: Int { firstPacket + packets.count }

    private var stream: AudioFileStreamID?
    private var packets: [Data] = []
    private var compressedFormat: AVAudioFormat?
    private var maxPacketSize = 0
    private var converter: AVAudioConverter?

    public init(fileType: AudioFileTypeID = kAudioFileMP3Type) {
        let me = unsafe Unmanaged.passUnretained(self).toOpaque()
        unsafe AudioFileStreamOpen(me, { client, stream, property, _ in
            unsafe Unmanaged<StreamingAudioDecoder>.fromOpaque(client).takeUnretainedValue().propertyChanged(stream, property)
        }, { client, bytes, packetCount, data, descriptions in
            unsafe Unmanaged<StreamingAudioDecoder>.fromOpaque(client).takeUnretainedValue().received(bytes, packetCount, data, descriptions)
        }, fileType, &stream)
    }

    deinit {
        if let stream = unsafe stream { unsafe AudioFileStreamClose(stream) }
    }

    /// Feed the next bytes of the stream.
    public func parse(_ data: Data) {
        guard let stream = unsafe stream else { return }
        unsafe data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            _ = unsafe AudioFileStreamParseBytes(stream, UInt32(raw.count), base, [])
        }
    }

    /// Decode packets `[index, index + count)` (stream indices). nil when
    /// they aren't here (not downloaded yet, or trimmed).
    public func decode(from index: Int, count: Int) -> [[Float]]? {
        guard let compressedFormat, let pcmFormat, let converter, index >= firstPacket, count > 0 else { return nil }
        let local = index - firstPacket
        let n = min(count, packets.count - local)
        guard n > 0 else { return nil }
        let input = AVAudioCompressedBuffer(format: compressedFormat, packetCapacity: AVAudioPacketCount(n), maximumPacketSize: maxPacketSize)
        var offset = 0
        for i in 0..<n {
            let packet = packets[local + i]
            unsafe packet.withUnsafeBytes { raw in
                unsafe input.data.advanced(by: offset).copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
            unsafe input.packetDescriptions?[i] = AudioStreamPacketDescription(mStartOffset: Int64(offset), mVariableFramesInPacket: 0, mDataByteSize: UInt32(packet.count))
            offset += packet.count
        }
        input.packetCount = AVAudioPacketCount(n)
        input.byteLength = UInt32(offset)

        let frames = AVAudioFrameCount(Double(n) * packetDuration * pcmFormat.sampleRate) + 4096
        guard let output = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: frames) else { return nil }
        var supplied = false
        var error: NSError?
        unsafe converter.convert(to: output, error: &error) { _, status in
            if supplied { unsafe status.pointee = .noDataNow; return nil }
            supplied = true
            unsafe status.pointee = .haveData
            return input
        }
        guard error == nil, let data = unsafe output.floatChannelData else { return nil }
        let length = Int(output.frameLength)
        return (0..<Int(pcmFormat.channelCount)).map { unsafe Array(UnsafeBufferPointer(start: data[$0], count: length)) }
    }

    /// Decoding restarts somewhere else (a seek): forget the decoder's state.
    public func resetDecoder() {
        converter?.reset()
    }

    /// Drop packets before `index` (memory: keep a window around the playhead).
    public func trim(before index: Int) {
        let drop = min(packets.count, index - firstPacket)
        guard drop > 0 else { return }
        packets.removeFirst(drop)
        firstPacket += drop
    }

    // MARK: AudioFileStream callbacks

    private func propertyChanged(_ stream: AudioFileStreamID, _ property: AudioFileStreamPropertyID) {
        guard property == kAudioFileStreamProperty_DataFormat else { return }
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard unsafe AudioFileStreamGetProperty(stream, property, &size, &asbd) == noErr,
              let compressed = unsafe AVAudioFormat(streamDescription: &asbd),
              let pcm = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: asbd.mSampleRate, channels: asbd.mChannelsPerFrame, interleaved: false) else { return }
        compressedFormat = compressed
        pcmFormat = pcm
        packetDuration = Double(asbd.mFramesPerPacket == 0 ? 1152 : asbd.mFramesPerPacket) / asbd.mSampleRate
        converter = AVAudioConverter(from: compressed, to: pcm)
    }

    private func received(_ bytes: UInt32, _ count: UInt32, _ data: UnsafeRawPointer, _ descriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?) {
        guard let descriptions = unsafe descriptions else { return }   // MP3 always describes its packets
        for i in 0..<Int(count) {
            let d = unsafe descriptions[i]
            let packet = unsafe Data(bytes: data.advanced(by: Int(d.mStartOffset)), count: Int(d.mDataByteSize))
            maxPacketSize = max(maxPacketSize, packet.count)
            packets.append(packet)
        }
    }
}
