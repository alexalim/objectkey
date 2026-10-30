import SwiftData
import SwiftUI

@main
struct ObjectKeyApp: App {
    @State private var store = ActivityStore()
    @State private var showSplash = true

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
        }
        .modelContainer(for: [KeyObject.self, ReferenceShot.self, ActivityLog.self])
    }
}
