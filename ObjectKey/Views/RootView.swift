import SwiftUI

/// 하단 탭: 오늘 · 내 물건 · (+) · 기록 · 마이.
/// 가운데 +는 화면을 바꾸는 탭이 아니라 "새로 만들기" 시트를 연다. 어느 탭에서든 같은 자리에서 시작한다.
struct RootView: View {
    enum Tab: Hashable { case today, objects, add, history, my }

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
                .tabItem { Label("내 물건", systemImage: "square.grid.2x2") }
                .tag(Tab.objects)
            Color.clear
                .tabItem { Label("새로 만들기", systemImage: "plus.circle.fill") }
                .tag(Tab.add)
            NavigationStack { HistoryView() }
                .tabItem { Label("기록", systemImage: "calendar") }
                .tag(Tab.history)
            NavigationStack { MyView() }
                .tabItem { Label("마이", systemImage: "person.crop.circle") }
                .tag(Tab.my)
        }
        .sheet(isPresented: $showAdd) { QuickAddSheet() }
        // 알림을 눌러 들어오면 오늘 탭에서 그 물건을 연다(홈이 route를 받아 상세를 띄운다).
        .onChange(of: route.keyID, initial: true) { _, id in
            if id != nil { showAdd = false; tab = .today }
        }
    }
}

/// 가운데 + 시트. 사진 등록 · 이름만 등록 · 말로 등록 세 길을 같은 무게로 보여 준다.
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
    @State private var route: Route?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                option("camera", "사진 찍어 등록", "물건을 찍어 두면 스캔으로 알아봐요") { route = .register(photos: true) }
                option("square.and.pencil", "이름만 적어 등록", "카메라 없이 바로 시작해요") { route = .register(photos: false) }
                option("sparkles", "말로 등록", "\"화요일 9시 아이스하키 90분\"처럼 한 문장으로") { route = .ask }
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("어떻게 시작할까요?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
        .presentationDetents([.medium])
        .sheet(item: $route) { r in
            switch r {
            case .register(let photos):
                RegisterView(startWithPhotos: photos) { dismiss() }
            case .ask:
                if #available(iOS 26.0, *) {
                    AskMokiView()
                } else {
                    ContentUnavailableView("iOS 26 이상에서 쓸 수 있어요", systemImage: "sparkles",
                                           description: Text("말로 등록은 기기 안 AI(Apple Intelligence)로 동작해요."))
                        .presentationDetents([.medium])
                }
            }
        }
    }

    private func option(_ icon: String, _ title: String, _ detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title3).frame(width: 40, height: 40)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
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
