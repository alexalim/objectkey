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
                    Chart(weekPoints(weekly)) { point in
                        AreaMark(x: .value("주", point.week), y: .value("완료율", point.percent))
                            .foregroundStyle(Color.orange.opacity(0.15))
                        LineMark(x: .value("주", point.week), y: .value("완료율", point.percent))
                            .foregroundStyle(Color.orange)
                        PointMark(x: .value("주", point.week), y: .value("완료율", point.percent))
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
                    Chart(weekdayBars(byWeekday)) { bar in
                        BarMark(x: .value("요일", bar.label), y: .value("채운 날", bar.count))
                            .foregroundStyle(bar.color)
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

    // 차트 입력을 작은 구조체로 미리 만든다. 식을 차트 안에 직접 쓰면 컴파일러가 타입 추론을 못 끝낸다.
    private struct WeekPoint: Identifiable {
        let week: Date
        let percent: Double
        var id: Date { week }
    }

    private struct WeekdayBar: Identifiable {
        let id: Int
        let label: String
        let count: Int
        let color: Color
    }

    private func weekPoints(_ weekly: [(weekStart: Date, rate: Double?)]) -> [WeekPoint] {
        weekly.compactMap { w in w.rate.map { WeekPoint(week: w.weekStart, percent: $0 * 100) } }
    }

    private func weekdayBars(_ counts: [Int: Int]) -> [WeekdayBar] {
        (0..<7).map { offset in
            let weekday = (calendar.firstWeekday - 1 + offset) % 7 + 1
            return WeekdayBar(id: weekday, label: calendar.veryShortWeekdaySymbols[weekday - 1], count: counts[weekday] ?? 0,
                              color: isDue(weekday) ? Color.orange : Color.orange.opacity(0.35))
        }
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
