import SwiftUI
import SwiftData
import GymCore
import GymData

/// Configurar el plan: sin plan, plantillas por días de la semana o un ciclo que se repite.
///
/// Todo se guarda al momento, como el resto de la app.
struct PlanEditorView: View {
    @Environment(\.modelContext) private var context
    @Query private var plans: [TrainingPlan]
    @Query private var templates: [WorkoutTemplate]

    @State private var isReordering = false
    @State private var errorMessage: String? = nil

    static let previewDays = 14

    private var calendar: Calendar { GymCalendar.make() }

    private var config: TrainingPlanConfig {
        plans.first?.config ?? .empty(calendar: calendar)
    }

    /// Plantillas por nombre, para elegirlas en los menús.
    private var sortedTemplates: [WorkoutTemplate] {
        templates.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private var templatesByID: [UUID: WorkoutTemplate] {
        Dictionary(templates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        let config = config
        List {
            Section {
                Picker("Modo", selection: Binding(get: { config.mode }, set: { mode in update { $0.mode = mode } })) {
                    Text("Sin plan").tag(PlanMode.none)
                    Text("Semana").tag(PlanMode.weekly)
                    Text("Ciclo").tag(PlanMode.cycle)
                }
                .pickerStyle(.segmented)
                .plainListRow()
            } footer: {
                Text(modeFooter(config.mode))
            }

            if templates.isEmpty && config.mode != .none {
                Section {
                    Text("Primero crea alguna plantilla en Entrenamientos para poder asignarla.")
                        .foregroundStyle(.secondary)
                }
            }

            switch config.mode {
            case .none:
                EmptyView()
            case .weekly:
                weeklySection(config.weekly)
            case .cycle:
                cycleSections(config.cycle)
            }

            if config.isActive && !isReordering {
                previewSection(config)
            }
        }
        .environment(\.editMode, .constant(isReordering ? .active : .inactive))
        .navigationTitle("Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if config.mode == .cycle {
                ToolbarItem(placement: .primaryAction) {
                    if isReordering {
                        Button("OK") { isReordering = false }
                            .bold()
                    } else {
                        Button("Ordenar") { isReordering = true }
                            .disabled(config.cycle.steps.count < 2)
                    }
                }
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

    // MARK: - Semana

    private func weeklySection(_ weekly: WeeklySchedule) -> some View {
        Section {
            ForEach(Weekday.allCases, id: \.self) { weekday in
                let assigned = weekly.templates(on: weekday)
                Menu {
                    ForEach(sortedTemplates) { template in
                        Button {
                            update { $0.weekly.toggle(template.id, on: weekday) }
                        } label: {
                            if assigned.contains(template.id) {
                                Label(template.displayName, systemImage: "checkmark")
                            } else {
                                Text(template.displayName)
                            }
                        }
                    }
                    Divider()
                    Button {
                        update { $0.weekly.setTemplates([], on: weekday) }
                    } label: {
                        if assigned.isEmpty {
                            Label("Descanso", systemImage: "checkmark")
                        } else {
                            Text("Descanso")
                        }
                    }
                } label: {
                    WeekdayRow(weekday: weekday, names: assigned.compactMap { templatesByID[$0]?.displayName })
                }
                .disabled(templates.isEmpty)
            }
        } header: {
            Text("Días de la semana")
        } footer: {
            Text("Toca un día para elegir su plantilla. Una misma plantilla puede ir en varios días; los días sin plantilla son de descanso.")
        }
    }

    // MARK: - Ciclo

    @ViewBuilder
    private func cycleSections(_ cycle: TrainingCycle) -> some View {
        let todayIndex = cycle.stepIndex(on: .now, calendar: calendar)
        Section {
            ForEach(Array(cycle.steps.enumerated()), id: \.element.id) { index, step in
                CycleStepRow(
                    position: index + 1,
                    name: PlanFormat.templateName(step.templateID, in: templatesByID),
                    isRest: step.isRest,
                    isMissing: step.templateID.map { templatesByID[$0] == nil } ?? false,
                    isToday: index == todayIndex
                )
            }
            .onMove { source, destination in
                update { $0.cycle.move(fromOffsets: source, toOffset: destination, today: .now, calendar: calendar) }
            }
            .onDelete { offsets in
                update { $0.cycle.remove(atOffsets: offsets, today: .now, calendar: calendar) }
            }

            if !isReordering {
                Menu {
                    ForEach(sortedTemplates) { template in
                        Button(template.displayName) {
                            update { $0.cycle.append(templateID: template.id, today: .now, calendar: calendar) }
                        }
                    }
                    Divider()
                    Button {
                        update { $0.cycle.append(templateID: nil, today: .now, calendar: calendar) }
                    } label: {
                        Label("Descanso", systemImage: "bed.double")
                    }
                } label: {
                    Label("Añadir al ciclo", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
            }
        } header: {
            Text("Ciclo")
        } footer: {
            Text(cycleFooter(cycle))
        }

        if !cycle.isEmpty && !isReordering {
            Section {
                Picker(
                    "Hoy toca",
                    selection: Binding(
                        get: { todayIndex ?? 0 },
                        set: { index in update { $0.cycle.setToday(index, today: .now, calendar: calendar) } }
                    )
                ) {
                    ForEach(Array(cycle.steps.enumerated()), id: \.element.id) { index, step in
                        Text("\(index + 1). \(PlanFormat.templateName(step.templateID, in: templatesByID))").tag(index)
                    }
                }
            } footer: {
                Text("Elige en qué punto del ciclo estás hoy; los días siguientes se cuentan desde ahí.")
            }
        }
    }

    // MARK: - Vista previa

    private func previewSection(_ config: TrainingPlanConfig) -> some View {
        Section("Próximos \(Self.previewDays) días") {
            ForEach(TrainingSchedule.days(from: .now, count: Self.previewDays, plan: config, calendar: calendar), id: \.date) { day in
                let names = day.templateIDs.compactMap { templatesByID[$0]?.displayName }
                HStack {
                    Text(calendar.isDateInToday(day.date) ? "Hoy" : PlanFormat.dayName(day.date))
                        .font(.subheadline.weight(calendar.isDateInToday(day.date) ? .bold : .regular))
                        .frame(width: 110, alignment: .leading)
                    Text(names.isEmpty ? "Descanso" : names.joined(separator: " + "))
                        .font(.subheadline.weight(names.isEmpty ? .regular : .semibold))
                        .foregroundStyle(names.isEmpty ? Color.secondary : Color.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Textos

    private func modeFooter(_ mode: PlanMode) -> String {
        switch mode {
        case .none:
            return "Sin plan, empiezas cada entrenamiento desde una plantilla o en blanco."
        case .weekly:
            return "Cada semana se repite igual: p. ej. lunes y jueves Pecho y tríceps."
        case .cycle:
            return "Una secuencia que se repite sin mirar la semana: p. ej. Pecho y tríceps, Espalda y bíceps, Pierna, Descanso."
        }
    }

    private func cycleFooter(_ cycle: TrainingCycle) -> String {
        if isReordering {
            return "Arrastra desde ≡ para cambiar el orden. Pulsa OK al terminar."
        }
        if cycle.isEmpty {
            return "Añade las plantillas y los descansos en orden."
        }
        return "Cada día avanza un paso, entrenes o no: si un día no entrenas, ese entreno se pierde y el ciclo sigue. Desliza para quitar un paso."
    }

    // MARK: - Guardar

    private func update(_ change: (inout TrainingPlanConfig) -> Void) {
        do {
            try TrainingPlan.update(in: context, change)
            try context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct WeekdayRow: View {
    let weekday: Weekday
    let names: [String]

    var body: some View {
        HStack {
            Text(weekday.name)
                .foregroundStyle(Color.primary)
            Spacer()
            Text(names.isEmpty ? "Descanso" : names.joined(separator: " + "))
                .foregroundStyle(names.isEmpty ? Color.secondary : Color.accentColor)
                .fontWeight(names.isEmpty ? .regular : .semibold)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct CycleStepRow: View {
    let position: Int
    let name: String
    let isRest: Bool
    let isMissing: Bool
    let isToday: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Text("\(position)")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(isToday ? Color.white : Color.secondary)
                .frame(width: 28, height: 28)
                .background(isToday ? Color.accentColor : Theme.fieldBackground, in: Circle())
            Text(name)
                .font(.headline.weight(isRest ? .regular : .semibold))
                .foregroundStyle(isRest || isMissing ? Color.secondary : Color.primary)
                .lineLimit(1)
            Spacer()
            if isToday {
                Text("Hoy")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
