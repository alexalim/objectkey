import SwiftUI

/// 처음 설치했을 때 넘겨 보는 소개. 안내 화면에서 다시 볼 수 있다.
struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private struct Page {
        let mood: Moki
        let title: String
        let body: String
    }

    private let pages = [
        Page(mood: .key, title: "물건이 열쇠가 돼요",
             body: "책, 컵, 영양제처럼 늘 쓰는 물건을 등록해 두세요. 카메라로 비추면 MOKI가 알아보고 기록을 시작해요."),
        Page(mood: .scan, title: "등록은 이름 하나면 돼요",
             body: "동작은 시간 기록·횟수 +1·정해진 시간 참석·휴식 타이머 중에서 골라요. 사진을 3장 찍어 두면 비추기만 해도 기록돼요. 사진은 없어도 돼요."),
        Page(mood: .success, title: "끊기지 않는 습관",
             body: "홈에서 오늘 할 일을 확인해요. 한 번 빠져도 괜찮아요. 두 번 연속만 피하면 이어지고, 평균 66일이면 습관이 돼요."),
        Page(mood: .reading, title: "카메라 없이도 돼요",
             body: "물건을 눌러 상세 화면의 버튼으로 기록하거나, 위젯·Siri·알림으로도 기록할 수 있어요. ✨ 버튼에 한 문장으로 말해도 돼요."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if page < pages.count - 1 {
                    Button("건너뛰기", action: onFinish).padding()
                }
            }
            .frame(height: 52)
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    VStack(spacing: 20) {
                        Spacer()
                        Image(pages[i].mood).resizable().scaledToFit().frame(height: 220)
                        Text(pages[i].title).font(.title.bold())
                        Text(pages[i].body).font(.body).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).padding(.horizontal, 32)
                        Spacer()
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            Button {
                if page < pages.count - 1 { withAnimation { page += 1 } } else { onFinish() }
            } label: {
                Text(page < pages.count - 1 ? "다음" : "시작하기").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            Text("홈 왼쪽 위 ? 버튼에서 언제든 다시 볼 수 있어요.").font(.footnote).foregroundStyle(.secondary).padding(.bottom, 8)
        }
        .background(Color(.systemBackground))
    }
}

/// 자세한 사용 안내. 홈 왼쪽 위 ? 버튼으로 연다.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showIntro = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { showIntro = true } label: { Label("소개 다시 보기", systemImage: "play.rectangle") }
                }
                guide("시작하기", "1.circle", [
                    "오른쪽 위 +로 등록해요. 이름만 있으면 저장돼요.",
                    "사진은 선택이에요. 노란 상자가 물건을 감싼 상태로 3장 이상 찍어 두면 비추기로 기록할 수 있고, 없으면 버튼·위젯·Siri·✨로 기록해요.",
                    "아래 '물건 비추기'로 물건을 비추면 정해 둔 일이 실행돼요. 비슷한 물건이 둘이면 어느 쪽인지 물어봐요.",
                ])
                guide("비추면 하는 일 4가지", "2.circle", [
                    "시간 기록: 비추면 시작, 다시 비추면 끝나고 기록돼요. 기록 중에는 잠금 화면에 시간이 보여요.",
                    "횟수 +1: 영양제·물처럼 비출 때마다 1회씩 쌓여요.",
                    "정해진 시간 참석: 수업처럼 시간이 정해진 일. 한 번 비추거나 알림의 '참석'을 누르면 정한 시간만큼 바로 기록돼요(하루 한 번).",
                    "휴식 타이머: 정한 시간만큼 쉬어요. 시간 기록 중이었다면 쉬는 동안 멈췄다가 이어져요.",
                ])
                guide("습관 규칙", "3.circle", [
                    "홈에서 물건을 오른쪽으로 밀거나 상세 화면의 ◎를 누르면 습관 설정이 열려요. 얼마나 자주 할지, 하루 목표, 무엇 다음에 할지, 알림을 정해요.",
                    "이틀 규칙: 한 번 빠져도 이어지고, 두 번 연속 빠지면 끊겨요. 끊기기 직전이면 불꽃이 빨갛게 바뀌어요.",
                    "평균 66일이면 습관이 된다고 해요(사람마다 18~254일). 1~22일 적응, 23~44일 회로 형성, 45~66일 자동화 단계로 보여 드려요.",
                ])
                guide("기록 보고 고치기", "4.circle", [
                    "물건을 누르면 연속 일수·최고 기록, 이번 달 완료율, 달력이 나와요.",
                    "달력 날짜를 누르면 깜빡한 기록을 더하거나 지우고, 그날 메모를 남길 수 있어요.",
                    "'통계 보기'에서 주별 완료율, 요일별·시간대별 기록을 볼 수 있어요.",
                ])
                guide("카메라 없이 기록하기", "5.circle", [
                    "상세 화면의 큰 버튼",
                    "홈 화면 위젯(중간 크기)의 ○ 버튼",
                    "Siri: \"MOKI에서 영양제 기록\" · 단축어 앱의 'MOKI 물건 기록' · 액션 버튼",
                    "정해진 시간 참석 알림을 길게 눌러 '참석'",
                ])
                guide("MOKI에게 말하기 ✨", "6.circle", [
                    "한 문장으로 등록·기록·질문을 할 수 있어요. 예: \"화요일 밤 9시 아이스하키 수업 90분, 30분 전에 알려줘\", \"어제 책 30분 읽었어\", \"이번 달 영양제 몇 번?\"",
                    "기기 안 AI(Apple Intelligence)로만 동작해 문장이 밖으로 나가지 않아요. 설정 → Apple Intelligence 및 Siri에서 켜 주세요(iOS 26, iPhone 15 Pro 이상).",
                ])
                guide("위젯과 잠금 화면", "7.circle", [
                    "홈 화면 빈 곳을 길게 누름 → 편집 → 위젯 추가 → MOKI → '오늘 할 일'.",
                    "잠금 화면을 길게 누름 → 사용자화 → 시계 아래 칸에서 MOKI를 추가해요.",
                    "시간 기록·휴식 중에는 잠금 화면과 Dynamic Island에 시간이 보여요. 안 보이면 설정 → MOKI → 실시간 현황을 켜 주세요.",
                ])
                Section {
                    Text("사진과 기록은 이 기기 안에만 저장돼요.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("사용 안내")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
            .fullScreenCover(isPresented: $showIntro) { OnboardingView { showIntro = false } }
        }
    }

    private func guide(_ title: String, _ icon: String, _ lines: [String]) -> some View {
        Section {
            ForEach(lines, id: \.self) { Text($0).font(.subheadline) }
        } header: {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(.primary).textCase(nil)
        }
    }
}
