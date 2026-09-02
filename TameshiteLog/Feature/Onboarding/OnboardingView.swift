import SwiftUI
import SwiftData

/// 初回起動。長い説明は挟まず、1 画面ですぐプラン作成へ進む。
struct OnboardingView: View {
    @AppStorage(AppStorageKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    @State private var isSettingUp = false
    @State private var isChoosingTransferFile = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                OnboardingJourneyMark()

                VStack(spacing: 16) {
                    Text("試したことと、\nからだの変化を見くらべる。")
                        .font(.system(.title, design: .rounded, weight: .bold))

                    Text("期間を分けて記録するから、\nいつもの状態との違いが見えてきます。")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

                HStack(spacing: 0) {
                    OnboardingStep(number: "1", title: "記録")
                    connector
                    OnboardingStep(number: "2", title: "区切る")
                    connector
                    OnboardingStep(number: "3", title: "比べる")
                }
                .padding(.horizontal, 34)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        isSettingUp = true
                    } label: {
                        Text("観察をはじめる")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ObservationPrimaryButtonStyle())

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

    private var connector: some View {
        Capsule()
            .fill(Color.accentColor.opacity(0.25))
            .frame(maxWidth: .infinity)
            .frame(height: 3)
            .offset(y: -10)
            .accessibilityHidden(true)
    }
}

private struct OnboardingJourneyMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.22), ObservationTheme.mint.opacity(0.22)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 112, height: 112)

            HStack(spacing: 7) {
                Circle().fill(Color.gray.opacity(0.55)).frame(width: 13, height: 13)
                Capsule().fill(Color.accentColor.opacity(0.45)).frame(width: 22, height: 5)
                Circle().fill(Color.accentColor).frame(width: 21, height: 21)
                Capsule().fill(Color.accentColor.opacity(0.45)).frame(width: 22, height: 5)
                Circle().fill(ObservationTheme.mint).frame(width: 13, height: 13)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct OnboardingStep: View {
    var number: String
    var title: String

    var body: some View {
        VStack(spacing: 7) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(ObservationTheme.ink, in: .circle)
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .frame(width: 58)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    OnboardingView()
        .modelContainer(SampleData.emptyPreviewContainer)
}
#endif
