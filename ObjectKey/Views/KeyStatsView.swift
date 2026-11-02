import Charts
import SwiftData
import SwiftUI
import ObjectKeyCore

/// 물건 하나의 통계. 상세 화면에서 연다.
struct KeyStatsView: View {
    let key: KeyObject
    @Environment(ActivityStore.self) private var store
    @Query private var allLogs: [ActivityLog]
    @State private var period: Period = .days30

    private let calendar = Calendar.current

    enum Period: String, CaseIterable, Identifiable {
        case days30 = "30일", days90 = "90일", all = "전체"
        var id: Self { self }
        var days: Int? {
            switch self {
            case .days30: return 30
            case .days90: return 90
            case .all: return nil
            }
        }
    }

    var body: some View {
        let logs = allLogs.filter { $0.keyID == key.id }
        let entries = KeyProgress.entries(key, logs: logs, state: store.state)
        let since = start(logs: logs)
        let rate = DailyProgress.completionRate(entries, goal: key.goalAmount, schedule: key.schedule,
                                                since: since, now: .now, calendar: calendar)
        let best = DailyProgress.bestStreak(entries, goal: key.goalAmount, schedule: key.schedule, now: .now, calendar: calendar)
        let count = logs.filter { $0.startedAt >= since }.count
        let weekly = DailyProgress.weeklyRates(entries, goal: key.goalAmount, schedule: key.schedule,
                                               since: since, now: .now, calendar: calendar)
        let byWeekday = DailyProgress.metDaysByWeekday(entries, goal: key.goalAmount, since: since, calendar: calendar)
        let byHour = DailyProgress.entriesByHour(entries, since: since, calendar: calendar)

        List {
            Section {
                Picker("기간", selection: $period) {
                    ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                HStack {
                    stat("\(best)일", "최고 기록")
                    stat(rate.map { String(format: "%.1f%%", $0 * 100) } ?? "–", "완료율")
                    stat("\(count)회", "기록")
                }
            } footer: {
                Text("\(since.formatted(.dateTime.year().month().day()))부터 · 완료율은 해야 했던 날(주) 중 채운 비율이에요.")
            }

            Section("주별 완료율") {
                if weekly.contains(where: { $0.rate != nil }) {
                    Chart(weekly.compactMap { w in w.rate.map { (w.weekStart, $0 * 100) } }, id: \.0) { point in
                        AreaMark(x: .value("주", point.0), y: .value("완료율", point.1))
                            .foregroundStyle(Color.orange.opacity(0.15))
                        LineMark(x: .value("주", point.0), y: .value("완료율", point.1))
                            .foregroundStyle(Color.orange)
                        PointMark(x: .value("주", point.0), y: .value("완료율", point.1))
                            .foregroundStyle(Color.orange).symbolSize(20)
                    }
                    .chartYScale(domain: 0...100)
                    .chartYAxis { AxisMarks(values: [0, 50, 100]) { AxisGridLine(); AxisValueLabel { Text("\($0.as(Int.self) ?? 0)%") } } }
                    .frame(height: 160)
                    .accessibilityLabel("주별 완료율 그래프")
                } else {
                    empty
                }
            }

            Section("요일별 채운 날") {
                if !byWeekday.isEmpty {
                    let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
                    Chart(order, id: \.self) { weekday in
                        BarMark(x: .value("요일", calendar.veryShortWeekdaySymbols[weekday - 1]),
                                y: .value("채운 날", byWeekday[weekday] ?? 0))
                            .foregroundStyle(isDue(weekday) ? Color.orange : Color.orange.opacity(0.35))
                            .cornerRadius(4)
                    }
                    .frame(height: 140)
                } else {
                    empty
                }
            }

            Section {
                if !byHour.isEmpty {
                    Chart(0..<24, id: \.self) { hour in
                        BarMark(x: .value("시", hour), y: .value("기록", byHour[hour] ?? 0))
                            .foregroundStyle(Color.accentColor)
                    }
                    .chartXScale(domain: 0...23)
                    .chartXAxis { AxisMarks(values: [0, 6, 12, 18, 23]) { AxisValueLabel { Text("\($0.as(Int.self) ?? 0)시") } } }
                    .frame(height: 120)
                } else {
                    empty
                }
            } header: {
                Text("언제 주로 하나요")
            } footer: {
                if let peak = byHour.max(by: { $0.value < $1.value })?.key {
                    Text("\(peak)시 무렵에 가장 많이 했어요.")
                }
            }
        }
        .navigationTitle("\(key.name) 통계")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var empty: some View {
        Text("이 기간에는 아직 기록이 없어요.").font(.subheadline).foregroundStyle(.secondary)
    }

    /// 기간 시작. 처음 시작한 날(등록일·가장 이른 기록)보다 앞으로는 가지 않는다.
    private func start(logs: [ActivityLog]) -> Date {
        let began = calendar.startOfDay(for: min(key.createdAt, logs.map(\.startedAt).min() ?? key.createdAt))
        guard let days = period.days,
              let from = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: .now)) else { return began }
        return max(began, from)
    }

    /// 요일 지정일 때 정한 요일은 진하게, 나머지는 옅게.
    private func isDue(_ weekday: Int) -> Bool {
        guard case .weekdays(let days) = key.schedule, !days.isEmpty else { return true }
        return days.contains(weekday)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold().monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
