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
            try bench.setMuscles([.chest, .triceps, .shoulders], in: context)
            try row.setMuscles([.back, .biceps], in: context)
            try squat.setMuscles([.quadriceps, .glutes], in: context)
            try deadlift.setMuscles([.hamstrings, .glutes, .lowerBack], in: context)

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

            // Plantillas: una creada a mano y otra guardada desde un entrenamiento.
            let legs = WorkoutTemplate(name: "Pierna", createdAt: .now.addingTimeInterval(-40 * 86_400))
            context.insert(legs)
            legs.addExercise(squat, targetSets: 4)
            legs.addExercise(deadlift, targetSets: 3)
            legs.lastUsedAt = calendar.date(byAdding: .day, value: -3, to: .now)
            let torso = WorkoutTemplate(name: "Torso", createdAt: .now.addingTimeInterval(-35 * 86_400))
            context.insert(torso)
            torso.addExercise(bench, targetSets: 4)
            torso.addExercise(row, targetSets: 2)
            torso.lastUsedAt = calendar.date(byAdding: .day, value: -1, to: .now)

            // Plan: ciclo Torso, Pierna, Descanso que empieza hoy con Torso; y por días de la
            // semana (lunes y jueves Torso, martes y viernes Pierna) para la otra captura.
            try TrainingPlan.update(in: context) { plan in
                #if DEBUG
                plan.mode = ScreenshotMode.usesWeeklyPlan ? .weekly : .cycle
                #else
                plan.mode = .cycle
                #endif
                for id in [torso.id, legs.id, nil] {
                    plan.cycle.append(templateID: id, today: .now, calendar: calendar)
                }
                plan.cycle.setToday(0, today: .now, calendar: calendar)
                plan.weekly.toggle(torso.id, on: .monday)
                plan.weekly.toggle(torso.id, on: .thursday)
                plan.weekly.toggle(legs.id, on: .tuesday)
                plan.weekly.toggle(legs.id, on: .friday)
            }

            try addCardio(in: context, calendar: calendar)

            guard includesWorkoutInProgress else {
                try context.save()
                return container
            }

            // Entrenamiento en curso desde la plantilla «Pierna», empezado hace 25 minutos:
            // sentadilla con 3 de 4 series marcadas y peso muerto con 1 de 3.
            try context.save()
            let current = try Workout.start(in: context, at: .now.addingTimeInterval(-25 * 60), from: legs)
            let squatEntry = current.orderedExercises[0]
            squatEntry.addSet(weightKg: 60, reps: 10, effort: .warmup)
            squatEntry.addSet(weightKg: 110, reps: 6)
            squatEntry.addSet(weightKg: 110, reps: 5)
            current.orderedExercises[1].addSuggestedSet()

            try context.save()
            return container
        } catch {
            fatalError("No se pudieron crear los datos de preview: \(error)")
        }
    }

    /// Cardio de ejemplo: cinta caminando y corriendo con mejora de ritmo, bici y VO2max.
    private static func addCardio(in context: ModelContext, calendar: Calendar) throws {
        let treadmill = try CardioActivity.create(named: "Cinta", equipment: .treadmill, muscles: CardioEquipment.treadmill.suggestedMuscles, in: context)
        let bike = try CardioActivity.create(named: "Bici estática", equipment: .bike, muscles: CardioEquipment.bike.suggestedMuscles, in: context)
        _ = try CardioActivity.create(named: "Elíptica", equipment: .elliptical, muscles: CardioEquipment.elliptical.suggestedMuscles, in: context)

        func day(_ daysAgo: Int, hour: Int) -> Date {
            let start = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: .now)) ?? .now
            return calendar.date(bySettingHour: hour, minute: 30, second: 0, of: start) ?? start
        }

        // Carrera en cinta: 5 km cada vez algo más rápidos.
        for (index, daysAgo) in [38, 31, 24, 17, 10, 2].enumerated() {
            let seconds = Double(31 * 60 - index * 45)
            try CardioSession.log(
                CardioSessionInput(
                    date: day(daysAgo, hour: 8), durationSeconds: seconds, distanceKm: 5, gait: .running,
                    inclinePercent: 1, speedKmh: (5 / (seconds / 3600) * 10).rounded() / 10,
                    rpe: 8 - (index > 3 ? 1 : 0), averageHeartRate: 162 - index * 2, maxHeartRate: 178 - index
                ),
                activity: treadmill, in: context
            )
        }
        // Caminar inclinado tras pesas.
        for (index, daysAgo) in [33, 26, 19, 12, 5, 1].enumerated() {
            try CardioSession.log(
                CardioSessionInput(
                    date: day(daysAgo, hour: 20), durationSeconds: 20 * 60, distanceKm: 1.9 + Double(index) * 0.05,
                    gait: .walking, inclinePercent: 10 + Double(index % 3), speedKmh: 5.8, rpe: 5, averageHeartRate: 128
                ),
                activity: treadmill, in: context
            )
        }
        for (index, daysAgo) in [29, 15, 8, 4].enumerated() {
            try CardioSession.log(
                CardioSessionInput(
                    date: day(daysAgo, hour: 19), durationSeconds: Double(30 + index * 5) * 60,
                    distanceKm: 12 + Double(index) * 2.5, level: 8 + Double(index), rpe: 6
                ),
                activity: bike, in: context
            )
        }
        for (daysAgo, value) in [(84, 44.1), (56, 45.0), (28, 45.6), (3, 46.4)] {
            try VO2MaxReading.log(value: value, at: day(daysAgo, hour: 9), in: context)
        }
    }
}
