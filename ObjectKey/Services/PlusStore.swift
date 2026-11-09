import Foundation
import Observation
import OSLog
import StoreKit
import UIKit

/// MOKI 플러스(평생 이용권, 비소모성 인앱 구매). 무료는 습관 3개까지, 플러스는 제한 없음과 편의 기능.
/// 구매 여부는 StoreKit의 현재 권한(Transaction.currentEntitlements)이 기준이고, 위젯·워치가 볼 수 있게 스냅숏에도 적는다.
@MainActor
@Observable
final class PlusStore {
    static let shared = PlusStore()
    static let productID = "com.aspynlim.moki.plus"
    /// 무료로 만들 수 있는 습관 수. 이미 더 있는 사람은 그대로 쓰고, 새로 더하는 것만 막는다.
    static let freeHabitLimit = 3

    private(set) var isPlus: Bool
    private(set) var product: Product?
    /// 상품 정보를 못 받았을 때의 이유(심사·네트워크). 결제 화면에 보여 준다.
    private(set) var loadProblem: String?

    private static let cacheKey = "moki.plus.cached"
    private var updates: Task<Void, Never>?

    init() {
        // 실행 직후 권한을 다시 확인하기 전까지는 마지막으로 확인한 값을 쓴다(위젯 깜빡임 방지).
        isPlus = UserDefaults.standard.bool(forKey: Self.cacheKey)
        #if DEBUG
        // UI 테스트는 결제 없이 모든 화면을 돈다. -ui-free면 무료 상태(결제 화면 확인용).
        if Self.demoPlus { isPlus = true }
        #endif
    }

    /// 앱이 켜질 때 한 번. 권한 확인, 상품 정보, 다른 기기·환불로 바뀐 거래 듣기.
    func start() {
        guard updates == nil else { return }
        updates = Task {
            for await update in Transaction.updates {
                if case .verified(let transaction) = update { await transaction.finish() }
                await refresh()
            }
        }
        Task {
            await refresh()
            await loadProduct()
        }
    }

    #if DEBUG
    private static var demoPlus: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-ui-demo") && !args.contains("-ui-free")
    }
    #endif

    func canAddHabit(currentCount: Int) -> Bool { isPlus || currentCount < Self.freeHabitLimit }

    func loadProduct() async {
        do {
            product = try await Product.products(for: [Self.productID]).first
            loadProblem = product == nil ? "지금은 App Store에서 상품을 받아 오지 못했어요. 잠시 뒤 [다시 불러오기]를 눌러 주세요." : nil
        } catch {
            loadProblem = "지금은 상품 정보를 불러오지 못했어요. 인터넷 연결을 확인해 주세요."
        }
    }

    /// 결제. 끝나면 결과 문구를 돌려준다(성공이면 nil).
    /// 결제. iOS 18.2 이상은 지금 앞에 있는 화면(scene)을 넘겨 결제 창을 띄울 곳을 분명히 한다.
    /// (SwiftUI의 PurchaseAction은 빌드 62에서 결제 창 없이 끝나지 않는 일이 있어 쓰지 않는다.)
    /// 끝나면 결과 문구를 돌려준다(성공이면 nil). 실패는 종류마다 문구를 달리해 원인을 알 수 있게 한다.
    func purchase() async -> String? {
        let log = Logger(subsystem: "com.aspynlim.moki", category: "plus")
        guard AppStore.canMakePayments else {
            log.error("purchase blocked: canMakePayments false")
            return "이 기기에서 앱 내 구입이 막혀 있어요. 설정 → 스크린 타임 → 콘텐츠 및 개인정보 보호 제한에서 확인해 주세요."
        }
        if product == nil { await loadProduct() }
        guard let product else { return loadProblem }
        do {
            let outcome: Product.PurchaseResult
            if #available(iOS 18.2, *), let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) {
                outcome = try await product.purchase(confirmIn: scene)
            } else {
                outcome = try await product.purchase()
            }
            log.info("purchase result: \(String(describing: outcome), privacy: .public)")
            switch outcome {
            case .success(let result):
                guard case .verified(let transaction) = result else { return "구매를 확인하지 못했어요. 구매 복원을 눌러 주세요." }
                await transaction.finish()
                await refresh()
                return nil
            case .pending:
                return "승인을 기다리고 있어요. 승인되면 자동으로 열려요."
            case .userCancelled:
                // 결제 창을 닫았거나, 계정 로그인을 거치며 취소로 끝난 경우.
                return "결제를 취소했어요. 다시 누르면 결제 창이 떠요. (취소됨)"
            @unknown default:
                return "결제 결과를 알 수 없어요. 구매 복원을 눌러 확인해 주세요. (알 수 없음)"
            }
        } catch {
            log.error("purchase error: \(String(describing: error), privacy: .public)")
            return "결제하지 못했어요. (\(error.localizedDescription))"
        }
    }

    /// 구매 복원. 같은 Apple 계정으로 산 적이 있으면 다시 열린다.
    func restore() async -> String {
        try? await AppStore.sync()
        await refresh()
        return isPlus ? "플러스를 다시 열었어요." : "이 Apple 계정으로 산 기록을 찾지 못했어요."
    }

    func refresh() async {
        var owned = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let t) = entitlement, t.productID == Self.productID, t.revocationDate == nil { owned = true }
        }
        #if DEBUG
        if Self.demoPlus { owned = true }
        #endif
        let changed = owned != isPlus
        isPlus = owned
        UserDefaults.standard.set(owned, forKey: Self.cacheKey)
        // 위젯·워치가 잠금 여부를 알 수 있게 요약을 다시 쓴다.
        if changed { WidgetBridge.refreshFromStore() }
    }
}
