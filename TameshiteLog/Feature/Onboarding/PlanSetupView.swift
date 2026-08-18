import SwiftUI
import SwiftData

/// 段階的なプラン作成。一度に全部聞かず、1 画面 1 問にする。
struct PlanSetupView: View {
    var onFinish: () -> Void

    @Environment(\.modelContext) private var context

    private enum Step: Int, CaseIterable {
        case planName
        case baseline
        case trial

        var question: String {
            switch self {
            case .planName: "何を観察しますか？"
            case .baseline: "まず、いつもの状態を記録しますか？"
            case .trial: "何を試しますか？"
            }
        }
    }

    @State private var step: Step = .planName
    @State private var planName = ""
    @State private var wantsBaseline = true
    @State private var trialName = ""
    @State private var trialType: TargetType = .medication

    private static let planSuggestions = ["下痢の経過観察", "お腹の調子", "睡眠の経過観察", "肌の調子"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgressView(value: Double(step.rawValue + 1), total: Double(Step.allCases.count))
                .padding(.horizontal)
                .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(step.question)
                        .font(.system(.title2, design: .rounded, weight: .bold))

                    switch step {
                    case .planName: planNameStep
                    case .baseline: baselineStep
                    case .trial: trialStep
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }

            footer
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("観察をはじめる")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.snappy, value: step)
    }

    // MARK: - 各ステップ

    private var planNameStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("例：下痢の経過観察", text: $planName)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))

            Text("あとから変えられます。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            FlowChips(items: Self.planSuggestions) { planName = $0 }
        }
    }

    private var baselineStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("何かを始める前の普段の状態を数日分記録しておくと、あとで「前と比べてどうだったか」を見られます。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ChoiceRow(
                title: "まず、いつもの状態を記録する",
                subtitle: "数日ぶん記録してから、試すことを始めます",
                isSelected: wantsBaseline
            ) { wantsBaseline = true }

            ChoiceRow(
                title: "すぐに試したいことがある",
                subtitle: "今日から試している期間として記録します",
                isSelected: !wantsBaseline
            ) { wantsBaseline = false }
        }
    }

    private var trialStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("例：コレバイン", text: $trialName)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))

            Picker("種類", selection: $trialType) {
                ForEach(TargetType.allCases) { type in
                    Label(type.label, systemImage: type.symbolName).tag(type)
                }
            }
            .pickerStyle(.menu)

            Text(wantsBaseline
                 ? "登録しておくと、いつもの状態の記録が終わったあと「次のフェーズを始める」からすぐ使えます。"
                 : "今日から、これを試している期間として記録を始めます。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("決まっていなければ、空のままでも進めます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            if step != .planName {
                Button("戻る") { back() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }

            Button(step == .trial ? "はじめる" : "次へ") { next() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(step == .planName && trimmedPlanName.isEmpty)
        }
        .padding()
        .background(.bar)
    }

    // MARK: -

    private var trimmedPlanName: String {
        planName.trimmingCharacters(in: .whitespaces)
    }

    private func next() {
        switch step {
        case .planName: step = .baseline
        case .baseline: step = .trial
        case .trial: createPlan()
        }
    }

    private func back() {
        switch step {
        case .planName: break
        case .baseline: step = .planName
        case .trial: step = .baseline
        }
    }

    private func createPlan() {
        let store = ObservationStore(context: context)
        let plan = store.createPlan(name: trimmedPlanName, startDate: .now)

        let trimmedTrial = trialName.trimmingCharacters(in: .whitespaces)
        let target = trimmedTrial.isEmpty ? nil : store.createTarget(name: trimmedTrial, type: trialType)

        if wantsBaseline {
            // 試すものは登録だけしておき、フェーズは「いつもの状態」から始める。
            store.startPhase(name: "いつもの状態", type: .baseline, on: .now, in: plan)
        } else {
            store.startPhase(
                name: target?.name ?? "試している期間",
                type: .intervention,
                targets: [target].compactMap { $0 },
                on: .now,
                in: plan
            )
        }

        onFinish()
    }
}

/// 候補をタップして入力できる小さなチップの並び。
private struct FlowChips: View {
    var items: [String]
    var onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Button(item) { onSelect(item) }
                        .font(.subheadline)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollIndicators(.hidden)
    }
}

/// はい／いいえ のような二択を、説明つきで選ばせる行。
private struct ChoiceRow: View {
    var title: String
    var subtitle: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        PlanSetupView {}
    }
    .modelContainer(SampleData.emptyPreviewContainer)
}
#endif
