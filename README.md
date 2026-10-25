# Simply Keys

A beautifully minimal, offline piano for iPhone. Full-width keys, glass controls, and the sounds you want—nothing between you and playing.

## Play

- 128-note range (C−1 through G9), scrollable across ten-plus octaves
- Key-width scale (5–15 white keys visible), multitouch chords, glide lock, and animated key presses
- Dynamic Touch: quieter at the hinge, louder at the bottom, with continuous expression as you move a finger
- Treble and bass starting ranges, note-name and accidental-spelling options
- Light and dark appearance, six accent-color presets, and Apple's custom color picker

## Instruments

- 21 bundled, offline instruments: grand/electric piano, harp, acoustic/electric/bass guitar, trumpet, flute, violin, cello, winds, mallets, synth, and more
- Import SF2 and DLS banks, simple one-sample SFZ patches, and WAV, AIFF, CAF, MP3, or M4A samples
- Instrument Studio supports both microphone recordings and audio-file imports:
  - **Analysis** uses one isolated sound to estimate a root pitch, refine tuning, balance volume, and stretch it across the keyboard. Root pitch is adjustable if detection is uncertain.
  - **Precision** accepts recordings of multiple notes and three playing strengths (pp, mf, ff), with optional repeated takes. The best take per pitch/strength is chosen by pitch and clipping measurements. Notes and velocity layers are mapped into a multisampled SoundFont with automatic gaps filled in.
- Adjustable sample normalization, gentle fades, optional crossfaded sustain loops; recordings and created banks remain on the device

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

**Build environment:** GitHub-hosted macOS with Xcode. iOS 16.0 or later; no third-party packages. The IPA is not signed to an Apple developer account by the workflow.

**Sample formats:** GarageBand and FL Studio proprietary projects are not direct instrument banks; export audio samples or compatible SF2/DLS files first. SFZ importing currently supports a simple neighboring-sample mapping, not complex multi-zone libraries. Single-sample instruments can lose realism at large pitch shifts, while Precision mode retains the timbre of its individually recorded samples.

## Project

[GitHub · MyPiano](https://github.com/vasquezgideon/MyPiano)

Source licensed under MIT; the original generated sound bank is CC0 1.0. No account, advertising, analytics, or network requirement.
