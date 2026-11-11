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

/// 습관 힘 한 줄. 0~100 숫자와 막대, 짧은 설명.
struct StrengthRow: View {
    let score: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("습관 힘").font(.subheadline)
                Spacer()
                Text("\(Int((score * 100).rounded()))").font(.headline.monospacedDigit())
            }
            ProgressView(value: score).tint(.orange)
            Text(Self.caption(score)).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
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
