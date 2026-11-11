import Foundation
import WatchConnectivity
import WidgetKit

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
        #if DEBUG
        // 화면 점검용: 아이폰 없이도 보기용 목록을 띄운다(App Store 워치 스크린샷).
        if ProcessInfo.processInfo.arguments.contains("-ui-demo") { snapshot = .sample }
        #endif
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    var today: WidgetSnapshot? { snapshot?.current() }
    /// 마지막으로 아이폰에서 목록을 받은 때. 화면에 "방금 받음"처럼 보여 준다.
    @Published private(set) var receivedAt: Date? = UserDefaults.standard.object(forKey: "moki.watch.receivedAt") as? Date

    /// 아이폰에 최신 목록을 달라고 한다. 워치 앱을 열 때와 새로고침 버튼에서 부른다.
    /// 연결돼 있으면 바로 답을 받고, 아니면 요청을 쌓아 뒀다가 아이폰이 깨어날 때 받는다.
    func requestSnapshot() {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(["want": "snapshot"], replyHandler: { reply in
                Task { @MainActor in self.receive(reply) }
            }, errorHandler: { _ in session.transferUserInfo(["want": "snapshot"]) })
        } else {
            session.transferUserInfo(["want": "snapshot"])
        }
    }

    /// 기록 요청. 아이폰 앱이 꺼져 있어도 transferUserInfo는 쌓였다가 전달된다.
    func record(_ id: UUID) {
        // 누른 때를 같이 보낸다. 아이폰과 떨어져 있다가 나중에 전달돼도 누른 날로 기록된다.
        let payload: [String: Any] = ["record": id.uuidString, "at": Date.now.timeIntervalSince1970]
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

    private func apply(_ s: WidgetSnapshot, fromPhone: Bool = false) {
        snapshot = s
        if fromPhone {
            receivedAt = .now
            UserDefaults.standard.set(receivedAt, forKey: "moki.watch.receivedAt")
        }
        if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: Self.cacheKey) }
        // 시계 화면 컴플리케이션이 읽도록 워치 안 공유 공간에도 쓰고 다시 그리게 한다.
        s.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    fileprivate func receive(_ context: [String: Any]) {
        guard let data = context["snapshot"] as? Data,
              let s = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return }
        apply(s, fromPhone: true)
    }
}

extension WatchStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        let reachable = session.isReachable
        // 받은 요약이 없으면(막 설치한 경우 등) 아이폰에 달라고 한다.
        if context["snapshot"] == nil {
            if reachable { session.sendMessage(["want": "snapshot"], replyHandler: nil) } else { session.transferUserInfo(["want": "snapshot"]) }
        }
        Task { @MainActor in
            self.reachable = reachable
            self.receive(context)
        }
    }

    /// 컴플리케이션용 전송(아이폰이 기록하면 워치 앱을 깨워 보낸다).
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in self.receive(userInfo) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.receive(applicationContext) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.reachable = reachable }
    }
}
