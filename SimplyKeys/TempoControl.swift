import SwiftUI

/// Logarithmic slider for a musical 0.1–999.9 BPM range, plus an exact
/// decimal field and 0.1 BPM stepper so very slow tempos remain selectable.
struct TempoControl: View {
    @Binding var bpm: Double
    @FocusState private var textFocused: Bool
    @State private var input = "100.0"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tempo")
                Spacer()
                TextField("BPM", text: $input)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.body.monospacedDigit().weight(.semibold))
                    .frame(width: 90)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 11))
                    .focused($textFocused)
                    .accessibilityLabel("Tempo in beats per minute")
                Text("BPM").font(.caption).foregroundStyle(.secondary)
            }
            Slider(value: Binding(
                get: { min(1, max(0, (log10(max(0.1, bpm)) + 1) / 4)) },
                set: { position in
                    bpm = min(999.9, max(0.1, (pow(10, position * 4 - 1) * 10).rounded() / 10))
                }), in: 0...1)
            HStack {
                Text("0.1").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Text("999.9").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Stepper("Fine tune · 0.1 BPM", value: Binding(
                get: { bpm },
                set: { bpm = min(999.9, max(0.1, ($0 * 10).rounded() / 10)) }),
                    in: 0.1...999.9, step: 0.1)
                .font(.subheadline)
        }
        .onAppear { input = String(format: "%.1f", bpm) }
        .onChange(of: bpm) { value in
            if !textFocused { input = String(format: "%.1f", value) }
        }
        .onChange(of: input) { value in
            guard textFocused, let number = Double(value.replacingOccurrences(of: ",", with: ".")),
                  number.isFinite, (0.1...999.9).contains(number) else { return }
            bpm = (number * 10).rounded() / 10
        }
        .onChange(of: textFocused) { focused in
            if !focused { input = String(format: "%.1f", bpm) }
        }
    }
}
