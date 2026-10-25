import AVFoundation
import Foundation

enum BeatDivision: Int, CaseIterable, Identifiable {
    case quarter = 1, eighth = 2, triplet = 3, sixteenth = 4
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .quarter: return "Quarter"
        case .eighth: return "Eighth"
        case .triplet: return "Triplet"
        case .sixteenth: return "Sixteenth"
        }
    }
}

/// Subdivision-aware click generator driven by the audio sample clock.
/// BPM is quarter-note tempo; 0.1–999.9 stays accurate without UI timers.
final class MetronomeEngine {
    private final class Clock {
        let lock = NSLock()
        var enabled = false
        var bpm = 100.0
        var division = 1
        var position = 0.0
        var step = 0
    }
    private let clock: Clock
    let node: AVAudioSourceNode
    let format: AVAudioFormat

    init() {
        let clock = Clock()
        self.clock = clock
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        self.format = format
        let sampleRate = format.sampleRate
        node = AVAudioSourceNode(format: format) { _, _, frames, output in
            let buffers = UnsafeMutableAudioBufferListPointer(output)
            clock.lock.lock()
            defer { clock.lock.unlock() }
            let period = sampleRate * 60 / (clock.bpm * Double(clock.division))
            for frame in 0..<Int(frames) {
                var tick: Float = 0
                if clock.enabled {
                    if clock.position >= period {
                        clock.position -= period
                        clock.step = (clock.step + 1) % (4 * clock.division)
                    }
                    let elapsed = clock.position / sampleRate
                    if elapsed < 0.026 {
                        let isBar = clock.step == 0
                        let isBeat = clock.step % clock.division == 0
                        let frequency = isBar ? 1830.0 : (isBeat ? 1380.0 : 920.0)
                        let strength = isBar ? 0.28 : (isBeat ? 0.19 : 0.12)
                        tick = Float(strength * sin(2 * .pi * frequency * elapsed) * exp(-elapsed * 168))
                    }
                    clock.position += 1
                }
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = tick
                }
            }
            return 0
        }
    }

    func set(active: Bool, bpm: Double, division: BeatDivision) {
        clock.lock.lock()
        defer { clock.lock.unlock() }
        let safeBPM = bpm.isFinite ? min(999.9, max(0.1, bpm)) : 100
        if (active && !clock.enabled) || clock.division != division.rawValue {
            clock.position = 0
            clock.step = 0
        }
        clock.enabled = active
        clock.bpm = safeBPM
        clock.division = division.rawValue
    }

    func stop() { set(active: false, bpm: 100, division: .quarter) }
}
