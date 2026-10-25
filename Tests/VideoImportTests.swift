import Foundation

@main
struct VideoImportTests {
    static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let video = directory.appendingPathComponent("with-audio.mp4")
        let withoutAudio = directory.appendingPathComponent("no-audio.mp4")
        precondition(MediaSampleImporter.isVideo(video))
        precondition(!MediaSampleImporter.isVideo(directory.appendingPathComponent("note.wav")))

        let samples = try await MediaSampleImporter.loadPCM(from: video)
        precondition(samples.count > 20_000, "Video's audio was not imported")
        let peak = samples.map { abs(Int($0)) }.max() ?? 0
        precondition(peak > 500, "Extracted audio was unexpectedly silent")
        let frequency = SampleTools.detectPitch(samples, near: 440)
        precondition(frequency != nil && abs(frequency! - 440) < 10,
                     "Extracted audio didn't retain the source pitch")

        do {
            _ = try await MediaSampleImporter.loadPCM(from: withoutAudio)
            fatalError("Video without a soundtrack should be rejected")
        } catch MediaSampleImporter.ImportError.noSoundtrack {
            // This is expected and should appear as a friendly message in the app.
        }
        print("Video import tests passed: MP4 soundtrack, pitch, silence detection, audio-only extraction.")
    }
}
