#if DEBUG
import SwiftUI

/// 화면 점검용: 위젯과 잠금 화면 현황을 앱 안에서 실제 크기로 그려 본다(-ui-widgets). 출시 빌드에는 없다.
struct WidgetGalleryView: View {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-ui-widgets") }

    var body: some View {
        let s = WidgetSnapshot.sample
        var allDone = s; allDone.items = s.items.map { var i = $0; i.done = true; return i }; allDone.mood = "success"
        let left = TodayActivityAttributes.ContentState(remaining: 2, total: 3, nextID: s.items[1].id.uuidString, nextName: "읽는 책",
                                                         nextEmoji: "📚", atRiskName: nil, dayEnd: .now.addingTimeInterval(5 * 3600), mood: "peek")
        let risk = TodayActivityAttributes.ContentState(remaining: 1, total: 3, nextID: s.items[2].id.uuidString, nextName: "아이스하키 수업",
                                                         nextEmoji: "🏒", atRiskName: "아이스하키 수업", dayEnd: .now.addingTimeInterval(2 * 3600), mood: "question")
        let done = TodayActivityAttributes.ContentState(remaining: 0, total: 3, nextID: nil, nextName: "", nextEmoji: "",
                                                         atRiskName: nil, dayEnd: .now.addingTimeInterval(5 * 3600), mood: "success")
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("홈 화면 위젯").font(.headline)
                    HStack(spacing: 12) {
                        widget(TodaySmallView(snapshot: s), width: 158)
                        widget(TodaySmallView(snapshot: allDone), width: 158)
                    }
                    widget(TodayMediumView(snapshot: s), width: 338)
                    Text("잠금 화면 현황").font(.headline)
                    lock(TodayLockView(state: left))
                    lock(TodayLockView(state: risk))
                    lock(TodayLockView(state: done))
                }
                .padding()
            }
            .navigationTitle("위젯 미리보기")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func widget<V: View>(_ v: V, width: CGFloat) -> some View {
        v.padding(16).frame(width: width, height: 158)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22))
            .shadow(radius: 4, y: 2)
    }

    private func lock<V: View>(_ v: V) -> some View {
        v.frame(width: 360).background(Color(.systemBackground).opacity(0.9), in: RoundedRectangle(cornerRadius: 22)).shadow(radius: 4, y: 2)
    }
}
#endif
