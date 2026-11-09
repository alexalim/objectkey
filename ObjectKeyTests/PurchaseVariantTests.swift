import StoreKit
import StoreKitTest
import UIKit
import XCTest
@testable import MOKI

// 계층: Integration — 진단용. StoreKit 결제를 부르는 방법별로 끝나는지 본다(기기에서 결제가 끝나지 않는 원인 찾기).
// 각 방법을 20초 안에 끝내지 못하면 "hang"으로 남긴다. 원인을 찾으면 지운다.
@MainActor
final class PurchaseVariantTests: XCTestCase {
    private var session: SKTestSession!

    override func setUp() async throws {
        session = try SKTestSession(configurationFileNamed: "MOKIPlus")
        session.disableDialogs = true
        session.clearTransactions()
        let scenes = UIApplication.shared.connectedScenes.map { "\($0.activationState.rawValue)" }
        print("plus variant: scenes=\(scenes)")
    }

    private func product() async throws -> Product {
        try XCTUnwrap(try await Product.products(for: [PlusStore.productID]).first)
    }

    /// 결과를 20초까지 기다린다. 못 끝내면 nil.
    private func within20s(_ work: @escaping @Sendable () async throws -> Product.PurchaseResult) async -> String {
        await withTaskGroup(of: String?.self) { group in
            group.addTask { do { return "\(try await work())" } catch { return "error \(error)" } }
            group.addTask { try? await Task.sleep(for: .seconds(20)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? "hang"
        }
    }

    func testA_plainOnMainActor() async throws {
        let p = try await product()
        print("plus variant A plain/main:", await within20s { @MainActor in try await p.purchase() })
    }

    func testB_plainDetached() async throws {
        let p = try await product()
        print("plus variant B plain/detached:", await within20s { try await Task.detached { try await p.purchase() }.value })
    }

    func testC_sceneOnMainActor() async throws {
        let p = try await product()
        guard #available(iOS 18.2, *),
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            print("plus variant C scene: no scene"); return
        }
        print("plus variant C scene/main:", await within20s { @MainActor in try await p.purchase(confirmIn: scene) })
    }

    func testD_viewControllerOnMainActor() async throws {
        let p = try await product()
        guard #available(iOS 18.2, *),
              let vc = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first?.keyWindow?.rootViewController else {
            print("plus variant D vc: no view controller"); return
        }
        print("plus variant D vc/main:", await within20s { @MainActor in try await p.purchase(confirmIn: vc) })
    }
}
