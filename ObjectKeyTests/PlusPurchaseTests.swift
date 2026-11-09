import StoreKit
import StoreKitTest
import XCTest
@testable import MOKI

// 계층: Integration — StoreKit 테스트 상점(MOKIPlus.storekit, Apple 계정 없이)에서 실제 PlusStore 구매·복원 코드를 돌린다.
// 기기에서 결제가 안 될 때 코드 문제인지 계정 문제인지 가르는 기준이다. 여기서 통과하면 코드 경로는 정상이다.
@MainActor
final class PlusPurchaseTests: XCTestCase {
    private var session: SKTestSession!

    override func setUp() async throws {
        session = try SKTestSession(configurationFileNamed: "MOKIPlus")
        session.disableDialogs = true
        session.clearTransactions()
        print("plus test: session ready")
        await PlusStore.shared.refresh()
        print("plus test: refreshed")
    }

    override func tearDown() async throws {
        session.clearTransactions()
        await PlusStore.shared.refresh()
    }

    func testProductLoadsWithPrice() async throws {
        await PlusStore.shared.loadProduct()
        let product = try XCTUnwrap(PlusStore.shared.product, PlusStore.shared.loadProblem ?? "상품 없음")
        XCTAssertEqual(product.id, PlusStore.productID)
    }

    func testPurchaseUnlocksPlusAndRestoreKeepsIt() async throws {
        XCTAssertFalse(PlusStore.shared.isPlus)
        let message = await PlusStore.shared.purchase()
        XCTAssertNil(message, "구매가 끝나야 한다: \(message ?? "")")
        XCTAssertTrue(PlusStore.shared.isPlus)
        _ = await PlusStore.shared.restore()
        XCTAssertTrue(PlusStore.shared.isPlus)
    }

    func testRefundLocksPlusAgain() async throws {
        _ = await PlusStore.shared.purchase()
        XCTAssertTrue(PlusStore.shared.isPlus)
        for transaction in session.allTransactions() { try session.refundTransaction(identifier: UInt(transaction.identifier)) }
        await PlusStore.shared.refresh()
        XCTAssertFalse(PlusStore.shared.isPlus)
    }
}
