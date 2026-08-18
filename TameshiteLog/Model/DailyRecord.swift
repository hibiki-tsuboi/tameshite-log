import Foundation
import SwiftData

/// 1 日 1 件の「まとめ」。任意入力なので、書かれなければ作られない。
///
/// 排便記録とは独立させている。まとめを書かなくても排便だけ記録できるようにするため。
@Model
final class DailyRecord {
    #Unique<DailyRecord>([\.date])

    /// startOfDay へ丸めた日付。
    var date: Date = Date.distantPast
    var overallCondition: ConditionLevel?
    var abdominalCondition: ConditionLevel?
    var note: String = ""
    var updatedAt: Date = Date.distantPast

    /// その日は排便がなかったと本人が記録したことを表す。
    ///
    /// 排便記録が 0 件なのは「なかった」と「まだ書いていない」の両方がありえるので、
    /// この 2 つを区別できないと 0 回の日を平均に入れられない。
    /// 便秘側の観察では 0 回そのものが見たい値になるため、明示的に立てられるようにしている。
    var hadNoBowelMovement: Bool = false

    init(
        date: Date,
        overallCondition: ConditionLevel? = nil,
        abdominalCondition: ConditionLevel? = nil,
        note: String = "",
        hadNoBowelMovement: Bool = false,
        calendar: Calendar = .current
    ) {
        self.date = calendar.startOfDay(for: date)
        self.overallCondition = overallCondition
        self.abdominalCondition = abdominalCondition
        self.note = note
        self.hadNoBowelMovement = hadNoBowelMovement
        self.updatedAt = .now
    }

    /// 何も書かれていないまとめは残さず消せるようにしておく。
    ///
    /// 「排便なし」も入力のひとつなので、これが立っている行は空とみなさない。
    /// ここを漏らすと 0 回の日が掃除されて集計から消える。
    var isEmpty: Bool {
        overallCondition == nil
            && abdominalCondition == nil
            && !hadNoBowelMovement
            && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
