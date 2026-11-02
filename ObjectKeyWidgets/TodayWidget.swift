import AppIntents
import SwiftUI
import WidgetKit

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(TodayEntry(date: .now, snapshot: WidgetSnapshot.load()?.current() ?? .sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date.now
        let entry = TodayEntry(date: now, snapshot: WidgetSnapshot.load()?.current(now: now))
        // 자정에 한 번 더 그려 어제 완료 표시를 지운다. 그 사이 변화는 앱이 다시 그리게 한다.
        let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime) ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }
}

/// 오늘 할 일 위젯. 홈 화면(작게·중간)과 잠금 화면(원형·직사각형).
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MokiToday", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("오늘 할 일")
        .description("오늘 할 일과 연속 일수를 보여 줘요. 중간 크기에서는 ○를 눌러 바로 기록할 수 있어요.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct TodayWidgetView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.items.isEmpty {
            switch family {
            case .systemMedium: MediumView(snapshot: snapshot)
            case .accessoryCircular: CircularView(snapshot: snapshot)
            case .accessoryRectangular: RectangularView(snapshot: snapshot)
            default: SmallView(snapshot: snapshot)
            }
        } else {
            VStack(spacing: 4) {
                Text("MOKI").font(.headline)
                Text(entry.snapshot == nil ? "앱을 한 번 열어 주세요" : "오늘은 쉬는 날").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct SmallView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let best = snapshot.items.max { $0.streak < $1.streak }
        VStack(alignment: .leading, spacing: 6) {
            Text("오늘 할 일").font(.caption.bold()).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(snapshot.doneCount)").font(.system(size: 40, weight: .bold, design: .rounded))
                Text("/\(snapshot.items.count)").font(.title3.bold()).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(snapshot.doneCount), total: Double(max(1, snapshot.items.count)))
                .tint(.orange)
            Spacer(minLength: 0)
            if let best, best.streak > 0 {
                Label("\(best.name) \(best.streak)일", systemImage: best.atRisk ? "flame" : "flame.fill")
                    .font(.caption2).foregroundStyle(best.atRisk ? .red : .orange).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MediumView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("오늘 할 일").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Text("\(snapshot.doneCount)/\(snapshot.items.count)").font(.caption.bold().monospacedDigit())
            }
            ForEach(snapshot.items.prefix(4)) { item in
                HStack(spacing: 8) {
                    // 아직 안 한 것만 누를 수 있다. 이미 한 것은 실수로 또 기록되지 않게 버튼이 아니다.
                    if item.done {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
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

private struct CircularView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        Gauge(value: Double(snapshot.doneCount), in: 0...Double(max(1, snapshot.items.count))) {
            Image(systemName: "checkmark")
        } currentValueLabel: {
            Text("\(snapshot.doneCount)/\(snapshot.items.count)")
        }
        .gaugeStyle(.accessoryCircular)
    }
}

private struct RectangularView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let next = snapshot.items.first { !$0.done }
        VStack(alignment: .leading, spacing: 2) {
            Text("MOKI 오늘 \(snapshot.doneCount)/\(snapshot.items.count)").font(.headline)
            if let next {
                Text("다음: \(next.time.map { "\($0) " } ?? "")\(next.name)").lineLimit(1)
            } else {
                Text("오늘 다 했어요!")
            }
        }
    }
}

extension WidgetSnapshot {
    static let sample = WidgetSnapshot(day: .now, items: [
        .init(id: UUID(), name: "영양제", emoji: "💊", done: true, streak: 13, atRisk: false, time: "09:00"),
        .init(id: UUID(), name: "읽는 책", emoji: "📚", done: false, streak: 4, atRisk: false, time: nil),
        .init(id: UUID(), name: "아이스하키 수업", emoji: "🏒", done: false, streak: 2, atRisk: false, time: "21:00"),
    ])
}
