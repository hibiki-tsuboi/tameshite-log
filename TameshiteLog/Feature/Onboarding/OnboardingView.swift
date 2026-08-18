import SwiftUI
import SwiftData

/// 初回起動。長い説明は挟まず、1 画面ですぐプラン作成へ進む。
struct OnboardingView: View {
    @AppStorage(AppStorageKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    @State private var isSettingUp = false

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

                    Text("記録は端末の中だけに保存されます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .navigationDestination(isPresented: $isSettingUp) {
                PlanSetupView { hasCompletedOnboarding = true }
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
