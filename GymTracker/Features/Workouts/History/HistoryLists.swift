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
                        Label("Comparar entrenamientos", systemImage: "arrow.left.arrow.right")
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
                let title = month.formatted(.dateTime.month(.wide).year()).capitalized
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(workout.displayTitle)
                    .font(.headline)
                Spacer()
                if workout.isSyncedToHealth {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.pink)
                        .font(.caption)
                        .accessibilityLabel("Registrado en Salud")
                }
            }
            Text(WorkoutFormat.dayAndTime(workout.startedAt))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                if let duration = workout.duration {
                    Label(WorkoutFormat.duration(duration), systemImage: "clock")
                }
                Label("\(workout.exercises.count) ej. · \(totals.workingSets) series", systemImage: "list.bullet")
                if totals.volumeKg > 0 {
                    Label(WorkoutFormat.volume(totals.volumeKg), systemImage: "scalemass")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
            if !workout.exercises.isEmpty {
                Text(workout.orderedExercises.map(\.name).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Secciones del historial por ejercicio: cada ejercicio hecho al menos una vez.
struct ExerciseHistorySections: View {
    let searchText: String

    @Query(sort: \ExerciseDefinition.name) private var definitions: [ExerciseDefinition]

    init(searchText: String) {
        self.searchText = searchText
    }

    private struct Item: Identifiable {
        let definition: ExerciseDefinition
        let lastEntry: WorkoutExercise
        let sessions: Int
        var id: UUID { definition.id }
    }

    var body: some View {
        let items = self.items
        if items.isEmpty {
            Section {
                if searchText.isEmpty {
                    ContentUnavailableView(
                        "Sin ejercicios",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Aquí verás la progresión de cada ejercicio cuando termines entrenamientos.")
                    )
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        } else {
            Section("Ordenados por último uso") {
                ForEach(items) { item in
                    NavigationLink(value: WorkoutRoute.exercise(item.definition)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.definition.name)
                                .font(.headline)
                            Text(subtitle(for: item))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private var items: [Item] {
        let key = ExerciseName.normalizedKey(searchText)
        return definitions
            .filter { key.isEmpty || $0.normalizedName.contains(key) }
            .compactMap { definition in
                let entries = definition.completedEntries
                guard let last = entries.first else { return nil }
                return Item(definition: definition, lastEntry: last, sessions: entries.count)
            }
            .sorted { ($0.lastEntry.performedAt ?? .distantPast) > ($1.lastEntry.performedAt ?? .distantPast) }
    }

    private func subtitle(for item: Item) -> String {
        var parts = ["\(item.sessions) \(item.sessions == 1 ? "sesión" : "sesiones")"]
        if let date = item.lastEntry.performedAt {
            parts.append("última \(WorkoutFormat.day(date))")
        }
        if let top = item.lastEntry.stats.topSet {
            parts.append("mejor serie \(WorkoutFormat.set(top))")
        }
        return parts.joined(separator: " · ")
    }
}
