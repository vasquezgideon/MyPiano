import Foundation

/// Reads the uncompressed PCM and key/velocity zones from a SoundFont 2 bank.
/// The parser is deliberately independent of AVFoundation so its region
/// selection can be regression-tested on GitHub before the iPhone build.
struct SoundFontRegions {
    enum BankError: Error { case unsupportedBank, missingProgram, malformedBank }

    struct Region {
        let sampleIndex: Int
        let lowKey: Int
        let highKey: Int
        let lowVelocity: Int
        let highVelocity: Int
        let root: Int
        let cents: Int
        let start: Int
        let end: Int
        let loopStart: Int
        let loopEnd: Int
        let rate: Int
        let looping: Bool
        let release: Double

        func matches(note: Int, velocity: Int) -> Bool {
            (lowKey...highKey).contains(note) && (lowVelocity...highVelocity).contains(velocity)
        }
    }

    let regions: [Region]
    private let bank: Data
    private let sampleDataOffset: Int
    private let sampleDataLength: Int

    init(url: URL, program: Int) throws {
        let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
        func u16(_ offset: Int) -> Int {
            guard offset >= 0, offset + 2 <= bytes.count else { return 0 }
            return Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
        }
        func u32(_ offset: Int) -> Int {
            guard offset >= 0, offset + 4 <= bytes.count else { return 0 }
            return u16(offset) | (u16(offset + 2) << 16)
        }
        func signature(_ offset: Int) -> String {
            guard offset >= 0, offset + 4 <= bytes.count else { return "" }
            return String(decoding: bytes[offset..<(offset + 4)], as: UTF8.self)
        }
        guard signature(0) == "RIFF", signature(8) == "sfbk" else { throw BankError.unsupportedBank }
        var chunks: [String: (start: Int, length: Int)] = [:]
        var outer = 12
        while outer + 8 <= bytes.count {
            let kind = signature(outer)
            let length = u32(outer + 4)
            let start = outer + 8
            guard length >= 0, start + length <= bytes.count else { throw BankError.malformedBank }
            if kind == "LIST", length >= 4 {
                let listName = signature(start)
                var offset = start + 4
                while offset + 8 <= start + length {
                    let chunkKind = signature(offset)
                    let chunkSize = u32(offset + 4)
                    let content = offset + 8
                    guard chunkSize >= 0, content + chunkSize <= start + length else {
                        throw BankError.malformedBank
                    }
                    chunks[listName + ":" + chunkKind] = (content, chunkSize)
                    offset = content + chunkSize + (chunkSize % 2)
                }
            }
            outer = start + length + (length % 2)
        }
        func chunk(_ name: String, recordSize: Int) throws -> (start: Int, count: Int) {
            guard let value = chunks["pdta:" + name], value.length % recordSize == 0 else {
                throw BankError.malformedBank
            }
            return (value.start, value.length / recordSize)
        }
        let phdr = try chunk("phdr", recordSize: 38)
        let pbag = try chunk("pbag", recordSize: 4)
        let pgen = try chunk("pgen", recordSize: 4)
        let inst = try chunk("inst", recordSize: 22)
        let ibag = try chunk("ibag", recordSize: 4)
        let igen = try chunk("igen", recordSize: 4)
        let shdr = try chunk("shdr", recordSize: 46)
        guard let smpl = chunks["sdta:smpl"], phdr.count >= 2,
              inst.count >= 2, shdr.count >= 2, pbag.count >= 2, ibag.count >= 2 else {
            throw BankError.malformedBank
        }

        func generators(bag: (start: Int, count: Int), gen: (start: Int, count: Int), index: Int) -> [Int: Int] {
            guard index >= 0, index + 1 < bag.count else { return [:] }
            let begin = u16(bag.start + 4 * index)
            let end = u16(bag.start + 4 * (index + 1))
            guard begin <= end, end <= gen.count else { return [:] }
            var result: [Int: Int] = [:]
            for i in begin..<end {
                let offset = gen.start + 4 * i
                result[u16(offset)] = u16(offset + 2)
            }
            return result
        }
        func bounds(_ amount: Int?) -> (Int, Int) {
            guard let amount else { return (0, 127) }
            let low = max(0, min(127, amount & 255))
            let high = max(low, min(127, (amount >> 8) & 255))
            return (low, high)
        }
        func signed(_ raw: Int) -> Int { raw < 32768 ? raw : raw - 65536 }
        func releaseSeconds(_ timecents: Int?) -> Double {
            guard let timecents else { return 0.25 }
            return max(0.06, min(2.0, pow(2.0, Double(signed(timecents)) / 1200.0)))
        }

        // A preset may contain one or more instrument zones; our own banks
        // use one per preset. Unknown global modulators do not affect region IDs.
        guard let selected = (0..<(phdr.count - 1)).first(where: {
            u16(phdr.start + $0 * 38 + 20) == program &&
            u16(phdr.start + $0 * 38 + 22) == 0
        }) else { throw BankError.missingProgram }
        let presetStart = u16(phdr.start + selected * 38 + 24)
        let presetEnd = u16(phdr.start + (selected + 1) * 38 + 24)
        guard presetStart <= presetEnd, presetEnd < pbag.count else { throw BankError.malformedBank }
        var selectedRegions: [Region] = []
        for p in presetStart..<presetEnd {
            let pzone = generators(bag: pbag, gen: pgen, index: p)
            guard let instrument = pzone[41], instrument + 1 < inst.count else { continue }
            let presetKeys = bounds(pzone[43])
            let presetVel = bounds(pzone[44])
            let instStart = u16(inst.start + instrument * 22 + 20)
            let instEnd = u16(inst.start + (instrument + 1) * 22 + 20)
            guard instStart <= instEnd, instEnd < ibag.count else { continue }
            var global: [Int: Int] = [:]
            for i in instStart..<instEnd {
                let local = generators(bag: ibag, gen: igen, index: i)
                guard let sampleID = local[53] else {
                    // Global zones contain defaults such as envelope settings.
                    global.merge(local) { _, newer in newer }
                    continue
                }
                guard sampleID < shdr.count - 1 else { continue }
                var zone = global
                zone.merge(local) { _, newer in newer }
                let keys = bounds(zone[43]), velocities = bounds(zone[44])
                let lowKey = max(keys.0, presetKeys.0)
                let highKey = min(keys.1, presetKeys.1)
                let lowVelocity = max(velocities.0, presetVel.0)
                let highVelocity = min(velocities.1, presetVel.1)
                guard lowKey <= highKey, lowVelocity <= highVelocity else { continue }
                let header = shdr.start + sampleID * 46
                let start = u32(header + 20)
                let end = u32(header + 24)
                let loopStart = u32(header + 28)
                let loopEnd = u32(header + 32)
                let rate = u32(header + 36)
                let original = Int(bytes[header + 40])
                let correction = Int(Int8(bitPattern: bytes[header + 41]))
                let root = zone[58].map { $0 & 255 } ?? original
                let sampleMode = zone[54] ?? 0
                guard rate > 0, start >= 0, start < end, end <= smpl.length / 2 else { continue }
                let isLooped = (sampleMode & 1) != 0 && loopStart >= start &&
                    loopEnd <= end && loopEnd > loopStart + 256
                selectedRegions.append(Region(
                    sampleIndex: sampleID, lowKey: lowKey, highKey: highKey,
                    lowVelocity: lowVelocity, highVelocity: highVelocity,
                    root: root, cents: correction, start: start, end: end,
                    loopStart: loopStart, loopEnd: loopEnd, rate: rate,
                    looping: isLooped, release: releaseSeconds(zone[38])))
            }
        }
        guard !selectedRegions.isEmpty else { throw BankError.missingProgram }
        self.regions = selectedRegions
        self.bank = bytes
        self.sampleDataOffset = smpl.start
        self.sampleDataLength = smpl.length
    }

    func region(for note: Int, velocity: Int) -> Region? {
        regions.first { $0.matches(note: note, velocity: velocity) } ??
        regions.filter { ($0.lowKey...$0.highKey).contains(note) }
            .min { abs(($0.lowVelocity + $0.highVelocity) / 2 - velocity) <
                   abs(($1.lowVelocity + $1.highVelocity) / 2 - velocity) }
    }

    func pcm(for region: Region, maxSeconds: Double = 12) -> [Int16]? {
        let frames = min(region.end - region.start, Int(Double(region.rate) * maxSeconds))
        let offset = sampleDataOffset + region.start * 2
        guard frames > 500, offset + frames * 2 <= sampleDataOffset + sampleDataLength else { return nil }
        var output = [Int16](repeating: 0, count: frames)
        for index in 0..<frames {
            let p = offset + index * 2
            let raw = UInt16(bank[p]) | (UInt16(bank[p + 1]) << 8)
            output[index] = Int16(bitPattern: raw)
        }
        return output
    }
}
