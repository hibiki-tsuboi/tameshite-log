//
//  TameshiteLogApp.swift
//  TameshiteLog
//

import SwiftUI
import SwiftData

@main
struct TameshiteLogApp: App {
    /// アプリ全体で使うモデル。プレビューは SampleData 側で別のコンテナを作る。
    static let schema: [any PersistentModel.Type] = [
        ObservationPlan.self,
        ObservationPhase.self,
        ObservationTarget.self,
        DailyRecord.self,
        TargetRecord.self,
        TargetAttachment.self,
        BowelMovement.self,
    ]

    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Schema(Self.schema))
        } catch {
            // 端末内保存しかしていないため、ここで失敗すると記録を読めない。
            // 黙って空の状態で起動すると既存の記録を上書きしかねないので、原因を残して落とす。
            fatalError("記録の保存領域を開けませんでした: \(error)")
        }

        #if DEBUG
        // `-sampleData` を付けて起動すると、30日分の架空データが入った状態で立ち上がる。
        // 画面の見え方を確認するための開発用の入口。
        if ProcessInfo.processInfo.arguments.contains("-sampleData") {
            SampleData.populate(container.mainContext)
            UserDefaults.standard.set(true, forKey: AppStorageKey.hasCompletedOnboarding)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // 画面の文言が日本語なので、DatePicker などシステムが描く部分も日本語に揃える。
                .environment(\.locale, Formatting.locale)
        }
        .modelContainer(container)
    }
}
