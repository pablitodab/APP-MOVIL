import XCTest
import SwiftData
import GymCore
@testable import GymData

final class ExerciseMusclesTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try GymPersistence.makeContainer(inMemory: true)
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    func testCreateStoresCanonicalMuscles() throws {
        let fondos = try ExerciseDefinition.create(named: "  Fondos ", muscles: [.triceps, .chest, .triceps], in: context)
        try context.save()
        XCTAssertEqual(fondos.name, "Fondos")
        XCTAssertEqual(try fondos.muscles(in: context), [.chest, .triceps])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseMuscles>()), 1)
    }

    func testCreateRejectsDuplicatesAndEmptyNames() throws {
        _ = try ExerciseDefinition.create(named: "Press banca", muscles: [.chest], in: context)
        XCTAssertThrowsError(try ExerciseDefinition.create(named: "PRESS bánca", muscles: [.triceps], in: context)) { error in
            XCTAssertEqual(error as? ExerciseDefinitionError, .duplicateName("Press banca"))
        }
        XCTAssertThrowsError(try ExerciseDefinition.create(named: "   ", muscles: [.chest], in: context)) { error in
            XCTAssertEqual(error as? ExerciseDefinitionError, .emptyName)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseDefinition>()), 1)
    }

    func testSetMusclesReplacesAndEmptyRemovesRow() throws {
        let katana = try ExerciseDefinition.findOrCreate(named: "Katana", in: context)
        XCTAssertEqual(try katana.muscles(in: context), [])

        try katana.setMuscles([.triceps], in: context)
        try katana.setMuscles([.shoulders, .triceps], in: context)
        try context.save()
        XCTAssertEqual(try katana.muscles(in: context), [.shoulders, .triceps])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseMuscles>()), 1)

        try katana.setMuscles([], in: context)
        try context.save()
        XCTAssertEqual(try katana.muscles(in: context), [])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseMuscles>()), 0)
    }

    func testByDefinitionMapsRows() throws {
        let bench = try ExerciseDefinition.create(named: "Press banca", muscles: [.chest, .triceps], in: context)
        let squat = try ExerciseDefinition.create(named: "Sentadilla", muscles: [.quadriceps], in: context)
        let curl = try ExerciseDefinition.findOrCreate(named: "Curl", in: context)
        try context.save()

        let map = ExerciseMuscles.byDefinition(try context.fetch(FetchDescriptor<ExerciseMuscles>()))
        XCTAssertEqual(map[bench.id], [.chest, .triceps])
        XCTAssertEqual(map[squat.id], [.quadriceps])
        XCTAssertNil(map[curl.id])
    }

    func testDeleteFromCatalogRemovesMuscles() throws {
        let unused = try ExerciseDefinition.create(named: "Jalón", muscles: [.back], in: context)
        try context.save()
        try unused.deleteFromCatalog(in: context)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseDefinition>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseMuscles>()), 0)
    }
}
