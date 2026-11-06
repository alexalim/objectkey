import SwiftData
import SwiftUI

/// 하단 탭: 오늘 · 습관 · (+) · 통계 · 마이. 기록 목록은 통계 안 "전체 기록 보기"에 있다.
/// 가운데 +는 화면을 바꾸는 탭이 아니라 "새로 만들기" 시트를 연다. 어느 탭에서든 같은 자리에서 시작한다.
struct RootView: View {
    enum Tab: Hashable { case today, objects, add, stats, my }

    @Environment(ActivityStore.self) private var store
    @State private var tab: Tab = .today
    @State private var showAdd = false
    @State private var route = NotificationRoute.shared

    var body: some View {
        TabView(selection: Binding(get: { tab }, set: { new in
            // + 탭은 고르지 않고 시트만 연다. 보고 있던 탭은 그대로 둔다.
            if new == .add { showAdd = true } else { tab = new }
        })) {
            HomeView()
                .tabItem { Label("오늘", systemImage: "checklist") }
                .tag(Tab.today)
            NavigationStack { ObjectsView() }
                .tabItem { Label("습관", systemImage: "square.grid.2x2") }
                .tag(Tab.objects)
            Color.clear
                .tabItem { Label("새로 만들기", systemImage: "plus.circle.fill") }
                .tag(Tab.add)
            NavigationStack { StatsView() }
                .tabItem { Label("통계", systemImage: "chart.bar.xaxis") }
                .tag(Tab.stats)
            NavigationStack { MyView() }
                .tabItem { Label("마이", systemImage: "person.crop.circle") }
                .tag(Tab.my)
        }
        .sheet(isPresented: $showAdd) { QuickAddSheet() }
        // 알림을 눌러 들어오면 오늘 탭에서 그 물건을 연다(홈이 route를 받아 상세를 띄운다).
        .onChange(of: route.keyID, initial: true) { _, id in
            if id != nil { showAdd = false; tab = .today }
        }
        .onChange(of: route.openStats, initial: true) { _, open in
            guard open else { return }
            showAdd = false
            tab = .stats
            route.openStats = false
        }
    }
}

/// 가운데 + 시트. 사진 등록 · 이름만 등록 · 한 문장으로 적기 세 길을 같은 무게로 보여 준다.
/// 카메라 권한은 여기서 묻지 않는다. "사진 찍어 등록"을 고른 뒤에 묻는다.
struct QuickAddSheet: View {
    private enum Route: Identifiable {
        case register(photos: Bool), ask
        var id: String {
            switch self {
            case .register(let photos): photos ? "photos" : "plain"
            case .ask: "ask"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Query private var keys: [KeyObject]
    @State private var route: Route?
    @State private var plus = PlusStore.shared
    /// 무료 범위를 넘을 때 보여 줄 플러스 안내 이유.
    @State private var paywallReason: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                option("camera", "사진 찍어 등록", "물건을 찍어 두면 스캔으로 알아봐요") { open(.register(photos: true)) }
                option("square.and.pencil", "이름만 적어 등록", "카메라 없이 바로 시작해요") { open(.register(photos: false)) }
                // "말"은 음성 인식으로 오해하기 쉬워 "적기"라고 쓴다. 등록뿐 아니라 기록·질문도 된다.
                // 기기 안 AI가 필요해 iOS 26 이상에서만 보여 준다.
                if #available(iOS 26.0, *) {
                option("sparkles", "한 문장으로 적기", "\"화요일 9시 아이스하키 90분\", \"어제 책 30분 읽었어\"") { open(.ask) }
                }
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("어떻게 시작할까요?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
        .presentationDetents([.medium])
        .sheet(isPresented: Binding(get: { paywallReason != nil }, set: { if !$0 { paywallReason = nil } })) {
            PlusPaywall(reason: paywallReason)
        }
        .sheet(item: $route) { r in
            switch r {
            case .register(let photos):
                RegisterView(startWithPhotos: photos) { dismiss() }
            case .ask:
                if #available(iOS 26.0, *) {
                    AskMokiView()
                } else {
                    ContentUnavailableView("iOS 26 이상에서 쓸 수 있어요", systemImage: "sparkles",
                                           description: Text("한 문장으로 적기는 휴대폰의 Apple Intelligence로 처리해요."))
                        .presentationDetents([.medium])
                }
            }
        }
    }

    /// 무료는 습관 3개까지, 한 문장으로 적기는 플러스. 넘으면 플러스 안내를 연다.
    private func open(_ r: Route) {
        switch r {
        case .register where !plus.canAddHabit(currentCount: keys.count):
            paywallReason = "무료로는 습관을 \(PlusStore.freeHabitLimit)개까지 만들 수 있어요."
        case .ask where !plus.isPlus:
            paywallReason = "한 문장으로 적기는 플러스에서 쓸 수 있어요."
        default:
            route = r
        }
    }

    private func option(_ icon: String, _ title: String, _ detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title3).frame(width: 40, height: 40)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .tint(.primary)
    }
}
