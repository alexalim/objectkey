import Charts
import SwiftUI
import ObjectKeyCore

/// 최근 1년 잔디. 한 칸이 하루, 한 줄이 한 요일. 빈칸은 옅은 회색이고, 놓친 날을 빨갛게 칠하지 않는다.
struct YearHeatmap: View {
    let days: [Date: DayStatus]
    var skipped: Set<Date> = []

    private let calendar = Calendar.current
    private let weeks = 53

    var body: some View {
        let columns = weekColumns
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let gap: CGFloat = 2
                let side = max(2, (geo.size.width - gap * CGFloat(weeks - 1)) / CGFloat(weeks))
                HStack(alignment: .top, spacing: gap) {
                    ForEach(columns.indices, id: \.self) { w in
                        VStack(spacing: gap) {
                            ForEach(0..<7, id: \.self) { d in
                                RoundedRectangle(cornerRadius: side / 4)
                                    .fill(color(columns[w][d]))
                                    .frame(width: side, height: side)
                            }
                        }
                    }
                }
            }
            .aspectRatio(CGFloat(weeks) / 7 * 0.93, contentMode: .fit)
            HStack(spacing: 10) {
                legend(Color.orange, "채운 날")
                legend(Color.orange.opacity(0.35), "조금 한 날")
                if !skipped.isEmpty { legend(Color.secondary.opacity(0.45), "건너뜀") }
                Spacer()
                Text("\(days.values.filter { $0 == .met }.count)일 채움").monospacedDigit()
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("최근 1년 동안 \(days.values.filter { $0 == .met }.count)일 채웠어요")
    }

    /// 이번 주가 맨 오른쪽 열. 각 열은 그 주의 날짜 7개(미래는 nil).
    private var weekColumns: [[Date?]] {
        let today = calendar.startOfDay(for: .now)
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return [] }
        return (0..<weeks).map { i in
            let start = calendar.date(byAdding: .weekOfYear, value: i - (weeks - 1), to: thisWeek) ?? thisWeek
            return (0..<7).map { d in
                calendar.date(byAdding: .day, value: d, to: start).flatMap { $0 <= today ? $0 : nil }
            }
        }
    }

    private func color(_ day: Date?) -> Color {
        guard let day else { return .clear }
        if skipped.contains(day) { return Color.secondary.opacity(0.45) }
        switch days[day] {
        case .met: return .orange
        case .partial: return Color.orange.opacity(0.35)
        case nil: return Color.secondary.opacity(0.12)
        }
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8); Text(label) }
    }
}

/// 습관 힘 한 줄. 레벨, 레벨마다 한 칸씩 나눈 막대, 짧은 설명.
struct StrengthRow: View {
    let score: Double

    var body: some View {
        let level = HabitLevel.of(score: score)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("습관 힘").font(.subheadline)
                Spacer()
                Text("Lv.\(level.level)").font(.headline.monospacedDigit()).foregroundStyle(LevelBar.color(level.level))
            }
            LevelBar(score: score)
            Text(Self.caption(score)).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("습관 힘 레벨 \(level.level)")
        .accessibilityValue(level.progress.map { "다음 레벨까지 \(Int(((1 - $0) * 100).rounded()))퍼센트 남음. " + Self.caption(score) } ?? Self.caption(score))
    }

    /// 점수대별 말. 낮아도 탓하지 않고 다음 한 번을 권한다.
    static func caption(_ score: Double) -> String {
        switch score {
        case ..<0.2: return "이제 막 시작했어요. 한 번 할 때마다 쌓여요."
        case ..<0.5: return "자리 잡는 중이에요. 하루 빠져도 조금만 줄어요."
        case ..<0.8: return "꽤 단단해졌어요. 지금처럼만 이어가면 돼요."
        default: return "몸에 붙은 습관이에요."
        }
    }
}

/// 습관 힘 추이(플러스 통계).
struct StrengthChart: View {
    let points: [HabitStrength.Point]

    var body: some View {
        Chart(points, id: \.day) { p in
            LineMark(x: .value("날짜", p.day), y: .value("습관 힘", p.score * 100))
                .foregroundStyle(Color.orange)
                .interpolationMethod(.monotone)
        }
        .chartYScale(domain: 0...100)
        .frame(height: 160)
    }
}

extension PeriodCompare {
    /// "지난 30일보다 4번 더 했어요". 줄었으면 탓하지 않고 이번 숫자만 담담히 말한다.
    static func sentence(recent: Int, previous: Int, days: Int) -> String {
        if recent > previous { return "지난 \(days)일보다 \(recent - previous)번 더 했어요." }
        if recent == previous { return "지난 \(days)일과 똑같이 \(recent)번 했어요. 꾸준해요." }
        return "최근 \(days)일 동안 \(recent)번 했어요. 한 번씩 다시 쌓아 가요."
    }
}

/// 레벨 막대. 레벨 수만큼 칸을 나누고, 지난 레벨 칸은 가득, 지금 레벨 칸은 다음 레벨까지 채운 만큼, 남은 칸은 비워 둔다.
/// 칸마다 색이 달라 어느 레벨인지 글자 없이도 보인다. 쉬면 지금 칸이 덜 차거나 앞 칸으로 돌아간다.
struct LevelBar: View {
    let score: Double

    /// 노랑에서 진한 주황으로, 레벨이 오를수록 진해진다.
    static func color(_ level: Int) -> Color {
        switch level {
        case ...1: Color(red: 1.0, green: 0.80, blue: 0.25)
        case 2: Color(red: 1.0, green: 0.65, blue: 0.20)
        case 3: Color(red: 1.0, green: 0.50, blue: 0.10)
        default: Color(red: 0.92, green: 0.33, blue: 0.08)
        }
    }

    var body: some View {
        let level = HabitLevel.of(score: score)
        HStack(spacing: 4) {
            ForEach(1...HabitLevel.maxLevel, id: \.self) { n in
                let fill = n < level.level ? 1 : n == level.level ? (level.progress ?? 1) : 0
                Capsule().fill(Color(.systemFill))
                    .overlay(alignment: .leading) {
                        GeometryReader { g in
                            Capsule().fill(Self.color(n)).frame(width: g.size.width * fill)
                        }
                    }
                    .clipShape(Capsule())
            }
        }
        .frame(height: 8)
    }
}
