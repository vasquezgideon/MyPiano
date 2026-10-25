import Foundation

func sample(_ midi: Int) -> [Int16] {
    let frequency = NoteNames.frequency(midi)
    return (0..<22_050).map { frame in
        Int16((sin(2 * .pi * frequency * Double(frame) / 22_050) * 11_000).rounded())
    }
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

for note in [48, 60, 65, 69, 81] {
    let pcm = sample(note)
    let expected = NoteNames.frequency(note)
    let detected = InstrumentAnalysis.fundamental(pcm)
    require(detected != nil, "Pitch analysis failed for \(note)")
    require(abs(1200 * log2(detected! / expected)) < 18, "Incorrect pitch estimate \(note)")
    let cleaned = try InstrumentAnalysis.clean(pcm)
    require(cleaned.count > 2048, "Sample cleaning removed too much audio")
}

let layers = [
    SoundFontLayer(note: 60, dynamic: .soft, pcm: sample(60)),
    SoundFontLayer(note: 60, dynamic: .strong, pcm: sample(60)),
    SoundFontLayer(note: 69, dynamic: .medium, pcm: sample(69))
]
for loop in [false, true] {
    let bank = try MultiSampleSoundFont.generate(layers, name: "Sampler test", loop: loop)
    require(String(decoding: bank.prefix(4), as: UTF8.self) == "RIFF", "Missing RIFF header")
    require(String(decoding: bank[8..<12], as: UTF8.self) == "sfbk", "Missing SoundFont type")
    let length = bank[4..<8].enumerated().reduce(0) { $0 + (Int($1.element) << (8 * $1.offset)) }
    require(length == bank.count - 8, "Invalid RIFF length")
    for (chunk, recordSize, recordCount) in [
        ("phdr", 38, 2), ("inst", 22, 2), ("ibag", 4, 4),
        ("shdr", 46, 4)] {
        let sequence = Data(chunk.utf8)
        guard let range = bank.range(of: sequence) else { fatalError("Missing chunk \(chunk)") }
        let position = range.upperBound
        let bytes = bank[position..<position + 4]
        let size = bytes.enumerated().reduce(0) { $0 + (Int($1.element) << (8 * $1.offset)) }
        require(size == recordSize * recordCount, "Malformed chunk \(chunk)")
    }
}
print("Audio tests passed: pitch estimates, cleanup, and three-layer SF2 with/without sustain.")

// Regression: an attack spike must not preserve blank tails or cause a hard
// discontinuity when the sample loops. Note-off release is encoded in the SF2.
let hz = NoteNames.frequency(69)
let rate = Int(SampleTools.sampleRate)
let silenceCount = rate / 3
var recorded = [Int16](repeating: 0, count: silenceCount)
for frame in 0..<(rate * 2) {
    let seconds = Double(frame) / Double(rate)
    let transient = frame < rate / 8 ? 2.0 : 1.0
    let tone = sin(2 * .pi * hz * seconds)
    recorded.append(Int16((tone * 8500 * transient).rounded()))
}
recorded += [Int16](repeating: 0, count: silenceCount)
let cleaned = try InstrumentAnalysis.clean(recorded)
require(cleaned.count < recorded.count - silenceCount / 2,
        "Cleaning did not remove the blank lead/tail")
require(cleaned.count > rate, "Cleaning removed too much sustained audio")
require(abs(Int(cleaned[0])) < 400, "Attack fade is missing")
require(abs(Int(cleaned[cleaned.count - 1])) < 400, "Release fade is missing")

let loop = InstrumentAnalysis.seamlessLoop(cleaned, root: 69)
require(loop.start > 0 && loop.end < loop.pcm.count && loop.end - loop.start > rate / 10,
        "Stable sustained tone did not yield usable loop boundaries")
let wrapDifference = abs(Int(loop.pcm[loop.end - 1]) - Int(loop.pcm[loop.start]))
require(wrapDifference < 3500, "Audible discontinuity at sample loop wrap")
let recordedPeak = recorded.map { abs(Int($0)) }.max()!
let cleanedPeak = cleaned.map { abs(Int($0)) }.max()!
require(cleanedPeak < recordedPeak, "Attack spike was not reduced")
let bankWithRelease = try MultiSampleSoundFont.generate([
    SoundFontLayer(note: 69, dynamic: .medium, pcm: cleaned)
], name: "Smooth instrument", loop: true)
require(bankWithRelease.range(of: Data("smpl".utf8)) != nil, "Loop instrument is missing audio")
print("Audio polish passed: trimming, level balancing, smooth loop, sample release.")
