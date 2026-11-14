import SwiftUI
import UIKit
import SwiftData
import GymCore
import GymData

/// Cierre del entrenamiento: horas, intensidad y peso para estimar calorías,
/// guardado en el historial y registro en Salud.
///
/// El entrenamiento se guarda siempre en local primero; si Salud falla se avisa
/// y se puede reintentar desde el detalle del historial.
struct FinishWorkoutView: View {
    @Bindable var workout: Workout
    let onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.healthService) private var healthService
    @Environment(\.openURL) private var openURL

    @State private var start: Date
    @State private var end = Date.now
    @State private var intensity: WorkoutIntensity
    @State private var bodyWeightKg: Double
    @State private var bodyWeightSource: String? = nil
    @State private var saveToHealth = true
    @State private var isSaving = false
    @State private var errorMessage: String? = nil
    @State private var healthWarning: String? = nil

    init(workout: Workout, onFinished: @escaping () -> Void) {
        _workout = Bindable(workout)
        self.onFinished = onFinished
        _start = State(initialValue: workout.startedAt)
        _intensity = State(initialValue: workout.intensity)
        _bodyWeightKg = State(initialValue: workout.bodyWeightKg ?? 0)
        _bodyWeightSource = State(initialValue: workout.bodyWeightKg == nil ? nil : "Último peso registrado en la app.")
    }

    var body: some View {
        NavigationStack {
            Form {
                summarySection

                Section("Horario") {
                    DatePicker("Inicio", selection: $start, in: ...end)
                    DatePicker("Fin", selection: $end, in: start...)
                    LabeledContent("Duración", value: WorkoutFormat.duration(end.timeIntervalSince(start)))
                }

                caloriesSection

                Section {
                    Toggle("Guardar en Salud", isOn: $saveToHealth)
                        .disabled(!healthService.isHealthDataAvailable)
                } footer: {
                    if healthService.isHealthDataAvailable {
                        Text(healthService is ShortcutsHealthService
                             ? "Se abrirá el atajo «\(HealthShortcuts.exportName)», que lo registra en Salud como entrenamiento de fuerza y vuelve aquí."
                             : "Se registra como entrenamiento de fuerza con las calorías activas estimadas.")
                    } else {
                        Text("Salud no está disponible en este dispositivo o versión de la app. El entrenamiento se guarda igualmente en el historial.")
                    }
                }
            }
            .navigationTitle("Terminar entrenamiento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Seguir entrenando") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Guardar") { Task { await save() } }
                            .bold()
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .task { await loadBodyWeightFromHealthIfNeeded() }
            .alert(
                "No se pudo guardar",
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .alert(
                "Guardado, pero no en Salud",
                isPresented: Binding(get: { healthWarning != nil }, set: { if !$0 { healthWarning = nil } })
            ) {
                Button("OK") { onFinished() }
            } message: {
                Text("\(healthWarning ?? "")\n\nEl entrenamiento está en tu historial. Puedes volver a intentarlo desde su detalle.")
            }
        }
    }

    // MARK: Secciones

    private var summarySection: some View {
        let totals = workout.totals
        return Section {
            TextField("Nombre (opcional), p. ej. Torso", text: $workout.title)
            LabeledContent("Ejercicios", value: "\(workout.exercises.count)")
            LabeledContent("Series efectivas", value: "\(totals.workingSets)")
            LabeledContent("Volumen", value: WorkoutFormat.volume(totals.volumeKg))
        } footer: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                if totals.isEmpty {
                    Text("No hay ninguna serie con repeticiones. Puedes guardarlo igualmente o volver y completarlo.")
                        .foregroundStyle(.orange)
                }
                let pending = (try? workout.pendingPlannedSets(in: context)) ?? 0
                if pending > 0 {
                    Text(pending == 1
                         ? "Queda 1 serie sin marcar con ✓: no se guardará. Si la hiciste, vuelve con «Seguir entrenando» y márcala."
                         : "Quedan \(pending) series sin marcar con ✓: no se guardarán. Si las hiciste, vuelve con «Seguir entrenando» y márcalas.")
                }
            }
        }
    }

    private var caloriesSection: some View {
        Section {
            Picker("Intensidad", selection: $intensity) {
                ForEach(WorkoutIntensity.allCases) { level in
                    Text(level.displayName).tag(level)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Peso corporal")
                Spacer()
                NumberField("—", value: $bodyWeightKg, range: 0...400)
                    .frame(width: 80)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemFill)))
                Text("kg").foregroundStyle(.secondary)
            }

            switch estimate {
            case .none:
                Label("Indica tu peso para estimar las calorías.", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            case .success(let result):
                LabeledContent("Calorías activas (estimadas)", value: WorkoutFormat.kcal(result.activeKcal))
            case .failure(let error):
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Calorías")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let bodyWeightSource {
                    Text(bodyWeightSource)
                }
                Text("Estimación por MET (\(intensity.met.formatted()) MET) × duración × peso, sin el gasto en reposo. Ligera: series de 8–15 reps con descansos; intensa: cargas altas y poco descanso. Un Apple Watch mide mejor.")
            }
        }
    }

    // MARK: Lógica

    private var bodyWeight: Double? { bodyWeightKg > 0 ? bodyWeightKg : nil }

    private var estimate: Result<CalorieEstimate, Error>? {
        guard let bodyWeight else { return nil }
        return Result {
            try CalorieCalculator.estimate(intensity: intensity, bodyWeightKg: bodyWeight, start: start, end: end)
        }
    }

    private func loadBodyWeightFromHealthIfNeeded() async {
        guard bodyWeight == nil, healthService.isHealthDataAvailable else { return }
        // Sin permiso o sin datos simplemente no se rellena: el usuario puede escribirlo.
        if let kg = try? await healthService.latestBodyMassKg(), kg > 0, bodyWeight == nil {
            bodyWeightKg = (kg * 10).rounded() / 10
            bodyWeightSource = "Peso más reciente de Salud."
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }

        if workout.isInProgress {
            workout.startedAt = start
            workout.intensity = intensity
            workout.bodyWeightKg = bodyWeight
            do {
                try workout.finish(at: end)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
        do {
            try context.save()
        } catch {
            errorMessage = "No se pudo guardar en el teléfono: \(error.localizedDescription)"
            return
        }

        if saveToHealth && healthService.isHealthDataAvailable {
            do {
                try await workout.syncToHealth(using: healthService, context: context)
            } catch HealthServiceError.pendingShortcut {
                // Modo Atajos: queda en cola y el atajo lo registra en Salud y vuelve a la app.
                openURL(HealthShortcuts.runURL(HealthShortcuts.exportName))
            } catch {
                healthWarning = error.localizedDescription
                return
            }
        }
        onFinished()
    }
}
