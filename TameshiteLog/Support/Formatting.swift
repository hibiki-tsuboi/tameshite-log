import Foundation

// 数値と日付の見せ方をここに集約する。
// 「増えた／減った」は事実として示すが、良い／悪いの評価は付けない。
enum Formatting {
    /// UI の文言をすべて日本語で書いているので、日付と数値の表記も日本語に固定する。
    /// 端末の地域設定が海外でも、画面の中で表記が混ざらないようにするため。
    static let locale = Locale(identifier: "ja_JP")

    /// 平均値など。小数第 1 位まで。
    static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
    }

    /// 差分。必ず符号を付けて増減の向きを明示する。
    static func signedDecimal(_ value: Double) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(0...1))
                .sign(strategy: .always(includingZero: false))
                .locale(locale)
        )
    }

    /// 変化率。四捨五入した整数パーセント。
    static func signedPercent(_ ratio: Double) -> String {
        let percent = (ratio * 100).rounded()
        let text = percent.formatted(
            .number
                .precision(.fractionLength(0))
                .sign(strategy: .always(includingZero: false))
                .locale(locale)
        )
        return text + "%"
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(locale))
    }

    /// 「20:41」。その日の時刻でなければ「8/14 20:41」まで出す。
    ///
    /// 保存時刻のように、いつの操作なのかが読めないと意味が変わる場所で使う。
    /// カレンダーから過去の日を開くと、その日と最後に書いた日は別になりうる。
    static func timestamp(_ date: Date, on day: Date, calendar: Calendar = .current) -> String {
        guard calendar.isDate(date, inSameDayAs: day) else {
            return "\(shortDate(date)) \(time(date))"
        }
        return time(date)
    }

    /// 「2026年8月18日」
    static func mediumDate(_ date: Date) -> String {
        date.formatted(.dateTime.year().month().day().locale(locale))
    }

    /// 「8/18」。期間の表示で並べても読みやすい短い形。
    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.defaultDigits).day().locale(locale))
    }

    /// 「8月18日(火)」
    static func weekdayDate(_ date: Date) -> String {
        date.formatted(.dateTime.month().day().weekday(.abbreviated).locale(locale))
    }

    /// 「8/18〜8/27」「8/18〜（継続中）」
    static func dateRange(from start: Date, to end: Date?) -> String {
        guard let end else { return "\(shortDate(start))〜（継続中）" }
        return "\(shortDate(start))〜\(shortDate(end))"
    }
}
