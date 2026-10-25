import SwiftUI
import UniformTypeIdentifiers

struct PianoScreen: View {
    @AppStorage("clef") private var clefValue = Clef.treble.rawValue
    @AppStorage("selectedSound") private var selectedSound = "built-in:0"
    @AppStorage("spelling") private var spellingValue = NoteSpelling.both.rawValue
    @AppStorage("appearance") private var appearanceValue = Appearance.system.rawValue
    @AppStorage("visibleWhiteKeys") private var visibleWhiteKeys = 8.0
    @AppStorage("glideLocked") private var glideLocked = false
    @AppStorage("metronomeBPM") private var metronomeBPM = 100.0
    @AppStorage("metronomeDivision") private var metronomeDivision = BeatDivision.quarter.rawValue
    @AppStorage("dynamicTouch") private var dynamicTouch = false
    @AppStorage("accentPreset") private var accentPreset = "apple"
    @AppStorage("customAccentHex") private var customAccentHex = "#007AFF"
    @AppStorage("importSampleRoot") private var importSampleRoot = -1

    @StateObject private var sound = SoundEngine()
    @StateObject private var library = InstrumentLibrary()
    @State private var showingSettings = false
    @State private var showingImporter = false
    @State private var importError: String?
    @State private var metronomeOn = false
    @Environment(\.scenePhase) private var scenePhase

    private var clef: Clef { Clef(rawValue: clefValue) ?? .treble }
    private var spelling: NoteSpelling { NoteSpelling(rawValue: spellingValue) ?? .both }
    private var appearance: Appearance { Appearance(rawValue: appearanceValue) ?? .system }
    private var accent: Color { Color(uiColor: accentUIColor) }
    private var accentUIColor: UIColor { AccentPalette.color(preset: accentPreset, customHex: customAccentHex) }
    private var division: BeatDivision { BeatDivision(rawValue: metronomeDivision) ?? .quarter }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                Color(uiColor: .systemBackground).ignoresSafeArea()

                PianoKeyboard(sound: sound, clef: clef, spelling: spelling,
                              whiteKeysOnScreen: visibleWhiteKeys, glideLocked: glideLocked,
                              dynamicTouch: dynamicTouch, accentColor: accentUIColor)
                    .ignoresSafeArea()

                HStack(spacing: 10) {
                    Button {
                        metronomeOn.toggle()
                        sound.metronomeSettings(isOn: metronomeOn, bpm: metronomeBPM, division: division)
                    } label: {
                        Image(systemName: "metronome.fill")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(metronomeOn ? accent : Color.primary)
                            .frame(width: 46, height: 46)
                    }
                    .buttonStyle(GlassCircleButtonStyle())
                    .accessibilityLabel(metronomeOn ? "Stop metronome" : "Start metronome")
                    .accessibilityValue("\(String(format: "%.1f", metronomeBPM)) beats per minute, \(division.title) notes")

                    Button {
                        sound.stopAll()
                        withAnimation(.easeInOut(duration: 0.18)) { glideLocked.toggle() }
                    } label: {
                        Image(systemName: glideLocked ? "lock.fill" : "lock.open")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(glideLocked ? accent : Color.primary)
                            .frame(width: 46, height: 46)
                    }
                    .buttonStyle(GlassCircleButtonStyle())
                    .accessibilityLabel(glideLocked ? "Unlock keyboard scrolling" : "Lock keyboard for glide")
                    .accessibilityHint(glideLocked ? "Swipe to scroll octaves" : "Swipe to play a sequence of notes")

                    Button {
                        sound.stopAll()
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(Color.primary)
                            .frame(width: 46, height: 46)
                    }
                    .buttonStyle(GlassCircleButtonStyle())
                    .accessibilityLabel("Settings")
                }
                .padding(.trailing, 16)
                .padding(.top, 12)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .sheet(isPresented: $showingSettings) {
            settingsSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .preferredColorScheme(appearance == .system ? nil : appearance == .dark ? .dark : .light)
        .statusBarHidden(true)
        .tint(accent)
        .onAppear {
            if selectedSound != "built-in:0" && selectedSound.hasPrefix("built-in:") == false
                && !library.instruments.contains(where: { $0.id == selectedSound }) {
                selectedSound = "built-in:0"
            }
            sound.select(selectedSound, library: library)
            sound.metronomeSettings(isOn: metronomeOn, bpm: metronomeBPM, division: division)
        }
        .onChange(of: selectedSound) { value in sound.select(value, library: library) }
        .onChange(of: metronomeBPM) { value in sound.metronomeSettings(isOn: metronomeOn, bpm: value, division: division) }
        .onChange(of: metronomeDivision) { _ in
            sound.metronomeSettings(isOn: metronomeOn, bpm: metronomeBPM, division: division)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { sound.resume() }
            else {
                metronomeOn = false
                sound.pause()
            }
        }
        .alert("Audio unavailable", isPresented: Binding(
            get: { sound.problem != nil },
            set: { if !$0 { sound.problem = nil } }
        )) { Button("OK", role: .cancel) {} }
        message: { Text(sound.problem ?? "") }
    }

    private var settingsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 15) {
                    settingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Keyboard", systemImage: "pianokeys").font(.headline)
                            HStack {
                                Text("Key scale")
                                Spacer()
                                Text("\(Int(visibleWhiteKeys)) keys across")
                                    .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            Slider(value: $visibleWhiteKeys, in: 5...15, step: 1)
                            Picker("Clef", selection: $clefValue) {
                                ForEach(Clef.allCases) { value in Text(value.title).tag(value.rawValue) }
                            }
                            .pickerStyle(.segmented)
                            Toggle("Dynamic touch", isOn: $dynamicTouch)
                            Text(dynamicTouch
                                 ? "At the hinge, keys play softly. Near the bottom edge, they play louder. Slide vertically to shape a held note."
                                 : "Every key plays at a consistent mezzo-forte level.")
                                .font(.footnote).foregroundStyle(.secondary)
                            Text("Treble starts at C4. Bass starts at C3. Both use the same pitches.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }

                    settingsCard {
                        VStack(alignment: .leading, spacing: 13) {
                            Label("Instruments", systemImage: "waveform").font(.headline)
                            Picker("Sound", selection: $selectedSound) {
                                Section("Included") {
                                    ForEach(Instrument.allCases) { instrument in
                                        Text(instrument.title).tag("built-in:\(instrument.rawValue)")
                                    }
                                }
                                if !library.instruments.isEmpty {
                                    Section("My instruments") {
                                        ForEach(library.instruments) { instrument in
                                            Text(instrument.name).tag(instrument.id)
                                        }
                                    }
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(accent)

                            Divider()
                            Button { showingImporter = true } label: {
                                Label("Import instrument", systemImage: "square.and.arrow.down")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .tint(accent)
                            NavigationLink {
                                InstrumentCreator(library: library, sound: sound) { instrument in
                                    selectedSound = instrument.id
                                }
                                .onAppear {
                                    metronomeOn = false
                                    sound.metronomeSettings(isOn: false, bpm: metronomeBPM, division: division)
                                    sound.select("built-in:0", library: library)
                                }
                                .onDisappear { sound.select(selectedSound, library: library) }
                            } label: {
                                Label("Create an instrument", systemImage: "mic.fill")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .tint(accent)
                            if !library.instruments.isEmpty {
                                NavigationLink {
                                    myInstruments
                                } label: {
                                    Label("Manage my instruments", systemImage: "music.note.list")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .tint(accent)
                            }
                            Picker("Audio sample root", selection: $importSampleRoot) {
                                Text("Auto detect").tag(-1)
                                ForEach([48, 55, 60, 65, 69, 72, 77, 81, 84], id: \.self) { note in
                                    Text(NoteNames.label(for: note, spelling: .sharps)).tag(note)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(accent)
                            Text("Import SF2, DLS, SFZ, WAV, AIFF, CAF, MP3 or M4A")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }

                    settingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Metronome", systemImage: "metronome").font(.headline)
                            TempoControl(bpm: $metronomeBPM)
                            Picker("Note division", selection: $metronomeDivision) {
                                ForEach(BeatDivision.allCases) { item in
                                    Text(item.title).tag(item.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)
                            Text("BPM follows quarter notes. Subdivisions add clicks between beats; the first beat of every four is accented.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    settingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Appearance", systemImage: "paintpalette").font(.headline)
                            Picker("Theme", selection: $appearanceValue) {
                                ForEach(Appearance.allCases) { value in Text(value.title).tag(value.rawValue) }
                            }
                            .pickerStyle(.segmented)
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Accent color").font(.subheadline.weight(.medium))
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 7), spacing: 9) {
                                    ForEach(AccentPalette.presets) { preset in
                                        Button {
                                            accentPreset = preset.id
                                        } label: {
                                            Circle()
                                                .fill(Color(uiColor: UIColor(rgbHex: preset.hex) ?? .systemBlue))
                                                .frame(width: 32, height: 32)
                                                .overlay {
                                                    if accentPreset == preset.id {
                                                        Image(systemName: "checkmark")
                                                            .font(.system(size: 12, weight: .bold))
                                                            .foregroundStyle(.white)
                                                    }
                                                }
                                        }
                                        .accessibilityLabel(preset.title)
                                        .accessibilityAddTraits(accentPreset == preset.id ? [.isSelected] : [])
                                    }
                                    ColorPicker("", selection: Binding(
                                        get: { Color(uiColor: UIColor(rgbHex: customAccentHex) ?? .systemBlue) },
                                        set: { chosen in
                                            customAccentHex = UIColor(chosen).rgbHex
                                            accentPreset = "custom"
                                        }), supportsOpacity: false)
                                        .labelsHidden()
                                        .accessibilityLabel("Choose custom accent color")
                                }
                                Text(accentPreset == "custom" ? "Custom color" : (AccentPalette.presets.first { $0.id == accentPreset }?.title ?? "Apple Blue"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Picker("Accidental labels", selection: $spellingValue) {
                                ForEach(NoteSpelling.allCases) { value in Text(value.title).tag(value.rawValue) }
                            }
                            .tint(accent)
                        }
                    }

                    settingsCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Credits", systemImage: "chevron.left.forwardslash.chevron.right")
                                .font(.headline)
                            Link(destination: URL(string: "https://github.com/vasquezgideon/MyPiano")!) {
                                HStack {
                                    Text("GitHub")
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                }
                            }
                            .tint(accent)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let url):
                do {
                    let added = try library.importFile(url, sampleRoot: importSampleRoot < 0 ? nil : importSampleRoot)
                    selectedSound = added.id
                    sound.select(added.id, library: library)
                } catch { importError = error.localizedDescription }
            case .failure(let error): importError = error.localizedDescription
            }
        }
        .alert("Import instrument", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) { Button("OK", role: .cancel) {} }
        message: { Text(importError ?? "") }
            .background(Color(uiColor: .secondarySystemBackground).ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showingSettings = false }.fontWeight(.semibold)
                }
            }
        }
    }

    private var myInstruments: some View {
        List {
            ForEach(library.instruments) { item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                    Text(item.type).font(.caption).foregroundStyle(.secondary)
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    let item = library.instruments[index]
                    if selectedSound == item.id { selectedSound = "built-in:0" }
                    library.delete(item)
                }
            }
        }
        .navigationTitle("My Instruments")
        .toolbar { EditButton() }
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(17)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 23, style: .continuous)
                    .strokeBorder(.white.opacity(0.24), lineWidth: 0.75)
            }
    }
}

private struct GlassCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.regularMaterial, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.36), lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.91 : 1)
            .animation(.easeOut(duration: 0.13), value: configuration.isPressed)
    }
}
