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
    }

    private func handle(_ message: [String: Any]) {
        guard let id = message["record"] as? String else { return }
        Task { @MainActor in WidgetBridge.record(id) }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in WidgetBridge.refreshFromStore() }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { handle(message) }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { handle(userInfo) }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
