import SwiftData
import SwiftUI
import ObjectKeyCore

extension HabitPhase {
    var label: String {
        switch self {
        case .adapting: return "1단계 적응"
        case .wiring: return "2단계 회로 형성"
        case .automating: return "3단계 자동화"
        case .formed: return "습관 안착"
        }
    }

    /// 단계별 한 줄 조언.
    var tip: String {
        switch self {
        case .adapting: return "작게라도 시작하는 것만 생각해요."
        case .wiring: return "쉬는 날에도 한 번은 비춰 주세요."
        case .automating: return "이제 몸이 먼저 기억하기 시작해요."
        case .formed: return "66일을 넘겼어요. 이제 내 습관이에요."
        }
    }
}

/// 하루 목표 입력. 세션은 5분 단위, 카운터는 1회 단위. 0이면 목표 없음.
struct GoalStepper: View {
    let actionKind: String
    @Binding var goal: Int

    var body: some View {
        let counter = actionKind == "counter"
        Stepper(goal == 0 ? "목표 없음 (하루 1번 비추기)" : "하루 \(goal)\(counter ? "회" : "분")",
                value: $goal, in: 0...(counter ? 100 : 600), step: counter ? 1 : 5)
    }
}

/// 습관 설정 공통 안내. 등록 화면과 설정 시트가 같은 문구를 쓴다.
enum HabitCopy {
    static let goalFooter = "처음에는 실패할 수 없을 만큼 작게 시작하세요. 목표 없음이면 하루 한 번만 비춰도 이어집니다. 하루 빠지는 건 괜찮지만, 이틀 연속 빠지면 끊겨요."
    static let cuePlaceholder = "이미 하는 행동 (예: 아침 커피 내린)"
    static let cueFooter = "이미 몸에 밴 행동 바로 뒤에 붙이면 잊지 않아요. \"…다음에\"로 표시됩니다."
}

/// 등록한 뒤 목표와 신호를 바꾸는 시트. 홈 목록에서 길게 눌러 연다.
struct GoalEditor: View {
    @Bindable var key: KeyObject
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    GoalStepper(actionKind: key.actionKind, goal: $key.dailyGoal)
                } header: {
                    Text("하루 목표")
                } footer: {
                    Text(HabitCopy.goalFooter)
                }
                Section {
                    TextField(HabitCopy.cuePlaceholder, text: $key.cue)
                        .submitLabel(.done)
                } header: {
                    Text("언제 할까요? (선택)")
                } footer: {
                    Text(HabitCopy.cueFooter)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("\(key.name) 습관 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// 오늘 진행률 링과 이어온 일수. 목록 행 오른쪽에 붙는다.
struct ProgressMark: View {
    let progress: KeyProgress

    var body: some View {
        HStack(spacing: 8) {
            if progress.streak > 0 {
                // 오늘 안 하면 끊기는 날은 빨간색으로 알린다.
                Label("\(progress.streak)", systemImage: progress.atRisk ? "flame" : "flame.fill")
                    .font(.subheadline.bold()).foregroundStyle(progress.atRisk ? .red : .orange)
                    .accessibilityLabel(progress.atRisk ? "\(progress.streak)일째, 오늘 안 하면 끊겨요" : "\(progress.streak)일째 이어가는 중")
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
        // 끊기기 직전인 습관이 가장 먼저다. 이틀 연속만은 막는다.
        if let risky = items.filter(\.progress.atRisk).max(by: { $0.progress.streak < $1.progress.streak }) {
            return (.question, "\(risky.key.name), 어제 쉬었어요. 오늘 비추지 않으면 \(risky.progress.streak)일이 끊겨요.")
        }
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
        if let best = items.max(by: { $0.progress.streak < $1.progress.streak }),
           let phase = best.progress.phase {
            return (.peek, "\(best.key.name) \(best.progress.streak)일째, \(phase.label). \(phase.tip)")
        }
        return (.scan, "오늘 첫 물건을 비춰 보세요. 작게 시작해도 충분해요.")
    }
}
