import Foundation

enum ExportError: LocalizedError {
    case pdfUnavailable

    var errorDescription: String? {
        switch self {
        case .pdfUnavailable: "PDF を作成できませんでした。"
        }
    }
}

/// 書き出したファイルの実体を作る。中身の組み立ては `ObservationReport` で済んでいるので、
/// ここは並べ方とファイルの置き場所だけを引き受ける。
enum ExportService {

    // MARK: - CSV

    /// 1 日 1 行。記録のない日は空欄にする。0 と書くと「その日は 0 回だった」と読めてしまうため。
    static func dailyCSV(for report: ObservationReport) -> String {
        let header = [
            "日付", "曜日", "フェーズ", "排便回数", "平均ブリストル値",
            "平均腹痛", "平均急な便意", "全体的な体調", "腹部の調子",
            "実施した観察対象", "メモ",
        ]

        let rows = report.days.map { day -> [String] in
            let tally = day.tally
            return [
                csvDate(day.date),
                weekday(day.date),
                day.phaseName,
                day.hasRecord ? String(tally.bowelCount) : "",
                number(tally.averageBristol),
                number(tally.averagePain),
                number(tally.averageUrgency),
                tally.overallCondition?.label ?? "",
                tally.abdominalCondition?.label ?? "",
                day.completedTargets.joined(separator: " / "),
                day.note,
            ]
        }

        return csv(header: header, rows: rows)
    }

    /// 排便 1 件 1 行。時刻や 1 回ごとのメモは日別表では落ちるので、控えとしてはこちらが本体。
    static func movementCSV(for report: ObservationReport) -> String {
        let header = [
            "日付", "曜日", "時刻", "ブリストル値", "便の状態",
            "腹痛", "腹痛の値", "急な便意", "急な便意の値", "フェーズ", "メモ",
        ]

        let rows = report.movements.map { movement -> [String] in
            [
                csvDate(movement.recordedAt),
                weekday(movement.recordedAt),
                csvTime(movement.recordedAt),
                String(movement.bristolScale.rawValue),
                movement.bristolScale.label,
                movement.abdominalPain.label,
                String(movement.abdominalPain.rawValue),
                movement.urgency.label,
                String(movement.urgency.rawValue),
                movement.phaseName,
                movement.note,
            ]
        }

        return csv(header: header, rows: rows)
    }

    // MARK: - ファイル

    /// 書き出し用の一時ディレクトリ。作り直すたびに空にして、古いファイルを残さない。
    static func prepareDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "Export", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @discardableResult
    static func write(_ text: String, to url: URL) throws -> URL {
        // Excel と Numbers が UTF-8 と判別できるよう BOM を付け、改行は CRLF にする。
        try ("\u{FEFF}" + text).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// 「ブリストルログ_下痢の経過観察_20260818.csv」のような名前を組み立てる。
    static func filename(planName: String, suffix: String, extension ext: String, date: Date = .now) -> String {
        let parts = ["ブリストルログ", sanitized(planName), suffix, stamp(date)].filter { !$0.isEmpty }
        return parts.joined(separator: "_") + "." + ext
    }

    // MARK: -

    private static func csv(header: [String], rows: [[String]]) -> String {
        ([header] + rows)
            .map { $0.map(escape).joined(separator: ",") }
            .joined(separator: "\r\n")
    }

    private nonisolated static func escape(_ field: String) -> String {
        let needsQuotes = field.contains { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }
        guard needsQuotes else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func number(_ value: Double?) -> String {
        guard let value else { return "" }
        // 表計算ソフトが数値として読めるよう、桁区切りを入れない素の表記にする。
        return String(format: "%.1f", value)
    }

    private static func weekday(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).locale(Formatting.locale))
    }

    /// 表計算ソフトが日付として解釈できる形。画面表示用の `Formatting` とは別物。
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    private static func csvDate(_ date: Date) -> String { dateFormatter.string(from: date) }
    private static func csvTime(_ date: Date) -> String { timeFormatter.string(from: date) }
    private static func stamp(_ date: Date) -> String { stampFormatter.string(from: date) }

    /// ファイル名に使えない文字と空白を落とす。日本語はそのまま残す。
    private static func sanitized(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:").union(.controlCharacters)
        let cleaned = name
            .components(separatedBy: invalid).joined()
            .components(separatedBy: .whitespacesAndNewlines).joined()
        return String(cleaned.prefix(24))
    }
}
