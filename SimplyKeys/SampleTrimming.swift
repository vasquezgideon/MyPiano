import Foundation

/// Edits the recorded mono PCM sample without modifying the original layer.
/// Selection fractions are in 0...1, so the UI can use the same values at any size.
enum SampleTrimming {
    static let minimumSeconds = 0.25
    static let fadeSeconds = 0.008

    static func bounds(count: Int, start: Double, end: Double,
                       sampleRate: Double = 22_050) -> Range<Int> {
        guard count > 0 else { return 0..<0 }
        let lower = max(0.0, min(1.0, start.isFinite ? start : 0))
        let upper = max(lower, min(1.0, end.isFinite ? end : 1))
        let minimum = min(count, max(1, Int((minimumSeconds * sampleRate).rounded(.up))))
        let low = min(count - minimum, max(0, Int((lower * Double(count)).rounded())))
        let high = min(count, max(low + minimum, Int((upper * Double(count)).rounded())))
        return low..<high
    }

    static func crop(_ pcm: [Int16], start: Double, end: Double,
                     fadeEdges: Bool = true, sampleRate: Double = 22_050) -> [Int16] {
        guard !pcm.isEmpty else { return [] }
        let selected = bounds(count: pcm.count, start: start, end: end, sampleRate: sampleRate)
        var result = Array(pcm[selected])
        guard fadeEdges, result.count > 2 else { return result }
        let fade = min(result.count / 2, max(1, Int((fadeSeconds * sampleRate).rounded())))
        guard fade > 0 else { return result }
        for i in 0..<fade {
            // Linear edge smoothing avoids clicks caused by trimming mid-cycle.
            let gain = Double(i) / Double(fade)
            result[i] = Int16((Double(result[i]) * gain).rounded())
            let tail = result.count - 1 - i
            result[tail] = Int16((Double(result[tail]) * gain).rounded())
        }
        return result
    }

    /// Single maximum-absolute-peak per column, for a fast, readable waveform.
    static func peaks(_ pcm: [Int16], count: Int = 140) -> [CGFloat] {
        guard count > 0, !pcm.isEmpty else { return [] }
        return (0..<count).map { bar in
            let begin = bar * pcm.count / count
            let finish = min(pcm.count, max(begin + 1, (bar + 1) * pcm.count / count))
            guard begin < finish else { return 0 }
            var peak = 0
            for sample in pcm[begin..<finish] { peak = max(peak, abs(Int(sample))) }
            return CGFloat(peak) / 32768.0
        }
    }
}
