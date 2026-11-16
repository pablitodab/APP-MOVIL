import SwiftUI
import SwiftData
import GymCore
import GymData

/// Secciones del historial de entrenamientos terminados, agrupadas por mes.
struct WorkoutHistorySections: View {
    let searchText: String
    let onDelete: (Workout) -> Void

    @Query(filter: #Predicate<Workout> { $0.endedAt != nil }, sort: \Workout.startedAt, order: .reverse)
    private var workouts: [Workout]

    init(searchText: String, onDelete: @escaping (Workout) -> Void) {
        self.searchText = searchText
        self.onDelete = onDelete
    }

    var body: some View {
        let items = filtered
        if workouts.isEmpty {
            Section {
                ContentUnavailableView(
                    "Sin entrenamientos",
                    systemImage: "dumbbell",
                    description: Text("Cuando termines tu primer entrenamiento aparecerá aquí.")
                )
            }
        } else if items.isEmpty {
            Section {
                ContentUnavailableView.search(text: searchText)
            }
        } else {
            if items.count >= 2 {
                Section {
                    NavigationLink(value: WorkoutRoute.comparison(baseline: items[1], current: items[0])) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Comparar entrenamientos")
                                    .font(.headline)
                                Text("Último frente al anterior, o elige dos")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            IconBadge(systemImage: "arrow.left.arrow.right")
                        }
                    }
                }
            }
            ForEach(Self.groupByMonth(items), id: \.month) { group in
                Section(group.title) {
                    ForEach(group.workouts) { workout in
                        NavigationLink(value: WorkoutRoute.workout(workout)) {
                            WorkoutHistoryRow(workout: workout)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                onDelete(workout)
                            } label: {
                                Label("Eliminar", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private var filtered: [Workout] {
        let key = ExerciseName.normalizedKey(searchText)
        guard !key.isEmpty else { return workouts }
        return workouts.filter { workout in
            ExerciseName.normalizedKey(workout.title).contains(key)
                || workout.exercises.contains { $0.definition?.normalizedName.contains(key) ?? false }
        }
    }

    private struct MonthGroup {
        let month: Date
        let title: String
        let workouts: [Workout]
    }

    private static func groupByMonth(_ workouts: [Workout]) -> [MonthGroup] {
        let calendar = GymCalendar.make()
        var groups: [MonthGroup] = []
        for workout in workouts {
            let month = calendar.dateInterval(of: .month, for: workout.startedAt)?.start ?? workout.startedAt
            if let last = groups.last, last.month == month {
                groups[groups.count - 1] = MonthGroup(month: month, title: last.title, workouts: last.workouts + [workout])
            } else {
                let title = StatsFormat.capitalized(month.formatted(.dateTime.month(.wide).year()))
                groups.append(MonthGroup(month: month, title: title, workouts: [workout]))
            }
        }
        return groups
    }
}

struct WorkoutHistoryRow: View {
    let workout: Workout

    var body: some View {
        let totals = workout.totals
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            DateTile(date: workout.startedAt)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(workout.displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                    if workout.isSyncedToHealth {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(Theme.health)
                            .font(.caption)
                            .accessibilityLabel("Registrado en Salud")
                    }
                    Spacer(minLength: 0)
                    Text(WorkoutFormat.time(workout.startedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !workout.exercises.isEmpty {
                    Text(workout.orderedExercises.map(\.name).joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                ViewThatFits(in: .horizontal) {
                    chips(totals: totals, includeVolume: true)
                    chips(totals: totals, includeVolume: false)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private func chips(totals: ExerciseSessionStats, includeVolume: Bool) -> some View {
        HStack(spacing: 6) {
            if let duration = workout.duration {
                StatChip(text: WorkoutFormat.duration(duration), systemImage: "clock")
            }
            StatChip(text: "\(totals.workingSets) series", systemImage: "list.bullet")
            if includeVolume, totals.volumeKg > 0 {
                StatChip(text: WorkoutFormat.volume(totals.volumeKg), systemImage: "scalemass")
            }
        }
    }
}

/// Día de la semana y número del día, para encabezar filas del historial.
struct DateTile: View {
    let date: Date

    var body: some View {
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.accentColor)
            Text(date.formatted(.dateTime.day()))
                .font(.title2.weight(.bold))
                .monospacedDigit()
        }
        .frame(width: 48, height: 52)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Secciones del historial por ejercicio: botón para crear ejercicios, filtro por músculo,
/// los ejercicios hechos (por último uso) y los creados que aún no se han hecho.
struct ExerciseHistorySections: View {
    let searchText: String
    let onCreate: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \ExerciseDefinition.name) private var definitions: [ExerciseDefinition]
    @Query private var muscleRows: [ExerciseMuscles]
    @State private var filter: MuscleFilter = .all

    init(searchText: String, onCreate: @escaping () -> Void) {
        self.searchText = searchText
        self.onCreate = onCreate
    }

    enum MuscleFilter: Hashable {
        case all
        case muscle(MuscleGroup)
        case unassigned
    }

    private struct Item: Identifiable {
        let definition: ExerciseDefinition
        let muscles: [MuscleGroup]
        let lastEntry: WorkoutExercise?
        let sessions: Int
        var id: UUID { definition.id }
    }

    var body: some View {
        let musclesByID = ExerciseMuscles.byDefinition(muscleRows)
        let all = allItems(musclesByID)
        let options = filterOptions(all)
        // Si el músculo elegido ya no está en la lista (se editó o se buscó otra cosa), todos.
        let active = options.contains(filter) ? filter : .all
        let items = filtered(all, by: active)
        let used = items.filter { $0.lastEntry != nil }
        let unused = items.filter { $0.lastEntry == nil }

        Section {
            Button(action: onCreate) {
                Label("Crear ejercicio", systemImage: "plus")
            }
            .buttonStyle(SecondaryActionButtonStyle())
            .plainListRow()
        }

        if options.count > 1 {
            Section {
                filterBar(options, active: active)
                    .plainListRow()
            }
        }

        if items.isEmpty {
            Section {
                if !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else if active != .all {
                    ContentUnavailableView(
                        "Ningún ejercicio",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("No hay ejercicios con ese músculo.")
                    )
                } else {
                    ContentUnavailableView(
                        "Sin ejercicios",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Crea tus ejercicios o añádelos en un entrenamiento. Aquí verás la progresión de cada uno.")
                    )
                }
            }
        } else {
            if !used.isEmpty {
                Section("Ordenados por último uso") {
                    ForEach(used) { item in
                        row(item)
                    }
                }
            }
            if !unused.isEmpty {
                Section {
                    ForEach(unused) { item in
                        row(item)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if item.definition.isUnused {
                                    Button(role: .destructive) {
                                        delete(item.definition)
                                    } label: {
                                        Label("Eliminar", systemImage: "trash")
                                    }
                                }
                            }
                    }
                } header: {
                    Text("Sin sesiones todavía")
                } footer: {
                    Text("Aparecerán arriba cuando termines un entrenamiento con ellos. Desliza para eliminar uno que no vayas a usar.")
                }
            }
        }
    }

    private func row(_ item: Item) -> some View {
        NavigationLink(value: WorkoutRoute.exercise(item.definition)) {
            HStack(spacing: Theme.Spacing.m) {
                IconBadge(systemImage: "dumbbell.fill", size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.definition.name)
                        .font(.headline)
                    MuscleSummaryText(muscles: item.muscles)
                    Text(subtitle(for: item))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func filterBar(_ options: [MuscleFilter], active: MuscleFilter) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(options, id: \.self) { option in
                    MuscleChip(title: title(for: option), isSelected: active == option) {
                        filter = option
                    }
                    .fixedSize()
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
        }
        .scrollClipDisabled()
        .sensoryFeedback(.selection, trigger: filter)
    }

    /// "Todos", los músculos que tiene algún ejercicio y "Sin músculo" si a alguno le falta.
    private func filterOptions(_ all: [Item]) -> [MuscleFilter] {
        let used = MuscleGroup.canonical(all.flatMap(\.muscles))
        var options: [MuscleFilter] = [.all] + used.map { .muscle($0) }
        if !used.isEmpty, all.contains(where: { $0.muscles.isEmpty }) {
            options.append(.unassigned)
        }
        return options
    }

    private func title(for option: MuscleFilter) -> String {
        switch option {
        case .all: return "Todos"
        case .muscle(let muscle): return muscle.displayName
        case .unassigned: return "Sin músculo"
        }
    }

    private func allItems(_ musclesByID: [UUID: [MuscleGroup]]) -> [Item] {
        let key = ExerciseName.normalizedKey(searchText)
        return definitions
            .filter { key.isEmpty || $0.normalizedName.contains(key) }
            .map { definition in
                let entries = definition.completedEntries
                return Item(
                    definition: definition,
                    muscles: musclesByID[definition.id] ?? [],
                    lastEntry: entries.first,
                    sessions: entries.count
                )
            }
            .sorted { lhs, rhs in
                let left = lhs.lastEntry?.performedAt ?? .distantPast
                let right = rhs.lastEntry?.performedAt ?? .distantPast
                if left != right { return left > right }
                return lhs.definition.name.localizedStandardCompare(rhs.definition.name) == .orderedAscending
            }
    }

    private func filtered(_ items: [Item], by filter: MuscleFilter) -> [Item] {
        switch filter {
        case .all: return items
        case .muscle(let muscle): return items.filter { $0.muscles.contains(muscle) }
        case .unassigned: return items.filter { $0.muscles.isEmpty }
        }
    }

    private func subtitle(for item: Item) -> String {
        guard let last = item.lastEntry else {
            // Puede tener entradas en el entrenamiento en curso, aún sin terminar.
            return item.definition.isUnused ? "Aún sin sesiones" : "En el entrenamiento en curso"
        }
        var parts = ["\(item.sessions) \(item.sessions == 1 ? "sesión" : "sesiones")"]
        if let date = last.performedAt {
            parts.append("última \(WorkoutFormat.day(date))")
        }
        if let top = last.stats.topSet {
            parts.append("mejor serie \(WorkoutFormat.set(top))")
        }
        return parts.joined(separator: " · ")
    }

    private func delete(_ definition: ExerciseDefinition) {
        // Solo los que no aparecen en ningún entrenamiento: borrar otro perdería historial.
        guard definition.isUnused else { return }
        do {
            try definition.deleteFromCatalog(in: context)
        } catch {
            context.delete(definition)
        }
        context.saveNow()
    }
}
