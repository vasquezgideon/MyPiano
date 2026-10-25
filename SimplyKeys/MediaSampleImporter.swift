import AVFoundation
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Audio-only import pipeline for Instrument Studio. Movie imports are never
/// treated as pictures: AVFoundation extracts the soundtrack to a temporary
/// M4A, which follows exactly the same trimming and pitch-analysis path as an
/// audio recording. The source file is never modified.
enum MediaSampleImporter {
    static let maximumImportSeconds = 30.0

    enum ImportError: LocalizedError {
        case noSoundtrack
        case unsupportedMovie
        case extractionFailed(String)

        var errorDescription: String? {
            switch self {
            case .noSoundtrack:
                return "This video doesn't contain an audio track. Choose a video with sound."
            case .unsupportedMovie:
                return "This video's audio format isn't supported by iOS. Try an MP4 or MOV with AAC audio."
            case .extractionFailed(let reason):
                return "Couldn't extract the video's audio. \(reason)"
            }
        }
    }

    static func isVideo(_ url: URL) -> Bool {
        // Document providers can offer more specific UTTypes than public.movie.
        // Fall back to the filename extension if no type can be inferred.
        let ext = url.pathExtension.lowercased()
        if ["mov", "mp4", "m4v", "3gp", "3g2"].contains(ext) { return true }
        if let type = UTType(filenameExtension: ext) {
            return type.conforms(to: .movie) || type.conforms(to: .video)
        }
        return false
    }

    static func loadPCM(from url: URL) async throws -> [Int16] {
        // Keep the security-scoped document accessible throughout export and
        // decoding. Files never leave the device and are never uploaded.
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }

        if isVideo(url) {
            let extracted = try await extractSoundtrack(from: url)
            defer { try? FileManager.default.removeItem(at: extracted) }
            return try await decodeAudio(at: extracted)
        }
        return try await decodeAudio(at: url)
    }

    private static func decodeAudio(at url: URL) async throws -> [Int16] {
        try await Task.detached(priority: .userInitiated) {
            try SampleTools.readAudio(at: url, maximumSeconds: maximumImportSeconds)
        }.value
    }

    private static func extractSoundtrack(from url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else { throw ImportError.noSoundtrack }

        guard let exporter = AVAssetExportSession(asset: asset,
                                                 presetName: AVAssetExportPresetAppleM4A),
              exporter.supportedFileTypes.contains(.m4a) else {
            throw ImportError.unsupportedMovie
        }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyPiano-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        exporter.outputURL = output
        exporter.outputFileType = .m4a
        // The existing waveform editor holds up to 30 seconds of audio. Only
        // export that much even when the selected video is much longer.
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        if seconds.isFinite, seconds > 0 {
            exporter.timeRange = CMTimeRange(start: .zero,
                duration: CMTime(seconds: min(maximumImportSeconds, seconds),
                                 preferredTimescale: 600))
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            exporter.exportAsynchronously { continuation.resume() }
        }
        guard exporter.status == .completed else {
            try? FileManager.default.removeItem(at: output)
            throw ImportError.extractionFailed(exporter.error?.localizedDescription ??
                "The video could not be decoded.")
        }
        return output
    }
}

/// PhotosPicker hands us an ephemeral file. Copy it during the transfer so the
/// audio extractor can safely read it after the picker has closed.
struct PickedInstrumentMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let fileExtension = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let temporary = FileManager.default.temporaryDirectory
                .appendingPathComponent("MyPiano-Photos-" + UUID().uuidString)
                .appendingPathExtension(fileExtension)
            try FileManager.default.copyItem(at: received.file, to: temporary)
            return Self(url: temporary)
        }
    }
}
