import SwiftUI
import SwiftData
import GymCore
import GymData

/// Apartado de la pestaña Entrenamientos con lo que toca hoy según el plan y los próximos
/// días, con el botón para empezar.
///
/// Sin plan, invita a crearlo (solo si ya hay plantillas que asignar); si no, no ocupa nada.
struct PlanSection: View {
    /// Entrenamientos terminados, del más reciente al más antiguo (para marcar lo hecho hoy).
    let finished: [Workout]
    let canStart: Bool
    let onStart: (WorkoutTemplate) -> Void
    let onEdit: () -> Void

    @Query private var plans: [TrainingPlan]
    @Query private var templates: [WorkoutTemplate]
    @Query private var uses: [WorkoutTemplateUse]
    @Environment(\.scenePhase) private var scenePhase
    /// Se renueva al cambiar de día o al volver a la app, para no enseñar el plan de ayer.
    @State private var now = Date.now

    static let upcomingDays = 6

    var body: some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in now = .now }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { now = .now }
            }
    }

    @ViewBuilder
    private var content: some View {
        let calendar = GymCalendar.make()
        let config = plans.first?.config
        let templatesByID = Dictionary(templates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if let config, let today = TrainingSchedule.day(now, plan: config, calendar: calendar) {
            let upcoming = TrainingSchedule.days(
                from: calendar.date(byAdding: .day, value: 1, to: today.date) ?? today.date,
                count: Self.upcomingDays,
                plan: config,
                calendar: calendar
            )
            Section {
                card(today: today, upcoming: upcoming, config: config, templatesByID: templatesByID, calendar: calendar)
                    .plainListRow()
            }
        } else if !templates.isEmpty {
            Section {
                PlanInvitation(onCreate: onEdit)
                    .plainListRow()
            }
        }
    }

    private func card(
        today: PlannedDay,
        upcoming: [PlannedDay],
        config: TrainingPlanConfig,
        templatesByID: [UUID: WorkoutTemplate],
        calendar: Calendar
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            header(today: today, config: config)
            TodayPlanContent(
                templates: today.templateIDs.compactMap { templatesByID[$0] },
                doneToday: doneToday(calendar: calendar),
                nextWorkout: upcoming.first { !$0.templateIDs.compactMap { templatesByID[$0] }.isEmpty },
                templatesByID: templatesByID,
                canStart: canStart,
                onStart: onStart
            )
            Divider()
            UpcomingDaysStrip(days: upcoming, templatesByID: templatesByID, calendar: calendar)
        }
        .gymCard()
    }

    private func header(today: PlannedDay, config: TrainingPlanConfig) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("HOY · \(PlanFormat.dayName(today.date).uppercased())")
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                if let index = today.cycleStepIndex {
                    Text("Día \(index + 1) de \(config.cycle.steps.count) del ciclo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Editar plan", action: onEdit)
                .font(.subheadline.weight(.semibold))
                // En una fila de List, un botón con el estilo por defecto se activa al
                // tocar cualquier parte de la fila (también "Empezar").
                .buttonStyle(.borderless)
        }
    }

    /// Plantillas de los entrenamientos terminados hoy.
    private func doneToday(calendar: Calendar) -> Set<UUID> {
        let start = calendar.startOfDay(for: now)
        let ids = Set(finished.prefix { $0.startedAt >= start }.map(\.id))
        guard !ids.isEmpty else { return [] }
        return Set(uses.filter { ids.contains($0.workoutID) }.map(\.templateID))
    }
}

/// Plantillas de hoy con su botón de empezar (o "Hecho"), o el día de descanso.
private struct TodayPlanContent: View {
    let templates: [WorkoutTemplate]
    let doneToday: Set<UUID>
    let nextWorkout: PlannedDay?
    let templatesByID: [UUID: WorkoutTemplate]
    let canStart: Bool
    let onStart: (WorkoutTemplate) -> Void

    var body: some View {
        if templates.isEmpty {
            HStack(spacing: Theme.Spacing.m) {
                IconBadge(systemImage: "bed.double.fill", tint: .indigo)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Descanso")
                        .font(.title3.weight(.bold))
                    if let nextText {
                        Text(nextText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            VStack(spacing: Theme.Spacing.m) {
                ForEach(templates) { template in
                    TodayTemplateRow(
                        template: template,
                        isDone: doneToday.contains(template.id),
                        canStart: canStart,
                        onStart: { onStart(template) }
                    )
                }
            }
        }
    }

    /// "Siguiente: Pecho y tríceps, mañana".
    private var nextText: String? {
        guard let nextWorkout else { return nil }
        let names = nextWorkout.templateIDs.compactMap { templatesByID[$0]?.displayName }
        guard !names.isEmpty else { return nil }
        return "Siguiente: \(names.joined(separator: " + ")), \(PlanFormat.relativeDay(nextWorkout.date))"
    }
}

private struct TodayTemplateRow: View {
    let template: WorkoutTemplate
    let isDone: Bool
    let canStart: Bool
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.m) {
                IconBadge(systemImage: isDone ? "checkmark" : "dumbbell.fill", tint: isDone ? .green : .accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.displayName)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                    Text(isDone ? "Hecho hoy" : template.countsSummary)
                        .font(.subheadline)
                        .foregroundStyle(isDone ? Color.green : Color.secondary)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            if !isDone {
                Button(action: onStart) {
                    Label("Empezar \(template.displayName)", systemImage: "play.fill")
                        .lineLimit(1)
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(!canStart || template.exercises.isEmpty)
                .accessibilityHint("Empieza el entrenamiento de hoy con las series de tu última sesión de esta plantilla")
                if template.exercises.isEmpty {
                    Text("La plantilla no tiene ejercicios todavía.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Fila horizontal con los próximos días del plan.
private struct UpcomingDaysStrip: View {
    let days: [PlannedDay]
    let templatesByID: [UUID: WorkoutTemplate]
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("PRÓXIMOS DÍAS")
                .font(.caption.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(days, id: \.date) { day in
                        let names = day.templateIDs.compactMap { templatesByID[$0]?.displayName }
                        UpcomingDayTile(date: day.date, names: names, calendar: calendar)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }
}

private struct UpcomingDayTile: View {
    let date: Date
    let names: [String]
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(Weekday(of: date, calendar: calendar).shortName) \(calendar.component(.day, from: date))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(names.isEmpty ? "Descanso" : names.joined(separator: " + "))
                .font(.subheadline.weight(names.isEmpty ? .regular : .semibold))
                .foregroundStyle(names.isEmpty ? Color.secondary : Color.primary)
                .lineLimit(2, reservesSpace: true)
        }
        .frame(width: 96, alignment: .leading)
        .padding(Theme.Spacing.s)
        .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Invita a planificar cuando aún no hay plan.
private struct PlanInvitation: View {
    let onCreate: () -> Void

    var body: some View {
        Button(action: onCreate) {
            HStack(spacing: Theme.Spacing.m) {
                IconBadge(systemImage: "calendar.badge.plus")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Planifica tus entrenos")
                        .font(.headline)
                    Text("Asigna plantillas a días de la semana o crea un ciclo, y aquí verás qué toca hoy.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .gymCard()
    }
}

/// Textos del plan.
enum PlanFormat {
    /// "hoy", "mañana" o "el viernes 21".
    static func relativeDay(_ date: Date, now: Date = .now) -> String {
        let calendar = GymCalendar.make()
        if calendar.isDate(date, inSameDayAs: now) { return "hoy" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "mañana"
        }
        return "el \(Weekday(of: date, calendar: calendar).name.lowercased()) \(calendar.component(.day, from: date))"
    }

    /// "Jueves 20".
    static func dayName(_ date: Date) -> String {
        let calendar = GymCalendar.make()
        return "\(Weekday(of: date, calendar: calendar).name) \(calendar.component(.day, from: date))"
    }

    /// Nombre de una plantilla del plan; si ya no existe, lo dice.
    static func templateName(_ id: UUID?, in templatesByID: [UUID: WorkoutTemplate]) -> String {
        guard let id else { return "Descanso" }
        return templatesByID[id]?.displayName ?? "Plantilla eliminada"
    }
}
