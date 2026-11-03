import SwiftUI
import WidgetKit

/// 시계 화면 컴플리케이션. 워치 앱이 받은 오늘 요약을 워치 안 공유 공간에서 읽는다.
@main
struct MokiComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MokiWatchToday", provider: Provider()) { entry in
            ComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("MOKI 오늘")
        .description("오늘 할 일 진행과 다음 할 일을 보여 줘요.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, snapshot: nil) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now, snapshot: WidgetSnapshot.load()?.current()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let now = Date.now
        // 자정에 다시 그려 어제 완료 표시를 지운다. 그 사이 변화는 워치 앱이 다시 그리게 한다.
        let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: [Entry(date: now, snapshot: WidgetSnapshot.load()?.current(now: now))], policy: .after(midnight)))
    }
}

struct ComplicationView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let done = entry.snapshot?.doneCount ?? 0
        let total = entry.snapshot?.items.count ?? 0
        let next = entry.snapshot?.items.first { !$0.done && $0.quit != true }
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(done), in: 0...Double(max(total, 1))) {
                Text("MOKI")
            } currentValueLabel: {
                Text("\(done)/\(total)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("MOKI 오늘 \(done)/\(total)").font(.headline)
                if let next {
                    Text("다음: \(next.time.map { "\($0) " } ?? "")\(next.name)").lineLimit(1)
                } else {
                    Text(total == 0 ? "아이폰에서 MOKI를 열어 주세요" : "오늘 다 했어요!").lineLimit(1)
                }
            }
        case .accessoryCorner:
            Text("\(done)/\(total)")
                .widgetLabel { Gauge(value: Double(done), in: 0...Double(max(total, 1))) { Text("MOKI") } }
        default:
            Text("MOKI \(done)/\(total)")
        }
    }
}
