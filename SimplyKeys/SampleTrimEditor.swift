import AVFoundation
import SwiftUI

/// Full-screen, landscape-friendly editor for individual recorded/imported samples.
/// The source remains untouched until the user explicitly taps Keep Selection.
struct SampleTrimEditor: View {
    let clip: RecordedLayer
    let onApply: ([Int16]) -> Void
    private let waveformPeaks: [CGFloat]

    init(clip: RecordedLayer, onApply: @escaping ([Int16]) -> Void) {
        self.clip = clip
        self.onApply = onApply
        self.waveformPeaks = SampleTrimming.peaks(clip.pcm)
    }

    @Environment(\.dismiss) private var dismiss
    @StateObject private var playback = SampleTrimPlayback()
    @State private var start: Double = 0
    @State private var end: Double = 1
    @State private var fadeEdges = true

    private var duration: Double { Double(clip.pcm.count) / SampleTools.sampleRate }
    private var minimumFraction: Double {
        min(1, SampleTrimming.minimumSeconds / max(0.001, duration))
    }
    private var selection: Range<Int> {
        SampleTrimming.bounds(count: clip.pcm.count, start: start, end: end,
                              sampleRate: SampleTools.sampleRate)
    }
    private var selectedSeconds: Double { Double(selection.count) / SampleTools.sampleRate }
    private var maximumFraction: Double { min(1, 8 / max(0.001, duration)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Trim & Crop Audio")
                        .font(.system(.title, design: .rounded, weight: .bold))
                    Text(clip.name).font(.subheadline).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(formatTime(start * duration))
                            .monospacedDigit()
                        Spacer()
                        Text("Selected · \(formatTime(selectedSeconds))")
                            .fontWeight(.semibold).monospacedDigit()
                        Spacer()
                        Text(formatTime(end * duration))
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    TrimWaveform(peaks: waveformPeaks, start: $start, end: $end,
                                 minimumFraction: minimumFraction,
                                 maximumFraction: maximumFraction)
                        .frame(height: 146)
                        .accessibilityLabel("Audio waveform; drag the left and right handles to crop")

                    HStack {
                        Label("Drag handles to trim, or drag inside the range to move it",
                              systemImage: "hand.draw")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Reset") {
                            playback.stop()
                            start = 0
                            end = maximumFraction
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))

                HStack(spacing: 14) {
                    Button {
                        if playback.isPlaying { playback.stop() }
                        else {
                            let pcm = SampleTrimming.crop(clip.pcm, start: start,
                                                          end: end, fadeEdges: fadeEdges,
                                                          sampleRate: SampleTools.sampleRate)
                            playback.play(pcm, sampleRate: SampleTools.sampleRate)
                        }
                    } label: {
                        Label(playback.isPlaying ? "Stop preview" : "Preview selection",
                              systemImage: playback.isPlaying ? "stop.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Toggle("Smooth cut edges", isOn: $fadeEdges)
                        .fixedSize(horizontal: true, vertical: false)
                }

                Text("Only the highlighted section (up to 8 seconds) becomes the instrument sample. The original file is not changed.")
                    .font(.footnote).foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.bordered)
                    Button {
                        playback.stop()
                        let cropped = SampleTrimming.crop(clip.pcm, start: start,
                                                          end: end, fadeEdges: fadeEdges,
                                                          sampleRate: SampleTools.sampleRate)
                        onApply(cropped)
                        dismiss()
                    } label: {
                        Label("Keep Selection", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedSeconds < SampleTrimming.minimumSeconds - 0.01 || selectedSeconds > 8.001)
                }
            }
            .frame(maxWidth: 830)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .navigationTitle("Edit Sample")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { end = maximumFraction }
        .onDisappear { playback.stop() }
    }

    private func formatTime(_ seconds: Double) -> String { String(format: "%.2fs", seconds) }
}

private struct TrimWaveform: View {
    let peaks: [CGFloat]
    @Binding var start: Double
    @Binding var end: Double
    let minimumFraction: Double
    let maximumFraction: Double

    private let handleWidth: CGFloat = 22
    @State private var leftOrigin: Double?
    @State private var rightOrigin: Double?
    @State private var selectionOrigin: (Double, Double)?

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color(uiColor: .tertiarySystemFill))

                Canvas { context, size in
                    let pitch = size.width / CGFloat(max(1, peaks.count))
                    for (index, peak) in peaks.enumerated() {
                        let height = max(2, peak * (size.height - 22))
                        let bar = CGRect(x: CGFloat(index) * pitch + 0.5,
                                         y: (size.height - height) / 2,
                                         width: max(1, pitch - 1.5), height: height)
                        context.fill(Path(roundedRect: bar, cornerRadius: 1.5),
                                     with: .color(.accentColor))
                    }
                }
                .padding(.horizontal, 1)

                // Dim the audio outside of the selected section.
                Color.black.opacity(0.47)
                    .frame(width: max(0, width * start))
                Color.black.opacity(0.47)
                    .frame(width: max(0, width * (1 - end)))
                    .offset(x: width * end)
                Rectangle()
                    .fill(Color.accentColor.opacity(0.10))
                    .frame(width: max(0, width * (end - start)))
                    .contentShape(Rectangle())
                    .offset(x: width * start)
                    .gesture(DragGesture(minimumDistance: 4)
                        .onChanged { gesture in
                            if selectionOrigin == nil { selectionOrigin = (start, end) }
                            guard let origin = selectionOrigin else { return }
                            let shift = max(-origin.0, min(1 - origin.1,
                                gesture.translation.width / width))
                            start = origin.0 + shift
                            end = origin.1 + shift
                        }
                        .onEnded { _ in selectionOrigin = nil })

                trimHandle
                    .offset(x: max(0, min(width - handleWidth, width * start - handleWidth / 2)))
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            if leftOrigin == nil { leftOrigin = start }
                            start = max(0, end - maximumFraction,
                                        min(end - minimumFraction,
                                            (leftOrigin ?? start) + gesture.translation.width / width))
                        }
                        .onEnded { _ in leftOrigin = nil })

                trimHandle
                    .offset(x: max(0, min(width - handleWidth, width * end - handleWidth / 2)))
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            if rightOrigin == nil { rightOrigin = end }
                            end = min(1, start + maximumFraction,
                                      max(start + minimumFraction,
                                          (rightOrigin ?? end) + gesture.translation.width / width))
                        }
                        .onEnded { _ in rightOrigin = nil })
            }
            .clipShape(RoundedRectangle(cornerRadius: 15))
        }
    }

    private var trimHandle: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.accentColor)
            .frame(width: handleWidth, height: 146)
            .overlay {
                Capsule().fill(.white.opacity(0.9))
                    .frame(width: 3, height: 26)
            }
            .contentShape(Rectangle())
            .accessibilityLabel("Trim handle")
    }
}

private final class SampleTrimPlayback: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    private var player: AVAudioPlayer?

    func play(_ samples: [Int16], sampleRate: Double) {
        stop()
        guard !samples.isEmpty else { return }
        do {
            let data = makeWAV(samples, sampleRate: sampleRate)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default,
                                                             options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let audio = try AVAudioPlayer(data: data)
            audio.delegate = self
            audio.prepareToPlay()
            isPlaying = audio.play()
            player = audio
        } catch { isPlaying = false }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { self.isPlaying = false }
    }

    private func makeWAV(_ samples: [Int16], sampleRate: Double) -> Data {
        var data = Data()
        func word(_ value: UInt16) {
            let n = value.littleEndian
            withUnsafeBytes(of: n) { data.append(contentsOf: $0) }
        }
        func dword(_ value: UInt32) {
            let n = value.littleEndian
            withUnsafeBytes(of: n) { data.append(contentsOf: $0) }
        }
        let bytes = UInt32(samples.count * 2)
        let rate = UInt32(sampleRate.rounded())
        data.append(contentsOf: "RIFF".utf8)
        dword(36 + bytes)
        data.append(contentsOf: "WAVEfmt ".utf8)
        dword(16) // PCM format header size
        word(1)   // signed integer PCM
        word(1)   // mono
        dword(rate)
        dword(rate * 2)
        word(2)
        word(16)
        data.append(contentsOf: "data".utf8)
        dword(bytes)
        for value in samples { word(UInt16(bitPattern: value)) }
        return data
    }
}
