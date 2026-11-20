import SwiftUI
import SwiftData
import OSLog
import GymCore
import GymData

private let logger = Logger(subsystem: "com.pablitodab.gymtracker", category: "plan")

/// En el editor de una plantilla: en qué días de la semana toca (uno o varios).
///
/// Si el plan es un ciclo, solo dice en qué pasos está; el ciclo se edita en el plan.
struct TemplatePlanDaysSection: View {
    let template: WorkoutTemplate

    @Environment(\.modelContext) private var context
    @Query private var plans: [TrainingPlan]
    @State private var errorMessage: String? = nil

    var body: some View {
        let config = plans.first?.config ?? .empty(calendar: GymCalendar.make())
        Section {
            if config.mode == .cycle {
                Text(cycleText(config.cycle))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                WeekdayChips(selected: config.weekly.weekdays(of: template.id)) { weekday in
                    toggle(weekday)
                }
                .plainListRow(vertical: Theme.Spacing.xs)
            }
        } header: {
            Text("Días de entreno")
        } footer: {
            if config.mode != .cycle {
                Text("Elige uno o varios días. La pestaña Entrenamientos te dirá qué toca hoy.")
            }
        }
        .alert(
            "No se pudo guardar el plan",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func cycleText(_ cycle: TrainingCycle) -> String {
        let positions = cycle.steps.enumerated().filter { $0.element.templateID == template.id }.map { "\($0.offset + 1)" }
        guard !positions.isEmpty else {
            return "Usas un ciclo y esta plantilla no está en él. Añádela desde Plan."
        }
        let list = ListFormatter.localizedString(byJoining: positions)
        return "Usas un ciclo de \(cycle.steps.count) días: esta plantilla es el día \(list)."
    }

    private func toggle(_ weekday: Weekday) {
        do {
            try TrainingPlan.update(in: context) { config in
                // Elegir un día sin plan activa el plan por días de la semana.
                if config.mode == .none { config.mode = .weekly }
                config.weekly.toggle(template.id, on: weekday)
            }
            try context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Siete botones redondos, de lunes a domingo, para marcar días.
private struct WeekdayChips: View {
    let selected: Set<Weekday>
    let onToggle: (Weekday) -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(Weekday.allCases, id: \.self) { weekday in
                let isOn = selected.contains(weekday)
                Button {
                    onToggle(weekday)
                } label: {
                    Text(weekday.initial)
                        .font(.headline)
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(isOn ? Color.accentColor : Theme.cardBackground, in: Circle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(weekday.name)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }
}

extension WorkoutTemplate {
    /// Quita la plantilla del plan antes de borrarla. Si falla, el plan conserva un id que
    /// ya no existe; la app lo ignora al mostrar el plan, así que solo se registra.
    func removeFromPlan(in context: ModelContext) {
        do {
            try TrainingPlan.removeTemplate(id, in: context)
        } catch {
            logger.error("No se pudo quitar la plantilla del plan: \(error.localizedDescription, privacy: .public)")
        }
    }
}
