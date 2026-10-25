import Foundation

@main
struct PitchModeTests {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Expected bundled SF2 file") }
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let patches = [0, 4, 10, 16, 24, 40, 46, 56, 73, 80]
        for patch in patches {
            let bank = try SoundFontRegions(url: url, program: patch)
            assert(bank.regions.count >= 10, "Missing instrument sample regions: \(patch)")
            for midi in stride(from: 0, through: 127, by: 4) {
                guard let region = bank.region(for: midi, velocity: 100) else {
                    fatalError("No sample for pitch \(midi) in preset \(patch)")
                }
                assert(abs(midi - region.root) <= 24, "Time-stretch range exceeded for built-in instrument")
                assert(region.rate >= 8000)
                let pcm = bank.pcm(for: region)
                assert(pcm != nil && pcm!.count > 500, "Sample PCM decoding failed")
            }
            print("Pitch regions OK — program \(patch), zones \(bank.regions.count)")
        }
        print("PASS: per-key pitch regions and uncompressed PCM")
    }
}
