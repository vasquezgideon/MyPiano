# MyPiano · 1.4.6

A beautifully minimal, offline piano for iPhone, designed for landscape play. Full-width keys, glass controls, and the sounds you want—nothing between you and playing.

## Play

- 128-note range (C−1 through G9), scrollable across ten-plus octaves
- Key-width scale (5–15 white keys visible), multitouch chords, glide lock, and animated key presses
- Dynamic Touch: quieter at the hinge, louder at the bottom, with continuous expression as you move a finger. The full loudness range applies separately to both the long natural keys and the shorter accidentals
- Treble and bass starting ranges, note-name and accidental-spelling options
- True-black keys in dark mode and white keys in light mode; animated presses swap natural keys to your accent color and accented keys to black/white. Includes six accent-color presets and Apple's custom color picker

## Pitch behavior

Settings → Instruments → **Pitch behavior** offers two modes:

- **Classic (default):** uses the standard SoundFont sampler. Higher pitches play back faster and shorter, like ordinary sample playback; it is also the lowest-latency option.
- **Time-Stretch:** uses independent `AVAudioPlayerNode` + `AVAudioUnitTimePitch` voices, with a constant playback rate (`1.0`). Pitch changes without changing sample duration. Sustained notes loop their original sustain sections. The effect is polyphonic, so notes of a chord are pitched independently. Time-Stretch is more CPU-intensive and may sound processed at large intervals. Ten simultaneous time-stretch voices are supported; extra held notes use Classic playback.

Both bundled and generated SF2 banks use their note/velocity sample zones to pick the closest matching recording. Compatible imported uncompressed SF2 banks are also supported. An unsupported bank (including DLS), more than 10 simultaneous time-stretched notes, or a shift larger than ±24 semitones from the available sample uses Classic automatically. This only changes the instrument playback algorithm; the piano interface and recorded samples are unchanged.

## Instruments

- 21 bundled, offline instruments: grand/electric piano, harp, acoustic/electric/bass guitar, trumpet, flute, violin, cello, winds, mallets, synth, and more
- Import SF2 and DLS banks, simple one-sample SFZ patches, and WAV, AIFF, CAF, MP3, or M4A samples
- Instrument Studio supports microphone recordings, audio-file imports, and **video imports from Files or Photos** (only the video soundtrack is used):
  - **Analysis** uses one isolated sound to estimate a root pitch, refine tuning, balance volume, and stretch it across the keyboard. Root pitch is adjustable if detection is uncertain.
  - **Precision** accepts recordings of multiple notes and three playing strengths (pp, mf, ff), with optional repeated takes. The best take per pitch/strength is chosen by pitch and clipping measurements. Notes and velocity layers are mapped into a multisampled SoundFont with automatic gaps filled in.
- Automatic trimming of quiet lead-ins and silent tails, controlled volume normalization, and gentle compression for inconsistent strikes
- Optional phase-matched, crossfaded sustain loops built from the recording’s stable region; unlooped notes fade at their natural end and release smoothly when lifted
- **Video-to-instrument:** choose a MOV, MP4 or M4V in Files, or choose a video from Photos. The app extracts the audio locally and opens the same waveform editor. Only the first 30 seconds of a longer video are loaded for trimming; videos without sound display a clear error. Supported codecs depend on iOS. The original video is never modified.
- **Trim & Crop editor:** after recording or importing a sample (imports can be up to 30 seconds; select a segment up to 8 seconds), open a waveform with draggable start/end handles to select just the portion to keep, preview it, reset the range, and optionally soften the cropped edges. The source recording is unchanged until "Keep Selection" is tapped. Every Precision-mode take also has a Trim & Crop button for later adjustments.
- Recordings and created banks remain on the device

## Metronome

- Dedicated top-right glass play/stop toggle
- Tempo from **0.1 to 999.9 BPM**, adjustable via a logarithmic slider, fine stepper, or precise decimal entry
- Quarter, eighth, triplet, and sixteenth-note subdivisions
- A stronger downbeat every four quarter notes, generated on the audio sample clock

## Build an unsigned IPA with GitHub Actions

1. Upload the **contents** of this project folder to your GitHub repository, including the hidden `.github/workflows` folder.
2. Go to **Actions → Build unsigned iPhone IPA → Run workflow** (or push to `main` / `master`).
3. Download the workflow artifact **SimplyKeys-unsigned-IPA** and extract `SimplyKeys-unsigned.ipa`.
4. Sign the unsigned IPA with your preferred signing/sideloading service to install it on iPhone.

**Build environment:** GitHub-hosted macOS with Xcode. iOS 16.0 or later; landscape orientation only; no third-party packages. The IPA is not signed to an Apple developer account by the workflow. Automated tests also check SoundFont pitch zones, MP4 soundtrack extraction and rejection of silent videos on the macOS runner.

**Sample formats:** GarageBand and FL Studio proprietary projects are not direct instrument banks; export audio samples or compatible SF2/DLS files first. SFZ importing currently supports a simple neighboring-sample mapping, not complex multi-zone libraries. Single-sample instruments can lose realism at large pitch shifts, while Precision mode retains the timbre of its individually recorded samples.

## Project

[GitHub · MyPiano](https://github.com/vasquezgideon/MyPiano)

Source licensed under MIT; the original generated sound bank is CC0 1.0. No account, advertising, analytics, or network requirement.
