import SwiftUI
import Combine

/// 「今日」が変わったことを画面に伝える。
///
/// `.now` を body の中で読むだけだと、読み直すきっかけがないまま画面が残りうる。
/// この app は記録の入る先も、開ける日の範囲も日付から決めているので、古い「今日」は
/// 前日への記録や、今日のマスが開けないといった形で表に出る。日付は状態として持ち、
/// 変わったら書き換える。
///
/// 見るのは 2 つ。開いたまま日付をまたぐ場合は `.NSCalendarDayChanged` が届き、
/// 眠っている間に日付が変わってから開き直す場合は復帰で拾う。片方だけだと取りこぼす。
struct CurrentDayTracker: ViewModifier {
    @Binding var day: Date

    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onReceive(
                NotificationCenter.default
                    .publisher(for: .NSCalendarDayChanged)
                    // 届くスレッドが決まっていないので、状態を触る前にメインへ寄せる。
                    .receive(on: RunLoop.main)
            ) { _ in
                refresh()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refresh() }
            }
    }

    /// 日が変わったときだけ書き換える。時刻まで毎回入れ直すと、日付から作っている
    /// `@Query` や `.id` が同じ日のうちに何度も作り直されてしまう。
    private func refresh() {
        let now = Date.now
        guard !Calendar.current.isDate(now, inSameDayAs: day) else { return }
        day = now
    }
}

extension View {
    /// `day` を「今日」として持ち続ける。日付が変わったら書き換わる。
    func tracksCurrentDay(_ day: Binding<Date>) -> some View {
        modifier(CurrentDayTracker(day: day))
    }
}
