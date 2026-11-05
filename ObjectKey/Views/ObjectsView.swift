import SwiftData
import SwiftUI
import ObjectKeyCore

/// 내 물건. 같은 물건을 쓰는 습관끼리 묶어 2열 카드로 보고, 누르면 그 물건의 습관 목록을 연다.
struct ObjectsView: View {
    @Environment(ActivityStore.self) private var store
    @Query(sort: \KeyObject.createdAt) private var keys: [KeyObject]
    @State private var search = ""
    @State private var openedOwner: KeyObject?
    @State private var showRegister = false

    /// 물건별 묶음(주인 습관이 맨 앞). 검색어가 습관 이름이나 태그에 걸리면 그 물건을 보여 준다.
    private var shown: [[KeyObject]] {
        let byID = Dictionary(uniqueKeysWithValues: keys.map { ($0.id, $0) })
        let groups = SharedObject.groups(keys.map(\.sharedHabit)).map { $0.compactMap { byID[$0] } }
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return groups }
        return groups.filter { group in
            group.contains { $0.name.localizedCaseInsensitiveContains(q) || $0.tags.contains { $0.localizedCaseInsensitiveContains(q) } }
        }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(shown, id: \.first?.id) { group in
                    if let owner = group.first {
                        Button { openedOwner = owner } label: { card(owner, habits: group) }
                            .tint(.primary)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("내 물건")
        .searchable(text: $search, prompt: "이름이나 태그")
        .overlay {
            if keys.isEmpty {
                ContentUnavailableView {
                    Image(.peek).resizable().scaledToFit().frame(height: 140)
                    Text("아직 등록한 물건이 없어요")
                } description: {
                    Text("카메라 없이 이름만 적어도 괜찮아요.")
                } actions: {
                    Button("첫 물건 등록하기") { showRegister = true }.buttonStyle(.borderedProminent)
                }
            } else if shown.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .sheet(item: $openedOwner) { ObjectSheet(owner: $0) }
        .sheet(isPresented: $showRegister) { RegisterView() }
    }

    private func card(_ key: KeyObject, habits: [KeyObject]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                KeyBadge(symbol: key.emoji, size: 48)
                Spacer()
                if habits.contains(where: { store.state.activeKeyID == $0.id }) {
                    Image(systemName: "record.circle").foregroundStyle(.red).accessibilityLabel("기록 중")
                }
            }
            Text(key.name).font(.headline).lineLimit(1)
            Text(habits.count > 1 ? "습관 \(habits.count)개" : key.actionTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Label(key.shots.isEmpty ? "사진 없음" : "사진 \(key.shots.count)장",
                  systemImage: key.shots.isEmpty ? "camera" : "camera.fill")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

/// 물건 상세. 이 물건에 연결한 습관들을 보고, 습관을 더하거나 각 습관의 기록·설정을 연다.
struct ObjectSheet: View {
    let owner: KeyObject

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \KeyObject.createdAt) private var keys: [KeyObject]
    @State private var detailKey: KeyObject?
    @State private var runKey: KeyObject?
    @State private var addingHabit = false
    @State private var plus = PlusStore.shared
    @State private var showPaywall = false

    var body: some View {
        let habits = owner.objectMembers(in: keys)
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        KeyBadge(symbol: owner.emoji, size: 72)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(owner.name).font(.title3.bold())
                            Label(owner.shots.isEmpty ? "사진 없음 · 스캔 대신 눌러서 해요" : "사진 \(owner.shots.count)장 · 스캔으로 알아봐요",
                                  systemImage: owner.shots.isEmpty ? "camera" : "camera.fill")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    ForEach(habits) { habit in
                        Button { runKey = habit } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(habit.name).font(.headline)
                                    Text(habit.actionTitle).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(Color.accentColor)
                            }
                        }
                        .tint(.primary)
                        .swipeActions { Button("기록·달력", systemImage: "calendar") { detailKey = habit }.tint(.orange) }
                        .contextMenu { Button("기록·달력 보기", systemImage: "calendar") { detailKey = habit } }
                    }
                    Button("이 물건에 습관 추가", systemImage: plus.isPlus ? "plus" : "lock.fill") {
                        if plus.isPlus { addingHabit = true } else { showPaywall = true }
                    }
                } header: {
                    Text("연결된 습관")
                } footer: {
                    Text("누르면 바로 할 수 있어요. 왼쪽으로 밀면 기록·달력을 봐요.")
                }
            }
            .navigationTitle("물건")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
            .sheet(item: $detailKey) { KeyDetailView(key: $0, keys: keys) }
            .sheet(item: $runKey) { HabitRunView(key: $0) }
            .sheet(isPresented: $addingHabit) { RegisterView(sharing: owner) }
            .sheet(isPresented: $showPaywall) { PlusPaywall(reason: "물건 하나에 습관 여러 개는 플러스에서 쓸 수 있어요.") }
        }
    }
}
