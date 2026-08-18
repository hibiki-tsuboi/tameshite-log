import Foundation
import SwiftData

/// 排便 1 回分の記録。このアプリで最も頻繁に作られるレコード。
///
/// フェーズへの参照はあえて持たない。どのフェーズに属するかは日付から導出するため、
/// あとからフェーズの期間を直しても集計が自動的に正しくなる。
@Model
final class BowelMovement {
    /// 日別集計用に startOfDay へ丸めた日付。述語で日を絞り込むために保存している。
    var date: Date = Date.distantPast
    /// 実際に記録した時刻。
    var recordedAt: Date = Date.distantPast
    var bristolScale: BristolScale = BristolScale.normal
    var abdominalPain: SymptomLevel = SymptomLevel.absent
    var urgency: SymptomLevel = SymptomLevel.absent
    var note: String = ""

    init(
        recordedAt: Date = .now,
        bristolScale: BristolScale,
        abdominalPain: SymptomLevel = .absent,
        urgency: SymptomLevel = .absent,
        note: String = "",
        calendar: Calendar = .current
    ) {
        self.recordedAt = recordedAt
        self.date = calendar.startOfDay(for: recordedAt)
        self.bristolScale = bristolScale
        self.abdominalPain = abdominalPain
        self.urgency = urgency
        self.note = note
    }

    /// 時刻を変えたら日も付け替える。片方だけ更新するとカレンダーと集計がずれる。
    func updateRecordedAt(_ newValue: Date, calendar: Calendar = .current) {
        recordedAt = newValue
        date = calendar.startOfDay(for: newValue)
    }
}
