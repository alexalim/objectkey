import StoreKit
import StoreKitTest
import XCTest
@testable import MOKI

// 계층: Integration — StoreKit 테스트 상점(MOKIPlus.storekit, Apple 계정 없이)에서 PlusStore의 권한 확인·복원·환불 처리를 본다.
// 결제 창을 띄우는 단계는 클라우드 시뮬레이터(화면 없는 테스트)에서 어떤 호출 방식으로도 끝나지 않아(2026-11-09 확인),
// 구매는 테스트 상점이 직접 만들고(buyProduct) 그 뒤 앱이 플러스를 제대로 알아보는지만 확인한다.
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

    func testBoughtPlusIsRecognizedAndRestored() async throws {
        XCTAssertFalse(PlusStore.shared.isPlus)
        try await XCTUnwrap(session).buyProduct(identifier: PlusStore.productID)
        await PlusStore.shared.refresh()
        XCTAssertTrue(PlusStore.shared.isPlus)
        _ = await PlusStore.shared.restore()
        XCTAssertTrue(PlusStore.shared.isPlus)
    }

    func testRefundLocksPlusAgain() async throws {
        let session = try XCTUnwrap(session)
        try await session.buyProduct(identifier: PlusStore.productID)
        await PlusStore.shared.refresh()
        XCTAssertTrue(PlusStore.shared.isPlus)
        for transaction in session.allTransactions() { try session.refundTransaction(identifier: transaction.identifier) }
        await PlusStore.shared.refresh()
        XCTAssertFalse(PlusStore.shared.isPlus)
    }
}
