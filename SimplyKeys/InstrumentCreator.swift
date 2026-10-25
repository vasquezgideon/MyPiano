import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

final class InstrumentRecorder: ObservableObject {
    @Published var recording = false
    @Published var error: String?
    private var recorder: AVAudioRecorder?
    private var fileURL: URL?

    func begin() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else { self.error = "Microphone access is needed to record an instrument."; return }
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playAndRecord, mode: .default,
                                            options: [.defaultToSpeaker, .mixWithOthers])
                    try session.setActive(true)
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString + ".caf")
                    let options: [String: Any] = [
                        AVFormatIDKey: Int(kAudioFormatLinearPCM),
                        AVSampleRateKey: SampleTools.sampleRate,
                        AVNumberOfChannelsKey: 1,
                        AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsBigEndianKey: false
                    ]
                    let recorder = try AVAudioRecorder(url: url, settings: options)
                    guard recorder.record(forDuration: 8) else { throw SampleTools.SampleError.unreadable }
                    self.recorder = recorder
                    self.fileURL = url
                    self.recording = true
                } catch { self.error = error.localizedDescription }
            }
        }
    }

    func finish() throws -> [Int16] {
        guard recording, let recorder, let url = fileURL else { throw SampleTools.SampleError.empty }
        recorder.stop()
        self.recorder = nil
        fileURL = nil
        recording = false
        defer {
            try? FileManager.default.removeItem(at: url)
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default,
                                                               options: [.mixWithOthers])
        }
        return try SampleTools.readAudio(at: url, maximumSeconds: 8)
    }

    func cancel() {
        recorder?.stop()
        recorder = nil
        recording = false
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        fileURL = nil
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default,
                                                          options: [.mixWithOthers])
    }
}


enum CreatorMode: String, CaseIterable {
    case analysis = "Analysis", precision = "Precision"
}

struct InstrumentCreator: View {
    let library: InstrumentLibrary
    let sound: SoundEngine
    let onCreated: (ImportedInstrument) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = InstrumentRecorder()

    @State private var name = "My Instrument"
    @State private var mode = CreatorMode.analysis
    @State private var oneClip: RecordedLayer?
    @State private var detectedRoot: Int?
    @State private var chosenRoot = 65
    @State private var note = 65
    @State private var dynamic = RecordingDynamic.medium
    @State private var takes: [RecordedLayer] = []
    @State private var loop = false
    @State private var importerVisible = false
    @State private var saving = false
    @State private var error: String?

    private var accent: Color { .accentColor }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Instrument Studio")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("Turn short audio clips into a playable instrument.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Picker("Creation mode", selection: $mode) {
                    ForEach(CreatorMode.allCases, id: \.self) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(recorder.recording || saving)

                studioCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(mode == .analysis ? "One sound, every key" : "Build a detailed sound bank",
                              systemImage: mode == .analysis ? "waveform.path" : "square.stack.3d.up")
                            .font(.headline)
                        Text(mode == .analysis
                             ? "Record or import one clear note. Its pitch is detected and gently corrected; the keyboard plays it at other pitches."
                             : "Capture different notes and volumes. Each sample keeps its own character; notes between samples are filled in automatically.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if mode == .precision {
                            Picker("Reference note", selection: $note) {
                                ForEach(36...96, id: \.self) { midi in
                                    Text(NoteNames.label(for: midi, spelling: .sharps)).tag(midi)
                                }
                            }
                            .pickerStyle(.menu)
                            Picker("Playing strength", selection: $dynamic) {
                                ForEach(RecordingDynamic.allCases) { value in
                                    Text(value.title).tag(value)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        Button {
                            sound.resume()
                            let referenceNote = mode == .analysis ? chosenRoot : note
                            sound.noteOn(referenceNote, velocity: 96)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                                sound.noteOff(referenceNote)
                            }
                        } label: {
                            Label("Play reference \(NoteNames.label(for: mode == .analysis ? chosenRoot : note, spelling: .sharps))",
                                  systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(recorder.recording || saving)

                        HStack(spacing: 12) {
                            Button {
                                if recorder.recording { finishRecording() }
                                else { sound.stopAll(); recorder.begin() }
                            } label: {
                                Label(recorder.recording ? "Stop" : "Record",
                                      systemImage: recorder.recording ? "stop.fill" : "mic.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(recorder.recording ? .red : accent)
                            Button { importerVisible = true } label: {
                                Label("Audio files", systemImage: "folder")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(recorder.recording || saving)
                        }
                        if recorder.recording {
                            Label("Recording — stop when the note has finished", systemImage: "waveform")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                        Text("WAV, AIFF, CAF, M4A and MP3 · short, isolated sounds work best")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if mode == .analysis, let oneClip {
                    studioCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Source recording", systemImage: "waveform")
                                .font(.headline)
                            Text(oneClip.name)
                                .lineLimit(2)
                            HStack {
                                Text("Source note")
                                Spacer()
                                Picker("Source note", selection: $chosenRoot) {
                                    ForEach(24...108, id: \.self) { midi in
                                        Text(NoteNames.label(for: midi, spelling: .sharps)).tag(midi)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                            if detectedRoot != nil {
                                Text("Estimated pitch is selected. Change the source note if the estimate is incorrect.")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("Pitch couldn't be identified reliably. Select the note you recorded.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Button("Replace recording", role: .destructive) {
                                self.oneClip = nil
                                detectedRoot = nil
                            }
                            .font(.subheadline)
                        }
                    }
                }

                if mode == .precision {
                    studioCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Samples", systemImage: "waveform.path.ecg").font(.headline)
                                Spacer()
                                Text("\(takes.count)/24")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            if takes.isEmpty {
                                Text("Add recordings for different notes and dynamics. Repeated takes are compared so the cleanest one can be used.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            ForEach(takes) { take in
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(NoteNames.label(for: take.note, spelling: .sharps)) · \(take.dynamic.title)")
                                            .font(.subheadline.weight(.medium))
                                        Text(take.name)
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Button(role: .destructive) {
                                        takes.removeAll { $0.id == take.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .accessibilityLabel("Remove \(take.name)")
                                }
                                if take.id != takes.last?.id { Divider() }
                            }
                        }
                    }
                }

                studioCard {
                    VStack(alignment: .leading, spacing: 13) {
                        Text("Finish").font(.headline)
                        TextField("Instrument name", text: $name)
                            .textInputAutocapitalization(.words)
                            .padding(12)
                            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                        Toggle("Smooth sustain loop", isOn: $loop)
                        Text("Use sustain for strings and winds; leave it off for piano, guitar and other plucked or struck sounds.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button { makeInstrument() } label: {
                            HStack {
                                if saving { ProgressView().tint(.white) }
                                Text(saving ? "Creating instrument…" : "Create instrument")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(saving || recorder.recording || (mode == .analysis ? oneClip == nil : takes.isEmpty))
                    }
                }
            }
            .padding(18)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(uiColor: .secondarySystemBackground))
        .navigationTitle("Instrument Studio")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { recorder.cancel() }
        .fileImporter(isPresented: $importerVisible, allowedContentTypes: [.audio],
                      allowsMultipleSelection: true) { result in
            do {
                for url in try result.get().prefix(mode == .analysis ? 1 : max(0, 24 - takes.count)) {
                    let permission = url.startAccessingSecurityScopedResource()
                    defer { if permission { url.stopAccessingSecurityScopedResource() } }
                    let pcm = try SampleTools.readAudio(at: url, maximumSeconds: 8)
                    appendClip(pcm, name: url.deletingPathExtension().lastPathComponent)
                }
            } catch { self.error = error.localizedDescription }
        }
        .alert("Instrument Studio", isPresented: Binding(
            get: { error != nil || recorder.error != nil },
            set: { if !$0 { error = nil; recorder.error = nil } }
        )) { Button("OK", role: .cancel) {} }
        message: { Text(error ?? recorder.error ?? "") }
    }

    private func studioCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(17)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func appendClip(_ pcm: [Int16], name: String) {
        if mode == .analysis {
            let pitch = InstrumentAnalysis.fundamental(pcm)
            let root = pitch.map { max(0, min(127, Int((69 + 12 * log2($0 / 440)).rounded()))) }
            detectedRoot = root
            chosenRoot = root ?? 65
            oneClip = RecordedLayer(name: name, note: chosenRoot, dynamic: .medium, pcm: pcm)
        } else if takes.count < 24 {
            takes.append(RecordedLayer(name: name, note: note, dynamic: dynamic, pcm: pcm))
        }
    }

    private func finishRecording() {
        do {
            let pcm = try recorder.finish()
            sound.resume()
            appendClip(pcm, name: "Recording \(mode == .analysis ? 1 : takes.count + 1)")
        } catch { self.error = "Couldn't read that recording. Try a longer, clearer note." }
    }

    private func makeInstrument() {
        saving = true
        let clips: [RecordedLayer]
        let type: String
        if mode == .analysis {
            guard var clip = oneClip else { saving = false; return }
            clip.note = chosenRoot
            clips = [clip]
            type = "Analysis"
        } else {
            clips = takes
            type = "Precision"
        }
        let title = name
        let sustain = loop
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                var output: [SoundFontLayer] = []
                let grouped = Dictionary(grouping: clips) { "\($0.note)-\($0.dynamic.rawValue)" }
                for takes in grouped.values {
                    // Repeated takes for one pitch/dynamic: use the closest-to-pitch
                    // take with the least clipped or distorted samples. Do not sum
                    // unaligned sound waves, which would cancel their harmonics.
                    let reference = NoteNames.frequency(takes[0].note)
                    let best = takes.min { a, b in
                        qualityPenalty(a, reference: reference) < qualityPenalty(b, reference: reference)
                    }!
                    output.append(try InstrumentAnalysis.prepare(best))
                }
                DispatchQueue.main.async {
                    do {
                        let created = try library.saveLayers(name: title, layers: output,
                                                             loop: sustain, type: type)
                        onCreated(created)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                    saving = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = error.localizedDescription
                    saving = false
                }
            }
        }
    }

    private func qualityPenalty(_ clip: RecordedLayer, reference: Double) -> Double {
        let detected = SampleTools.detectPitch(clip.pcm, near: reference)
        let cents = detected.map { abs(1200 * log2($0 / reference)) } ?? 140
        let clipped = Double(clip.pcm.filter { abs(Int($0)) > 32000 }.count) / Double(max(1, clip.pcm.count))
        return cents + clipped * 2000
    }
}
