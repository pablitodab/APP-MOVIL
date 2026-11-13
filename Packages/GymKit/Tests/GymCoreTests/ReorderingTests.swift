import XCTest
@testable import GymCore

final class ReorderingTests: XCTestCase {
    private let items = ["a", "b", "c", "d"]

    func testMoveDownMatchesSwiftUISemantics() {
        // En SwiftUI, arrastrar "a" justo debajo de "c" llega como fromOffsets [0], toOffset 3.
        XCTAssertEqual(Reordering.moved(items, fromOffsets: [0], toOffset: 3), ["b", "c", "a", "d"])
    }

    func testMoveToEnd() {
        XCTAssertEqual(Reordering.moved(items, fromOffsets: [1], toOffset: 4), ["a", "c", "d", "b"])
    }

    func testMoveUp() {
        XCTAssertEqual(Reordering.moved(items, fromOffsets: [3], toOffset: 0), ["d", "a", "b", "c"])
    }

    func testMoveMultiple() {
        XCTAssertEqual(Reordering.moved(items, fromOffsets: [0, 2], toOffset: 4), ["b", "d", "a", "c"])
    }

    func testMoveOntoItselfIsNoOp() {
        XCTAssertEqual(Reordering.moved(items, fromOffsets: [1], toOffset: 1), items)
        XCTAssertEqual(Reordering.moved(items, fromOffsets: [1], toOffset: 2), items)
    }

    func testInvalidInputsAreIgnored() {
        XCTAssertEqual(Reordering.moved(items, fromOffsets: [10], toOffset: 0), items)
        XCTAssertEqual(Reordering.moved(items, fromOffsets: [0], toOffset: 99), ["b", "c", "d", "a"])
        XCTAssertEqual(Reordering.moved([String](), fromOffsets: [0], toOffset: 0), [])
    }
}
