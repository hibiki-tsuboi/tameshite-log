import Foundation

/// 端末を移すときに書き出す 1 ファイル分の中身。
///
/// PDF・CSV の書き出しとは別物。あちらは人に渡すためのもので、処方箋が写っている写真を
/// 意図的に外している。こちらは自分の記録をそのまま新しい端末へ移すためのもので、
/// 写真も含めて全部入る ── だからこのファイルは人に渡さない。置き場所も「書き出し」の
/// 節ではなく「データ管理」にしてある。
///
/// SwiftData のモデルには触らない素の値だけで組む。復元は「まるごと置き換え」なので、
/// 取り込む側で既存の記録と混ぜるための情報（一意な識別子など）は持たない。
/// 混ぜられない理由は `ObservationStore.restore(from:)` に書いてある。
///
/// 素の値だけの型なので `nonisolated`。既定が MainActor 隔離なので、これを付けないと
/// Codable の適合まで隔離され、JSON の変換を `Task.detached` へ出せない。
nonisolated struct TransferArchive: Codable, Sendable {

    /// 読み込む側が、自分の知らない形式を黙って取り込まないための番号。
    static let currentFormatVersion = 1

    var formatVersion: Int = Self.currentFormatVersion
    /// 作ったアプリのバージョン。取り込みには使わず、問い合わせのときの手がかりに残す。
    var appVersion: String
    var createdAt: Date
    var reminder: Reminder
    var targets: [Target]
    var plans: [Plan]
    var summaries: [Summary]
    var movements: [Movement]

    /// 復元の前に「何が入っているファイルか」を出すための一行。
    var contentDescription: String {
        var parts: [String] = []
        if !plans.isEmpty { parts.append("プラン \(plans.count)件") }
        if !targets.isEmpty { parts.append("観察対象 \(targets.count)件") }
        if !movements.isEmpty { parts.append("排便 \(movements.count)件") }
        if !summaries.isEmpty { parts.append("まとめ \(summaries.count)日") }
        let photos = targets.reduce(0) { $0 + $1.attachments.count }
        if photos > 0 { parts.append("写真 \(photos)枚") }
        return parts.isEmpty ? "記録は入っていません" : parts.joined(separator: " ・ ")
    }

    /// リマインダーの設定。記録ではないが、移した先で鳴らないと移した気がしない。
    ///
    /// オンボーディング済みフラグは入れない。あれは記録ではなくインストールの状態で、
    /// 復元で false に戻すと、設定画面まで来た人をオンボーディングに送り返してしまう。
    struct Reminder: Codable, Sendable {
        var isEnabled: Bool
        var hour: Int
        var minute: Int

        static func current(_ defaults: UserDefaults = .standard) -> Reminder {
            Reminder(
                isEnabled: defaults.bool(forKey: AppStorageKey.reminderEnabled),
                hour: defaults.object(forKey: AppStorageKey.reminderHour) as? Int
                    ?? AppStorageKey.defaultReminderHour,
                minute: defaults.object(forKey: AppStorageKey.reminderMinute) as? Int
                    ?? AppStorageKey.defaultReminderMinute
            )
        }

        func apply(to defaults: UserDefaults = .standard) {
            defaults.set(isEnabled, forKey: AppStorageKey.reminderEnabled)
            defaults.set(hour, forKey: AppStorageKey.reminderHour)
            defaults.set(minute, forKey: AppStorageKey.reminderMinute)
        }
    }

    /// 観察対象と、それに紐づく実施記録・写真。
    ///
    /// 実施記録は対象の下に置く。日付だけの記録（排便・まとめ）と違って対象への参照が要り、
    /// 平らに並べると復元のときに結び直す手がかりを別に持たなければならない。
    struct Target: Codable, Sendable {
        /// ファイルの中だけで通じる番号。フェーズがどの対象を見ていたかを指すために持つ。
        var id: UUID
        var name: String
        var type: TargetType
        var note: String
        var createdAt: Date
        var attachments: [Attachment]
        var completions: [Completion]

        struct Attachment: Codable, Sendable {
            /// `AttachmentImage.prepared(from:)` を通したあとの JPEG。JSON では base64 になる。
            /// 復元では作り直さない ── もう一度縮小をかけると、そのぶんだけ字が読めなくなる。
            var image: Data
            var createdAt: Date
        }

        /// 実施したかどうかの記録。行があること自体が「記録した」を意味する。
        ///
        /// 行なし / `isCompleted == false` / `true` の 3 つを区別して持つ。ここを
        /// 「実施した日の一覧」に畳むと、復元した先で飲み忘れが未記録に化ける。
        struct Completion: Codable, Sendable {
            var date: Date
            var isCompleted: Bool
        }
    }

    struct Plan: Codable, Sendable {
        var name: String
        var startDate: Date
        var endDate: Date?
        var createdAt: Date
        var isActive: Bool
        var phases: [Phase]

        struct Phase: Codable, Sendable {
            var name: String
            var type: PhaseType
            var startDate: Date
            var endDate: Date?
            var note: String
            var warmupDays: Int
            var targetIDs: [UUID]
        }
    }

    /// 1 日のまとめ。
    struct Summary: Codable, Sendable {
        var date: Date
        var overallCondition: ConditionLevel?
        var abdominalCondition: ConditionLevel?
        var note: String
        var updatedAt: Date
        var hadNoBowelMovement: Bool
    }

    /// 排便 1 件。
    ///
    /// `date`（startOfDay）と `recordedAt` の両方をそのまま持つ。`recordedAt` だけ入れて
    /// 復元時に丸め直すと、書き出した端末と復元先のタイムゾーンが違うときに記録が別の日へ
    /// 移る。見えていた日付をそのまま持ち帰るほうを採る。
    struct Movement: Codable, Sendable {
        var date: Date
        var recordedAt: Date
        var bristolScale: BristolScale
        var abdominalPain: SymptomLevel
        var urgency: SymptomLevel
        var note: String
    }
}
