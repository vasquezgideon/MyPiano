import AVFoundation
import Combine
import Foundation

struct ImportedInstrument: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    let filename: String
    let program: Int
    let type: String
}

/// On-device collection of imported banks and user-created sampled instruments.
final class InstrumentLibrary: ObservableObject {
    @Published private(set) var instruments: [ImportedInstrument] = []

    let directory: URL
    private var catalog: URL { directory.appendingPathComponent("Instruments.json") }

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent("MyPianoInstruments", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: catalog),
           let saved = try? JSONDecoder().decode([ImportedInstrument].self, from: data) {
            instruments = saved.filter { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.filename).path) }
        }
    }

    private func store(_ item: ImportedInstrument) throws -> ImportedInstrument {
        instruments.append(item)
        do { try saveCatalog(); return item }
        catch { instruments.removeAll { $0.id == item.id }; throw error }
    }

    private func saveCatalog() throws {
        let data = try JSONEncoder().encode(instruments)
        try data.write(to: catalog, options: .atomic)
    }

    @discardableResult
    func saveSample(name: String, pcm: [Int16], root: Int, loop: Bool) throws -> ImportedInstrument {
        let id = UUID().uuidString
        let filename = id + ".sf2"
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = try SampleSoundFont.generate(pcm, name: title.isEmpty ? "My Instrument" : title,
                                                root: root, loop: loop)
        let file = directory.appendingPathComponent(filename)
        try data.write(to: file, options: .atomic)
        do {
            return try store(ImportedInstrument(id: id, name: title.isEmpty ? "My Instrument" : title,
                                                filename: filename, program: 0, type: "Recorded"))
        } catch { try? FileManager.default.removeItem(at: file); throw error }
    }

    @discardableResult
    func saveLayers(name: String, layers: [SoundFontLayer], loop: Bool,
                    type: String = "Created") throws -> ImportedInstrument {
        let id = UUID().uuidString
        let filename = id + ".sf2"
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = title.isEmpty ? "My Instrument" : title
        let data = try MultiSampleSoundFont.generate(layers, name: cleanName, loop: loop)
        let url = directory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        do {
            return try store(ImportedInstrument(id: id, name: cleanName,
                                                filename: filename, program: 0, type: type))
        } catch { try? FileManager.default.removeItem(at: url); throw error }
    }

    @discardableResult
    func importFile(_ sourceURL: URL, sampleRoot: Int? = nil) throws -> ImportedInstrument {
        let authorized = sourceURL.startAccessingSecurityScopedResource()
        defer { if authorized { sourceURL.stopAccessingSecurityScopedResource() } }
        let ext = sourceURL.pathExtension.lowercased()
        let id = UUID().uuidString
        let filename = id + "." + (ext == "dls" ? "dls" : "sf2")
        let target = directory.appendingPathComponent(filename)
        let name = sourceURL.deletingPathExtension().lastPathComponent
        let program: Int
        let category: String

        if ["sf2", "dls"].contains(ext) {
            let data = try Data(contentsOf: sourceURL)
            guard data.count > 64 else { throw SampleTools.SampleError.unreadable }
            program = ext == "sf2" ? firstSF2Program(in: data) : 0
            category = ext.uppercased()
            try data.write(to: target, options: .atomic)
        } else if ["wav", "aif", "aiff", "caf", "mp3", "m4a"].contains(ext) {
            let pcm = try SampleTools.readAudio(at: sourceURL)
            let detected = [110.0, 164.81, 246.94, 349.23, 493.88, 739.99, 987.77]
                .compactMap { SampleTools.detectPitch(pcm, near: $0) }
            // Root note may be supplied by the user; otherwise, prefer a pitch
            // estimate near standard equal-tempered MIDI tuning.
            let best = detected.min { a, b in
                let da = abs(12 * log2(a / 440) - (12 * log2(a / 440)).rounded())
                let db = abs(12 * log2(b / 440) - (12 * log2(b / 440)).rounded())
                return da < db
            }
            let root = sampleRoot.map { max(0, min(127, $0)) } ??
                (best.map { max(0, min(127, Int((69 + 12 * log2($0 / 440)).rounded()))) } ?? 60)
            let data = try SampleSoundFont.generate(pcm, name: name, root: root, loop: false)
            try data.write(to: target, options: .atomic)
            program = 0
            category = "Sample"
        } else if ext == "sfz" {
            // A portable one-sample SFZ, with its adjacent referenced sample.
            // Complex multi-zone SFZ libraries should be exported as SF2 first.
            let text = try String(contentsOf: sourceURL, encoding: .utf8)
            guard let sample = sfzValue("sample", in: text),
                  !sample.contains(".."), !sample.hasPrefix("/"),
                  !sample.contains(":") else { throw SampleTools.SampleError.unsupported }
            let audioURL = sourceURL.deletingLastPathComponent().appendingPathComponent(sample)
            let pcm = try SampleTools.readAudio(at: audioURL)
            let keyString = sfzValue("pitch_keycenter", in: text) ?? "60"
            let key = max(0, min(127, Int(keyString) ?? 60))
            let loop = sfzValue("loop_mode", in: text) == "loop_continuous"
            let data = try SampleSoundFont.generate(pcm, name: name, root: key, loop: loop)
            try data.write(to: target, options: .atomic)
            program = 0
            category = "SFZ sample"
        } else {
            throw SampleTools.SampleError.unsupported
        }

        do {
            return try store(ImportedInstrument(id: id, name: name, filename: filename,
                                                program: program, type: category))
        } catch { try? FileManager.default.removeItem(at: target); throw error }
    }

    func delete(_ item: ImportedInstrument) {
        instruments.removeAll { $0.id == item.id }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(item.filename))
        try? saveCatalog()
    }

    // Read the first preset's program from the SoundFont phdr chunk.
    private func firstSF2Program(in data: Data) -> Int {
        let signature = Data("phdr".utf8)
        guard let range = data.range(of: signature), range.lowerBound + 8 + 22 <= data.count else { return 0 }
        let offset = range.lowerBound + 8 + 20
        return Int(data[offset]) | Int(data[offset + 1]) << 8
    }

    private func sfzValue(_ key: String, in text: String) -> String? {
        // Small SFZ subset: one simple <region>, sample=..., pitch_keycenter=...
        let pattern = #"(?:^|\s)"# + NSRegularExpression.escapedPattern(for: key) + #"\s*=\s*("[^"]+"|[^\s]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }
}
