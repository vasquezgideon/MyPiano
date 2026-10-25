import AVFoundation
import Combine

/// One polyphonic sampler; separate melodic MIDI channels let each finger glide
/// dynamically without changing the volume of the other fingers in a chord.
final class SoundEngine: ObservableObject {
    @Published var problem: String?

    private let engine = AVAudioEngine()
    private let sampler = AVAudioUnitSampler()
    private let metronome = MetronomeEngine()
    private var selectedSource = ""
    private var loaded = false

    static let touchChannels: [UInt8] = (1...8).map(UInt8.init) + (10...15).map(UInt8.init)

    init() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default,
                                                              options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            engine.attach(sampler)
            engine.attach(metronome.node)
            engine.connect(sampler, to: engine.mainMixerNode, format: nil)
            engine.connect(metronome.node, to: engine.mainMixerNode, format: metronome.format)
            try engine.start()
        } catch {
            problem = "Audio couldn't start: \(error.localizedDescription)"
        }
    }

    func select(_ identifier: String, library: InstrumentLibrary) {
        guard !identifier.isEmpty else { return }
        guard identifier != selectedSource || !loaded else { return }
        stopAll()
        do {
            let program: UInt8
            let bankURL: URL
            if identifier.hasPrefix("built-in:") {
                program = UInt8(clamping: Int(identifier.dropFirst("built-in:".count)) ?? 0)
                guard let url = Bundle.main.url(forResource: "SimplyKeys", withExtension: "sf2") else {
                    throw SampleTools.SampleError.unreadable
                }
                bankURL = url
            } else if let instrument = library.instruments.first(where: { $0.id == identifier }) {
                bankURL = library.directory.appendingPathComponent(instrument.filename)
                program = UInt8(clamping: instrument.program)
            } else {
                return
            }
            try sampler.loadSoundBankInstrument(at: bankURL, program: program, bankMSB: 0x79, bankLSB: 0)
            // Channel 0 is the studio reference note; channel 9 is percussion.
            // Explicitly select the same patch for every independent finger voice.
            for channel in [UInt8(0)] + Self.touchChannels {
                sampler.sendProgramChange(program, bankMSB: 0x79, bankLSB: 0, onChannel: channel)
                sampler.sendController(11, withValue: 127, onChannel: channel)
            }
            selectedSource = identifier
            loaded = true
            problem = nil
            resume()
        } catch {
            loaded = false
            problem = "Couldn't load the instrument: \(error.localizedDescription)"
        }
    }

    func noteOn(_ midi: Int, velocity: UInt8 = 100, channel: UInt8 = 0) {
        guard loaded, (0...127).contains(midi) else { return }
        if !engine.isRunning { try? engine.start() }
        sampler.startNote(UInt8(midi), withVelocity: velocity, onChannel: channel)
    }
    func noteOff(_ midi: Int, channel: UInt8 = 0) {
        guard loaded, (0...127).contains(midi) else { return }
        sampler.stopNote(UInt8(midi), onChannel: channel)
    }
    func expression(_ value: UInt8, channel: UInt8) {
        guard loaded else { return }
        sampler.sendController(11, withValue: value, onChannel: channel)
    }
    func stopAll() {
        for channel in [UInt8(0)] + Self.touchChannels {
            sampler.sendController(123, withValue: 0, onChannel: channel)
            sampler.sendController(11, withValue: 127, onChannel: channel)
        }
    }
    func metronomeSettings(isOn: Bool, bpm: Double, division: BeatDivision) {
        metronome.set(active: isOn, bpm: bpm, division: division)
    }
    func resume() {
        try? AVAudioSession.sharedInstance().setActive(true)
        if !engine.isRunning { try? engine.start() }
    }
    func pause() { stopAll(); metronome.stop(); engine.pause() }
}
