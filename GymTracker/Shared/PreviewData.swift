import Foundation
import SwiftData
import GymCore
import GymData

/// Datos de ejemplo solo para las previews de Xcode y las capturas del simulador en Debug
/// (`ScreenshotMode`), siempre en una base de datos en memoria. Nunca llegan a la app real.
@MainActor
enum PreviewData {
    static let container = makeContainer(includesWorkoutInProgress: true)

    #if DEBUG
    /// Se crea una sola vez: las capturas navegan entre pestañas sin perder los datos.
    static let screenshotContainer = makeContainer(includesWorkoutInProgress: ScreenshotMode.includesWorkoutInProgress)
    #endif

    static func makeContainer(includesWorkoutInProgress: Bool) -> ModelContainer {
        do {
            let container = try GymPersistence.makeContainer(inMemory: true)
            let context = container.mainContext
            let calendar = GymCalendar.make()
            let bench = try ExerciseDefinition.findOrCreate(named: "Press banca", in: context)
            let row = try ExerciseDefinition.findOrCreate(named: "Remo con mancuerna", in: context)
            let squat = try ExerciseDefinition.findOrCreate(named: "Sentadilla", in: context)
            let deadlift = try ExerciseDefinition.findOrCreate(named: "Peso muerto rumano", in: context)

            /// Entrenamiento terminado hace `daysAgo` días, empezando a las `hour`.
            func addWorkout(daysAgo: Int, hour: Int, minutes: Int, title: String, build: (Workout) -> Void) throws {
                let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: .now)) ?? .now
                let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
                let workout = Workout(startedAt: start, title: title, bodyWeightKg: 80)
                context.insert(workout)
                build(workout)
                try workout.finish(at: start.addingTimeInterval(TimeInterval(minutes * 60)))
            }

            // Torso y pierna alternos durante cinco semanas, con progresión de cargas.
            let torsoDays = [31, 26, 19, 12, 5, 1]
            for (index, daysAgo) in torsoDays.enumerated() {
                let top = 70 + Double(index) * 2.5
                try addWorkout(daysAgo: daysAgo, hour: 18, minutes: 58 + index * 2, title: "Torso") { workout in
                    let benchEntry = workout.addExercise(bench)
                    benchEntry.addSet(weightKg: 40, reps: 12, effort: .warmup)
                    benchEntry.addSet(weightKg: top, reps: 8)
                    benchEntry.addSet(weightKg: top, reps: 7)
                    benchEntry.addSet(weightKg: top, reps: 6, effort: .failure)
                    let rowEntry = workout.addExercise(row)
                    rowEntry.addSet(weightKg: 26 + Double(index) * 2, reps: 10, side: .left)
                    rowEntry.addSet(weightKg: 26 + Double(index) * 2, reps: 10, side: .right)
                }
            }
            let legDays = [29, 22, 15, 8, 3]
            for (index, daysAgo) in legDays.enumerated() {
                let top = 90 + Double(index) * 5
                try addWorkout(daysAgo: daysAgo, hour: 19, minutes: 64 + index, title: "Pierna") { workout in
                    let squatEntry = workout.addExercise(squat)
                    squatEntry.addSet(weightKg: 60, reps: 10, effort: .warmup)
                    squatEntry.addSet(weightKg: top, reps: 6)
                    squatEntry.addSet(weightKg: top, reps: 6)
                    squatEntry.addSet(weightKg: top - 20, reps: 10, effort: .dropset)
                    let deadliftEntry = workout.addExercise(deadlift)
                    deadliftEntry.addSet(weightKg: 70 + Double(index) * 5, reps: 10)
                    deadliftEntry.addSet(weightKg: 70 + Double(index) * 5, reps: 9)
                }
            }

            guard includesWorkoutInProgress else {
                try context.save()
                return container
            }

            // Entrenamiento en curso, empezado hace 25 minutos.
            let current = Workout(startedAt: .now.addingTimeInterval(-25 * 60), title: "Pierna", bodyWeightKg: 80)
            context.insert(current)
            let squatEntry = current.addExercise(squat)
            squatEntry.addSet(weightKg: 60, reps: 10, effort: .warmup)
            squatEntry.addSet(weightKg: 110, reps: 6)
            squatEntry.addSet(weightKg: 110, reps: 5)
            let deadliftEntry = current.addExercise(deadlift)
            deadliftEntry.addSuggestedSet()

            try context.save()
            return container
        } catch {
            fatalError("No se pudieron crear los datos de preview: \(error)")
        }
    }
}
