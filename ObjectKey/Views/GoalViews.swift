import SwiftData
import SwiftUI
import ObjectKeyCore

/// 하루 목표 입력. 세션은 5분 단위, 카운터는 1회 단위. 0이면 목표 없음.
struct GoalStepper: View {
    let actionKind: String
    @Binding var goal: Int

    var body: some View {
        let counter = actionKind == "counter"
        Stepper(goal == 0 ? "목표 없음" : "하루 \(goal)\(counter ? "회" : "분")",
                value: $goal, in: 0...(counter ? 100 : 600), step: counter ? 1 : 5)
    }
}

/// 등록한 뒤 목표를 바꾸는 시트. 홈 목록에서 길게 눌러 연다.
struct GoalEditor: View {
    @Bindable var key: KeyObject
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    GoalStepper(actionKind: key.actionKind, goal: $key.dailyGoal)
                } footer: {
                    Text("목표를 채운 날이 이어지면 연속 일수가 올라갑니다. 목표가 없으면 하루에 한 번만 비춰도 이어집니다.")
                }
            }
            .navigationTitle("\(key.name) 하루 목표")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

/// 오늘 진행률 링과 연속 일수. 목록 행 오른쪽에 붙는다.
struct ProgressMark: View {
    let progress: KeyProgress

    var body: some View {
        HStack(spacing: 8) {
            if progress.streak > 0 {
                Label("\(progress.streak)", systemImage: "flame.fill")
                    .font(.subheadline.bold()).foregroundStyle(.orange)
                    .accessibilityLabel("\(progress.streak)일 연속")
            }
            if let fraction = progress.fraction {
                ZStack {
                    Circle().stroke(.quaternary, lineWidth: 4)
                    Circle().trim(from: 0, to: fraction)
                        .stroke(progress.metToday ? Color.green : Color.accentColor,
                                style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 26, height: 26)
                .accessibilityLabel("오늘 목표 \(Int(fraction * 100))퍼센트")
            }
        }
    }
}

/// 오늘 상태에 따라 MOKI가 반응하는 홈 상단.
struct MoodHeader: View {
    let items: [(key: KeyObject, progress: KeyProgress)]

    var body: some View {
        let r = reaction
        Section {
            HStack(spacing: 12) {
                Image(r.mood).resizable().scaledToFit().frame(width: 64, height: 64)
                Text(r.message).font(.subheadline)
            }
        }
    }

    private var reaction: (mood: Moki, message: String) {
        let goals = items.filter { $0.progress.goal != nil }
        let metGoals = goals.filter { $0.progress.metToday }.count
        let activeToday = items.filter { $0.progress.today > 0 }.count
        if !goals.isEmpty, metGoals == goals.count {
            return (.success, "오늘 목표를 모두 채웠어요!")
        }
        if !goals.isEmpty, metGoals > 0 || activeToday > 0 {
            return (.key, "오늘 목표 \(metGoals)/\(goals.count) 달성. 계속 가 볼까요?")
        }
        if activeToday > 0 {
            return (.reading, "오늘도 비추고 있어요. 좋아요!")
        }
        if let best = items.max(by: { $0.progress.streak < $1.progress.streak }), best.progress.streak > 0 {
            return (.peek, "\(best.key.name) \(best.progress.streak)일 연속! 오늘도 비추면 이어져요.")
        }
        return (.scan, "오늘 첫 물건을 비춰 보세요.")
    }
}
