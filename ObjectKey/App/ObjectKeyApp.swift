import SwiftData
import SwiftUI

@main
struct ObjectKeyApp: App {
    @State private var store = ActivityStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(store)
        }
        .modelContainer(for: [KeyObject.self, ReferenceShot.self, ActivityLog.self])
    }
}
