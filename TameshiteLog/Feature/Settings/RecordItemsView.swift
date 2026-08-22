import SwiftUI

/// 今どの項目を記録しているかの一覧。
/// MVP では固定だが、あとから項目を足せる設計であることをここで示しておく。
struct RecordItemsView: View {
    private struct Item: Identifiable {
        var id: String { title }
        var title: String
        var detail: String
        var symbolName: String
    }

    private let items: [Item] = [
        Item(title: "排便", detail: "時刻と回数", symbolName: "clock"),
        Item(title: "ブリストル便形状スケール", detail: "1〜7 の 7 段階", symbolName: "7.circle"),
        Item(title: "腹痛", detail: "なし / 軽い / 中程度 / 強い", symbolName: "bolt.heart"),
        Item(title: "急な便意", detail: "なし / 軽い / 中程度 / 強い", symbolName: "exclamationmark.triangle"),
        Item(title: "全体的な体調", detail: "良い / 普通 / 悪い", symbolName: "face.smiling"),
        Item(title: "腹部の調子", detail: "良い / 普通 / 悪い", symbolName: "circle.dashed"),
        Item(title: "観察対象の実施状況", detail: "実施の有無", symbolName: "checkmark.circle"),
        Item(title: "メモ", detail: "1 回ごと・1 日ごと", symbolName: "text.alignleft"),
    ]

    var body: some View {
        List {
            Section {
                ForEach(items) { item in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: item.symbolName)
                            .foregroundStyle(.tint)
                    }
                }
            } header: {
                Text("いま記録できる項目")
            } footer: {
                Text("項目は今のところ固定です。食事や睡眠など、自由に決められる項目は今後の追加を想定しています。")
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle("記録項目")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { RecordItemsView() }
}
