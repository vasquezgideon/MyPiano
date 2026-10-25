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
