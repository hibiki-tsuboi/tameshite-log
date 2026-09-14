import Foundation

// 数値と日付の見せ方をここに集約する。
// 「増えた／減った」は事実として示すが、良い／悪いの評価は付けない。
enum Formatting {
    /// UI の文言をすべて日本語で書いているので、日付と数値の表記も日本語に固定する。
    /// 端末の地域設定が海外でも、画面の中で表記が混ざらないようにするため。
    static let locale = Locale(identifier: "ja_JP")

    /// 暦も固定する。locale だけでは足りない。
    ///
    /// `Date.FormatStyle` の calendar の既定は `.autoupdatingCurrent` で、`.locale(_:)` を
    /// 付けても戻らない。端末の暦法を「和暦」にすると `ja_JP` のまま「令和8年9月14日」になる。
    /// 一方 CSV の日付列とファイル名は en_US_POSIX の西暦で固定してあるので、同じ 1 回の
    /// 書き出しで PDF だけ元号になり、渡された側が 2 つの暦を突き合わせることになる。
    ///
    /// 「和暦を選んだ人には和暦で」という選び方は取れない。年を持たない `shortDate` や
    /// `weekdayDate` には元から元号が出ず、CSV も固定なので、どのみち揃わない。
    ///
    /// タイムゾーンと週の始まりは端末のものを引き継ぐ。ここで決めたいのは暦法だけで、
    /// 日曜始まりか月曜始まりかは利用者の地域設定に従うべきものなので。
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        let current = Calendar.current
        calendar.locale = locale
        calendar.timeZone = current.timeZone
        calendar.firstWeekday = current.firstWeekday
        return calendar
    }

    /// locale と暦を当てた日付書式。日付の表示はすべてここを通す。
    /// 1 か所でも素の `.dateTime` を使うと、そこだけ端末の暦で描かれる。
    private static func dateStyle(
        _ build: (Date.FormatStyle) -> Date.FormatStyle
    ) -> Date.FormatStyle {
        var style = build(.dateTime)
        style.locale = locale
        style.calendar = calendar
        return style
    }

    /// 平均値など。小数第 1 位まで。
    static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
    }

    /// 表のセル用。小数第 1 位で桁を揃える。
    ///
    /// `decimal(_:)` は 4.0 を「4」と書く。文章の中ではそのほうが自然に読めるが、
    /// 同じ列に 4.6 と並ぶと桁が揃わず、表として読みにくくなる。
    static func fixedDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(locale))
    }

    /// 表のセル用の差分。符号を付けたうえで小数第 1 位に揃える。
    static func signedFixedDecimal(_ value: Double) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(1))
                .sign(strategy: .always(includingZero: false))
                .locale(locale)
        )
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
        date.formatted(dateStyle { $0.hour().minute() })
    }

    /// 「火」。曜日だけを書く。紙面と CSV で幅を選べるようにしてある。
    static func weekday(_ date: Date, _ width: Date.FormatStyle.Symbol.Weekday) -> String {
        date.formatted(dateStyle { $0.weekday(width) })
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
        date.formatted(dateStyle { $0.year().month().day() })
    }

    /// 「2026年9月」。カレンダーの月見出し用。
    static func monthTitle(_ date: Date) -> String {
        date.formatted(dateStyle { $0.year().month() })
    }

    /// 「8/18」。期間の表示で並べても読みやすい短い形。
    static func shortDate(_ date: Date) -> String {
        date.formatted(dateStyle { $0.month(.defaultDigits).day() })
    }

    /// 「8月18日(火)」
    static func weekdayDate(_ date: Date) -> String {
        date.formatted(dateStyle { $0.month().day().weekday(.abbreviated) })
    }

    /// 「8/18〜8/27」「8/18〜（継続中）」
    static func dateRange(from start: Date, to end: Date?) -> String {
        guard let end else { return "\(shortDate(start))〜（継続中）" }
        return "\(shortDate(start))〜\(shortDate(end))"
    }
}
