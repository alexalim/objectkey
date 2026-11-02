import SwiftData
import SwiftUI
import UserNotifications

@main
struct ObjectKeyApp: App {
    @State private var store = ActivityStore.shared
    @State private var showSplash = true
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // 알림의 "참석" 버튼은 앱이 꺼져 있어도 이 처리기로 들어온다. 실행 직후에 연결해야 놓치지 않는다.
        UNUserNotificationCenter.current().delegate = NotificationHandler.shared
    }

    var body: some Scene {
        WindowGroup {
            // 홈은 뒤에서 미리 준비하고, 첫 화면을 누르면 걷어낸다.
            root
                .environment(store)
            // 앱을 완전히 새로 켤 때만이 아니라, 홈 화면으로 나갔다가 다시 열 때도 보여 준다.
            // 제어 센터를 내리는 정도(inactive)로는 다시 띄우지 않는다.
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { showSplash = true }
            }
        }
        .modelContainer(AppModel.container)
    }

    @ViewBuilder
    private var root: some View {
        let content = ZStack {
            HomeView()
            if showSplash {
                SplashView { withAnimation(.easeOut(duration: 0.3)) { showSplash = false } }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        #if DEBUG
        // UI 테스트: 실제 저장소 대신 데모 데이터가 든 메모리 저장소를 쓴다.
        if DemoData.isEnabled { content.modelContainer(DemoData.container) } else { content }
        #else
        content
        #endif
    }
}
