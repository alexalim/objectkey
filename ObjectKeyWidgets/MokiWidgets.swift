import ActivityKit
import SwiftUI
import WidgetKit

@main
struct MokiWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        MokiLiveActivity()
        TodayLiveActivity()
    }
}

/// 진행 중인 시간 기록·휴식을 잠금 화면과 Dynamic Island에 보여 준다.
struct MokiLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MokiActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Badge(state: context.state).font(.title2)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.title).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Clock(state: context.state).font(.title3.monospacedDigit().bold())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.isBreak ? "휴식 중 · 끝나면 멈춰 둔 기록이 이어져요" : "기록 중 · MOKI에서 완료를 눌러 끝내요")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } compactLeading: {
                Badge(state: context.state)
            } compactTrailing: {
                Clock(state: context.state).monospacedDigit().frame(maxWidth: 52)
            } minimal: {
                Badge(state: context.state)
            }
        }
    }
}

private struct LockScreenView: View {
    let state: MokiActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            Badge(state: state).font(.largeTitle)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.isBreak ? "휴식" : "기록 중").font(.caption).foregroundStyle(.white.opacity(0.7))
                Text(state.title).font(.headline).foregroundStyle(.white).lineLimit(1)
            }
            Spacer()
            Clock(state: state).font(.system(size: 34, weight: .bold).monospacedDigit()).foregroundStyle(.white)
        }
        .padding(16)
    }
}

/// 물건 이모지. 없으면 동작에 맞는 기호.
private struct Badge: View {
    let state: MokiActivityAttributes.ContentState

    var body: some View {
        if state.emoji.isEmpty {
            Image(systemName: state.isBreak ? "cup.and.saucer.fill" : "timer").foregroundStyle(.orange)
        } else {
            Text(state.emoji)
        }
    }
}

/// 시스템이 직접 세는 시계. 앱이 매초 갱신하지 않아도 흐른다.
private struct Clock: View {
    let state: MokiActivityAttributes.ContentState

    var body: some View {
        if let end = state.end, end > state.start {
            Text(timerInterval: state.start...end, countsDown: true)
        } else {
            Text(state.start, style: .timer)
        }
    }
}

/// 잠금 화면·Dynamic Island의 "오늘 남은 습관". 다음 습관을 바로 완료할 수 있다.
struct TodayLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TodayActivityAttributes.self) { context in
            TodayLockView(state: context.state)
                .activityBackgroundTint(Color(.systemBackground).opacity(0.9))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image("wmoki-\(context.state.mood)").resizable().scaledToFit().frame(width: 44, height: 44)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TodayCopy.headline(context.state)).font(.headline).lineLimit(1)
                        Text(TodayCopy.detail(context.state)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let id = context.state.nextID.flatMap(UUID.init(uuidString:)) {
                        Button(intent: WidgetRecordIntent(keyID: id)) {
                            Text("완료").font(.subheadline.bold())
                        }
                        .buttonStyle(.borderedProminent).tint(.orange)
                    }
                }
            } compactLeading: {
                Image("wmoki-\(context.state.mood)").resizable().scaledToFit().padding(2)
            } compactTrailing: {
                Text(context.state.remaining == 0 ? "✓" : "\(context.state.remaining)").font(.caption.bold().monospacedDigit())
                    .foregroundStyle(context.state.remaining == 0 ? .green : .orange)
            } minimal: {
                Text(context.state.remaining == 0 ? "✓" : "\(context.state.remaining)").font(.caption2.bold())
                    .foregroundStyle(context.state.remaining == 0 ? .green : .orange)
            }
        }
    }
}

private struct TodayLockView: View {
    let state: TodayActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            Image("wmoki-\(state.mood)").resizable().scaledToFit().frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(TodayCopy.headline(state)).font(.headline).lineLimit(1)
                Text(TodayCopy.detail(state)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                ProgressView(value: Double(state.total - state.remaining), total: Double(max(1, state.total))).tint(.orange)
            }
            if let id = state.nextID.flatMap(UUID.init(uuidString:)) {
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
        let hour = Calendar.current.component(.hour, from: .now)
        if let risk = s.atRiskName, hour >= 18 {
            let left = max(1, Int(s.dayEnd.timeIntervalSinceNow / 3600))
            return "자정까지 \(left)시간 · \(risk) 한 번이면 이어져요"
        }
        let emoji = s.nextEmoji.isEmpty ? "" : s.nextEmoji + " "
        return "다음: \(emoji)\(s.nextName)"
    }
}
