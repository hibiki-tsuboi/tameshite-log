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
                day.hasBowelCount ? String(tally.bowelCount) : "",
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
    ///
    /// 名前を分けられるようにしてある。引き継ぎファイルを同じ場所に作ると、
    /// 作り直しのたびに書き出した CSV と PDF まで消えてしまう。
    static func prepareDirectory(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: name, directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// 書き出し画面 1 つぶんの置き場所を作る。
    ///
    /// 画面ごとに別のディレクトリにする。`prepareDirectory(named:)` は渡された場所を
    /// 空にしてから作り直すので、書き出し画面が 2 つ開いていると、あとから準備を始めた側が
    /// 先に開いた側の PDF と CSV まで消す。消えたことは画面に出ず、先に開いた側の共有ボタンだけが
    /// 実体のない URL を指したままになる。書き出しの入口は比較タブと設定に分かれているので、
    /// 2 つ開いた状態は起こりうる。
    ///
    /// 前回の起動で残ったぶんは、プロセスで最初に準備するときにまとめて片付ける。
    /// その時点では動いている書き出しがまだ無いので、誰のファイルも巻き添えにしない。
    static func prepareExportDirectory(for session: UUID) throws -> URL {
        if !hasClearedExportRoot {
            hasClearedExportRoot = true
            try? FileManager.default.removeItem(at: exportRoot)
        }
        return try prepareDirectory(named: "\(exportRootName)/\(session.uuidString)")
    }

    private static let exportRootName = "Export"

    private static var exportRoot: URL {
        FileManager.default.temporaryDirectory.appending(path: exportRootName, directoryHint: .isDirectory)
    }

    private static var hasClearedExportRoot = false

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

    /// 表計算ソフトが数式として評価してしまう先頭文字。
    ///
    /// メモに「- 朝からお腹が痛い」と箇条書きのつもりで書くと、Excel・Numbers・
    /// Google スプレッドシートはその行を数式として評価し、セルには本文ではなく
    /// #NAME? が出る。= + @ でも同じで、引用符で囲んでも評価は止まらない。
    /// 書き出した本人の手元では起きず、渡した相手の画面でだけ本文が消えるので、
    /// 本人はメモが欠けていることに気づけない。
    private nonisolated static let formulaPrefixes: Set<Character> = ["=", "+", "-", "@", "\t", "\r"]

    /// 先頭に ' を足して文字列だと伝える。3 つとも ' 自体は表示しない。
    /// このアプリの CSV に負の数は出ないので、- を巻き込む心配はない。
    private nonisolated static func escape(_ field: String) -> String {
        let isFormula = field.first.map(formulaPrefixes.contains) ?? false
        let text = isFormula ? "'" + field : field
        let needsQuotes = isFormula
            || text.contains { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }
        guard needsQuotes else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func number(_ value: Double?) -> String {
        guard let value else { return "" }
        // 表計算ソフトが数値として読めるよう、桁区切りを入れない素の表記にする。
        return String(format: "%.1f", value)
    }

    private static func weekday(_ date: Date) -> String {
        Formatting.weekday(date, .abbreviated)
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
