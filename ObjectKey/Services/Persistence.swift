import OSLog
import SwiftData
import UIKit

extension ModelContext {
    /// 저장하고, 실패하면 조용히 넘기지 않는다. 로그를 남기고 바꾼 내용을 되돌린 뒤 사용자에게 알린다.
    /// 되돌리지 않으면 화면에는 남아 있다가 앱을 다시 켜면 사라져, 저장된 줄 알게 된다.
    @MainActor
    @discardableResult
    func saveOrReport() -> Bool {
        do {
            try save()
            return true
        } catch {
            Logger(subsystem: "com.aspynlim.moki", category: "store").error("save failed: \(error.localizedDescription, privacy: .public)")
            rollback()
            AppAlert.show("저장하지 못했어요", message: "방금 바꾼 내용이 저장되지 않았어요. 저장 공간을 확인하고 다시 해 주세요.")
            return false
        }
    }
}

/// 어느 화면에서든 띄우는 알림창. 시트가 떠 있어도 가장 위 화면에 띄운다.
/// 화면이 없을 때(위젯·워치 기록으로 뒤에서 깨어났을 때)는 띄우지 않는다.
@MainActor
enum AppAlert {
    static func show(_ title: String, message: String) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard var top = scene?.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default))
        top.present(alert, animated: true)
    }
}
