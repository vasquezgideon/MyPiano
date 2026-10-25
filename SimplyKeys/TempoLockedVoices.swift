import AVFoundation
import Foundation

/// A pitch-corrected voice per finger. Shifting one mixed output would destroy
/// the harmony of chords; every player has its own AVAudioUnitTimePitch.
/// Rate is always 1.0 so note duration does not track transposition.
final class TempoLockedVoices {
    private final class Voice {
        let player = AVAudioPlayerNode()
        let pitch = AVAudioUnitTimePitch()
        let volume = AVAudioMixerNode()
        var midi: Int?
        var channel: UInt8?
        var currentGain: Float = 0
        var targetGain: Float = 0
        var releasing = false
        var releaseDuration: TimeInterval = 0.2
        var endsAt: TimeInterval = .infinity
        var lastUpdate: TimeInterval = 0
        var isLooping = false

        func reset() {
            player.stop()
            midi = nil
            channel = nil
            releasing = false
            isLooping = false
            currentGain = 0
            targetGain = 0
            endsAt = .infinity
            volume.outputVolume = 0
        }
    }
    private struct Prepared {
        let first: AVAudioPCMBuffer
        let loop: AVAudioPCMBuffer?
        let duration: TimeInterval
    }

    private let format = AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1)!
    private var voices: [Voice] = []
    private var bank: SoundFontRegions?
    private var samples: [Int: Prepared] = [:]
    private var timer: Timer?

    var canPlay: Bool { bank != nil }

    deinit { timer?.invalidate() }

    func load(url: URL, program: Int) {
        clear()
        samples.removeAll()
        bank = try? SoundFontRegions(url: url, program: program)
    }

    func activate(in engine: AVAudioEngine) {
        guard voices.isEmpty else { return }
        let wasRunning = engine.isRunning
        if wasRunning { engine.pause() }
        // Ten pitch units keep the CPU and latency reasonable on iPhones.
        // Overflowing voices safely use the regular SoundFont sampler.
        for _ in 0..<10 {
            let voice = Voice()
            voice.pitch.rate = 1.0
            voice.pitch.overlap = 8.0
            engine.attach(voice.player)
            engine.attach(voice.pitch)
            engine.attach(voice.volume)
            engine.connect(voice.player, to: voice.pitch, format: format)
            engine.connect(voice.pitch, to: voice.volume, format: format)
            engine.connect(voice.volume, to: engine.mainMixerNode, format: nil)
            voices.append(voice)
        }
        engine.prepare()
        if wasRunning { try? engine.start() }
        let clock = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updateEnvelopes()
        }
        RunLoop.main.add(clock, forMode: .common)
        timer = clock
    }

    /// Returns false when a bank cannot be decoded, a voice is unavailable,
    /// or the pitch interval exceeds the processor's +/- two-octave range.
    /// In that case the caller transparently plays the classic sample instead.
    @discardableResult
    func noteOn(_ midi: Int, velocity: UInt8, channel: UInt8) -> Bool {
        guard let bank, let region = bank.region(for: midi, velocity: Int(velocity)) else { return false }
        let cents = Float((midi - region.root) * 100 - region.cents)
        guard (-2400...2400).contains(cents) else { return false }
        guard let voice = voices.first(where: { $0.channel == channel }) ??
                          voices.first(where: { $0.midi == nil }) else { return false }
        guard let prepared = preparedSample(region, bank: bank) else { return false }
        voice.reset()
        voice.midi = midi
        voice.channel = channel
        voice.pitch.pitch = cents
        voice.pitch.rate = 1.0
        voice.targetGain = velocityGain(velocity)
        voice.releaseDuration = region.release
        voice.lastUpdate = Date.timeIntervalSinceReferenceDate
        voice.isLooping = prepared.loop != nil
        // A stable sustain loops after the original attack, not at the silent
        // beginning of the recording. Key-up fades the voice before stopping.
        voice.player.scheduleBuffer(prepared.first, completionHandler: nil)
        if let loop = prepared.loop {
            voice.player.scheduleBuffer(loop, at: nil, options: [.loops], completionHandler: nil)
        } else {
            voice.endsAt = voice.lastUpdate + prepared.duration + 0.1
        }
        voice.player.play()
        return true
    }

    func noteOff(_ midi: Int, channel: UInt8) -> Bool {
        guard let voice = voices.first(where: { $0.channel == channel && $0.midi == midi }) else {
            return false
        }
        voice.releasing = true
        voice.targetGain = 0
        return true
    }

    func expression(_ value: UInt8, channel: UInt8) -> Bool {
        guard let voice = voices.first(where: { $0.channel == channel && $0.midi != nil }) else {
            return false
        }
        if !voice.releasing { voice.targetGain = Float(value) / 127.0 }
        return true
    }

    func clear() { voices.forEach { $0.reset() } }

    private func velocityGain(_ velocity: UInt8) -> Float {
        let v = Float(velocity) / 127.0
        return max(0.02, pow(v, 1.2))
    }

    private func updateEnvelopes() {
        let now = Date.timeIntervalSinceReferenceDate
        for voice in voices where voice.midi != nil {
            let dt = max(0.001, min(0.08, now - voice.lastUpdate))
            voice.lastUpdate = now
            let timeConstant = voice.releasing ? voice.releaseDuration : 0.015
            let smoothing = Float(min(1, dt / max(0.01, timeConstant)))
            voice.currentGain += (voice.targetGain - voice.currentGain) * smoothing
            voice.volume.outputVolume = min(1, max(0, voice.currentGain))
            if (voice.releasing && voice.currentGain < 0.003) ||
                (!voice.isLooping && now >= voice.endsAt) {
                voice.reset()
            }
        }
    }

    private func preparedSample(_ region: SoundFontRegions.Region,
                                bank: SoundFontRegions) -> Prepared? {
        if let cached = samples[region.sampleIndex] { return cached }
        guard let input = bank.pcm(for: region) else { return nil }
        // Convert source PCM to the fixed render format. This also supports
        // imported SoundFonts recorded at 44.1/48 kHz or other sample rates.
        let rateRatio = Double(region.rate) / format.sampleRate
        let count = Int(Double(input.count) / rateRatio)
        guard count >= 256, count <= 22_050 * 12,
              let first = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
              let dest = first.floatChannelData?[0] else { return nil }
        first.frameLength = AVAudioFrameCount(count)
        for i in 0..<count {
            let source = Double(i) * rateRatio
            let index = min(input.count - 1, Int(source))
            let next = min(input.count - 1, index + 1)
            let t = Float(source - Double(index))
            dest[i] = ((1 - t) * Float(input[index]) + t * Float(input[next])) / 32768
        }

        let lastLoopFrame = Int(Double(region.loopEnd - region.start) / rateRatio)
        let firstLoopFrame = Int(Double(region.loopStart - region.start) / rateRatio)
        var attack = first
        var sustain: AVAudioPCMBuffer?
        if region.looping, firstLoopFrame >= 0,
           lastLoopFrame <= count, lastLoopFrame - firstLoopFrame >= 256 {
            if let prefix = AVAudioPCMBuffer(pcmFormat: format,
                                              frameCapacity: AVAudioFrameCount(lastLoopFrame)),
               let prefixDst = prefix.floatChannelData?[0] {
                prefix.frameLength = AVAudioFrameCount(lastLoopFrame)
                for i in 0..<lastLoopFrame { prefixDst[i] = dest[i] }
                attack = prefix
            }
            let length = lastLoopFrame - firstLoopFrame
            if let loop = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(length)),
               let loopDst = loop.floatChannelData?[0] {
                loop.frameLength = AVAudioFrameCount(length)
                for i in 0..<length { loopDst[i] = dest[firstLoopFrame + i] }
                sustain = loop
            }
        }
        let value = Prepared(first: attack, loop: sustain,
                             duration: Double(attack.frameLength) / format.sampleRate)
        samples[region.sampleIndex] = value
        return value
    }
}
