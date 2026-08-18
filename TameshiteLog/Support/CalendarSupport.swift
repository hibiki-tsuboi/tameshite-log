import Foundation

// このアプリの記録はすべて「日」単位で束ねる。
// 保存時に startOfDay へ丸めておくことで、日をまたぐ集計とカレンダー表示を単純な等値比較で扱える。
extension Calendar {
    /// start から end までの各日（両端を含む）を昇順で返す。
    func days(from start: Date, through end: Date) -> [Date] {
        let first = startOfDay(for: start)
        let last = startOfDay(for: end)
        guard first <= last else { return [] }

        var result: [Date] = []
        var cursor = first
        while cursor <= last {
            result.append(cursor)
            guard let next = date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    /// start から end までの日数（両端を含む）。同じ日なら 1。
    func dayCount(from start: Date, through end: Date) -> Int {
        let first = startOfDay(for: start)
        let last = startOfDay(for: end)
        guard first <= last else { return 0 }
        return (dateComponents([.day], from: first, to: last).day ?? 0) + 1
    }

    /// フェーズ開始日を 1 日目とした経過日数。
    func elapsedDayNumber(from start: Date, to date: Date) -> Int {
        dayCount(from: start, through: date)
    }

    func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        isDate(lhs, inSameDayAs: rhs)
    }

    /// その月の 1 日。
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? startOfDay(for: date)
    }

    /// 月グリッドに必要な、週の頭で揃えた日付の並び。
    func monthGridDays(for month: Date) -> [Date] {
        let first = startOfMonth(for: month)
        guard let range = range(of: .day, in: .month, for: first),
              let last = date(byAdding: .day, value: range.count - 1, to: first) else { return [] }

        let leading = (component(.weekday, from: first) - firstWeekday + 7) % 7
        let trailing = 6 - (component(.weekday, from: last) - firstWeekday + 7) % 7
        guard let gridStart = date(byAdding: .day, value: -leading, to: first),
              let gridEnd = date(byAdding: .day, value: trailing, to: last) else { return [] }

        return days(from: gridStart, through: gridEnd)
    }

    /// firstWeekday を反映した曜日名（日曜始まりとは限らない）。
    var orderedShortWeekdaySymbols: [String] {
        let symbols = shortWeekdaySymbols
        let offset = firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }
}
