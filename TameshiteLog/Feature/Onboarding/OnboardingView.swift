import SwiftUI
import SwiftData

/// 初回起動。長い説明は挟まず、1 画面ですぐプラン作成へ進む。
struct OnboardingView: View {
    @AppStorage(AppStorageKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    @State private var isSettingUp = false
    @State private var isChoosingTransferFile = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                    .font(.system(size: 68))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(spacing: 20) {
                    Text("変えてみたことと、\nからだの変化を記録。")
                        .font(.system(.title, design: .rounded, weight: .bold))

                    Text("毎日の記録から\n前後の変化を振り返れます。")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        isSettingUp = true
                    } label: {
                        Text("観察をはじめる")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    // 引き継ぎファイルを持って新しい端末を開いた人が、ここ以外で復元にたどり着けない。
                    // タブは hasCompletedOnboarding が立ってからで、それにはプランを作るしかないので、
                    // 案内がないと先に数日ぶん記録してしまう ── 復元は全置き換えなので、その数日は
                    // あとから消える。順番を間違えると戻せないほうを、先に見せる。
                    Button("引き継ぎファイルから復元") {
                        isChoosingTransferFile = true
                    }
                    .font(.subheadline)
                    .padding(.top, 4)

                    Text("記録は端末の中だけに保存されます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .appBackground()
            .navigationDestination(isPresented: $isSettingUp) {
                PlanSetupView { hasCompletedOnboarding = true }
            }
            // 復元できたら記録はもう入っている。プラン作成を通す必要はない。
            .transferRestore(isPresented: $isChoosingTransferFile) {
                hasCompletedOnboarding = true
            }
        }
    }
}

#if DEBUG
#Preview {
    OnboardingView()
        .modelContainer(SampleData.emptyPreviewContainer)
}
#endif
