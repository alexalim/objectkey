import Foundation
import WatchConnectivity

/// 아이폰 ↔ 워치. 오늘 요약을 워치로 보내고, 워치에서 누른 기록을 받아 단축어와 같은 경로로 남긴다.
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    /// 앱이 켜질 때 바로 부른다. 워치 기록 때문에 앱이 뒤에서 깨어날 때도 이 경로로 받는다.
    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// 워치에 최신 요약을 보낸다. 같은 내용이면 시스템이 알아서 합친다.
    func push(_ snapshot: WidgetSnapshot) {
        let session = WCSession.default
        guard WCSession.isSupported(), session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        try? session.updateApplicationContext(["snapshot": data])
        // 시계 화면에 컴플리케이션이 있으면 워치 앱을 깨워 바로 다시 그리게 한다(하루 횟수 제한이 있어 남았을 때만).
        if session.isComplicationEnabled, session.remainingComplicationUserInfoTransfers > 0 {
            session.transferCurrentComplicationUserInfo(["snapshot": data])
        }
    }

    private func handle(_ message: [String: Any]) {
        if message["want"] != nil {
            // 워치가 요약이 없다고 알려 오면 바로 보낸다(예: 워치 앱을 막 설치했을 때).
            Task { @MainActor in WidgetBridge.refreshFromStore() }
            return
        }
        guard let id = message["record"] as? String else { return }
        // 워치에서 누른 때. 아이폰이 멀리 있다가 다음 날 받아도 누른 날로 남긴다(옛 워치 앱은 없어서 지금으로).
        let tapped = (message["at"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? .now
        Task { @MainActor in WidgetBridge.record(id, at: min(tapped, .now)) }
    }

    /// 워치 앱이 설치되거나 짝이 바뀌면 바로 요약을 보낸다. 안 그러면 아이폰 앱을 다시 켤 때까지 워치가 비어 있다.
    func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in WidgetBridge.refreshFromStore() }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in WidgetBridge.refreshFromStore() }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { handle(message) }

    /// 워치가 답장을 기다리는 요청. "want"면 최신 요약을 바로 돌려준다(앱이 꺼져 있어도 iOS가 깨워 준다).
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard message["want"] != nil else { handle(message); replyHandler([:]); return }
        Task { @MainActor in
            WidgetBridge.refreshFromStore()
            if let data = try? JSONEncoder().encode(WidgetSnapshot.load() ?? WidgetSnapshot(day: .now, items: [], plus: PlusStore.shared.isPlus)) {
                replyHandler(["snapshot": data])
            } else {
                replyHandler([:])
            }
        }
    }

    /// 아이폰과 워치가 다시 가까워지면 최신 요약을 보낸다.
    func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in WidgetBridge.refreshFromStore() }
    }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { handle(userInfo) }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
