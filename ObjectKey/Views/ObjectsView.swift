import SwiftData
import SwiftUI

/// 내 물건. 등록한 물건을 2열 카드로 모아 보고, 누르면 상세(기록·달력·설정)를 연다.
struct ObjectsView: View {
    @Environment(ActivityStore.self) private var store
    @Query(sort: \KeyObject.createdAt) private var keys: [KeyObject]
    @State private var search = ""
    @State private var detailKey: KeyObject?
    @State private var showRegister = false

    private var shown: [KeyObject] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return keys }
        return keys.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.tags.contains { $0.localizedCaseInsensitiveContains(q) } }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(shown) { key in
                    Button { detailKey = key } label: { card(key) }
                        .tint(.primary)
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
        .sheet(item: $detailKey) { KeyDetailView(key: $0, keys: keys) }
        .sheet(isPresented: $showRegister) { RegisterView() }
    }

    private func card(_ key: KeyObject) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                KeyBadge(symbol: key.emoji, size: 48)
                Spacer()
                if store.state.activeKeyID == key.id {
                    Image(systemName: "record.circle").foregroundStyle(.red).accessibilityLabel("기록 중")
                }
            }
            Text(key.name).font(.headline).lineLimit(1)
            Text(key.actionTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
