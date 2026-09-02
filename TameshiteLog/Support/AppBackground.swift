import SwiftUI

extension View {
    /// アプリ全体の背景。写真素材ではなく、フェーズ色とカードが読みやすい静かな面にする。
    /// List / Form に敷くときは `.scrollContentBackground(.hidden)` を合わせる。
    func appBackground() -> some View {
        background {
            ZStack {
                Color(.systemBackground)
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.13),
                        ObservationTheme.sand.opacity(0.12),
                        Color.clear,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [ObservationTheme.mint.opacity(0.12), .clear],
                    center: .bottomTrailing,
                    startRadius: 20,
                    endRadius: 420
                )
            }
            .ignoresSafeArea()
        }
    }
}
