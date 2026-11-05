import SwiftData
import XCTest
import ObjectKeyCore
@testable import MOKI

// 계층: Integration — 실제 SwiftData 저장소(메모리)에서 같은 물건을 쓰는 습관의 사진이 주인 삭제 뒤에도 남는지 본다.
@MainActor
final class SharedObjectStoreTests: XCTestCase {
    func testDeletingOwnerHandsPhotosToNextHabit() throws {
        let context = ModelContext(try AppTestStore.make())
        let shoes = KeyObject(name: "운동화", emoji: "👟", action: .session, threshold: 0.58)
        let walk = KeyObject(name: "5분 걷기", emoji: "👟", action: .session, threshold: 0.6)
        let stretch = KeyObject(name: "스트레칭", emoji: "👟", action: .session, threshold: 0.6)
        [shoes, walk, stretch].forEach(context.insert)
        shoes.shots = [ReferenceShot(vector: FeatureVector(values: [0.1, 0.2], revision: 1), thumbnail: nil)]
        walk.photoSourceID = shoes.id
        stretch.photoSourceID = shoes.id
        try context.save()
        XCTAssertEqual(walk.objectMembers(in: [shoes, walk, stretch]).map(\.id), [shoes.id, walk.id, stretch.id])

        shoes.handOverObject(in: [shoes, walk, stretch])
        context.delete(shoes)
        try context.save()

        XCTAssertEqual(walk.shots.count, 1)
        XCTAssertNil(walk.photoSourceID)
        XCTAssertEqual(walk.threshold, 0.58)
        XCTAssertEqual(stretch.photoSourceID, walk.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReferenceShot>()), 1)
    }
}
