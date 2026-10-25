import Foundation

// Lightweight test dependencies so the pure audio sample builder can run in
// GitHub Actions before Xcode compiles the iOS-specific AVFoundation sources.
enum NoteNames {
    static func frequency(_ note: Int) -> Double {
        440 * pow(2, Double(note - 69) / 12)
    }
}

enum SampleTools {
    static let sampleRate = 22_050.0
    enum SampleError: Error { case empty, unsupported }
    static func detectPitch(_ pcm: [Int16], near expected: Double) -> Double? { nil }
    static func retune(_ pcm: [Int16], actualHz: Double, desiredHz: Double) -> [Int16] { pcm }
}
