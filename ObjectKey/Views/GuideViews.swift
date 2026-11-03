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
             body: "책, 컵, 영양제처럼\n늘 쓰는 물건을 등록해요.\n스캔하면 MOKI가 알아보고 기록해요."),
        Page(mood: .scan, title: "등록은 이름 하나면 돼요",
             body: "동작은 4가지 중에서 골라요.\n사진을 찍어 두면 스캔만으로 기록돼요.\n사진은 없어도 돼요."),
        Page(mood: .success, title: "끊기지 않는 습관",
             body: "오늘 할 일은 홈에서 확인해요.\n한 번 빠져도 괜찮아요.\n평균 66일이면 습관이 돼요."),
        Page(mood: .reading, title: "카메라 없이도 돼요",
             body: "버튼·위젯·Siri로도 기록해요.\n✨ 버튼에 한 문장으로 말해도 돼요."),
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
                            .multilineTextAlignment(.center).lineSpacing(4).padding(.horizontal, 32)
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
                    ("plus.circle", "오른쪽 위 + 로 등록해요"),
                    ("character.cursor.ibeam", "이름만 있으면 저장돼요"),
                    ("camera", "사진 3장을 찍어 두면 스캔으로 기록돼요"),
                    ("hand.tap", "사진이 없으면 버튼·위젯·Siri로 기록해요"),
                ])
                guide("스캔하면 하는 동작", "2.circle", [
                    ("timer", "시간 기록: 스캔하면 시작, 다시 스캔하면 끝"),
                    ("plus.square", "횟수 +1: 스캔할 때마다 1회"),
                    ("calendar.badge.clock", "정해진 시간 참석: 한 번 스캔하면 정한 시간만큼 기록"),
                    ("cup.and.saucer", "휴식 타이머: 쉬는 동안 시간 기록은 잠시 멈춰요"),
                    ("nosign", "끊기: 했을 때만 기록, 안 한 날이 성공"),
                    ("drop", "횟수에 단위를 쓰면 정한 양만큼 더해져요 (예: 물 250ml)"),
                    ("questionmark.circle", "비슷한 물건이 둘이면 어느 쪽인지 물어봐요"),
                ])
                guide("습관 규칙", "3.circle", [
                    ("hand.point.right", "물건을 오른쪽으로 밀면 습관 설정"),
                    ("repeat", "매일 · 요일 지정 · 주 N회 중에서 골라요"),
                    ("checkmark.circle", "한 번 빠져도 괜찮아요"),
                    ("flame", "두 번 연속 빠지면 끊겨요"),
                    ("leaf", "평균 66일이면 습관이 돼요 (사람마다 달라요)"),
                ])
                guide("기록 보고 고치기", "4.circle", [
                    ("hand.tap", "물건을 누르면 달력과 기록이 나와요"),
                    ("minus.circle", "잘못 누른 횟수는 상세 화면의 −1로 되돌려요"),
                    ("calendar", "날짜를 눌러 기록을 더하거나 지워요"),
                    ("note.text", "그날 메모도 남길 수 있어요"),
                    ("chart.xyaxis.line", "'통계 보기'에서 추이를 봐요"),
                ])
                guide("카메라 없이 기록하기", "5.circle", [
                    ("rectangle.and.hand.point.up.left", "상세 화면의 큰 버튼"),
                    ("square.grid.2x2", "홈 화면 위젯의 ○ 버튼"),
                    ("mic", "Siri: \"MOKI에서 영양제 기록\""),
                    ("bell", "참석 알림을 길게 눌러 '참석'"),
                ])
                guide("태그로 묶기", "6.circle", [
                    ("number", "등록·습관 설정에서 #태그를 붙여요"),
                    ("line.3.horizontal.decrease", "홈 위 칩을 눌러 태그별로 봐요"),
                    ("slider.horizontal.3", "칩 끝 아이콘에서 이름 바꾸기·지우기"),
                ])
                guide("MOKI에게 말하기 ✨", "7.circle", [
                    ("sparkles", "✨ 버튼에 한 문장으로 말해요"),
                    ("text.bubble", "\"화요일 밤 9시 아이스하키 수업\""),
                    ("text.bubble", "\"어제 책 30분 읽었어\""),
                    ("text.bubble", "\"이번 달 영양제 몇 번?\""),
                    ("lock", "기기 안 AI라 문장이 밖으로 나가지 않아요"),
                    ("gearshape", "설정 → Apple Intelligence를 켜 주세요"),
                ])
                guide("백업", "8.circle", [
                    ("square.and.arrow.up", "기록 화면 ⋯ → 백업 내보내기"),
                    ("icloud", "iCloud Drive에 저장해 두세요"),
                    ("square.and.arrow.down", "새 기기에서 ⋯ → 백업 가져오기"),
                    ("arrow.triangle.2.circlepath", "같은 파일을 두 번 가져와도 겹치지 않아요"),
                ])
                guide("위젯과 잠금 화면", "9.circle", [
                    ("square.grid.2x2", "홈 화면 길게 누르기 → 편집 → 위젯 추가 → MOKI"),
                    ("lock.iphone", "잠금 화면 길게 누르기 → 사용자화 → MOKI"),
                    ("timer", "시간 기록 중에는 잠금 화면에 시간이 보여요"),
                    ("gearshape", "안 보이면 설정 → MOKI → 실시간 현황 켜기"),
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

    /// 한 줄에 한 가지. 줄마다 아이콘을 붙여 훑어보기 쉽게 한다.
    private func guide(_ title: String, _ icon: String, _ lines: [(icon: String, text: String)]) -> some View {
        Section {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Label {
                    Text(line.text).font(.subheadline)
                } icon: {
                    Image(systemName: line.icon).foregroundStyle(Color.accentColor)
                }
            }
        } header: {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(.primary).textCase(nil)
        }
    }
}
