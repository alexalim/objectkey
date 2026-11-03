import Foundation
import WatchConnectivity

/// 워치 쪽 상태. 아이폰이 보낸 오늘 요약을 보여 주고, 누른 기록을 아이폰으로 보낸다.
/// 워치는 아이폰의 공유 공간을 읽을 수 없어서 WatchConnectivity로 주고받는다.
@MainActor
final class WatchStore: NSObject, ObservableObject {
    @Published private(set) var snapshot: WidgetSnapshot?
    @Published private(set) var reachable = false

    private static let cacheKey = "moki.watch.snapshot"

    override init() {
        super.init()
        // 아이폰과 연결이 없어도 마지막으로 받은 목록은 보여 준다.
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey) {
            snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    var today: WidgetSnapshot? { snapshot?.current() }

    /// 기록 요청. 아이폰 앱이 꺼져 있어도 transferUserInfo는 쌓였다가 전달된다.
    func record(_ id: UUID) {
        let payload = ["record": id.uuidString]
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in session.transferUserInfo(payload) }
        } else {
            session.transferUserInfo(payload)
        }
        // 아이폰이 새 요약을 보낼 때까지 먼저 완료로 보여 준다.
        if var s = snapshot, let i = s.items.firstIndex(where: { $0.id == id }) {
            s.items[i].done = true
            apply(s)
        }
    }

    private func apply(_ s: WidgetSnapshot) {
        snapshot = s
        if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: Self.cacheKey) }
    }

    fileprivate func receive(_ context: [String: Any]) {
        guard let data = context["snapshot"] as? Data,
              let s = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return }
        apply(s)
    }
}

extension WatchStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        let reachable = session.isReachable
        Task { @MainActor in
            self.reachable = reachable
            self.receive(context)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.receive(applicationContext) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.reachable = reachable }
    }
}
