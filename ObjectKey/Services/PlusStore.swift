import Foundation
import Observation
import OSLog
import StoreKit
import UIKit
import ObjectKeyCore

/// MOKI 플러스(평생 이용권, 비소모성 인앱 구매). 무료는 습관 3개까지, 플러스는 제한 없음과 편의 기능.
/// 구매 여부는 StoreKit의 현재 권한(Transaction.currentEntitlements)이 기준이고, 위젯·워치가 볼 수 있게 스냅숏에도 적는다.
@MainActor
@Observable
final class PlusStore {
    static let shared = PlusStore()
    static let productID = "com.aspynlim.moki.plus"
    /// 7일 맛보기. 0원 비소모성 상품이라 Apple 계정에 한 번만 남고, 받은 때(purchaseDate)부터 센다.
    static let trialID = "com.aspynlim.moki.trial7"
    /// 무료로 만들 수 있는 습관 수. 이미 더 있는 사람은 그대로 쓰고, 새로 더하는 것만 막는다.
    static let freeHabitLimit = 3

    /// 플러스 기능이 열려 있는지(샀거나 맛보기 중). 기능 잠금은 모두 이것으로 판단한다.
    private(set) var isPlus: Bool
    /// 평생 이용권을 샀는지. 맛보기 중에도 결제 버튼은 보여야 해서 따로 둔다.
    private(set) var owned: Bool
    /// 맛보기를 시작한 때. 없으면 아직 안 썼다.
    private(set) var trialStarted: Date?
    private(set) var product: Product?
    private(set) var trialProduct: Product?
    /// 상품 정보를 못 받았을 때의 이유(심사·네트워크). 결제 화면에 보여 준다.
    private(set) var loadProblem: String?

    private static let cacheKey = "moki.plus.cached"
    private static let trialKey = "moki.plus.trialStarted"
    private var updates: Task<Void, Never>?
    /// 결제가 진행 중인지. 로그인 시트가 오래 떠 있는 동안 다시 눌러도 두 번째 결제를 시작하지 않는다.
    private(set) var purchasing = false

    init() {
        // 실행 직후 권한을 다시 확인하기 전까지는 마지막으로 확인한 값을 쓴다(위젯 깜빡임 방지).
        owned = UserDefaults.standard.bool(forKey: Self.cacheKey)
        trialStarted = UserDefaults.standard.object(forKey: Self.trialKey) as? Date
        isPlus = PlusTrial.access(owned: owned, trialStarted: trialStarted, now: .now).grantsPlus
        #if DEBUG
        // UI 테스트는 결제 없이 모든 화면을 돈다. -ui-free면 무료 상태(결제 화면 확인용).
        if Self.demoPlus { owned = true; isPlus = true }
        #endif
    }

    var access: PlusAccess { PlusTrial.access(owned: owned, trialStarted: trialStarted, now: .now) }

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
            let products = try await Product.products(for: [Self.productID, Self.trialID])
            product = products.first { $0.id == Self.productID }
            trialProduct = products.first { $0.id == Self.trialID }
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
        guard !purchasing else { return "아직 결제가 진행 중이에요. 뜬 창을 마무리해 주세요." }
        purchasing = true
        defer { purchasing = false }
        log.info("purchase start \(product.id, privacy: .public)")
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
                // 검증된 거래를 손에 쥐었으니 바로 연다. 권한 목록 갱신 시점에 기대지 않는다.
                if transaction.productID == Self.productID { setAccess(owned: true, trialStarted: trialStarted) }
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

    /// 7일 맛보기 시작. 0원 결제 창이 뜬다. 끝나면 결과 문구(시작했으면 nil).
    /// 플러스 결제와 길을 나눈다: 맛보기 거래로 "샀다"고 표시하면 7일 뒤에도 잠기지 않는다.
    func startTrial() async -> String? {
        guard let trialProduct else { return "지금은 맛보기를 불러오지 못했어요. 잠시 뒤 다시 해 주세요." }
        guard !purchasing else { return "아직 진행 중이에요. 뜬 창을 마무리해 주세요." }
        purchasing = true
        defer { purchasing = false }
        do {
            switch try await trialProduct.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                setAccess(owned: owned, trialStarted: transaction.purchaseDate)
                return nil
            case .success:
                return "맛보기를 확인하지 못했어요. 구매 복원을 눌러 주세요."
            case .pending:
                return "승인을 기다리고 있어요. 승인되면 자동으로 열려요."
            case .userCancelled:
                return "맛보기를 시작하지 않았어요."
            @unknown default:
                return "결과를 알 수 없어요. 구매 복원을 눌러 확인해 주세요."
            }
        } catch {
            return "맛보기를 시작하지 못했어요. (\(error.localizedDescription))"
        }
    }

    /// 구매 복원. 같은 Apple 계정으로 산 적이 있으면 다시 열린다.
    /// 로그인 창을 닫거나 네트워크가 끊겨 동기화가 안 됐을 때 "산 기록 없음"으로 잘못 말하지 않는다.
    func restore() async -> String {
        do {
            try await AppStore.sync()
        } catch {
            await refresh()
            if isPlus { return "플러스를 다시 열었어요." }
            return "복원을 마치지 못했어요. 다시 해 주세요. (\(error.localizedDescription))"
        }
        await refresh()
        return isPlus ? "플러스를 다시 열었어요." : "이 Apple 계정으로 산 기록을 찾지 못했어요."
    }

    private func setAccess(owned: Bool, trialStarted: Date?) {
        let unlocked = PlusTrial.access(owned: owned, trialStarted: trialStarted, now: .now).grantsPlus
        let changed = unlocked != isPlus
        self.owned = owned
        self.trialStarted = trialStarted
        isPlus = unlocked
        UserDefaults.standard.set(owned, forKey: Self.cacheKey)
        UserDefaults.standard.set(trialStarted, forKey: Self.trialKey)
        // 위젯·워치가 잠금 여부를 알 수 있게 요약을 다시 쓴다(맛보기가 끝났을 때도 여기서 잠긴다).
        if changed { WidgetBridge.refreshFromStore() }
    }

    /// 권한 다시 읽기. 앱이 앞으로 올 때마다 부른다: 맛보기가 끝났으면 이때 잠긴다.
    /// 맛보기 거래는 7일이 지나도 권한 목록에 남는다. 그래서 "썼다"는 표시로만 쓰고, 열지는 않는다.
    func refresh() async {
        var owned = false
        var trial: Date?
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let t) = entitlement, t.revocationDate == nil else { continue }
            if t.productID == Self.productID { owned = true }
            if t.productID == Self.trialID { trial = t.purchaseDate }
        }
        #if DEBUG
        if Self.demoPlus { owned = true }
        #endif
        setAccess(owned: owned, trialStarted: trial ?? trialStarted)
    }
}
