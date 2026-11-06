import StoreKit
import SwiftUI

/// MOKI 플러스 안내와 결제. 무엇이 열리는지, 값이 얼마인지, 한 번 결제라는 것을 먼저 보여 준다.
struct PlusPaywall: View {
    /// 어디서 막혀서 왔는지. 맨 위에 한 줄로 보여 준다.
    var reason: String?

    @Environment(\.dismiss) private var dismiss
    @State private var plus = PlusStore.shared
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Image(.success).resizable().scaledToFit().frame(height: 120)
                    Text("MOKI 플러스").font(.title.bold())
                    if let reason { Text(reason).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                    VStack(alignment: .leading, spacing: 12) {
                        feature("infinity", "습관 개수 제한 없음", "무료는 \(PlusStore.freeHabitLimit)개까지예요")
                        feature("link", "물건 하나에 습관 여러 개", "운동화 → 걷기, 스트레칭")
                        feature("square.grid.2x2", "위젯 · 잠금 화면 · Apple Watch", "앱을 열지 않고 확인하고 기록")
                        feature("chart.xyaxis.line", "자세한 통계", "주별 · 요일별 · 시간대")
                        feature("heart", "건강 앱 자동 완료 · 단계별 루틴", "걸음 수로 채우기, 세수 → 양치 → 스트레칭")
                        feature("sparkles", "한 문장으로 적기", "\"어제 책 30분 읽었어\"")
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                    Text("기록·스캔·알림·기본 통계·백업은 계속 무료예요.").font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if plus.isPlus {
                        Label("플러스를 쓰고 있어요", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(.green)
                    } else {
                        // 상품 정보가 없으면 결제를 시도해도 아무 일도 안 일어난다. 그때는 다시 불러오기로 바꾼다.
                        Button {
                            Task {
                                busy = true
                                if plus.product == nil {
                                    await plus.loadProduct()
                                    message = nil
                                } else {
                                    message = await plus.purchase()
                                }
                                busy = false
                                if plus.isPlus { dismiss() }
                            }
                        } label: {
                            Group {
                                if busy {
                                    ProgressView().tint(.white)
                                } else {
                                    Text(plus.product.map { "\($0.displayPrice) · 한 번 결제로 평생" } ?? "다시 불러오기")
                                }
                            }
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(busy)
                        Button("구매 복원") {
                            Task { busy = true; message = await plus.restore(); busy = false }
                        }
                        .font(.subheadline).disabled(busy)
                    }
                    if let message, !message.isEmpty { Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                    else if let problem = plus.loadProblem, !plus.isPlus { Text(problem).font(.footnote).foregroundStyle(.secondary) }
                }
                .padding()
                .background(.bar)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
            .task { if plus.product == nil { await plus.loadProduct() } }
        }
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(Color.accentColor).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

/// 설정 화면 안의 플러스 기능 한 줄. 누르면 플러스 안내를 연다.
struct PlusLockRow: View {
    let title: String
    @State private var showPaywall = false

    var body: some View {
        Button { showPaywall = true } label: {
            HStack {
                Label(title, systemImage: "lock.fill")
                Spacer()
                Text("플러스").font(.caption.bold()).foregroundStyle(Color.accentColor)
            }
        }
        .tint(.primary)
        .sheet(isPresented: $showPaywall) { PlusPaywall(reason: "\(title): 플러스에서 쓸 수 있어요.") }
    }
}

/// 플러스 기능 자리. 플러스면 내용을, 아니면 잠긴 안내와 [플러스 보기]를 보여 준다.
struct PlusLocked<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @State private var plus = PlusStore.shared
    @State private var showPaywall = false

    var body: some View {
        if plus.isPlus {
            content()
        } else {
            ContentUnavailableView {
                Label(title, systemImage: "lock.fill")
            } description: {
                Text("MOKI 플러스에서 쓸 수 있어요.")
            } actions: {
                Button("플러스 보기") { showPaywall = true }.buttonStyle(.borderedProminent)
            }
            .sheet(isPresented: $showPaywall) { PlusPaywall(reason: "\(title): 플러스에서 쓸 수 있어요.") }
        }
    }
}
