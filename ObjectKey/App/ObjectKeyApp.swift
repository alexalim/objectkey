import SwiftData
import SwiftUI
import UserNotifications

@main
struct ObjectKeyApp: App {
    @State private var store = ActivityStore.shared
    @State private var showSplash = true
    /// 소개를 한 번 끝까지 봤거나 건너뛰었는지.
    @AppStorage("didFinishOnboarding") private var didFinishOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // 알림의 "참석" 버튼은 앱이 꺼져 있어도 이 처리기로 들어온다. 실행 직후에 연결해야 놓치지 않는다.
        UNUserNotificationCenter.current().delegate = NotificationHandler.shared
        // 위젯 체크 버튼은 앱을 뒤에서 깨워 이 경로로 기록한다.
        WidgetActions.record = { WidgetBridge.record($0) }
        // 워치에서 누른 기록도 앱이 뒤에서 깨어나 받는다.
        WatchBridge.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            // 홈은 뒤에서 미리 준비하고, 첫 화면을 누르면 걷어낸다.
            root
                .environment(store)
                // 처음 설치하면 시작 화면을 누른 뒤 소개를 한 번 보여 준다.
                .fullScreenCover(isPresented: Binding(get: { !showSplash && !didFinishOnboarding },
                                                      set: { if !$0 { didFinishOnboarding = true } })) {
                    OnboardingView { didFinishOnboarding = true }
                }
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
