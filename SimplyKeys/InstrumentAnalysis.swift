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

    /// Remove DC and near-silence, apply a modest level correction and fades.
    static func clean(_ pcm: [Int16], targetRMS: Double = 0.14) throws -> [Int16] {
        guard pcm.count > 1700 else { throw SampleTools.SampleError.empty }
        let maximum = Double(pcm.map { abs(Int($0)) }.max() ?? 0)
        guard maximum > 300 else { throw SampleTools.SampleError.empty }
        let threshold = max(200, maximum * 0.045)
        let first = pcm.firstIndex { abs(Int($0)) > Int(threshold) } ?? 0
        let last = pcm.lastIndex { abs(Int($0)) > Int(threshold) } ?? pcm.count - 1
        let start = max(0, first - 280)
        let finish = min(pcm.count, last + 1 + 2400)
        guard finish - start > 1700 else { throw SampleTools.SampleError.empty }
        var segment = Array(pcm[start..<finish]).map(Double.init)
        let dc = segment.reduce(0, +) / Double(segment.count)
        for i in segment.indices { segment[i] -= dc }
        let loudness = sqrt(segment.reduce(0) { $0 + $1 * $1 } / Double(segment.count)) / 32768
        guard loudness > 0.0005 else { throw SampleTools.SampleError.empty }
        let target = min(2.5, targetRMS / loudness)
        let largest = segment.map(abs).max() ?? 1
        let gain = min(target, 31500 / max(1, largest))
        let fadeIn = min(180, segment.count / 8)
        let fadeOut = min(500, segment.count / 8)
        var output = [Int16](repeating: 0, count: segment.count)
        for i in segment.indices {
            let fade = min(1, min(Double(i) / Double(max(1, fadeIn)),
                                  Double(segment.count - 1 - i) / Double(max(1, fadeOut))))
            output[i] = Int16(max(-32767, min(32767, Int((segment[i] * gain * fade).rounded()))))
        }
        return output
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
            var sample = Array(layer.pcm.prefix(8 * Int(SampleTools.sampleRate)))
            let sampleCount = sample.count
            let loopStart = loop ? max(400, Int(Double(sampleCount) * 0.33)) : 0
            let loopEnd = loop ? max(loopStart + 128, Int(Double(sampleCount) * 0.78)) : sampleCount
            if loop && loopEnd < sample.count {
                let seam = min(440, loopStart - 1, loopEnd - loopStart - 1)
                if seam > 16 {
                    for i in 0..<seam {
                        let alpha = Double(i) / Double(seam)
                        let destination = loopEnd - seam + i
                        let source = loopStart - seam + i
                        sample[destination] = Int16((Double(sample[destination]) * (1 - alpha)
                                                      + Double(sample[source]) * alpha).rounded())
                    }
                }
            }
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
            generators.append(gen(38, timecents(loop ? 0.23 : 0.38)))
            if loop { generators.append(gen(54, 1)) }
            generators.append(gen(53, sampleIndex))
            generatorIndex += loop ? 5 : 4
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
