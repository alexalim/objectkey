import SwiftData
import SwiftUI

@main
struct ObjectKeyApp: App {
    @State private var store = ActivityStore()
    @State private var showSplash = true
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            // 홈은 뒤에서 미리 준비하고, 첫 화면을 누르면 걷어낸다.
            ZStack {
                HomeView()
                if showSplash {
                    SplashView { withAnimation(.easeOut(duration: 0.3)) { showSplash = false } }
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .environment(store)
            // 앱을 완전히 새로 켤 때만이 아니라, 홈 화면으로 나갔다가 다시 열 때도 보여 준다.
            // 제어 센터를 내리는 정도(inactive)로는 다시 띄우지 않는다.
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { showSplash = true }
            }
        }
        .modelContainer(for: [KeyObject.self, ReferenceShot.self, ActivityLog.self])
    }
}
