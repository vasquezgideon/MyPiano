import Foundation

@main
struct TrimTests {
    static func main() {
        let rate = 22_050.0
        let length = Int(rate * 2)
        let source = (0..<length).map { i -> Int16 in
            if i < length / 4 || i >= 3 * length / 4 { return 0 }
            return Int16((sin(Double(i) * 2 * .pi * 220 / rate) * 20_000).rounded())
        }
        let originalCopy = source
        let selected = SampleTrimming.crop(source, start: 0.25, end: 0.75,
                                           fadeEdges: false, sampleRate: rate)
        assert(selected.count == length / 2)
        assert(selected == Array(source[(length / 4)..<(3 * length / 4)]))
        assert(source == originalCopy, "Cropping must not change original sample")

        let smoothed = SampleTrimming.crop(source, start: 0.25, end: 0.75,
                                           fadeEdges: true, sampleRate: rate)
        assert(smoothed.count == selected.count)
        assert(smoothed.first == 0 && smoothed.last == 0)
        assert(smoothed[smoothed.count / 2] == selected[selected.count / 2])
        let all = SampleTrimming.crop(source, start: 0, end: 1, fadeEdges: false, sampleRate: rate)
        assert(all == source)

        let tiny = SampleTrimming.crop(source, start: 0.5, end: 0.50001,
                                       fadeEdges: false, sampleRate: rate)
        assert(tiny.count >= Int(SampleTrimming.minimumSeconds * rate))
        let reversed = SampleTrimming.crop(source, start: 0.9, end: 0.1, sampleRate: rate)
        assert(reversed.count >= Int(SampleTrimming.minimumSeconds * rate))
        assert(SampleTrimming.peaks(source, count: 120).count == 120)
        assert(SampleTrimming.peaks([], count: 120).isEmpty)
        assert(SampleTrimming.crop([], start: 0, end: 1).isEmpty)
        print("Trim tests passed: boundaries, non-destructive edit, fades, min length, waveform.")
    }
}
