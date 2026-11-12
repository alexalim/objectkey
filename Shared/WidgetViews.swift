import AppIntents
import SwiftUI

// 홈 화면 위젯·잠금 화면 현황의 그림. 위젯 확장이 쓰고, 앱은 화면 점검(-ui-widgets)에서 같은 그림을 미리 본다.

/// 토끼 표정 + 연속 일수 + 이번 주 요일 점 + 남은 개수. 숫자만 있던 전 모습보다 홈 화면에 남겨 둘 이유가 생긴다.
struct TodaySmallView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let best = snapshot.items.max { $0.streak < $1.streak }
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    if let best, best.streak > 0 {
                        Label("\(best.streak)일", systemImage: best.atRisk ? "flame" : "flame.fill")
                            .font(.title3.bold()).foregroundStyle(best.atRisk ? .red : .orange)
                    } else {
                        Text("오늘").font(.title3.bold())
                    }
                    Text(snapshot.remaining == 0 ? "오늘 다 했어요!" : "\(snapshot.remaining)개 남았어요")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 2)
                Image("wmoki-\(snapshot.mood ?? "peek")").resizable().scaledToFit().frame(width: 52, height: 52)
            }
            Spacer(minLength: 0)
            WeekDots(days: snapshot.weekDays)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 이번 주 7칸. 채운 날은 주황 원, 오늘은 테두리, 지난 빈 날은 옅게, 미래는 더 옅게.
struct WeekDots: View {
    let days: [Bool]?

    var body: some View {
        let calendar = Calendar.current
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        let todayIndex = (calendar.component(.weekday, from: .now) - calendar.firstWeekday + 7) % 7
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { i in
                let done = days.flatMap { i < $0.count ? $0[i] : nil } ?? false
                VStack(spacing: 2) {
                    ZStack {
                        Circle().fill(done ? Color.orange : Color.secondary.opacity(i > todayIndex ? 0.08 : 0.18))
                        if done { Image(systemName: "checkmark").font(.system(size: 7, weight: .bold)).foregroundStyle(.white) }
                    }
                    .frame(width: 14, height: 14)
                    .overlay { if i == todayIndex { Circle().stroke(Color.orange, lineWidth: 1.5) } }
                    Text(symbols[(first + i) % 7]).font(.system(size: 8)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .opacity(days == nil ? 0.4 : 1)
    }
}


struct TodayMediumView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let best = snapshot.items.max { $0.streak < $1.streak }
        HStack(spacing: 10) {
            // 왼쪽: 토끼 · 연속 · 요일 점
            VStack(spacing: 4) {
                Image("wmoki-\(snapshot.mood ?? "peek")").resizable().scaledToFit().frame(width: 48, height: 48)
                if let best, best.streak > 0 {
                    Label("\(best.streak)일", systemImage: best.atRisk ? "flame" : "flame.fill")
                        .font(.caption.bold()).foregroundStyle(best.atRisk ? .red : .orange)
                }
                WeekDots(days: snapshot.weekDays)
            }
            .frame(width: 112)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(snapshot.remaining == 0 ? "오늘 다 했어요!" : "\(snapshot.remaining)개 남았어요").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Text("\(snapshot.doneCount)/\(snapshot.items.count)").font(.caption.bold().monospacedDigit())
            }
            ForEach(snapshot.items.prefix(3)) { item in
                HStack(spacing: 8) {
                    // 아직 안 한 것만 누를 수 있다. 이미 한 것은 실수로 또 기록되지 않게 버튼이 아니다.
                    if item.done {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else if item.quit == true {
                        Image(systemName: "xmark.circle").foregroundStyle(.red)
                    } else {
                        Button(intent: WidgetRecordIntent(keyID: item.id)) {
                            Image(systemName: "circle").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    if !item.emoji.isEmpty { Text(item.emoji) }
                    Text(item.name).font(.subheadline).lineLimit(1).strikethrough(item.done, color: .secondary)
                    if let time = item.time { Text(time).font(.caption2.monospacedDigit()).foregroundStyle(.secondary) }
                    Spacer(minLength: 4)
                    if item.streak > 0 {
                        Label("\(item.streak)", systemImage: item.atRisk ? "flame" : "flame.fill")
                            .font(.caption2.bold()).foregroundStyle(item.atRisk ? .red : .orange)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        }
    }
}

struct TodayLockView: View {
    let state: TodayActivityAttributes.ContentState
    var isStale = false

    var body: some View {
        HStack(spacing: 12) {
            Image("wmoki-\(isStale ? "peek" : state.mood)").resizable().scaledToFit().frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(isStale ? "MOKI" : TodayCopy.headline(state)).font(.headline).lineLimit(1)
                Text(isStale ? TodayCopy.stale : TodayCopy.detail(state)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if !isStale {
                    ProgressView(value: Double(state.total - state.remaining), total: Double(max(1, state.total))).tint(.orange)
                }
            }
            if !isStale, let id = state.nextID.flatMap(UUID.init(uuidString:)) {
                Button(intent: WidgetRecordIntent(keyID: id)) {
                    Text("완료").font(.subheadline.bold()).padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent).tint(.orange)
            }
        }
        .padding(14)
    }
}

/// 오늘 현황 문구. 저녁에 끊기기 직전 습관이 있으면 남은 시간을 함께 말하되, 다그치지 않는다.
enum TodayCopy {
    static func headline(_ s: TodayActivityAttributes.ContentState) -> String {
        s.remaining == 0 ? "오늘 다 했어요!" : "오늘 \(s.remaining)개 남았어요"
    }

    static func detail(_ s: TodayActivityAttributes.ContentState) -> String {
        if s.remaining == 0 { return "토끼도 뿌듯해요. 내일 또 만나요." }
        // 시간을 세어 보여 주면 재촉이 된다. 무엇을 하면 이어지는지만 말한다.
        if let risk = s.atRiskName { return "\(risk) 한 번이면 오늘도 이어져요" }
        // 다음 할 게 없는데 남은 게 있으면 끊기 습관을 오늘 어긴 경우다.
        if s.nextName.isEmpty { return "끊기 습관만 남았어요. 내일 다시 지켜 봐요." }
        let emoji = s.nextEmoji.isEmpty ? "" : s.nextEmoji + " "
        return "다음: \(emoji)\(s.nextName)"
    }

    /// 자정이 지나 묵은 카드일 때. 어제 숫자와 완료 버튼을 보여 주지 않는다.
    static let stale = "새 날이에요 · MOKI를 열면 오늘 할 일이 떠요"
}
