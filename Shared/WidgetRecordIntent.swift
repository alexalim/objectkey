import AppIntents
import Foundation

/// 위젯의 체크 버튼. LiveActivityIntent라서 위젯이 아니라 앱 프로세스에서 실행된다(앱 저장소에 기록해야 하므로).
struct WidgetRecordIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "MOKI 위젯에서 기록"
    static let isDiscoverable = false

    @Parameter(title: "물건 ID")
    var keyID: String

    init() {}

    init(keyID: UUID) {
        self.keyID = keyID.uuidString
    }

    func perform() async throws -> some IntentResult {
        await MainActor.run { WidgetActions.record?(keyID) }
        return .result()
    }
}

/// 앱이 실행되면서 기록 방법을 꽂아 둔다. 위젯 확장에서는 비어 있다.
@MainActor
enum WidgetActions {
    static var record: ((String) -> Void)?
}
