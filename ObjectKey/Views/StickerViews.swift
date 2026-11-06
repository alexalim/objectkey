import SwiftData
import SwiftUI
import ObjectKeyCore

/// 스티커 모으기. 가장 길게 이어 간 날 수(모든 습관 중 최고)로 받는다.
enum Stickers {
    /// 받는 순서. Milestones.streakDays와 같은 순서로 하나씩 열린다.
    static let order: [Moki] = [.peek, .scan, .key, .reading, .writing, .exercise, .meditate, .success,
                                .music, .creative, .break, .question]

    /// 본 스티커 수. 새로 받은 게 있으면 완료 화면에서 한 번 축하한다.
    static let seenKey = "stickersSeen"

    @MainActor
    static func bestStreak(keys: [KeyObject], logs: [ActivityLog], state: ActivityState) -> Int {
        keys.filter(\.supportsGoal).map { key in
            let entries = KeyProgress.entries(key, logs: logs.filter { $0.keyID == key.id }, state: state)
            return DailyProgress.bestStreak(entries, goal: key.goalAmount, schedule: key.schedule, skipped: key.skipped,
                                            now: .now, calendar: .current)
        }.max() ?? 0
    }

    /// 새로 받은 스티커가 있으면 가장 마지막 것을 돌려주고 본 것으로 표시한다.
    @MainActor
    static func claimNew(bestStreak: Int) -> Moki? {
        let unlocked = Milestones.unlocked(bestStreak: bestStreak)
        let seen = UserDefaults.standard.integer(forKey: seenKey)
        guard unlocked > seen else { return nil }
        UserDefaults.standard.set(unlocked, forKey: seenKey)
        return order[unlocked - 1]
    }
}

/// 마이 → 스티커 모음. 받은 건 또렷하게, 아직인 건 흐리게 보이고 며칠 이어 가면 받는지 적는다.
struct StickerBookView: View {
    @Environment(ActivityStore.self) private var store
    @Query private var keys: [KeyObject]
    @Query private var logs: [ActivityLog]

    var body: some View {
        let best = Stickers.bestStreak(keys: keys, logs: logs, state: store.state)
        let unlocked = Milestones.unlocked(bestStreak: best)
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text("\(unlocked) / \(Stickers.order.count)").font(.title.bold().monospacedDigit())
                    Text(Milestones.daysToNext(bestStreak: best).map { "\($0)일 더 이어 가면 다음 스티커를 받아요." }
                         ?? "모든 스티커를 모았어요!")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 16) {
                    ForEach(Array(Stickers.order.enumerated()), id: \.offset) { i, moki in
                        let open = i < unlocked
                        VStack(spacing: 6) {
                            Image(moki).resizable().scaledToFit()
                                .saturation(open ? 1 : 0)
                                .opacity(open ? 1 : 0.25)
                                .overlay { if !open { Image(systemName: "lock.fill").foregroundStyle(.secondary) } }
                            Text("\(Milestones.streakDays[i])일").font(.caption.bold().monospacedDigit())
                                .foregroundStyle(open ? .primary : .secondary)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(open ? "\(Milestones.streakDays[i])일 스티커, 받음" : "\(Milestones.streakDays[i])일 스티커, 아직")
                    }
                }
                Text("어느 습관이든 가장 길게 이어 간 날 수로 받아요. 건너뛴 날과 쉬는 날은 끊기지 않아요.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding()
        }
        .navigationTitle("스티커 모음")
        .navigationBarTitleDisplayMode(.inline)
    }
}
