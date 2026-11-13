import SwiftUI

/// Campo numérico pensado para el gimnasio: teclado numérico, acepta coma o punto
/// y solo escribe en el modelo valores válidos. Un valor no válido se muestra en rojo
/// y no sobrescribe el dato guardado. Vacío equivale a 0.
struct NumberField: View {
    private let placeholder: String
    @Binding private var value: Double
    private let allowsDecimals: Bool
    private let range: ClosedRange<Double>

    @State private var text = ""
    @FocusState private var isFocused: Bool

    init(_ placeholder: String, value: Binding<Double>, allowsDecimals: Bool = true, range: ClosedRange<Double>) {
        self.placeholder = placeholder
        self._value = value
        self.allowsDecimals = allowsDecimals
        self.range = range
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(allowsDecimals ? .decimalPad : .numberPad)
            .multilineTextAlignment(.center)
            .monospacedDigit()
            .focused($isFocused)
            .foregroundStyle(parse(text) == nil ? Color.red : Color.primary)
            .onAppear { text = format(value) }
            .onChange(of: text) { _, newText in
                if let parsed = parse(newText), parsed != value {
                    value = parsed
                }
            }
            .onChange(of: value) { _, newValue in
                // Cambios externos (p. ej. al rellenar una serie sugerida).
                if !isFocused { text = format(newValue) }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused { text = format(value) }
            }
    }

    private func parse(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if trimmed.isEmpty { return 0 }
        let parsed: Double?
        if allowsDecimals {
            parsed = Double(trimmed)
        } else {
            parsed = Int(trimmed).map(Double.init)
        }
        guard let parsed, parsed.isFinite, range.contains(parsed) else { return nil }
        return parsed
    }

    private func format(_ number: Double) -> String {
        guard number != 0 else { return "" }
        return number.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }
}
