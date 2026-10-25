import AVFoundation
import Foundation

// Utilities for turning a short recording (or an imported audio sample) into a
// playable SoundFont. Everything happens on the device, with no cloud service.
enum SampleTools {
    static let sampleRate = 22_050.0

    enum SampleError: LocalizedError {
        case unreadable, empty, unsupported
        var errorDescription: String? {
            switch self {
            case .unreadable: return "This audio file couldn't be opened."
            case .empty: return "The recording is silent or too short."
            case .unsupported: return "Choose an audio sample, SoundFont, or DLS instrument bank."
            }
        }
    }

    static func readAudio(at url: URL, maximumSeconds: Double = 8) throws -> [Int16] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard format.sampleRate > 0, format.channelCount > 0,
              format.commonFormat == .pcmFormatFloat32 else { throw SampleError.unreadable }
        let frames = min(Int64(format.sampleRate * maximumSeconds), file.length)
        guard frames >= 500 else { throw SampleError.empty }
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        try file.read(into: buffer, frameCount: AVAudioFrameCount(frames))
        guard let channels = buffer.floatChannelData, buffer.frameLength >= 500 else { throw SampleError.empty }
        let count = Int(buffer.frameLength)
        let nChannels = Int(format.channelCount)
        let targetCount = Int(Double(count) * sampleRate / format.sampleRate)
        var output = [Int16](repeating: 0, count: targetCount)
        for i in 0..<targetCount {
            let location = Double(i) * format.sampleRate / sampleRate
            let j = min(Int(location), count - 1)
            let next = min(j + 1, count - 1)
            let fraction = Float(location - Double(j))
            var value: Float = 0
            for channel in 0..<nChannels {
                value += channels[channel][j] * (1 - fraction) + channels[channel][next] * fraction
            }
            value /= Float(nChannels)
            output[i] = Int16(max(-32767, min(32767, Int(value * 30000))))
        }
        guard output.contains(where: { abs(Int($0)) > 180 }) else { throw SampleError.empty }
        return output
    }

    // Autocorrelation near a target pitch. The user is given an audible pitch
    // reference, which makes estimating the fundamental much more reliable.
    static func detectPitch(_ pcm: [Int16], near expected: Double) -> Double? {
        guard pcm.count >= 4096 else { return nil }
        let size = 4096
        let hop = 512
        var bestStart = 0
        var bestEnergy = 0.0
        if pcm.count > size {
            for start in stride(from: 0, through: min(pcm.count - size, Int(sampleRate * 2)), by: hop) {
                var energy = 0.0
                for i in stride(from: start, to: start + size, by: 8) {
                    let v = Double(pcm[i]) / 32768
                    energy += v * v
                }
                if energy > bestEnergy { bestEnergy = energy; bestStart = start }
            }
        }
        guard bestEnergy > 0.015 else { return nil }
        let raw = (0..<size).map { Double(pcm[bestStart + $0]) / 32768 }
        let average = raw.reduce(0, +) / Double(size)
        let values = raw.map { $0 - average }
        let lowLag = max(12, Int(sampleRate / (expected * 1.24)))
        let highLag = min(900, Int(sampleRate / (expected / 1.24)))
        guard lowLag <= highLag else { return nil }
        var bestLag = lowLag
        var bestScore = -1.0
        var correlations = [Double](repeating: 0, count: highLag + 1)
        for lag in lowLag...highLag {
            var numerator = 0.0, power1 = 0.0, power2 = 0.0
            for i in stride(from: 0, to: size - lag, by: 2) {
                let a = values[i], b = values[i + lag]
                numerator += a * b
                power1 += a * a
                power2 += b * b
            }
            let score = numerator / max(1e-10, sqrt(power1 * power2))
            correlations[lag] = score
            if score > bestScore { bestScore = score; bestLag = lag }
        }
        guard bestScore > 0.56 else { return nil }
        var interpolated = Double(bestLag)
        if bestLag > lowLag && bestLag < highLag {
            let a = correlations[bestLag - 1], b = correlations[bestLag], c = correlations[bestLag + 1]
            let denominator = a - 2 * b + c
            if abs(denominator) > 1e-8 {
                interpolated += max(-0.5, min(0.5, 0.5 * (a - c) / denominator))
            }
        }
        return sampleRate / interpolated
    }

    static func retune(_ pcm: [Int16], actualHz: Double, desiredHz: Double) -> [Int16] {
        guard actualHz > 0, desiredHz > 0 else { return pcm }
        let ratio = desiredHz / actualHz
        guard (0.75...1.35).contains(ratio) else { return pcm }
        let length = max(1, min(Int(Double(pcm.count) / ratio), Int(sampleRate * 12)))
        return (0..<length).map { i in
            let pos = Double(i) * ratio
            let a = min(Int(pos), pcm.count - 1)
            let b = min(a + 1, pcm.count - 1)
            let fraction = pos - Double(a)
            return Int16((Double(pcm[a]) * (1 - fraction) + Double(pcm[b]) * fraction).rounded())
        }
    }
}

// Minimal standards-compliant mono SoundFont 2.01 with one melodic preset.
// A 16-bit PCM sample becomes a genuinely polyphonic, pitched instrument with
// configurable looping via AVAudioUnitSampler (no extra audio libraries).
enum SampleSoundFont {
    private static func u16(_ n: Int) -> Data { var x = UInt16(truncatingIfNeeded: n).littleEndian; return withUnsafeBytes(of: &x) { Data($0) } }
    private static func u32(_ n: Int) -> Data { var x = UInt32(truncatingIfNeeded: n).littleEndian; return withUnsafeBytes(of: &x) { Data($0) } }
    private static func bytes(_ value: String) -> Data { Data(value.utf8) }
    private static func name(_ text: String) -> Data {
        var bytes = Array(text.utf8.prefix(19))
        bytes += [UInt8](repeating: 0, count: 20 - bytes.count)
        return Data(bytes)
    }
    private static func evenCString(_ text: String) -> Data {
        var data = bytes(text + "\u{0}")
        if data.count % 2 != 0 { data.append(0) }
        return data
    }
    private static func chunk(_ id: String, _ body: Data) -> Data {
        var output = concatenate(bytes(id), u32(body.count), body)
        if body.count % 2 != 0 { output.append(0) }
        return output
    }
    private static func concatenate(_ parts: Data...) -> Data {
        var output = Data()
        for part in parts { output.append(part) }
        return output
    }
    private static func generator(_ code: Int, _ amount: Int) -> Data { concatenate(u16(code), u16(amount)) }
    private static func sfTime(_ seconds: Double) -> Int { Int((1200 * log2(max(0.001, seconds))).rounded()) & 0xFFFF }

    static func generate(_ pcm: [Int16], name title: String, root: Int, loop: Bool) throws -> Data {
        guard pcm.count > 2048 else { throw SampleTools.SampleError.empty }
        let rootPitch = max(0, min(127, root))
        // Protect the beginning/end from clicks; the SF2 sample has guard frames.
        var values = Array(pcm.prefix(Int(SampleTools.sampleRate * 8)))
        let fade = min(220, values.count / 12)
        for i in 0..<fade {
            values[i] = Int16(Double(values[i]) * Double(i) / Double(fade))
            values[values.count - i - 1] = Int16(Double(values[values.count - i - 1]) * Double(i) / Double(fade))
        }
        let sampleLength = values.count
        let loopStart = loop ? max(1000, Int(Double(sampleLength) * 0.32)) : 0
        let loopEnd = loop ? max(loopStart + 128, Int(Double(sampleLength) * 0.70)) : sampleLength
        var pcmData = Data(capacity: (sampleLength + 46) * 2)
        for sample in values { pcmData.append(u16(Int(sample))) }
        pcmData.append(Data(repeating: 0, count: 92))

        let phdr = concatenate(name(title), u16(0), u16(0), u16(0), u32(0), u32(0), u32(0),
                               name("EOP"), u16(0), u16(0), u16(1), u32(0), u32(0), u32(0))
        let pbag = concatenate(u16(0), u16(0), u16(1), u16(0))
        let pgen = concatenate(generator(41, 0), generator(0, 0))
        let inst = concatenate(name(title), u16(0), name("EOI"), u16(1))
        let ibag = concatenate(u16(0), u16(0), u16(loop ? 3 : 2), u16(0))
        let igen = concatenate(generator(38, sfTime(loop ? 0.18 : 0.32)),
                               loop ? generator(54, 1) : Data(),
                               generator(53, 0), generator(0, 0))
        let shdr = concatenate(name("Recorded"), u32(0), u32(sampleLength),
                               u32(loopStart), u32(loopEnd), u32(Int(SampleTools.sampleRate)),
                               Data([UInt8(rootPitch), 0]), u16(0), u16(1),
                               name("EOS"), u32(sampleLength + 46), u32(sampleLength + 46),
                               u32(sampleLength + 46), u32(sampleLength + 46),
                               u32(Int(SampleTools.sampleRate)), Data([0, 0]), u16(0), u16(1))
        let info = chunk("LIST", concatenate(bytes("INFO"),
            chunk("ifil", concatenate(u16(2), u16(1))),
            chunk("isng", bytes("EMU8000\u{0}")),
            chunk("INAM", evenCString(title))))
        let sdta = chunk("LIST", concatenate(bytes("sdta"), chunk("smpl", pcmData)))
        let pdta = chunk("LIST", concatenate(bytes("pdta"),
            chunk("phdr", phdr), chunk("pbag", pbag), chunk("pmod", Data(repeating: 0, count: 10)),
            chunk("pgen", pgen), chunk("inst", inst), chunk("ibag", ibag),
            chunk("imod", Data(repeating: 0, count: 10)), chunk("igen", igen), chunk("shdr", shdr)))
        let output = concatenate(bytes("sfbk"), info, sdta, pdta)
        return chunk("RIFF", output)
    }
}
