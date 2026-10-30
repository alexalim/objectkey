import SwiftUI

/// 앱을 열면 먼저 보이는 화면. 누르면 홈으로 넘어간다.
struct SplashView: View {
    let onStart: () -> Void
    @State private var pulse = false

    var body: some View {
        Button(action: onStart) {
            VStack(spacing: 16) {
                Spacer()
                Image(.key).resizable().scaledToFit().frame(height: 200)
                Text("MOKI").font(.system(size: 44, weight: .heavy, design: .rounded))
                Text("물건을 비추면 습관이 시작돼요").font(.headline).foregroundStyle(.secondary)
                Spacer()
                Text("화면을 눌러 시작하세요")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .opacity(pulse ? 1 : 0.35)
                    .padding(.bottom, 48)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("MOKI 시작하기")
        .onAppear {
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
