# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this app is

ためしてログ (TameshiteLog) — an iOS 26 app for logging daily bowel/symptom records and comparing **before and after starting, stopping, or changing something**. The first use case is diarrhea + medication, but the domain is deliberately generalized: the core concept is `ObservationTarget` (medication / supplement / food / exercise / lifestyle / other), never `Medication`.

Japanese-only UI, single app target, no dependencies, no test target, all data on-device (SwiftData, no account, no network).

## Build and run

```bash
# Build
xcodebuild -project TameshiteLog.xcodeproj -scheme TameshiteLog \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' build

# Run with 30 days of fake data (DEBUG only) — the fastest way to see every screen
xcrun simctl boot "iPhone 17 Pro"
xcrun simctl install "iPhone 17 Pro" \
  "$(ls -dt ~/Library/Developer/Xcode/DerivedData/TameshiteLog-*/Build/Products/Debug-iphonesimulator/TameshiteLog.app | head -1)"
xcrun simctl launch "iPhone 17 Pro" jp.hibiki.TameshiteLog -sampleData
xcrun simctl io "iPhone 17 Pro" screenshot shot.png
```

Deployment target is **iOS 26.0**. Always pass an explicit `OS=` in the destination: several installed runtimes (26.0–26.5) each expose a device named "iPhone 17 Pro", and an ambiguous destination silently resolves to whichever one xcodebuild picks.

`ls -dt` in the install line is deliberate: Xcode and `xcodebuild` keep separate `TameshiteLog-<hash>` directories under DerivedData, so a plain `ls -d ... | head -1` sorts alphabetically and can hand you a build from hours ago. Sorting by modification time picks the one you just built. The symptom is a screenshot that stubbornly shows the code you already changed.

Without `-sampleData` a fresh install opens onboarding. There is no test target, so `xcodebuild test` fails until one is added.

On first launch CoreData logs a wall of `Failed to stat path .../default.store` errors, then `Recovery attempt ... was successful!`. That is the store being created, not a bug.

## Layers

`Model/` SwiftData models · `Analytics/` pure computation · `Service/` mutations, notifications, sample data · `Feature/<Screen>/` views · `Feature/Shared/` cards reused by 今日 and カレンダー · `Support/` formatting, calendar, palette.

`ObservationAnalyzer` takes plain arrays and returns plain structs — it touches neither views nor the persistence layer, so the comparison logic can be reasoned about (and tested) on its own. Views fetch with `@Query` and hand the results to it.

## Invariants that are easy to break

**Records are not linked to phases.** `BowelMovement`, `DailyRecord`, and `TargetRecord` carry only a date. Which phase a record belongs to is derived from that date every time. This is why editing a phase's start/end date silently re-derives every aggregate — do not add a phase relationship to a record model to "make queries easier".

**Every record has two dates.** `date` is `startOfDay` (what predicates filter on) and `recordedAt` is the real timestamp. Setting one without the other desynchronizes the calendar from the charts; use `BowelMovement.updateRecordedAt(_:)`.

**Averages divide by days that have a record, not by elapsed days.** A day with no entry means "did not log", not "zero". `DailyTally.hasRecord` defines the distinction, and `PhaseSummary` exposes both `elapsedDays` and `recordedDays` so the UI can show the basis. Bristol/pain/urgency averages are taken **per movement**, not as a mean of daily means, so busy days are not down-weighted.

**`endDate == nil` means ongoing, not "ends today".** Use `effectiveEndDate(asOf:)` for anything that aggregates, and cap at today for anything that paints (an ongoing phase would otherwise colour the rest of the month in the calendar).

**Exactly one plan has `isActive`.** `ObservationStore.activate(_:)` clears the others; every screen reads the active plan via `#Predicate { $0.isActive }`.

**Cross-model rules live in `ObservationStore`, not in views.** Starting a phase closes the previous one, daily summaries are created lazily and pruned when emptied, etc.

## Product constraints

**No medical judgement, ever.** The app states measured differences and nothing more: 「記録上、平均排便回数が58%減少しています」 is fine; 「効いています」「続けてください」 is not. `MetricChange.sentence(referenceName:)` is the single place that phrases a change — keep new copy neutral there rather than composing verdicts in views.

**Recording must stay a few seconds.** Open → pick a Bristol value → save. Time is prefilled; pain, urgency, and notes are optional. Do not add required fields to `BowelMovementEditor`.

## Swift and project details

- **New files need no project-file edit.** `objectVersion = 77` with a `PBXFileSystemSynchronizedRootGroup` for `TameshiteLog/` — anything under that directory joins the target automatically. Hand-editing `project.pbxproj` to register sources will produce conflicting entries.
- **Everything is `@MainActor` by default** (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`), so explicit `@MainActor` annotations are redundant noise; off-main work needs `nonisolated` or `@concurrent`. Language mode is Swift 5, so data-race diagnostics are warnings.
- **Wrap `#Preview` in `#if DEBUG` whenever it touches `SampleData`.** `SampleData` is DEBUG-only but the preview macro expands in all configurations, so an unguarded preview breaks the Release build. Verify with `-configuration Release`.
- **Japanese formatting is pinned**, not inherited from the device: `Formatting.locale` is `ja_JP` and the root view sets `.environment(\.locale, Formatting.locale)` so system-drawn controls match the hardcoded Japanese copy.
- **`SymptomLevel.absent`, not `.none`** — `.none` collides with `Optional.none` at use sites.
- **There is no `Info.plist` file** (`GENERATE_INFOPLIST_FILE = YES`); new keys go in as `INFOPLIST_KEY_*` build settings — but not every key works that way. `CFBundleDevelopmentRegion` is generated from `DEVELOPMENT_LANGUAGE` (the project's `developmentRegion`), so an `INFOPLIST_KEY_CFBundleDevelopmentRegion` is silently ignored. After adding a key, check the built `.app/Info.plist` with PlistBuddy rather than assuming the setting took.
- **The home-screen name is `CFBundleDisplayName` (ためしてログ), not the target name.** `CFBundleName` stays `TameshiteLog`; renaming the target would not change what users see.
