import SwiftUI
import ObjectKeyCore

/// 공유 카드. 기기 안에서 그림으로 만들어 메시지·SNS로 보낸다. 기록 자체는 밖으로 보내지 않는다.
enum ShareCard {
    /// 카드 화면을 그림으로 굽는다. 어두운 모드여도 카드는 밝게 만든다.
    @MainActor
    static func render<V: View>(_ view: V) -> UIImage? {
        let renderer = ImageRenderer(content: view.frame(width: 340).environment(\.colorScheme, .light))
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// 습관 하나의 기록 카드. 66일 단계와 1년 잔디를 함께 담는다.
struct HabitShareCard: View {
    let name: String
    let emoji: String
    let metDays: Int
    let bestStreak: Int
    let strength: Double?
    let phase: String?
    let days: [Date: DayStatus]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                KeyBadge(symbol: emoji, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.title3.bold())
                    if let phase { Text(phase).font(.subheadline).foregroundStyle(.orange) }
                }
            }
            HStack {
                number("\(metDays)일", "채운 날")
                number("\(bestStreak)일", "최고 기록")
                if let strength { number("\(Int((strength * 100).rounded()))", "습관 힘") }
            }
            YearHeatmap(days: days)
            HStack {
                Image(.peek).resizable().scaledToFit().frame(width: 28, height: 28)
                Text("MOKI · 물건 하나, 습관 하나").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(Color.white)
    }

    private func number(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.bold().monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// 한 해 결산 카드.
struct YearShareCard: View {
    let year: Int
    let metDays: Int
    let habits: Int
    let bestStreak: Int
    let topHabit: String?
    let stickers: Int

    var body: some View {
        VStack(spacing: 14) {
            Image(.success).resizable().scaledToFit().frame(height: 110)
            Text("\(String(year))년의 MOKI").font(.title2.bold())
            VStack(spacing: 8) {
                line("채운 날", "\(metDays)일")
                line("함께한 습관", "\(habits)개")
                line("가장 길게 이어 간 기록", "\(bestStreak)일")
                if let topHabit { line("가장 많이 한 습관", topHabit) }
                line("모은 스티커", "\(stickers) / \(Stickers.order.count)")
            }
            .padding()
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            Text("MOKI · 물건 하나, 습관 하나").font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .background(Color.white)
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).bold() }.font(.subheadline)
    }
}

/// 구운 카드를 보여 주고 공유한다.
struct ShareCardSheet: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Image(uiImage: image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(radius: 6, y: 2)
                    .padding()
            }
            .safeAreaInset(edge: .bottom) {
                ShareLink(item: Image(uiImage: image), preview: SharePreview("MOKI 기록 카드", image: Image(uiImage: image))) {
                    Label("공유하기", systemImage: "square.and.arrow.up").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).padding()
            }
            .navigationTitle("기록 카드")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
    }
}

/// 시트에 넘길 그림. sheet(item:)에 쓰려고 Identifiable로 감싼다.
struct CardImage: Identifiable {
    let id = UUID()
    let image: UIImage
}
