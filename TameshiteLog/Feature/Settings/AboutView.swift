import SwiftUI

struct AboutView: View {
    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ブリストルログ")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text("変えてみたことと、からだの変化を記録して、前後を見くらべるためのアプリです。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                LabeledContent("バージョン", value: version)
            }

            Section {
                Text("本アプリは日々の記録・振り返りを目的としたもので、診断や治療方針を提供するものではありません。服薬や症状については医師・薬剤師に相談してください。")
                    .font(.footnote)
            } header: {
                Text("ご注意")
            }

            Section {
                Label("記録は端末の中だけに保存されます", systemImage: "iphone")
                Label("アカウント登録は不要です", systemImage: "person.crop.circle.badge.xmark")
                Label("外部サーバーへの送信はありません", systemImage: "network.slash")
            } header: {
                Text("プライバシー")
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle("アプリについて")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { AboutView() }
}
