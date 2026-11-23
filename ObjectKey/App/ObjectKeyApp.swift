import SwiftData
import SwiftUI
import ObjectKeyCore
import UserNotifications

@main
struct ObjectKeyApp: App {
    @State private var store = ActivityStore.shared
    @State private var showSplash = true
    @State private var route = NotificationRoute.shared
    /// 소개를 한 번 끝까지 봤거나 건너뛰었는지.
    @AppStorage("didFinishOnboarding") private var didFinishOnboarding = false
    /// 맛보기가 끝났다는 안내를 이미 보여 줬는지. 한 번만 알린다.
    @AppStorage("trialEndNoticeShown") private var trialEndNoticeShown = false
    @State private var showTrialEnded = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // 알림의 "참석" 버튼은 앱이 꺼져 있어도 이 처리기로 들어온다. 실행 직후에 연결해야 놓치지 않는다.
        UNUserNotificationCenter.current().delegate = NotificationHandler.shared
        // 위젯 체크 버튼은 앱을 뒤에서 깨워 이 경로로 기록한다.
        WidgetActions.record = { WidgetBridge.record($0) }
        // 워치에서 누른 기록도 앱이 뒤에서 깨어나 받는다.
        WatchBridge.shared.activate()
        // 플러스 구매 여부 확인과, 다른 기기·환불로 바뀐 거래 듣기.
        PlusStore.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            // 홈은 뒤에서 미리 준비하고, 첫 화면을 누르면 걷어낸다.
            root
                .environment(store)
                // 처음 설치하면 시작 화면을 누른 뒤 소개를 한 번 보여 준다.
                .fullScreenCover(isPresented: Binding(get: { !showSplash && !didFinishOnboarding },
                                                      set: { if !$0 { didFinishOnboarding = true } })) {
                    OnboardingView(onFinish: { didFinishOnboarding = true },
                                   onCreateFirst: { didFinishOnboarding = true; NotificationRoute.shared.openRegister = true })
                }
            // 앱을 완전히 새로 켤 때만이 아니라, 홈 화면으로 나갔다가 다시 열 때도 보여 준다.
            // 제어 센터를 내리는 정도(inactive)로는 다시 띄우지 않는다.
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { showSplash = true }
                // 맛보기가 끝났는지는 앱이 앞으로 올 때 다시 본다(끝나면 위젯·워치도 이때 잠긴다).
                if phase == .active {
                    Task {
                        await PlusStore.shared.refresh()
                        if PlusStore.shared.access == .trialUsed, !trialEndNoticeShown {
                            trialEndNoticeShown = true
                            showTrialEnded = true
                        }
                    }
                }
            }
            .sheet(isPresented: $showTrialEnded) {
                PlusPaywall(reason: "\(PlusTrial.days)일 맛보기가 끝났어요. 만든 습관과 기록은 그대로예요. 위젯·잠금 화면·워치·자세한 통계를 계속 쓰려면 플러스를 열어 주세요.")
            }
            // 알림을 눌러 들어오면 시작 화면 없이 그 물건으로 바로 간다.
            .onChange(of: route.skipSplash, initial: true) { _, skip in
                guard skip else { return }
                showSplash = false
                route.skipSplash = false
            }
        }
        .modelContainer(AppModel.container)
    }

    @ViewBuilder
    private var root: some View {
        let content = ZStack {
            RootView()
            if showSplash {
                SplashView { withAnimation(.easeOut(duration: 0.3)) { showSplash = false } }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        #if DEBUG
        // UI 테스트: 실제 저장소 대신 데모 데이터가 든 메모리 저장소를 쓴다. -ui-widgets면 위젯 미리보기만 띄운다.
        if WidgetGalleryView.isEnabled { WidgetGalleryView() }
        else if DemoData.isEnabled { content.modelContainer(DemoData.container) } else { content }
        #else
        content
        #endif
    }
}
