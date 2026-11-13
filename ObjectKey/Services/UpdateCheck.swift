import Foundation
import Observation
import ObjectKeyCore

/// 앱스토어에 새 버전이 있는지 확인한다. 시작 화면에서 한 줄로 알려 주기만 하고 막지는 않는다.
/// Apple의 공개 조회 API에 번들 ID만 보낸다. 개인정보는 가지 않는다.
@MainActor
@Observable
final class UpdateCheck {
    static let shared = UpdateCheck()

    /// 지금 깐 버전보다 새 버전이 앱스토어에 있을 때만 채워진다.
    private(set) var latest: String?
    let storeURL = URL(string: "https://apps.apple.com/kr/app/id6828238769")!

    /// 너무 자주 묻지 않는다. 앱스토어 조회 결과는 어차피 몇 시간 단위로 바뀐다.
    private static let interval: TimeInterval = 6 * 3600
    private static let lastKey = "updateCheck.lastAt"
    private static let latestKey = "updateCheck.latest"
    private var running = false

    private init() {
        #if DEBUG
        // UI 테스트: 조회 없이 "-ui-update 9.9" 같은 인자로 안내 줄을 띄운다.
        if let forced = Self.forcedVersion { latest = forced; return }
        #endif
        // 지난번 결과를 먼저 보여 준다. 그 사이 업데이트했으면 현재 버전과 비교해 걸러진다.
        apply(UserDefaults.standard.string(forKey: Self.latestKey))
    }

    #if DEBUG
    private static var forcedVersion: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-ui-update"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    #endif

    static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    func check(now: Date = .now) async {
        guard !running else { return }
        #if DEBUG
        // 데모·테스트 실행에서는 진짜 앱스토어에 묻지 않는다.
        if Self.forcedVersion != nil || DemoData.isEnabled { return }
        #endif
        let last = UserDefaults.standard.object(forKey: Self.lastKey) as? Date ?? .distantPast
        guard now.timeIntervalSince(last) >= Self.interval else { return }
        running = true
        defer { running = false }
        guard let id = Bundle.main.bundleIdentifier,
              let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(id)&country=kr") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        // 실패하면 조용히 넘어간다. 다음에 열 때 다시 묻는다.
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let version = Self.parse(data) else { return }
        UserDefaults.standard.set(now, forKey: Self.lastKey)
        UserDefaults.standard.set(version, forKey: Self.latestKey)
        apply(version)
    }

    /// 조회 응답에서 버전만 꺼낸다. 결과가 비어 있으면(아직 등록 전·조회 실패) nil.
    static func parse(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let version = results.first?["version"] as? String else { return nil }
        return version
    }

    private func apply(_ version: String?) {
        latest = version.flatMap { AppVersion.isNewer($0, than: Self.current) ? $0 : nil }
    }
}
