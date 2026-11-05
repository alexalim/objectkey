import SwiftData
import SwiftUI
import ObjectKeyCore

/// 통계 탭. 전체 요약과 습관별 연속·이번 달 완료율을 보여 주고, 누르면 그 습관의 통계를 연다.
/// 기록 목록(날짜별 원본)은 맨 아래 "전체 기록 보기"에서 본다.
struct StatsView: View {
    @Environment(ActivityStore.self) private var store
    @Query(sort: \KeyObject.createdAt) private var keys: [KeyObject]
    @Query private var logs: [ActivityLog]

    private let calendar = Calendar.current

    private struct Row: Identifiable {
        let key: KeyObject
        let streak: Int
        let monthRate: Double?
        let weekDone: Int
        var id: UUID { key.id }
    }

    var body: some View {
        let rows = keys.filter(\.supportsGoal).map(row)
        let today = TodayPlan.counts(keys: keys, logs: logs, state: store.state)
        let monthStart = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        let monthCount = logs.filter { $0.startedAt >= monthStart }.count
        let best = rows.max { $0.streak < $1.streak }
        List {
            Section {
                HStack {
                    tile(today.total == 0 ? "–" : "\(today.done)/\(today.total)", "오늘")
                    tile("\(monthCount)회", "이번 달 기록")
                    tile(best.map { "\($0.streak)일" } ?? "–", best.map { "\($0.key.name) 연속" } ?? "연속")
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 8, bottom: 12, trailing: 8))
            }
            if !rows.isEmpty {
                Section {
                    ForEach(rows) { r in
                        NavigationLink { PlusLocked(title: "자세한 통계") { KeyStatsView(key: r.key) } } label: {
                            HStack(spacing: 12) {
                                KeyBadge(symbol: r.key.emoji, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.key.name).font(.headline)
                                    Text(r.key.schedule.label).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    // 주 N회는 달 완료율이 주가 끝나야 정해져 비어 보이므로, 이번 주 진행을 보여 준다(상세 화면과 같음).
                                    Text(value(r))
                                        .font(.headline.monospacedDigit())
                                    Label("\(r.streak)일", systemImage: "flame.fill")
                                        .font(.caption.monospacedDigit()).foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                } header: {
                    Text("습관별")
                } footer: {
                    Text("숫자는 이번 달 완료율이에요(주 N회는 이번 주 횟수). 쉬는 날은 빼고 세요. 누르면 주별·요일별·시간대 통계를 봐요.")
                }
            }
            Section {
                NavigationLink { HistoryView() } label: { Label("전체 기록 보기", systemImage: "list.bullet.rectangle") }
            } footer: {
                Text("날짜별 기록을 보고, 밀어서 지울 수 있어요.")
            }
        }
        .navigationTitle("통계")
        .overlay {
            if keys.isEmpty {
                ContentUnavailableView {
                    Image(.reading).resizable().scaledToFit().frame(height: 120)
                    Text("아직 통계가 없어요")
                } description: {
                    Text("습관을 등록하고 기록하면 여기에 쌓여요.")
                }
            }
        }
    }

    private func row(_ key: KeyObject) -> Row {
        let mine = logs.filter { $0.keyID == key.id }
        let entries = KeyProgress.entries(key, logs: mine, state: store.state)
        let progress = DailyProgress.evaluate(entries, goal: key.goalAmount, schedule: key.schedule, now: .now, calendar: calendar)
        // 상세 화면과 같은 기준: 이번 달 1일과 처음 시작한 날 중 늦은 날부터.
        let monthStart = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        let began = min(key.createdAt, mine.map(\.startedAt).min() ?? key.createdAt)
        let rate = DailyProgress.completionRate(entries, goal: key.goalAmount, schedule: key.schedule,
                                                since: max(monthStart, began), now: .now, calendar: calendar)
        return Row(key: key, streak: progress.streak, monthRate: rate, weekDone: progress.weekDone)
    }

    private func value(_ r: Row) -> String {
        if case .perWeek(let n) = r.key.schedule { return "이번 주 \(r.weekDone)/\(n)" }
        return r.monthRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "아직"
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold().monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}
