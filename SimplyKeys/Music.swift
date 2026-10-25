import Foundation

enum Instrument: Int, CaseIterable, Identifiable {
    case piano = 0, electricPiano = 4, musicBox = 10, vibraphone = 11, marimba = 12
    case organ = 16, accordion = 21, acousticGuitar = 24, electricGuitar = 26, bassGuitar = 32
    case violin = 40, cello = 42, harp = 46, strings = 48
    case trumpet = 56, trombone = 57, saxophone = 65, oboe = 68, clarinet = 71, flute = 73, synth = 80

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .piano: return "Grand Piano"
        case .electricPiano: return "Electric Piano"
        case .musicBox: return "Music Box"
        case .vibraphone: return "Vibraphone"
        case .marimba: return "Marimba"
        case .organ: return "Organ"
        case .accordion: return "Accordion"
        case .acousticGuitar: return "Acoustic Guitar"
        case .electricGuitar: return "Electric Guitar"
        case .bassGuitar: return "Bass Guitar"
        case .violin: return "Violin"
        case .cello: return "Cello"
        case .harp: return "Harp"
        case .strings: return "Strings"
        case .trumpet: return "Trumpet"
        case .trombone: return "Trombone"
        case .saxophone: return "Saxophone"
        case .oboe: return "Oboe"
        case .clarinet: return "Clarinet"
        case .flute: return "Flute"
        case .synth: return "Synth"
        }
    }
}

enum Clef: String, CaseIterable, Identifiable {
    case treble, bass
    var id: String { rawValue }
    var title: String { self == .treble ? "Treble" : "Bass" }
    var startingNote: Int { self == .treble ? 60 : 48 }
}

enum NoteSpelling: String, CaseIterable, Identifiable {
    case both, sharps, flats
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum NoteNames {
    static let natural = ["C", "", "D", "", "E", "F", "", "G", "", "A", "", "B"]
    static let sharp = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    static let flat = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]
    static func isBlack(_ midi: Int) -> Bool { natural[midi % 12].isEmpty }
    static func label(for midi: Int, spelling: NoteSpelling, compact: Bool = false) -> String {
        let index = midi % 12
        let octave = midi / 12 - 1
        if !isBlack(midi) { return compact ? natural[index] : "\(natural[index])\(octave)" }
        switch spelling {
        case .sharps: return compact ? sharp[index] : "\(sharp[index])\(octave)"
        case .flats: return compact ? flat[index] : "\(flat[index])\(octave)"
        case .both: return compact ? sharp[index] : "\(sharp[index])\(octave)\n\(flat[index])\(octave)"
        }
    }
    static func frequency(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }
}


enum PitchMode: String, CaseIterable, Identifiable {
    case classic, preserveDuration
    var id: String { rawValue }
    var title: String {
        switch self {
        case .classic: return "Classic"
        case .preserveDuration: return "Time-Stretch"
        }
    }
}
