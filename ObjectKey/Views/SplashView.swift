import SwiftUI

/// 앱을 열면 먼저 보이는 화면. 누르면 홈으로 넘어간다.
/// 앱스토어에 새 버전이 있으면 아래에 한 줄로 알려 준다. 시작은 그대로 할 수 있다.
struct SplashView: View {
    let onStart: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var update = UpdateCheck.shared
    @State private var pulse = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Button(action: onStart) {
                VStack(spacing: 16) {
                    Spacer()
                    Image(.key).resizable().scaledToFit().frame(height: 200)
                    Text("MOKI").font(.system(size: 44, weight: .heavy, design: .rounded))
                    Text("물건을 스캔하면 습관이 시작돼요").font(.headline).foregroundStyle(.secondary)
                    Spacer()
                    Text("화면을 누르면 시작해요")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .opacity(pulse ? 1 : 0.35)
                        .padding(.bottom, update.latest == nil ? 48 : 96)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("MOKI 시작하기")

            // 시작 버튼 안에 버튼을 겹치면 어느 쪽이 눌리는지 애매해져서 따로 띄운다.
            if let latest = update.latest {
                Button { openURL(update.storeURL) } label: {
                    Label("새 버전 \(latest) · 업데이트하기", systemImage: "arrow.down.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(.orange.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
                .tint(.orange)
                .padding(.bottom, 40)
                .transition(.opacity)
                .accessibilityIdentifier("splash-update")
            }
        }
        .animation(.easeOut(duration: 0.3), value: update.latest)
        .onAppear {
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { pulse = true }
        }
        .task { await update.check() }
    }
}
