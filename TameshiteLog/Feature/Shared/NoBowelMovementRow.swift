import SwiftUI
import SwiftData

/// 「その日は排便がなかった」を明示するための行。今日画面とカレンダーの日別画面で共有する。
/// 排便記録が 1 件もない日にだけ置く（呼び出し側が判断する）。
///
/// 排便記録が 0 件の日は、集計では「まだ書いていない日」として平均から外している。
/// 未記録を 0 と数えると平均が実態より低く出るためで、それ自体は変えたくない。
/// ただし 0 回だったこと自体が見たい値になる観察（便秘など）では、それでは 0 の日が残らない。
/// ここで明示された日だけを 0 回として集計に入れる。
struct NoBowelMovementRow: View {
    let day: Date

    @Environment(\.modelContext) private var context
    @Query private var records: [DailyRecord]

    init(day: Date) {
        self.day = day
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        _records = Query(filter: #Predicate<DailyRecord> { $0.date >= start && $0.date < end })
    }

    private var record: DailyRecord? { records.first }
    private var isMarked: Bool { record?.hadNoBowelMovement ?? false }
    private var store: ObservationStore { ObservationStore(context: context) }

    var body: some View {
        // 排便を記録した日には出さない。記録がある日に「なかった」を選べると矛盾するため。
        // 記録を足したときに印を下ろすのは `ObservationStore.addMovement` の役目にしてある。
        Button {
            store.setNoBowelMovement(!isMarked, for: day)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isMarked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isMarked ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("排便はなかった")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Text(isMarked ? "0 回として集計に入ります" : "記録しないままだと「未記録」として集計から外れます")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isMarked ? "排便はなかった、記録済み。取り消す" : "排便はなかったとして記録する")
        .accessibilityAddTraits(isMarked ? [.isSelected] : [])
    }
}
