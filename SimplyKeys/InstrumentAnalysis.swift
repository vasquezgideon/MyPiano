import Foundation

/// Short mono recordings, one or several notes, prepared on-device.
enum RecordingDynamic: Int, CaseIterable, Identifiable {
    case soft = 42, medium = 86, strong = 120
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .soft: return "Soft (pp)"
        case .medium: return "Medium (mf)"
        case .strong: return "Strong (ff)"
        }
    }
    var targetRMS: Double {
        switch self {
        case .soft: return 0.105
        case .medium: return 0.14
        case .strong: return 0.185
        }
    }
}

struct RecordedLayer: Identifiable {
    let id = UUID()
    var name: String
    var note: Int
    var dynamic: RecordingDynamic
    var pcm: [Int16]
}

struct SoundFontLayer {
    var note: Int
    var dynamic: RecordingDynamic
    var pcm: [Int16]
}

enum InstrumentAnalysis {
    /// YIN-style normalized difference search on the loudest stable window.
    /// Single-note material works best: chords/noisy material may not resolve.
    static func fundamental(_ pcm: [Int16]) -> Double? {
        let size = 4096
        guard pcm.count >= size else { return nil }
        let sampleRate = SampleTools.sampleRate
        let lowLag = max(12, Int(sampleRate / 1600))
        let highLag = min(640, Int(sampleRate / 45))
        var strongest = 0.0
        var bestStart = 0
        for begin in stride(from: 0, through: max(0, min(pcm.count - size, Int(sampleRate * 2))), by: 512) {
            var energy = 0.0
            for i in stride(from: begin, to: begin + size, by: 16) {
                let v = Double(pcm[i]) / 32768
                energy += v * v
            }
            if energy > strongest { strongest = energy; bestStart = begin }
        }
        guard strongest > 0.009 else { return nil }
        let waveform = (0..<size).map { Double(pcm[bestStart + $0]) / 32768 }
        var differences = [Double](repeating: 0, count: highLag + 1)
        for lag in lowLag...highLag {
            var sum = 0.0
            for i in stride(from: 0, to: size - highLag, by: 2) {
                let delta = waveform[i] - waveform[i + lag]
                sum += delta * delta
            }
            differences[lag] = sum
        }
        var accumulated = 0.0
        var winningLag = -1
        var bestCMND = 1.0
        for lag in 1...highLag {
            accumulated += differences[lag]
            if lag < lowLag || accumulated == 0 { continue }
            let score = differences[lag] * Double(lag) / accumulated
            if score < bestCMND { bestCMND = score; winningLag = lag }
            // First confident local minimum, rather than lower-octave harmonics.
            if score < 0.15 && lag < highLag && differences[lag + 1] > differences[lag] {
                winningLag = lag
                bestCMND = score
                break
            }
        }
        guard winningLag > 0, bestCMND < 0.28 else { return nil }
        return sampleRate / Double(winningLag)
    }

    /// Process an isolated note without changing its musical pitch.
    /// A short RMS envelope detects leading/trailing room noise much more
    /// reliably than using a single loud transient as the threshold.
    static func clean(_ pcm: [Int16], targetRMS: Double = 0.14) throws -> [Int16] {
        guard pcm.count > 1700 else { throw SampleTools.SampleError.empty }
        let rate = Int(SampleTools.sampleRate)
        let window = max(64, rate / 100)  // ~10 ms
        let blocks = (pcm.count + window - 1) / window
        var energy = [Double](repeating: 0, count: blocks)
        var high = 0.0
        for block in 0..<blocks {
            let lower = block * window
            let upper = min(pcm.count, lower + window)
            var sum = 0.0
            for i in lower..<upper {
                let x = Double(pcm[i]) / 32768
                sum += x * x
            }
            energy[block] = sqrt(sum / Double(upper - lower))
            high = max(high, energy[block])
        }
        guard high > 0.006 else { throw SampleTools.SampleError.empty }
        // Require more than a stray impulse before marking a note as audible.
        let gate = max(0.0018, high * 0.012)
        guard let firstBlock = energy.firstIndex(where: { $0 > gate }),
              let lastBlock = energy.lastIndex(where: { $0 > gate }) else {
            throw SampleTools.SampleError.empty
        }
        let start = max(0, firstBlock * window - rate / 100)
        let end = min(pcm.count, (lastBlock + 1) * window + rate / 80)
        guard end - start > 1700 else { throw SampleTools.SampleError.empty }

        var values = Array(pcm[start..<end]).map(Double.init)
        let dc = values.reduce(0, +) / Double(values.count)
        for i in values.indices { values[i] -= dc }

        // Normalize against typical active sound, rather than an unusually
        // loud first strike. Keep the requested pp / mf / ff distinctions.
        let levels = energy[firstBlock...lastBlock].filter { $0 > gate }.sorted()
        let typical = levels[levels.count / 2]
        guard typical > 0.0005 else { throw SampleTools.SampleError.empty }
        let baseGain = min(5.0, targetRMS / typical)
        let strongestAfterGain = (values.map(abs).max() ?? 0) * baseGain
        let safetyGain = min(1.0, 31300 / max(1, strongestAfterGain))
        let gain = baseGain * safetyGain

        // A gentle, windowed compressor tames unexpectedly loud attacks and
        // recording fluctuations, without flattening the natural instrument.
        // The gain curve changes gradually, avoiding zipper noise.
        let compressionWindow = max(1, rate / 40) // ~25 ms
        let half = compressionWindow / 2
        var prefix = [Double](repeating: 0, count: values.count + 1)
        for i in values.indices {
            let v = values[i] / 32768
            prefix[i + 1] = prefix[i] + v * v
        }
        let fadeIn = min(rate / 125, values.count / 10)  // ~8 ms
        let fadeOut = min(rate / 30, values.count / 8)  // ~33 ms
        var output = [Int16](repeating: 0, count: values.count)
        var smoothedGain = 1.0
        for i in values.indices {
            let low = max(0, i - half)
            let highIndex = min(values.count, i + half + 1)
            let local = sqrt(max(0, prefix[highIndex] - prefix[low]) / Double(highIndex - low))
            let desired = min(1.20, max(0.60, pow(typical / max(local, 0.0005), 0.28)))
            // Faster adjustment for loud attacks; slower rebound thereafter.
            let response = desired < smoothedGain ? 0.006 : 0.0008
            smoothedGain += (desired - smoothedGain) * response
            let entry = min(1.0, Double(i) / Double(max(1, fadeIn)))
            let exit = min(1.0, Double(values.count - 1 - i) / Double(max(1, fadeOut)))
            let signal = values[i] * gain * smoothedGain * min(entry, exit)
            output[i] = Int16(clamping: Int(max(-32000, min(32000, signal)).rounded()))
        }
        return output
    }

    struct LoopRegion {
        let pcm: [Int16]
        let start: Int
        let end: Int
    }

    /// Find a seam inside the sustained portion, then crossfade its final
    /// milliseconds into the preceding samples of the loop's entry point.
    /// Short recordings with no stable sustain still receive a safe fade.
    static func seamlessLoop(_ pcm: [Int16], root: Int) -> LoopRegion {
        let count = pcm.count
        guard count >= 5000 else { return LoopRegion(pcm: pcm, start: 0, end: count) }
        let period = min(350, max(16, Int((SampleTools.sampleRate / NoteNames.frequency(root)).rounded())))
        let comparison = min(220, max(48, period * 2))
        let fade = min(440, max(110, period * 3))
        let firstStart = max(fade + comparison + 2, count / 5)
        let lastStart = min(count * 46 / 100, count - 2 * fade - 2)
        let firstEnd = max(count * 65 / 100, lastStart + fade * 2 + comparison)
        let lastEnd = min(count * 93 / 100, count - 1)
        guard firstStart < lastStart, firstEnd < lastEnd else {
            return LoopRegion(pcm: pcm, start: 0, end: count)
        }
        let step = max(12, period / 3)
        let peak = Double(pcm.map { abs(Int($0)) }.max() ?? 1)
        var bestScore = Double.infinity
        var bestStart = firstStart
        var bestEnd = firstEnd
        // Compare both amplitude and phase around each proposed loop boundary.
        for loopStart in stride(from: firstStart, through: lastStart, by: step * 2) {
            for loopEnd in stride(from: firstEnd, through: lastEnd, by: step) {
                var difference = 0.0
                var levelA = 0.0
                var levelB = 0.0
                for k in stride(from: 0, to: comparison, by: 3) {
                    let a = Double(pcm[loopStart - comparison + k])
                    let b = Double(pcm[loopEnd - comparison + k])
                    difference += (a - b) * (a - b)
                    levelA += a * a
                    levelB += b * b
                }
                let n = Double((comparison + 2) / 3)
                let loudA = sqrt(levelA / n)
                let loudB = sqrt(levelB / n)
                if min(loudA, loudB) < peak * 0.075 { continue }
                let mismatch = sqrt(difference / n) / max(250, (loudA + loudB) / 2)
                let levelDifference = abs(loudA - loudB) / max(250, (loudA + loudB) / 2)
                let score = mismatch + levelDifference * 0.7
                if score < bestScore {
                    bestScore = score
                    bestStart = loopStart
                    bestEnd = loopEnd
                }
            }
        }
        // Preserve the original recording if it contains no stable sustain.
        guard bestScore.isFinite else {
            return LoopRegion(pcm: pcm, start: 0, end: count)
        }
        var result = pcm
        let seam = min(fade, bestStart - 1, bestEnd - bestStart - 1)
        if seam > 16 {
            for i in 0..<seam {
                let t = Double(i + 1) / Double(seam + 1)
                let dst = bestEnd - seam + i
                let src = bestStart - seam + i
                let blended = Double(result[dst]) * (1 - t) + Double(pcm[src]) * t
                result[dst] = Int16(clamping: Int(blended.rounded()))
            }
            // Match the last loop frame exactly to the frame directly before
            // its entry; this removes the discontinuity on wraparound.
            result[bestEnd - 1] = pcm[bestStart - 1]
        }
        return LoopRegion(pcm: result, start: bestStart, end: bestEnd)
    }

    static func prepare(_ layer: RecordedLayer) throws -> SoundFontLayer {
        let target = NoteNames.frequency(layer.note)
        let measured = SampleTools.detectPitch(layer.pcm, near: target) ?? fundamental(layer.pcm)
        let input = try clean(layer.pcm, targetRMS: layer.dynamic.targetRMS)
        let corrected: [Int16]
        if let measured, measured.isFinite, abs(12 * log2(measured / target)) < 3.2 {
            corrected = SampleTools.retune(input, actualHz: measured, desiredHz: target)
        } else {
            corrected = input
        }
        return SoundFontLayer(note: layer.note, dynamic: layer.dynamic, pcm: corrected)
    }
}

/// SoundFont 2.01 with one preset and instrument, but many per-key/velocity
/// sample zones. Nearest-note zones split at pitch midpoints; each dynamic
/// layer occupies a separate velocity range.
enum MultiSampleSoundFont {
    private static func u16(_ v: Int) -> Data {
        var n = UInt16(truncatingIfNeeded: v).littleEndian
        return withUnsafeBytes(of: &n) { Data($0) }
    }
    private static func u32(_ v: Int) -> Data {
        var n = UInt32(truncatingIfNeeded: v).littleEndian
        return withUnsafeBytes(of: &n) { Data($0) }
    }
    private static func bytes(_ s: String) -> Data { Data(s.utf8) }
    private static func name(_ s: String) -> Data {
        let letters = Array(s.utf8.prefix(19))
        return Data(letters + Array(repeating: UInt8(0), count: 20 - letters.count))
    }
    private static func concat(_ parts: Data...) -> Data {
        var output = Data()
        for part in parts { output.append(part) }
        return output
    }
    private static func chunk(_ id: String, _ bytes: Data) -> Data {
        var content = concat(self.bytes(id), u32(bytes.count), bytes)
        if bytes.count % 2 != 0 { content.append(0) }
        return content
    }
    private static func textChunk(_ string: String) -> Data {
        var data = bytes(string + "\u{0}")
        if data.count % 2 != 0 { data.append(0) }
        return data
    }
    private static func gen(_ opcode: Int, _ value: Int) -> Data { concat(u16(opcode), u16(value)) }
    private static func range(_ lower: Int, _ upper: Int) -> Int { lower | (upper << 8) }
    private static func timecents(_ sec: Double) -> Int { Int((1200 * log2(max(0.001, sec))).rounded()) & 0xFFFF }

    static func generate(_ layers: [SoundFontLayer], name title: String, loop: Bool) throws -> Data {
        guard !layers.isEmpty, layers.count <= 48 else { throw SampleTools.SampleError.unsupported }
        let ordered = layers.sorted {
            $0.note == $1.note ? $0.dynamic.rawValue < $1.dynamic.rawValue : $0.note < $1.note
        }
        let roots = Array(Set(ordered.map(\.note))).sorted()
        var pcmData = Data()
        var sampleHeaders = Data()
        var bags = Data()
        var generators = Data()
        var sampleOffset = 0
        var zoneIndex = 0
        var generatorIndex = 0

        for (sampleIndex, layer) in ordered.enumerated() {
            guard (0...127).contains(layer.note), layer.pcm.count > 1700 else {
                throw SampleTools.SampleError.empty
            }
            let original = Array(layer.pcm.prefix(8 * Int(SampleTools.sampleRate)))
            let processed = loop ? InstrumentAnalysis.seamlessLoop(original, root: layer.note) :
                InstrumentAnalysis.LoopRegion(pcm: original, start: 0, end: original.count)
            let sample = processed.pcm
            let sampleCount = sample.count
            let hasLoop = loop && processed.start > 0 && processed.end > processed.start
            let loopStart = hasLoop ? processed.start : 0
            let loopEnd = hasLoop ? processed.end : sampleCount
            for value in sample { pcmData.append(u16(Int(value))) }
            pcmData.append(Data(repeating: 0, count: 92)) // 46 guard frames
            sampleHeaders.append(concat(name("Note \(layer.note)"),
                u32(sampleOffset), u32(sampleOffset + sampleCount),
                u32(sampleOffset + loopStart), u32(sampleOffset + loopEnd),
                u32(Int(SampleTools.sampleRate)), Data([UInt8(layer.note), 0]), u16(0), u16(1)))
            sampleOffset += sampleCount + 46

            let rootPosition = roots.firstIndex(of: layer.note)!
            let low = rootPosition == 0 ? 0 : (roots[rootPosition - 1] + layer.note) / 2 + 1
            let high = rootPosition == roots.count - 1 ? 127 : (layer.note + roots[rootPosition + 1]) / 2
            let velocities = ordered.filter { $0.note == layer.note }.map { $0.dynamic.rawValue }
            let vpos = velocities.firstIndex(of: layer.dynamic.rawValue)!
            let velocityLow = vpos == 0 ? 0 : (velocities[vpos - 1] + velocities[vpos]) / 2 + 1
            let velocityHigh = vpos == velocities.count - 1 ? 127 : (velocities[vpos] + velocities[vpos + 1]) / 2

            bags.append(concat(u16(generatorIndex), u16(0)))
            generators.append(gen(43, range(low, high)))
            generators.append(gen(44, range(velocityLow, velocityHigh)))
            generators.append(gen(38, timecents(hasLoop ? 0.32 : 0.58)))
            if hasLoop { generators.append(gen(54, 3)) }
            generators.append(gen(53, sampleIndex))
            generatorIndex += hasLoop ? 5 : 4
            zoneIndex += 1
        }

        bags.append(concat(u16(generatorIndex), u16(0))) // terminal instrument bag
        generators.append(gen(0, 0)) // terminal instrument generator
        sampleHeaders.append(concat(name("EOS"), u32(sampleOffset), u32(sampleOffset),
                                    u32(sampleOffset), u32(sampleOffset),
                                    u32(Int(SampleTools.sampleRate)), Data([0, 0]), u16(0), u16(1)))

        let presetHeaders = concat(name(title), u16(0), u16(0), u16(0), u32(0), u32(0), u32(0),
                                   name("EOP"), u16(0), u16(0), u16(1), u32(0), u32(0), u32(0))
        let presetBags = concat(u16(0), u16(0), u16(1), u16(0))
        let presetGens = concat(gen(41, 0), gen(0, 0))
        let instruments = concat(name(title), u16(0), name("EOI"), u16(zoneIndex))
        let info = chunk("LIST", concat(bytes("INFO"),
            chunk("ifil", concat(u16(2), u16(1))),
            chunk("isng", textChunk("EMU8000")),
            chunk("INAM", textChunk(title))))
        let samples = chunk("LIST", concat(bytes("sdta"), chunk("smpl", pcmData)))
        let presets = chunk("LIST", concat(bytes("pdta"),
            chunk("phdr", presetHeaders), chunk("pbag", presetBags),
            chunk("pmod", Data(repeating: 0, count: 10)), chunk("pgen", presetGens),
            chunk("inst", instruments), chunk("ibag", bags),
            chunk("imod", Data(repeating: 0, count: 10)), chunk("igen", generators),
            chunk("shdr", sampleHeaders)))
        let full = concat(bytes("sfbk"), info, samples, presets)
        return chunk("RIFF", full)
    }
}
