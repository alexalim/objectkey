import XCTest
@testable import ObjectKeyCore

// 계층: Unit — 물건 하나를 여러 습관이 함께 쓸 때의 묶기·주인·사진 넘겨받기 규칙.
final class SharedObjectTests: XCTestCase {
    private let shoes = UUID(), walk = UUID(), stretch = UUID(), book = UUID()

    func test_groups_putOwnerFirst_andKeepRegistrationOrder() {
        let habits = [SharedObject.Habit(id: shoes, source: nil), .init(id: book, source: nil),
                      .init(id: walk, source: shoes), .init(id: stretch, source: shoes)]
        XCTAssertEqual(SharedObject.groups(habits), [[shoes, walk, stretch], [book]])
    }

    func test_missingOwner_makesHabitItsOwnObject() {
        let orphan = SharedObject.Habit(id: walk, source: shoes)
        XCTAssertEqual(SharedObject.owner(of: orphan, among: [orphan]), walk)
        XCTAssertEqual(SharedObject.groups([orphan]), [[walk]])
    }

    func test_heir_isFirstBorrower_orNilWhenAlone() {
        let habits = [SharedObject.Habit(id: shoes, source: nil), .init(id: walk, source: shoes), .init(id: stretch, source: shoes)]
        XCTAssertEqual(SharedObject.heir(of: shoes, among: habits), walk)
        XCTAssertNil(SharedObject.heir(of: book, among: habits + [.init(id: book, source: nil)]))
    }
}
