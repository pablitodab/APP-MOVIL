import XCTest
@testable import GymCore

final class AppGroupLocatorTests: XCTestCase {
    private let base = "group.com.pablitodab.gymtracker"

    func testOrderIsBaseThenAltStoreThenProfileWithoutDuplicates() {
        let candidates = AppGroupLocator.candidates(
            base: base,
            altStoreGroups: ["group.com.pablitodab.gymtracker.ABCDE12345"],
            profileGroups: ["group.com.pablitodab.gymtracker.ABCDE12345", "group.com.pablitodab.gymtracker.ZZZ"]
        )
        XCTAssertEqual(candidates, [
            base,
            "group.com.pablitodab.gymtracker.ABCDE12345",
            "group.com.pablitodab.gymtracker.ZZZ",
        ])
    }

    func testIgnoresGroupsOfOtherApps() {
        let candidates = AppGroupLocator.candidates(
            base: base,
            altStoreGroups: ["group.com.rileytestut.AltStore.ABCDE12345"],
            profileGroups: ["group.com.pablitodab.gymtrackerpro", "group.com.pablitodab"]
        )
        XCTAssertEqual(candidates, [base])
    }

    func testLocateReturnsFirstGroupWithContainer() {
        let renamed = base + ".ABCDE12345"
        let url = URL(fileURLWithPath: "/tmp/shared")
        let found = AppGroupLocator.locate(candidates: [base, renamed]) { $0 == renamed ? url : nil }
        XCTAssertEqual(found?.group, renamed)
        XCTAssertEqual(found?.url, url)
    }

    func testLocateReturnsNilWithoutAnyGrantedGroup() {
        // Caso Sideloadly con Apple ID gratuito: ningún grupo concedido.
        XCTAssertNil(AppGroupLocator.locate(candidates: [base]) { _ in nil })
    }

    func testProfileExposesAppGroups() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>Entitlements</key><dict>
        <key>com.apple.security.application-groups</key>
        <array><string>group.com.pablitodab.gymtracker.ABCDE12345</string></array>
        </dict></dict></plist>
        """
        let profile = try ProvisioningProfile.parse(Data(xml.utf8))
        XCTAssertEqual(profile.appGroups, ["group.com.pablitodab.gymtracker.ABCDE12345"])
    }

    func testProfileWithoutAppGroups() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>Entitlements</key><dict>
        <key>get-task-allow</key><true/>
        </dict></dict></plist>
        """
        XCTAssertEqual(try ProvisioningProfile.parse(Data(xml.utf8)).appGroups, [])
    }
}

final class TrainingSnapshotTests: XCTestCase {
    private let calendar = GymCalendar.make(timeZone: TimeZone(identifier: "UTC")!)

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 18) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour)))
    }

    func testRoundTripThroughDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertNil(try TrainingSnapshot.read(fromDirectory: directory))

        let snapshot = TrainingSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            workoutDates: [try date(2026, 11, 10), try date(2026, 11, 3)]
        )
        try snapshot.write(toDirectory: directory)
        let read = try XCTUnwrap(try TrainingSnapshot.read(fromDirectory: directory))
        XCTAssertEqual(read, snapshot)
        XCTAssertEqual(read.workoutDates, [try date(2026, 11, 3), try date(2026, 11, 10)])
    }

    func testRejectsUnknownVersion() {
        let data = Data(#"{"version":99,"generatedAt":"2026-11-13T10:00:00Z","workoutDates":[]}"#.utf8)
        XCTAssertThrowsError(try TrainingSnapshot.decode(data)) { error in
            XCTAssertEqual(error as? TrainingSnapshot.StoreError, .unsupportedVersion(99))
        }
    }

    func testSummaryForCurrentMonthAndStreak() throws {
        // Jueves 13-11-2026. Entrenos: semana del 2 y semana del 9 → racha de 2 semanas.
        let now = try date(2026, 11, 13, hour: 9)
        let dates = [
            try date(2026, 10, 20),
            try date(2026, 11, 3),
            try date(2026, 11, 10),
            try date(2026, 11, 12),
            try date(2026, 11, 13, hour: 20), // aún no ha ocurrido: no cuenta
        ]
        let summary = try XCTUnwrap(TrainingCalendarSummary(workoutDates: dates, now: now, calendar: calendar))

        XCTAssertEqual(summary.grid.month.start, calendar.startOfDay(for: try date(2026, 11, 1)))
        XCTAssertEqual(summary.trainedDaysThisMonth, 3)
        XCTAssertFalse(summary.trainedDays.contains(calendar.startOfDay(for: now)))
        XCTAssertEqual(summary.streak.current, 2)
        XCTAssertTrue(summary.streak.isCurrentWeekDone)

        let week = summary.currentWeek(calendar: calendar)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.first, calendar.startOfDay(for: try date(2026, 11, 9))) // lunes
        XCTAssertEqual(week.last, calendar.startOfDay(for: try date(2026, 11, 15))) // domingo
    }
}
