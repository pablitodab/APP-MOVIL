import Foundation
import SwiftData
import GymCore
import GymData

/// Datos de ejemplo solo para las previews de Xcode (base de datos en memoria).
/// No los uses en la app: nunca se muestran al usuario.
@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        do {
            let container = try GymPersistence.makeContainer(inMemory: true)
            let context = container.mainContext
            let bench = try ExerciseDefinition.findOrCreate(named: "Press banca", in: context)
            let row = try ExerciseDefinition.findOrCreate(named: "Remo con mancuerna", in: context)

            let start = Date.now.addingTimeInterval(-26 * 3600)
            let workout = Workout(startedAt: start, title: "Torso", bodyWeightKg: 80)
            context.insert(workout)
            let benchEntry = workout.addExercise(bench)
            benchEntry.addSet(weightKg: 40, reps: 12, effort: .warmup)
            benchEntry.addSet(weightKg: 80, reps: 8)
            benchEntry.addSet(weightKg: 80, reps: 6, effort: .failure)
            let rowEntry = workout.addExercise(row)
            rowEntry.addSet(weightKg: 30, reps: 10, side: .left)
            rowEntry.addSet(weightKg: 30, reps: 10, side: .right)
            try workout.finish(at: start.addingTimeInterval(65 * 60))

            context.insert(Workout(title: "Pierna"))
            try context.save()
            return container
        } catch {
            fatalError("No se pudieron crear los datos de preview: \(error)")
        }
    }()
}
