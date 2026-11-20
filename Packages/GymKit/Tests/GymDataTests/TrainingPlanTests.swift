import XCTest
import SwiftData
import GymCore
@testable import GymData

final class TrainingPlanTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private let calendar = GymCalendar.make()
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        container = try GymPersistence.makeContainer(inMemory: true)
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    private func template(_ name: String) throws -> WorkoutTemplate {
        let template = WorkoutTemplate(name: name)
        context.insert(template)
        template.addExercise(try ExerciseDefinition.findOrCreate(named: "Ejercicio de \(name)", in: context), targetSets: 1)
        return template
    }

    func testThereIsOnlyOnePlan() throws {
        let first = try TrainingPlan.current(in: context, now: base)
        try context.save()
        let second = try TrainingPlan.current(in: context, now: base.addingTimeInterval(60))
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TrainingPlan>()), 1)
        XCTAssertFalse(first.config.isActive)
    }

    func testUpdatePersistsTheCycle() throws {
        let push = try template("P/T")
        let legs = try template("Pierna")
        try TrainingPlan.update(in: context, now: base) { config in
            config.mode = .cycle
            config.cycle.append(templateID: push.id, today: base, calendar: calendar)
            config.cycle.append(templateID: legs.id, today: base, calendar: calendar)
            config.cycle.append(templateID: nil, today: base, calendar: calendar)
        }
        try context.save()

        let fresh = ModelContext(container)
        let config = try TrainingPlan.current(in: fresh).config
        let days = TrainingSchedule.days(from: base, count: 4, plan: config, calendar: calendar)
        XCTAssertEqual(days.map(\.templateIDs), [[push.id], [legs.id], [], [push.id]])
    }

    func testRemovingATemplateTakesItOutOfThePlan() throws {
        let push = try template("P/T")
        let pull = try template("E/B")
        try TrainingPlan.update(in: context, now: base) { config in
            config.mode = .weekly
            config.weekly.toggle(push.id, on: .monday)
            config.weekly.toggle(pull.id, on: .tuesday)
            config.cycle.append(templateID: push.id, today: base, calendar: calendar)
        }
        try TrainingPlan.removeTemplate(push.id, in: context, now: base)
        let config = try TrainingPlan.current(in: context).config
        XCTAssertEqual(config.weekly.templates(on: .monday), [])
        XCTAssertEqual(config.weekly.templates(on: .tuesday), [pull.id])
        XCTAssertTrue(config.cycle.isEmpty)
    }

    func testCompletedTemplatesOnlyCountFinishedWorkoutsStartedFromATemplate() throws {
        let legs = try template("Pierna")
        let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: base)!
        let fromTemplate = try Workout.start(in: context, at: morning, from: legs)
        fromTemplate.orderedExercises.first?.addSet(weightKg: 100, reps: 5)
        try fromTemplate.finish(at: morning.addingTimeInterval(3600))

        let free = try Workout.start(in: context, at: morning.addingTimeInterval(4 * 3600))
        free.addExercise(try ExerciseDefinition.findOrCreate(named: "Curl", in: context)).addSet(weightKg: 10, reps: 10)
        try free.finish(at: morning.addingTimeInterval(5 * 3600))

        // En curso: aún no cuenta como hecho.
        _ = try Workout.start(in: context, at: morning.addingTimeInterval(6 * 3600), from: legs)
        try context.save()

        let day = try XCTUnwrap(calendar.dateInterval(of: .day, for: morning))
        let done = try Workout.completedTemplatesByDay(in: day, calendar: calendar, context: context)
        XCTAssertEqual(done, [day.start: [legs.id]])
    }
}
