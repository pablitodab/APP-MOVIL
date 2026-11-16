import SwiftUI
import SwiftData
import Charts
import GymCore
import GymData

/// Historial del VO2max: lecturas apuntadas a mano o importadas de Salud con el atajo
/// «Salud a GymTracker» (dato «VO2max» en «Guardar datos de Salud en GymTracker»).
struct VO2MaxHistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \VO2MaxReading.measuredAt, order: .reverse) private var readings: [VO2MaxReading]
    @State private var adding = false

    var body: some View {
        List {
            Section {
                Button {
                    adding = true
                } label: {
                    Label("Añadir lectura", systemImage: "plus.circle.fill")
                        .font(.headline)
                }
            } footer: {
                Text("Llega solo si añades el dato «VO2max» al atajo «Salud a GymTracker»; si no, apúntalo a mano. El Apple Watch lo estima en caminatas, carreras o senderismo al aire libre. Más alto indica mejor forma aeróbica.")
            }

            if readings.isEmpty {
                ContentUnavailableView(
                    "Sin lecturas",
                    systemImage: "lungs",
                    description: Text("Añade tu primer VO2max para empezar a ver su evolución.")
                )
            } else {
                if readings.count >= 2 {
                    Section("Evolución") {
                        chart
                            .frame(height: 180)
                            .padding(.vertical, 8)
                        let first = readings[readings.count - 1]
                        ComparisonRow(
                            title: "Desde \(WorkoutFormat.day(first.measuredAt))",
                            metric: MetricComparison(baseline: first.value, current: readings[0].value),
                            kind: .vo2Max,
                            higherIsBetter: true
                        )
                    }
                }
                Section("Lecturas") {
                    ForEach(readings) { reading in
                        HStack {
                            Text(StatsFormat.capitalized(WorkoutFormat.day(reading.measuredAt)))
                            if reading.source == .health {
                                Image(systemName: "heart.fill")
                                    .font(.caption)
                                    .foregroundStyle(Theme.health)
                                    .accessibilityLabel("De Salud")
                            }
                            Spacer()
                            Text("\(CardioFormat.vo2Max(reading.value)) ml/kg/min")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("VO2max")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) {
            VO2MaxFormSheet(lastValue: readings.first?.value)
                .presentationDetents([.medium])
        }
    }

    private var chart: some View {
        Chart(readings) { reading in
            LineMark(x: .value("Fecha", reading.measuredAt, unit: .day), y: .value("VO2max", reading.value))
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Theme.cardio.gradient)
            PointMark(x: .value("Fecha", reading.measuredAt, unit: .day), y: .value("VO2max", reading.value))
                .symbolSize(50)
                .foregroundStyle(Theme.cardio)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxisLabel("ml/kg/min")
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(readings[index])
        }
        context.saveNow()
    }
}

/// Formulario corto para apuntar una lectura.
private struct VO2MaxFormSheet: View {
    let lastValue: Double?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var value: Double = 0
    @State private var date = Date.now
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("VO2max") {
                        HStack(spacing: 4) {
                            NumberField(lastValue.map(CardioFormat.vo2Max) ?? "45", value: $value, range: 0...VO2Max.range.upperBound)
                                .frame(width: 72)
                                .padding(.vertical, 6)
                                .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            Text("ml/kg/min")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    DatePicker("Fecha", selection: $date, in: ...Date.now, displayedComponents: .date)
                } footer: {
                    if let lastValue {
                        Text("Última lectura: \(CardioFormat.vo2Max(lastValue)).")
                    }
                }
            }
            .navigationTitle("Nueva lectura")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .bold()
                        .disabled(value <= 0)
                }
            }
            .alert(
                "No se pudo guardar",
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        do {
            try VO2MaxReading.log(value: value, at: date, in: context)
            try context.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
