import XCTest
@testable import ObjectKeyCore

// 계층: Unit — 외부 의존 없는 순수 인식 판정 로직.
final class MatchingTests: XCTestCase {
    private let book = UUID()
    private let mug = UUID()

    private func v(_ values: [Float], rev: Int = 2) -> FeatureVector { FeatureVector(values: values, revision: rev) }

    private func keys(threshold: Float = 0.5) -> [RegisteredKey] {
        [
            RegisteredKey(id: book, references: [v([1, 0, 0]), v([0.9, 0.1, 0])], threshold: threshold),
            RegisteredKey(id: mug, references: [v([0, 1, 0])], threshold: threshold),
        ]
    }

    func test_closeToOneKey_returnsMatchWithNearestReference() {
        let outcome = ObjectMatcher().evaluate(v([0.95, 0.05, 0]), against: keys())
        guard case .match(let c) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(c.keyID, book)
        XCTAssertLessThan(c.distance, 0.1)
    }

    func test_unregisteredObject_farFromAll_returnsNoMatch() {
        XCTAssertEqual(ObjectMatcher().evaluate(v([0, 0, 1]), against: keys()), .noMatch)
    }

    func test_twoKeysSimilarlyClose_returnsAmbiguous() {
        // book의 [0.9,0.1,0]과 mug의 [0,1,0]에서 같은 거리 → 1위/2위 비율 1
        let outcome = ObjectMatcher().evaluate(v([0.45, 0.55, 0]), against: keys(threshold: 1.0))
        guard case .ambiguous(let cs) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(Set(cs.map(\.keyID)), [book, mug])
    }

    func test_secondCandidateOutsideThreshold_stillCountsForAmbiguity() {
        // mug는 임계값 밖이지만 book과 거리 차이가 거의 없으면 확정하면 안 된다
        let ks = [
            RegisteredKey(id: book, references: [v([1, 0, 0])], threshold: 0.75),
            RegisteredKey(id: mug, references: [v([0, 1, 0])], threshold: 0.1),
        ]
        let outcome = ObjectMatcher().evaluate(v([0.5, 0.48, 0]), against: ks)
        guard case .ambiguous = outcome else { return XCTFail("\(outcome)") }
    }

    func test_mismatchedRevision_isNeverCompared() {
        let outcome = ObjectMatcher().evaluate(v([1, 0, 0], rev: 1), against: keys())
        XCTAssertEqual(outcome, .noMatch)
    }

    func test_noKeys_returnsNoMatch() {
        XCTAssertEqual(ObjectMatcher().evaluate(v([1, 0, 0]), against: []), .noMatch)
    }

    func test_stabilityFilter_requiresConsecutiveSameKey() {
        var filter = StabilityFilter(requiredStreak: 3)
        let m = ScanOutcome.match(Candidate(keyID: book, distance: 0.1))
        let other = ScanOutcome.match(Candidate(keyID: mug, distance: 0.1))
        XCTAssertNil(filter.feed(m))
        XCTAssertNil(filter.feed(other))   // 다른 물건이 끼면 처음부터
        XCTAssertNil(filter.feed(m))
        XCTAssertNil(filter.feed(m))
        XCTAssertEqual(filter.feed(m), m)
        XCTAssertNil(filter.feed(m))        // 확정 후 초기화
    }

    func test_stabilityFilter_noMatchBreaksStreak() {
        var filter = StabilityFilter(requiredStreak: 2)
        let m = ScanOutcome.match(Candidate(keyID: book, distance: 0.1))
        XCTAssertNil(filter.feed(m))
        XCTAssertNil(filter.feed(.noMatch))
        XCTAssertNil(filter.feed(m))
        XCTAssertEqual(filter.feed(m), m)
    }

    func test_stabilityFilter_ambiguousAlsoNeedsStreak() {
        var filter = StabilityFilter(requiredStreak: 2)
        let amb = ScanOutcome.ambiguous([Candidate(keyID: book, distance: 0.2), Candidate(keyID: mug, distance: 0.21)])
        let m = ScanOutcome.match(Candidate(keyID: book, distance: 0.1))
        XCTAssertNil(filter.feed(amb))
        XCTAssertNil(filter.feed(m))       // 결과 종류가 바뀌면 처음부터
        XCTAssertNil(filter.feed(amb))
        XCTAssertEqual(filter.feed(amb), amb)
    }

    func test_calibration_isClampedAndScalesWithSpread() {
        XCTAssertEqual(Calibration.suggestThreshold(for: [v([1, 0, 0])]), Calibration.minimumThreshold)
        XCTAssertEqual(Calibration.suggestThreshold(for: [v([1, 0, 0]), v([0, 1, 0])]), Calibration.maximumThreshold)
        let mid = Calibration.suggestThreshold(for: [v([1, 0, 0]), v([1, 0.3, 0])])
        XCTAssertEqual(mid, 0.3 * Calibration.marginFactor, accuracy: 1e-5)
    }
}
