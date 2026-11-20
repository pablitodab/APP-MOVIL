import XCTest
@testable import GymCore

final class TrainingScheduleTests: XCTestCase {
    private let calendar = GymCalendar.make(timeZone: TimeZone(identifier: "Europe/Madrid")!)
    private let push = UUID()   // Pecho y tríceps
    private let pull = UUID()   // Espalda y bíceps
    private let legs = UUID()   // Pierna

    /// Lunes 17-11-2025 a las 9:00.
    private func day(_ offset: Int, hour: Int = 9) -> Date {
        let monday = calendar.date(from: DateComponents(year: 2025, month: 11, day: 17, hour: hour))!
        return calendar.date(byAdding: .day, value: offset, to: monday)!
    }

    func testWeekdayFollowsIsoOrderWhateverTheHour() {
        XCTAssertEqual(Weekday(of: day(0), calendar: calendar), .monday)
        XCTAssertEqual(Weekday(of: day(2, hour: 23), calendar: calendar), .wednesday)
        XCTAssertEqual(Weekday(of: day(6, hour: 0), calendar: calendar), .sunday)
        XCTAssertEqual(Weekday.allCases.map(\.initial).joined(), "LMXJVSD")
    }

    func testWeeklyPlanAssignsTemplatesToSeveralDays() {
        var weekly = WeeklySchedule()
        weekly.toggle(push, on: .monday)
        weekly.toggle(pull, on: .tuesday)
        weekly.toggle(legs, on: .wednesday)
        weekly.toggle(push, on: .thursday)
        weekly.toggle(pull, on: .friday)
        let plan = TrainingPlanConfig(mode: .weekly, weekly: weekly, cycle: TrainingCycle(anchorDay: day(0), calendar: calendar))

        let days = TrainingSchedule.days(from: day(0), count: 8, plan: plan, calendar: calendar)
        XCTAssertEqual(days.map(\.templateIDs), [[push], [pull], [legs], [push], [pull], [], [], [push]])
        XCTAssertEqual(days.first?.date, calendar.startOfDay(for: day(0)))
        XCTAssertEqual(weekly.weekdays(of: push), [.monday, .thursday])
        XCTAssertTrue(days[5].isRest)
    }

    func testWeeklyToggleRemovesAndKeepsOtherTemplatesOfTheDay() {
        var weekly = WeeklySchedule()
        weekly.toggle(push, on: .monday)
        weekly.toggle(legs, on: .monday)
        XCTAssertEqual(weekly.templates(on: .monday), [push, legs])
        weekly.toggle(push, on: .monday)
        XCTAssertEqual(weekly.templates(on: .monday), [legs])
        weekly.removeTemplate(legs)
        XCTAssertTrue(weekly.isEmpty)
    }

    /// El ejemplo del usuario: tres entrenos y un descanso, que se repite sin mirar la semana.
    func testCycleRepeatsAcrossWeeksFollowingTheCalendar() {
        var cycle = TrainingCycle(anchorDay: day(0), calendar: calendar)
        for id in [push, pull, legs, nil] { cycle.append(templateID: id, today: day(0), calendar: calendar) }
        let plan = TrainingPlanConfig(mode: .cycle, cycle: cycle)

        let days = TrainingSchedule.days(from: day(0), count: 14, plan: plan, calendar: calendar)
        // Semana 1: L P/T, M E/B, X Pierna, J descanso, V P/T, S E/B, D Pierna.
        // Semana 2: L descanso, M P/T…
        XCTAssertEqual(days.map(\.templateIDs), [
            [push], [pull], [legs], [], [push], [pull], [legs],
            [], [push], [pull], [legs], [], [push], [pull],
        ])
        XCTAssertEqual(days.map(\.cycleStepIndex), [0, 1, 2, 3, 0, 1, 2, 3, 0, 1, 2, 3, 0, 1])
    }

    func testCycleDoesNotWaitWhenADayIsSkipped() {
        var cycle = TrainingCycle(anchorDay: day(0), calendar: calendar)
        for id in [push, pull, legs, nil] { cycle.append(templateID: id, today: day(0), calendar: calendar) }
        // Pase lo que pase en el historial, el día 1 siempre toca E/B y el 2 Pierna.
        XCTAssertEqual(cycle.step(on: day(1, hour: 22), calendar: calendar)?.templateID, pull)
        XCTAssertEqual(cycle.step(on: day(2, hour: 0), calendar: calendar)?.templateID, legs)
    }

    func testCycleWorksBeforeTheAnchorDay() {
        var cycle = TrainingCycle(anchorDay: day(10), calendar: calendar)
        for id in [push, pull, legs, nil] { cycle.append(templateID: id, today: day(10), calendar: calendar) }
        XCTAssertEqual(cycle.stepIndex(on: day(9), calendar: calendar), 3)
        XCTAssertEqual(cycle.stepIndex(on: day(5), calendar: calendar), 3)
        XCTAssertEqual(cycle.stepIndex(on: day(6), calendar: calendar), 0)
    }

    func testCycleSurvivesDaylightSavingChange() {
        // En Madrid el 26-10-2025 se retrasa la hora: ese día dura 25 h.
        let saturday = calendar.date(from: DateComponents(year: 2025, month: 10, day: 25, hour: 23))!
        var cycle = TrainingCycle(anchorDay: saturday, calendar: calendar)
        for id in [push, pull] { cycle.append(templateID: id, today: saturday, calendar: calendar) }
        let monday = calendar.date(from: DateComponents(year: 2025, month: 10, day: 27, hour: 0, minute: 30))!
        XCTAssertEqual(cycle.stepIndex(on: monday, calendar: calendar), 0)
    }

    func testSetTodayReanchorsTheCycle() {
        var cycle = TrainingCycle(anchorDay: day(0), calendar: calendar)
        for id in [push, pull, legs, nil] { cycle.append(templateID: id, today: day(0), calendar: calendar) }
        cycle.setToday(2, today: day(5), calendar: calendar)
        XCTAssertEqual(cycle.step(on: day(5), calendar: calendar)?.templateID, legs)
        XCTAssertEqual(cycle.step(on: day(6), calendar: calendar)?.isRest, true)
        XCTAssertEqual(cycle.step(on: day(7), calendar: calendar)?.templateID, push)
        cycle.setToday(9, today: day(5), calendar: calendar) // fuera de rango: no cambia
        XCTAssertEqual(cycle.step(on: day(5), calendar: calendar)?.templateID, legs)
    }

    func testEditingStepsKeepsWhatIsDueToday() {
        var cycle = TrainingCycle(anchorDay: day(0), calendar: calendar)
        for id in [push, pull, legs] { cycle.append(templateID: id, today: day(0), calendar: calendar) }
        // Día 1: toca E/B. Añadir un descanso al principio no debe cambiar lo de hoy.
        cycle.editSteps(today: day(1), calendar: calendar) { $0.insert(CycleStep(templateID: nil), at: 0) }
        XCTAssertEqual(cycle.step(on: day(1), calendar: calendar)?.templateID, pull)
        XCTAssertEqual(cycle.step(on: day(2), calendar: calendar)?.templateID, legs)
        XCTAssertEqual(cycle.step(on: day(3), calendar: calendar)?.isRest, true)

        // Mover: E/B sigue siendo el de hoy aunque cambie de posición.
        cycle.move(fromOffsets: [2], toOffset: 0, today: day(1), calendar: calendar)
        XCTAssertEqual(cycle.steps.map(\.templateID), [pull, nil, push, legs])
        XCTAssertEqual(cycle.step(on: day(1), calendar: calendar)?.templateID, pull)
    }

    func testRemovingTodaysStepMovesToTheOneInItsPlace() {
        var cycle = TrainingCycle(anchorDay: day(0), calendar: calendar)
        for id in [push, pull, legs, nil] { cycle.append(templateID: id, today: day(0), calendar: calendar) }
        cycle.removeTemplate(pull, today: day(1), calendar: calendar)
        XCTAssertEqual(cycle.steps.map(\.templateID), [push, legs, nil])
        XCTAssertEqual(cycle.step(on: day(1), calendar: calendar)?.templateID, legs)

        cycle.remove(atOffsets: [0, 1, 2], today: day(1), calendar: calendar)
        XCTAssertTrue(cycle.isEmpty)
        XCTAssertNil(cycle.stepIndex(on: day(1), calendar: calendar))
    }

    func testInactivePlanReturnsNothing() {
        let empty = TrainingPlanConfig.empty(today: day(0), calendar: calendar)
        XCTAssertFalse(empty.isActive)
        XCTAssertNil(TrainingSchedule.day(day(0), plan: empty, calendar: calendar))
        var weeklyWithoutDays = empty
        weeklyWithoutDays.mode = .weekly
        XCTAssertFalse(weeklyWithoutDays.isActive)
        XCTAssertEqual(TrainingSchedule.days(from: day(0), count: 7, plan: weeklyWithoutDays, calendar: calendar), [])
    }

    func testConfigRoundTripsThroughJSON() throws {
        var plan = TrainingPlanConfig.empty(today: day(0), calendar: calendar)
        plan.mode = .cycle
        plan.weekly.toggle(push, on: .friday)
        plan.cycle.append(templateID: legs, today: day(0), calendar: calendar)
        plan.cycle.append(templateID: nil, today: day(0), calendar: calendar)
        let decoded = try JSONDecoder().decode(TrainingPlanConfig.self, from: JSONEncoder().encode(plan))
        XCTAssertEqual(decoded, plan)
    }

    func testRemoveTemplateClearsBothModes() {
        var plan = TrainingPlanConfig.empty(today: day(0), calendar: calendar)
        plan.weekly.toggle(push, on: .monday)
        plan.cycle.append(templateID: push, today: day(0), calendar: calendar)
        plan.cycle.append(templateID: nil, today: day(0), calendar: calendar)
        plan.removeTemplate(push, today: day(0), calendar: calendar)
        XCTAssertTrue(plan.weekly.isEmpty)
        XCTAssertEqual(plan.cycle.steps.map(\.templateID), [nil])
    }
}
