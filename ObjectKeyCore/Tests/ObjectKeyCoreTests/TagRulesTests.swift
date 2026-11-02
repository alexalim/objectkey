import XCTest
@testable import ObjectKeyCore

// 계층: Unit — 태그 이름 정리·목록 순서·바꾸기·문장 속 태그 찾기.
final class TagRulesTests: XCTestCase {
    func test_normalize() {
        XCTAssertEqual(TagRules.normalize("  #운동 "), "운동")
        XCTAssertEqual(TagRules.normalize("##건강"), "건강")
        XCTAssertNil(TagRules.normalize("  # "))
        XCTAssertEqual(TagRules.normalize("아주아주아주긴태그이름입니다")?.count, TagRules.maxLength)
    }

    func test_all_defaultsFirstThenUsedSorted() {
        XCTAssertEqual(TagRules.all(used: [["회사", "건강"], ["가족"], []]), ["운동", "건강", "공부", "가족", "회사"])
        XCTAssertEqual(TagRules.all(used: [["건강"], ["회사"]], includeDefaults: false), ["건강", "회사"])
    }

    func test_rename_mergesDuplicates() {
        XCTAssertEqual(TagRules.rename(["운동", "건강"], from: "운동", to: "#헬스"), ["헬스", "건강"])
        XCTAssertEqual(TagRules.rename(["운동", "건강"], from: "운동", to: "건강"), ["건강"])
        XCTAssertEqual(TagRules.rename(["운동"], from: "운동", to: "  "), ["운동"], "빈 이름으로는 바꾸지 않는다")
    }

    func test_mentioned_onlyWhenSaidAsTag() {
        let known = ["운동", "건강", "공부"]
        XCTAssertEqual(TagRules.mentioned(in: "건강 태그로 영양제 등록해줘", known: known), ["건강"])
        XCTAssertEqual(TagRules.mentioned(in: "#운동 #건강 아침 스트레칭", known: known), ["운동", "건강"])
        XCTAssertEqual(TagRules.mentioned(in: "운동 매트 30분", known: known), [], "이름 속 '운동'은 태그가 아니다")
    }
}
