import Foundation
import Observation
import StoreKit

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
        // UI 테스트는 결제 없이 모든 화면을 돈다.
        if ProcessInfo.processInfo.arguments.contains("-ui-demo") { isPlus = true }
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

    func canAddHabit(currentCount: Int) -> Bool { isPlus || currentCount < Self.freeHabitLimit }

    func loadProduct() async {
        do {
            product = try await Product.products(for: [Self.productID]).first
            loadProblem = product == nil ? "지금은 상품 정보를 불러오지 못했어요. 잠시 뒤 다시 열어 주세요." : nil
        } catch {
            loadProblem = "지금은 상품 정보를 불러오지 못했어요. 인터넷 연결을 확인해 주세요."
        }
    }

    /// 결제. 끝나면 결과 문구를 돌려준다(성공이면 nil).
    func purchase() async -> String? {
        if product == nil { await loadProduct() }
        guard let product else { return loadProblem }
        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result else { return "구매를 확인하지 못했어요. 구매 복원을 눌러 주세요." }
                await transaction.finish()
                await refresh()
                return nil
            case .pending:
                return "승인을 기다리고 있어요. 승인되면 자동으로 열려요."
            case .userCancelled:
                return ""
            @unknown default:
                return ""
            }
        } catch {
            return "결제하지 못했어요. 잠시 뒤 다시 해 주세요."
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
        if ProcessInfo.processInfo.arguments.contains("-ui-demo") { owned = true }
        #endif
        let changed = owned != isPlus
        isPlus = owned
        UserDefaults.standard.set(owned, forKey: Self.cacheKey)
        // 위젯·워치가 잠금 여부를 알 수 있게 요약을 다시 쓴다.
        if changed { WidgetBridge.refreshFromStore() }
    }
}
