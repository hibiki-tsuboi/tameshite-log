# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this app is

ブリストルログ (TameshiteLog) — an iOS 26 app for logging daily bowel/symptom records and comparing **before and after starting, stopping, or changing something**. The first use case is diarrhea + medication, but the domain is deliberately generalized: the core concept is `ObservationTarget` (medication / supplement / food / exercise / lifestyle / other), never `Medication`.

Japanese-only UI, single app target, no dependencies, no test target, all data on-device (SwiftData, no account, no network).

## Build and run

```bash
# Build
xcodebuild -project TameshiteLog.xcodeproj -scheme TameshiteLog \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' build

# Run with ~6 weeks of fake data (DEBUG only) — the fastest way to see every screen
xcrun simctl boot "iPhone 17 Pro"
xcrun simctl install "iPhone 17 Pro" \
  "$(ls -dt ~/Library/Developer/Xcode/DerivedData/TameshiteLog-*/Build/Products/Debug-iphonesimulator/TameshiteLog.app | head -1)"
xcrun simctl launch "iPhone 17 Pro" jp.hibiki.bristollog -sampleData
xcrun simctl io "iPhone 17 Pro" screenshot shot.png
```

Deployment target is **iOS 26.0**. Always pass an explicit `OS=` in the destination: several installed runtimes (26.0–26.5) each expose a device named "iPhone 17 Pro", and an ambiguous destination silently resolves to whichever one xcodebuild picks.

`ls -dt` in the install line is deliberate: Xcode and `xcodebuild` keep separate `TameshiteLog-<hash>` directories under DerivedData, so a plain `ls -d ... | head -1` sorts alphabetically and can hand you a build from hours ago. Sorting by modification time picks the one you just built. The symptom is a screenshot that stubbornly shows the code you already changed.

Without `-sampleData` a fresh install opens onboarding. There is no test target, so `xcodebuild test` fails until one is added.

`SampleData.specs` is sized so every branch of the analysis UI appears at once: one phase that clears `AnalysisBasis.minimumComparisonDays` and one that does not, one with `warmupDays`, one with alternating adherence (so both sides of the実施/未実施 comparison clear the minimum), and one that produces 0-movement days. Shortening a phase there can quietly remove a screen state from view.

There is no way to script taps on the simulator here, so verifying a screen other than 今日 means temporarily pointing `MainTabView.selection` (or `TodayPlanView`'s `day`) at what you want to see, screenshotting, then reverting. For the PDF, set `isExporting = true`, launch, and pull the file out of `xcrun simctl get_app_container ... data` under `tmp/Export`.

On first launch CoreData logs a wall of `Failed to stat path .../default.store` errors, then `Recovery attempt ... was successful!`. That is the store being created, not a bug.

## Layers

`Model/` SwiftData models · `Analytics/` pure computation · `Service/` mutations, notifications, sample data · `Feature/<Screen>/` views · `Feature/Shared/` cards reused by 今日 and カレンダー · `Support/` formatting, calendar, palette.

`ObservationAnalyzer` takes plain arrays and returns plain structs — it touches neither views nor the persistence layer, so the comparison logic can be reasoned about (and tested) on its own. Views fetch with `@Query` and hand the results to it.

## Invariants that are easy to break

**Records are not linked to phases.** `BowelMovement`, `DailyRecord`, and `TargetRecord` carry only a date. Which phase a record belongs to is derived from that date every time. This is why editing a phase's start/end date silently re-derives every aggregate — do not add a phase relationship to a record model to "make queries easier".

**Every record has two dates.** `date` is `startOfDay` (what predicates filter on) and `recordedAt` is the real timestamp. Setting one without the other desynchronizes the calendar from the charts; use `BowelMovement.updateRecordedAt(_:)`.

**Averages divide by days that have a record, not by elapsed days.** A day with no entry means "did not log", not "zero". `DailyTally.hasRecord` defines the distinction, and `PhaseSummary` exposes `elapsedDays`, `analyzedDays`, and `recordedDays` so the UI can show the basis. Bristol/pain/urgency averages are taken **per movement**, not as a mean of daily means, so busy days are not down-weighted.

**A zero-movement day only counts when the user says so.** `DailyRecord.hadNoBowelMovement` is the difference between "there was none" and "not written yet"; it makes `isEmpty` false so the day flows through `hasSummary` into `hasRecord` and is averaged as 0. Anything that prunes empty summaries must keep that flag in `isEmpty`, or 0-count days silently vanish from the averages.

**`warmupDays` narrows the aggregation window, not the phase.** `elapsedDays` still counts from the real start date; `ObservationPhase.analysisStartDate(calendar:)` moves only where averages and comparisons begin. Excluded days keep their records and are still plotted, so the chart shows points outside the average line by design — do not "fix" that by dropping them from `dailyTallies`.

**Three states of a `TargetRecord`, not two.** No row = not logged; a row with `isCompleted == false` = explicitly did not do it. `ObservationAnalyzer` compares only explicitly-marked days, so collapsing these two into one boolean would silently turn "forgot to log" into "skipped it" — the same error as counting an unlogged day as 0. `ObservationStore.toggleTarget` cycles untracked → done → not-done → untracked (deleting the row) to keep the third state reachable and reversible. The row's second line names which of the three it is, in the same words as the footer's tap cycle — it used to show the target's type, which the name already tells you, while the shape of a circle does not tell you whether the day is unrecorded or recorded.

**A `TargetRecord` carries no time of day.** `ObservationAnalyzer.markedDays` splits days into 実施した/実施しなかった by `isCompleted` alone, and neither the PDF nor the CSVs print a completion time, so a timestamp on the row has no reader — what it does have is a question it cannot answer: a twice-a-day medication has two times and one row. The rule is that the row is one day's worth, marked 実施した only when the whole day was; `TargetChecklistCard`'s footer states it, since nothing about a checkmark says it. Re-adding a time drags its own invariant back with it — `.now` on a day backfilled from the calendar stamps today's clock, and an hour-and-minute picker cannot then correct the day — so it needs a reader that justifies the weight, which day-level averaging is not.

**Adherence is reported as counts, never as a rate.** `TargetAdherence` exposes `completedDays` / `skippedDays` / `untrackedDays` against `analyzedDays`. A percentage would have to guess what untracked days mean, which is the one thing the data cannot say.

**Below `AnalysisBasis.minimumComparisonDays`, show the numbers but not the sentence.** `PhaseComparison.meetsMinimum` / `AdherenceComparison.meetsMinimum` gate `MetricChange.sentence(referenceName:)` only. The deltas stay visible — hiding data the user entered is worse — but a one-day difference must not be phrased as a finding.

**`endDate == nil` means ongoing, not "ends today".** Use `effectiveEndDate(asOf:)` for anything that aggregates, and cap at today for anything that paints (an ongoing phase would otherwise colour the rest of the month in the calendar).

**Exactly one plan has `isActive`.** `ObservationStore.activate(_:)` clears the others; every screen reads the active plan via `#Predicate { $0.isActive }`.

**Phases within a plan never overlap.** Any given day belongs to at most one phase. This is the precondition for deriving phase membership from a date at all, so it is not a nicety — overlap breaks the app quietly. `ObservationPlan.phase(on:)` and `MonthCalendarView.phaseColor(on:)` both resolve a tie by taking the later-starting phase, so the UI shows one phase and hides the other; meanwhile `ObservationAnalyzer.summary(for:)` filters records by date alone and feeds the overlapping days into *both* phases' averages. The visible damage is a baseline-versus-intervention comparison that is partly a comparison with itself, `recordedDays` inflated past `AnalysisBasis.minimumComparisonDays` so a sentence appears that the data does not support, and a phase whose targets never reach `TargetChecklistCard` (it reads `phase(on:)`) yet keeps accruing `untrackedDays` — unrecordable days counted as unrecorded. None of it surfaces as an error.

Gaps are legal and deliberate: a day belonging to no phase is normal, and `PhaseStartSheet` allows starting one inside a past gap. The rule is also per-plan — records carry no plan reference either, so two plans covering the same days is the intended way to re-slice the same records.

**Every phase date edit goes through `ObservationStore`'s フェーズの期間 section.** `startPhase` and `moveStart(of:to:)` call `closePhases(startingBefore:in:excluding:)`, which closes every phase that starts earlier and still extends into the new start — *not* only the ongoing ones, since starting inside a closed phase overlaps just as badly. Phases already ending before that day are left alone, so gaps are never silently filled. `setEnd(of:to:)` stops at the day before the next phase and refuses `nil` unless `canBeOngoing(_:)`: only the last phase can be ongoing, because dropping a middle phase's end date swallows every phase after it.

The pickers and the store are a pair. `closePhases` clamps with `max(previousDay, start)` so a phase can never end before it begins, and that floor stays unreachable only because `newPhaseStartRange(in:)` and `startDateRange(for:)` keep the new start after every earlier phase's start — loosen a bound and the clamp starts emitting one-day phases that overlap instead. `startDateRange(for:)` bounds against the previous phase's **start**, not its end, so a boundary moves in one step with the previous phase's end following; bounding on the end instead makes the user open a gap and close it from the other side. Both builders go through `range(from:to:)`: an inverted `ClosedRange` traps at runtime, and a last phase that started today inverts the naive bounds. That clamp only keeps the picker from trapping; it does not make the collapsed range a legal one. When the latest phase starts today the bounds invert and `newPhaseStartRange(in:)` collapses to *tomorrow* — opening the sheet on that lands a phase in the future, the one thing the upper bound exists to prevent. So every entry that opens `PhaseStartSheet` gates on `canStartNewPhase(in:asOf:)` and disables itself with the reason spelled out; the clamp is the backstop, not the guard. Judge it against today rather than the day on screen, since that is what the sheet's own range uses.

**Days after today are not recordable.** The calendar wraps only past and present cells in a `NavigationLink`; future cells render dimmed and without `.isButton`. `DayDetailView` is the only way to reach a day's editors, so blocking navigation is what keeps records out of the future — the same reason `effectiveEndDate(asOf:)` and the phase bands stop at today. Phase boundaries are capped at today too: a phase starting tomorrow could not be recorded into, would leave today belonging to no phase, and would push `newPhaseStartRange`'s lower bound past today so no phase covering today could be started either.

**"Today" is state, not a `.now` read inside `body`.** `TodayView` and `MonthCalendarView` each hold `@State private var today` and apply `.tracksCurrentDay($today)` (`Support/CurrentDay.swift`), which refreshes on `.NSCalendarDayChanged` and on `scenePhase == .active`. Reading `.now` in `body` looks equivalent but has nothing to trigger a re-read: leave the app open across midnight and 今日 keeps yesterday's date — and because the screen derives a record's date from the day it is showing, everything entered after that lands on yesterday. The calendar goes stale the same way, leaving today's cell dimmed and un-navigable because `isFuture` is measured against a stale bound. The notification covers being open at midnight and the scene phase covers waking to a new day; either alone drops half the cases. `.NSCalendarDayChanged` arrives on an unspecified thread, so the publisher hops to the main run loop before touching state, and `refresh()` compares by day rather than assigning `.now` every time — `TodayPlanView` is keyed on `today` and builds its `@Query` predicates from it, so a churning value would rebuild the subtree on every fire.

**Phase actions live on the 今日 card, not in its toolbar.** The phase block in `TodayPlanView.header` is the `NavigationLink` into `PhaseEditorView`, and one `フェーズを始める` button sits under it — the same wording as `PlanEditorView`'s, and the same wording whether or not a phase covers today. The screen is opened several times a day to record, so its one toolbar slot belongs to nothing rarer than that; ending a phase is a step further in (the 終了日 toggle, whose range already tops out at today) because it is the choice that drops days out of the comparison. What this replaced was exactly the duplicate to avoid: a toolbar item and a card button opening the same `PhaseStartSheet` under different names, both on screen at once whenever no phase covered today.

**The 今日 card order puts the input with no other entry point first.** `TodayView` is フェーズ → 観察対象 → 今日の排便 → 今日の記録 → 1日のまとめ. 排便 has the pinned `safeAreaInset` button, so its card sliding below the fold costs nothing — the input is always on screen. The target checklist is the only input living in the scroll, and `MovementListCard` above it grows with every record, so putting the checklist under the list means the one action that cannot be reconstructed later (a day's adherence) is the first thing to go off screen, and further off with every 排便 recorded. `countCard` is a display; a display can be scrolled to. `DayDetailView` repeats the order so the same cards are not in two arrangements.

**Nothing on the checklist appears just because the screen did.** 今日 is opened several times a day to record, so anything shown on appear is shown on every visit, and 未記録 is a legal state for most of the day — the app knows neither how many doses a target has nor when they are due — so an alert would report a non-problem all morning, cost a dismissal tap on every unrelated visit, and be closed unread within days, at which point it no longer reminds anyone but still charges the tap. Two quieter versions were built and removed as well: a 記録する label on the right of untracked rows, which appeared in one state of three and so read as an unfinished row rather than as an affordance, and a one-time hint above the rows retired by the first tap. What the card says about itself is the caption under each name and the footer. Forgetting is what the reminder in `NotificationService` is for: once, at an hour the user chose.

**`TargetAttachment` never reaches the export.** The photos on an observation target are prescriptions and drug information sheets — they carry the patient's name, birthdate, insurer number, and clinic. The PDF and the CSVs exist to be handed to someone, so a photo that leaks into `ReportPageView` or `ExportService` hands all of that over too, and the sharer cannot tell from the share sheet that it happened. Nothing in `Analytics/` or `Feature/Export/` may read `ObservationTarget.attachments`; the type is for on-device reference only. `AttachmentImage.prepared(from:)` is the only way in, and it re-encodes rather than storing the original so that Exif — including the coordinates of wherever the photo was taken — is dropped on the way.

**The transfer archive is the one file that carries photos, and it is not part of 書き出し.** `TransferArchive` exists so a phone can be replaced: it holds every model plus the attachment bytes, which is exactly why it must never appear where the export files are. It lives in 設定 > データ管理 > データの引き継ぎ, its footer says not to hand it to anyone, and it writes to a separate `Transfer` directory because `ExportService.prepareDirectory(named:)` empties whatever directory it is given — pointing it at `Export` would delete the CSVs the user just made. Restoring replaces everything rather than merging: records carry no plan reference, `DailyRecord` is `#Unique` on date, and `TargetRecord`'s three states collapse the moment one side wins, so every merge rule silently corrupts one of the three. `ObservationStore.restore(from:)` writes the archived `date` values back verbatim after each `init` has recomputed them — the initialisers re-apply `startOfDay`, and a device in another timezone would otherwise move records to a different day. Delete and insert share one `save()`, with `rollback()` on failure, so a half-restored store cannot replace the records that were already there.

**Cross-model rules live in `ObservationStore`, not in views.** Starting a phase closes the previous one, daily summaries are created lazily and pruned when emptied, etc. `PhaseEditorView` holds the dates in `@State` and writes them through the store rather than binding `@Bindable phase` straight to the pickers — a direct binding is what let phases overlap in the first place.

## Product constraints

**No medical judgement, ever.** The app states measured differences and nothing more: 「記録上、平均排便回数が58%減少しています」 is fine; 「効いています」「続けてください」 is not. `MetricChange.sentence(referenceName:)` is the single place that phrases a change — keep new copy neutral there rather than composing verdicts in views.

**Show the spread next to the average.** `PhaseSummary.spreads` carries min/max per metric so a reader can see whether a difference sits inside the day-to-day range. This is a measurement statement, not an interpretation, so it does not conflict with the rule above — and without it a small delta reads as more than it is.

**Recording must stay a few seconds.** Open → pick a Bristol value → save. Time is prefilled; pain, urgency, and notes are optional. Do not add required fields to `BowelMovementEditor`.

## Swift and project details

- **New files need no project-file edit.** `objectVersion = 77` with a `PBXFileSystemSynchronizedRootGroup` for `TameshiteLog/` — anything under that directory joins the target automatically. Hand-editing `project.pbxproj` to register sources will produce conflicting entries.
- **Everything is `@MainActor` by default** (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`), so explicit `@MainActor` annotations are redundant noise; off-main work needs `nonisolated` or `@concurrent`. Language mode is Swift 5, so data-race diagnostics are warnings.
- **Wrap `#Preview` in `#if DEBUG` whenever it touches `SampleData`.** `SampleData` is DEBUG-only but the preview macro expands in all configurations, so an unguarded preview breaks the Release build. Verify with `-configuration Release`.
- **Every full screen calls `.appBackground()`, including the branch that shows nothing.** A `Form` or `List` needs `.scrollContentBackground(.hidden)` alongside it or the system background covers the image. Apply it to the container that holds *both* branches, not to the loaded-content branch — 経過 and 今日 each paint an empty state instead of their content, and hanging the modifier on the content view leaves those two screens on the plain system background. Sheets are their own screens: `BowelMovementEditor`, `PhaseStartSheet`, and the editors reached from 設定 all need it too. `PhotoViewer` is the one deliberate exception, on `.background(.black)` because it shows a photo.
- **The accent color is applied at the root, not only in the asset catalog.** `AccentColor.colorset` holds the app's teal (`ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` and the generated `NSAccentColorName` both point at it), but on iOS 26 that alone left every SwiftUI control on the default blue. `TameshiteLogApp` applies `.tint(Color(.accent))` to `RootView`, which is what actually tints the buttons, checkmarks, tab bar, and the `Color.accentColor` call sites. Verify a colour change by screenshot, not by reading `Assets.car` — the asset compiles either way.
- **iPhone is portrait-only; iPad keeps all four orientations.** `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone` lists portrait alone. Landscape is not a flag away from working: in ~300pt of landscape content height, `PhaseTimelineChart`'s fixed `height: 240` plus the card's chrome (~366pt) pushes the metric picker off screen, and the calendar's six 59pt rows plus its headers (~438pt) mean a month no longer fits on one screen — which is the whole point of that screen. Re-enabling landscape means making the chart height depend on the viewport and deciding what a landscape month looks like first. iPad is left alone because Split View and Stage Manager hand the app arbitrary aspect ratios regardless of what it declares.
- **Japanese formatting is pinned**, not inherited from the device: `Formatting.locale` is `ja_JP` and the root view sets `.environment(\.locale, Formatting.locale)` so system-drawn controls match the hardcoded Japanese copy.
- **`SymptomLevel.absent`, not `.none`** — `.none` collides with `Optional.none` at use sites.
- **There is no `Info.plist` file** (`GENERATE_INFOPLIST_FILE = YES`); new keys go in as `INFOPLIST_KEY_*` build settings — but not every key works that way. `CFBundleDevelopmentRegion` is generated from `DEVELOPMENT_LANGUAGE` (the project's `developmentRegion`), so an `INFOPLIST_KEY_CFBundleDevelopmentRegion` is silently ignored. After adding a key, check the built `.app/Info.plist` with PlistBuddy rather than assuming the setting took.
- **The home-screen name is `CFBundleDisplayName` (ブリストルログ), not the target name.** `CFBundleName` stays `TameshiteLog`; renaming the target would not change what users see. The bundle identifier is `jp.hibiki.bristollog`, which matches neither — every `simctl` command wants the identifier, and passing the target name fails with `Simulator device failed to launch` rather than "no such app".
