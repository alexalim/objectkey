import StoreKit
import StoreKitTest
import XCTest
@testable import MOKI

// 계층: Integration — StoreKit 테스트 상점(MOKIPlus.storekit, Apple 계정 없이)에서 PlusStore의 권한 확인·복원·환불 처리를 본다.
// 클라우드 빌드는 서명 없이(CODE_SIGNING_ALLOWED=NO) 만들어 테스트 상점도 구매를 거부한다("notEntitled", 2026-11-09 확인).
// 그 경우 구매 테스트는 건너뛰고, 서명된 빌드(맥에서 직접 실행)에서만 끝까지 확인한다.
@MainActor
final class PlusPurchaseTests: XCTestCase {
    private var session: SKTestSession?

    override func setUp() async throws {
        let session = try SKTestSession(configurationFileNamed: "MOKIPlus")
        session.disableDialogs = true
        session.clearTransactions()
        self.session = session
        await PlusStore.shared.refresh()
    }

    override func tearDown() async throws {
        session?.clearTransactions()
        await PlusStore.shared.refresh()
    }

    func testProductLoadsWithPrice() async throws {
        await PlusStore.shared.loadProduct()
        let product = try XCTUnwrap(PlusStore.shared.product, PlusStore.shared.loadProblem ?? "상품 없음")
        XCTAssertEqual(product.id, PlusStore.productID)
    }

    /// 테스트 상점에서 산다. 서명이 없어 거부되면 이 환경에서는 확인할 수 없으니 건너뛴다.
    private func buy() async throws {
        do {
            try await XCTUnwrap(session).buyProduct(identifier: PlusStore.productID)
        } catch {
            throw XCTSkip("서명 없는 빌드라 테스트 구매가 거부됨: \(error)")
        }
    }

    func testBoughtPlusIsRecognizedAndRestored() async throws {
        XCTAssertFalse(PlusStore.shared.isPlus)
        try await buy()
        await PlusStore.shared.refresh()
        XCTAssertTrue(PlusStore.shared.isPlus)
        _ = await PlusStore.shared.restore()
        XCTAssertTrue(PlusStore.shared.isPlus)
    }

    func testRefundLocksPlusAgain() async throws {
        let session = try XCTUnwrap(session)
        try await buy()
        await PlusStore.shared.refresh()
        XCTAssertTrue(PlusStore.shared.isPlus)
        for transaction in session.allTransactions() { try session.refundTransaction(identifier: transaction.identifier) }
        await PlusStore.shared.refresh()
        XCTAssertFalse(PlusStore.shared.isPlus)
    }
}
