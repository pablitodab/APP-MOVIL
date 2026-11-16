import SwiftUI
import UIKit
import SwiftData
import GymCore
import GymData

/// Apuntar una sesión de cardio después de entrenar, o corregir una ya guardada.
/// Solo se guarda en la app: no se envía a Salud.
struct CardioSessionFormSheet: View {
    enum Mode {
        case create(activity: CardioActivity?)
        case edit(CardioSession)
    }

    let mode: Mode
    var onSaved: (CardioSession) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \CardioActivity.name) private var activities: [CardioActivity]
    @Query(sort: \CardioSession.performedAt, order: .reverse) private var sessions: [CardioSession]

    @State private var activityID: UUID? = nil
    @State private var date = Date.now
    @State private var hours: Double = 0
    @State private var minutes: Double = 0
    @State private var seconds: Double = 0
    @State private var distanceKm: Double = 0
    @State private var gait: CardioGait = .other
    @State private var speedKmh: Double = 0
    @State private var inclinePercent: Double = 0
    @State private var level: Double = 0
    @State private var rpe: Int? = nil
    @State private var averageHeartRate: Double = 0
    @State private var maxHeartRate: Double = 0
    @State private var notes = ""
    @State private var loaded = false
    @State private var creatingActivity = false
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                activitySection
                if activity != nil {
                    sessionSection
                    if equipment.tracksMachineSpeed || equipment.tracksIncline || equipment.tracksLevel {
                        machineSection
                    }
                    effortSection
                    Section("Notas") {
                        TextField("Cómo te has sentido, programa de la máquina…", text: $notes, axis: .vertical)
                            .lineLimit(2...6)
                    }
                }
            }
            .navigationTitle(isEditing ? "Editar sesión" : "Registrar cardio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .bold()
                        .disabled(activity == nil || durationSeconds <= 0)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") { hideKeyboard() }
                }
            }
            .sheet(isPresented: $creatingActivity) {
                CardioActivityFormSheet(mode: .create) { created in
                    activityID = created.id
                    applyDefaults(for: created)
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
            .onAppear(perform: load)
        }
    }

    // MARK: Secciones

    @ViewBuilder
    private var activitySection: some View {
        Section {
            if activities.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Primero crea el tipo de cardio que haces: cinta, bici, elíptica, remo…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        creatingActivity = true
                    } label: {
                        Label("Crear tipo de cardio", systemImage: "plus")
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                }
                .padding(.vertical, Theme.Spacing.xs)
            } else {
                Picker("Tipo", selection: activityBinding) {
                    ForEach(activities) { activity in
                        Label(activity.name, systemImage: activity.equipment.systemImage)
                            .tag(Optional(activity.id))
                    }
                }
                .pickerStyle(.navigationLink)
                Button {
                    creatingActivity = true
                } label: {
                    Label("Nuevo tipo", systemImage: "plus")
                }
                if !gaitOptions.isEmpty {
                    Picker("Modalidad", selection: $gait) {
                        ForEach(gaitOptions) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        } header: {
            Text("Tipo")
        } footer: {
            if !gaitOptions.isEmpty {
                Text("El ritmo caminando y el ritmo corriendo se guardan y comparan por separado.")
            }
        }
    }

    private var sessionSection: some View {
        Section {
            DatePicker("Inicio", selection: $date, in: ...Date.now.addingTimeInterval(3600))
            LabeledContent("Duración") {
                HStack(spacing: Theme.Spacing.xs) {
                    unitField("0", value: $hours, unit: "h", range: 0...23)
                    unitField("0", value: $minutes, unit: "min", range: 0...59)
                    unitField("0", value: $seconds, unit: "s", range: 0...59)
                }
            }
            LabeledContent("Distancia") {
                unitField("—", value: $distanceKm, unit: "km", range: 0...500, decimals: true, width: 72)
            }
            if let summary = computedSummary {
                LabeledContent("Calculado") {
                    Text(summary)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.accentColor)
                }
            }
        } header: {
            Text("Sesión")
        } footer: {
            Text("La distancia es opcional; con ella la app calcula el ritmo y la velocidad media.")
        }
    }

    private var machineSection: some View {
        Section {
            if equipment.tracksMachineSpeed {
                LabeledContent("Velocidad") {
                    unitField("—", value: $speedKmh, unit: "km/h", range: 0...60, decimals: true, width: 72)
                }
            }
            if equipment.tracksIncline {
                LabeledContent("Inclinación") {
                    unitField("—", value: $inclinePercent, unit: "%", range: 0...40, decimals: true, width: 72)
                }
            }
            if equipment.tracksLevel {
                LabeledContent("Nivel") {
                    unitField("—", value: $level, unit: "", range: 0...100, decimals: true, width: 72)
                }
            }
        } header: {
            Text("Máquina (opcional)")
        } footer: {
            Text("Lo que pusiste en la máquina. Si cambiaste durante la sesión, apunta el más habitual.")
        }
    }

    private var effortSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack {
                    Text("Intensidad (RPE)")
                    Spacer()
                    Text(rpe.map { "\($0) · \(CardioFormat.rpeLabel($0))" } ?? "Sin indicar")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(rpe == nil ? Color.secondary : Color.accentColor)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                    ForEach(1...10, id: \.self) { value in
                        Button {
                            rpe = rpe == value ? nil : value
                        } label: {
                            Text("\(value)")
                                .font(.headline)
                                .monospacedDigit()
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .foregroundStyle(rpe == value ? Color.white : Color.primary)
                                .background(
                                    rpe == value ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Theme.fieldBackground),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("RPE \(value), \(CardioFormat.rpeLabel(value))")
                        .accessibilityAddTraits(rpe == value ? .isSelected : [])
                    }
                }
                .sensoryFeedback(.selection, trigger: rpe)
            }
            .padding(.vertical, Theme.Spacing.xs)
            LabeledContent("FC media") {
                unitField("—", value: $averageHeartRate, unit: "lpm", range: 0...250, width: 64)
            }
            LabeledContent("FC máxima") {
                unitField("—", value: $maxHeartRate, unit: "lpm", range: 0...250, width: 64)
            }
        } header: {
            Text("Esfuerzo")
        } footer: {
            Text("RPE: 1 muy suave, 10 máximo esfuerzo. La frecuencia cardiaca, si la ves en el reloj o la máquina.")
        }
    }

    private func unitField(
        _ placeholder: String,
        value: Binding<Double>,
        unit: String,
        range: ClosedRange<Double>,
        decimals: Bool = false,
        width: CGFloat = 44
    ) -> some View {
        HStack(spacing: 4) {
            NumberField(placeholder, value: value, allowsDecimals: decimals, range: range)
                .frame(width: width)
                .padding(.vertical, 6)
                .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            if !unit.isEmpty {
                Text(unit)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Estado

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var activity: CardioActivity? {
        activities.first { $0.id == activityID }
    }

    private var equipment: CardioEquipment { activity?.equipment ?? .other }

    private var gaitOptions: [CardioGait] {
        guard activity != nil, equipment.supportsGait else { return [] }
        return equipment == .other ? CardioGait.allCases : CardioGait.paced
    }

    private var activityBinding: Binding<UUID?> {
        Binding(
            get: { activityID },
            set: { newID in
                activityID = newID
                if let selected = activities.first(where: { $0.id == newID }) {
                    applyDefaults(for: selected)
                }
            }
        )
    }

    private var durationSeconds: Double { hours * 3600 + minutes * 60 + seconds }

    private var input: CardioSessionInput {
        CardioSessionInput(
            date: date,
            durationSeconds: durationSeconds,
            distanceKm: distanceKm > 0 ? distanceKm : nil,
            gait: gaitOptions.contains(gait) ? gait : .other,
            inclinePercent: inclinePercent > 0 ? inclinePercent : nil,
            speedKmh: speedKmh > 0 ? speedKmh : nil,
            level: level > 0 ? level : nil,
            rpe: rpe,
            averageHeartRate: averageHeartRate > 0 ? Int(averageHeartRate) : nil,
            maxHeartRate: maxHeartRate > 0 ? Int(maxHeartRate) : nil,
            notes: notes
        )
    }

    /// "5:32 /km · 10,8 km/h" mientras se escribe.
    private var computedSummary: String? {
        let current = input
        let sample = CardioSample(date: current.date, durationSeconds: current.durationSeconds, distanceKm: current.distanceKm, gait: current.gait)
        let parts = [sample.paceSecondsPerKm.map(CardioFormat.pace), sample.averageSpeedKmh.map(CardioFormat.speed)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Modalidad de la última sesión de ese tipo (en la cinta, casi siempre la misma).
    private func applyDefaults(for selected: CardioActivity) {
        let options: [CardioGait] = selected.equipment.supportsGait
            ? (selected.equipment == .other ? CardioGait.allCases : CardioGait.paced)
            : []
        guard !options.isEmpty else { gait = .other; return }
        let last = sessions.first { $0.activity?.id == selected.id }?.gait
        gait = last.flatMap { options.contains($0) ? $0 : nil } ?? options[0]
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch mode {
        case .create(let initial):
            let selected = initial ?? sessions.first?.activity ?? (activities.count == 1 ? activities.first : nil)
            activityID = selected?.id
            if let selected { applyDefaults(for: selected) }
        case .edit(let session):
            let current = session.input
            activityID = session.activity?.id
            date = current.date
            let total = Int(current.durationSeconds.rounded())
            hours = Double(total / 3600)
            minutes = Double((total % 3600) / 60)
            seconds = Double(total % 60)
            distanceKm = current.distanceKm ?? 0
            gait = current.gait
            speedKmh = current.speedKmh ?? 0
            inclinePercent = current.inclinePercent ?? 0
            level = current.level ?? 0
            rpe = current.rpe
            averageHeartRate = Double(current.averageHeartRate ?? 0)
            maxHeartRate = Double(current.maxHeartRate ?? 0)
            notes = current.notes
        }
    }

    private func save() {
        hideKeyboard()
        do {
            let saved: CardioSession
            switch mode {
            case .create:
                saved = try CardioSession.log(input, activity: activity, in: context)
            case .edit(let session):
                guard let activity else { throw CardioValidationError.missingActivity }
                try session.apply(input, activity: activity)
                saved = session
            }
            try context.save()
            onSaved(saved)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

#Preview("Nueva") {
    CardioSessionFormSheet(mode: .create(activity: nil))
        .modelContainer(PreviewData.container)
}
