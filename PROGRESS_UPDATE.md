# Progress and reporting — October 13, 2026

## Available reports

Open **Progress**. Choose Day, Week, Month or Custom, then select a date or inclusive date range. Previous/Next move whole calendar periods. Weeks follow the device calendar's first weekday. Current periods end at today's available cutoff, not a forecast. Custom ranges support up to 90 calendar days per query; any historical month can be selected individually.

- **Calories:** native Swift Charts plot logged intake against estimated resting + active expenditure. Missing values create gaps. Actual recorded zero values remain valid. Today's incomplete values are faded points, without a line to completed-day values.
- **Range balance:** intake minus expenditure over only the same closed days that have both required energy values and logged food. The matched-day count is shown. An empty diary is unknown intake, not confirmed zero. Totals describe recorded food, with the number of logged days shown; neither food nor Health coverage is assumed complete.
- **Macros:** protein, carbohydrate and fat history, range totals and daily numeric detail. Invalid logged values make that metric's total unavailable rather than silently dropping the bad day.
- **Weight:** latest daily sample per source, plus a trailing seven-calendar-day mean using recorded days only, with at least two days required. Six lookback days are read before the selected range so means at its start remain meaningful. Missing days are not filled. Manual and Apple Health series are never pooled; multiple readings on one day do not overweight its mean. Short-term fluctuations do not directly measure fat gain or loss.
- **Weight history & manual entry:** all readable Health samples and locally stored manual samples, labeled by source. Add/edit/delete manual entries in kilograms. Historical additions default to the selected period's last day, and editing preserves their timestamps unless changed explicitly. Health samples are read-only; manual entries are never written to Apple Health.
- **Training:** daily manual completed-session frequency, all-state strength history, cardio/stair-climber history and exercise progression by external load, reps and recorded sets. Progression reuses the existing calculation engine and snapshot exercise IDs, including exercises no longer in the library. Active/cancelled sessions do not contribute to completed frequency or progression.
- **Health workout history:** unique Health UUID records and readable-day coverage are displayed separately from manual counts. Possible manual matches use the existing conservative time/activity rule. No combined manual-plus-imported count is produced, and workout/machine calories never become expenditure inputs.
- **Daily details:** original persisted food portions, macros, resting/active readings (unavailable versus query-failed), the exact calculation window/time zone, expenditure, balance, quality reasons, manual sessions and readable Health records.

Charts use native Swift Charts on the existing iOS 17 deployment target, with accessible labels and numeric history/detail views. No charting dependency, network service, analytics or external nutrition data was added.

## Architecture and files

New files:

- `PersonalFitness/Progress/Core/ProgressLogic.swift`: pure calendar ranges, day reports, coverage-aware range totals, chart gaps, source-separated weight trends and validation. Included in the standalone Swift package.
- `PersonalFitness/Progress/ProgressModel.swift`: range selection, cancellable refresh, explicit Health connection and loading/error states; stale reads cannot overwrite newer dates.
- `PersonalFitness/Progress/ProgressStore.swift`: range-scoped local snapshots and validated manual-weight upsert/delete operations.
- `PersonalFitness/Progress/ProgressView.swift`: native report controls, summaries, navigation and daily history.
- `PersonalFitness/Progress/ProgressCharts.swift`: native energy, macro, weight and exercise charts with explicit labels and units.
- `PersonalFitness/Progress/WeightHistoryView.swift`: source-labeled samples and manual editor.
- `PersonalFitness/Progress/TrainingReportView.swift`: manual/Health frequency/history and range-specific exercise progression.
- `PersonalFitness/Progress/ReportDetailView.swift`: underlying daily values and calculation explanations.
- `PersonalFitness/Models/ManualWeight.swift`: one new SwiftData model; existing models are preserved.
- `PersonalFitnessTests/Calculations/ProgressLogicTests.swift`, `Persistence/ProgressStoreTests.swift`, `Health/ProgressModelTests.swift`, `PersonalFitnessUITests/ProgressFlowTests.swift`.

Updated existing navigation, model-container schema, dashboard preview schema, HealthData/HealthKitService read-only history boundary, Package.swift, project membership and Charts framework linkage, generator/validator, README and verification screenshots. Existing targets, deployment settings, signing configuration and Health permissions are preserved. The project was extended rather than recreated.

The reports use the existing energy reconciliation engine and HealthKit statistics aggregates, not raw energy sums. Health history adds a read-only body-mass sample query using the already requested body-weight permission. Refresh/launch never requests authorization; only Connect Apple Health does. Query failures and unavailable readings remain explicit. Health samples stay in memory and are refreshed, not copied into a second local import database.

SwiftData adds only ManualWeight, with stable IDs, positive finite values and nonfuture timestamps. Source-specific weight series prevent a manually copied Health weight from influencing a pooled trend twice. A disk migration test opens a prior seven-model workout/nutrition store and verifies food/workout records remain intact.

## Verification

Environment: Xcode 27.0 (27A266a), iOS 27 simulator on iPhone 17e (`SIMULATOR_UUID`), unchanged iOS 17 deployment target.

| Check | Actual result |
| --- | --- |
| Final complete Debug `build test` | Exit 0, `TEST SUCCEEDED`; 101 hosted unit + 5 UI tests, zero failures |
| Final Debug simulator build / unsigned Release generic-iPhone build | Both exit 0, `BUILD SUCCEEDED`; no physical signing/install is claimed |
| Standalone `swift test` | Exit 0; 59 tests passed (overlap hosted cases) |
| Corrected Progress UI test | Exit 0; historical manual entry/edit, relaunch persistence and daily missing-data detail passed |
| Accessible-label audit | Passed `.sufficientElementDescription` on the tested weight-history screen; not a full VoiceOver test |
| Disk persistence/migration | Passed; manual weight edits retain IDs/dates, prior nutrition/workout schema preserved |
| Project/tool/plist checks | Passed; all three existing targets and their build configurations preserved, Charts linked and source membership valid |
| Visual review | Source-labeled weight-history screen reviewed; screenshot contains an isolated fixture, not personal measurements |
| Git diff/status | Unavailable: workspace has no Git repository |

Initial compilation errors (an observable-model initializer, a formatter closure and a SwiftUI.ProgressView naming collision) were fixed. An initial UI assertion needed to scroll a lazy list; the corrected test passed. Earlier failed test diagnostic collection stalled after cases finished and that owned command was stopped. The final complete command used `-collect-test-diagnostics never` and completed normally with exit 0. Final chart-title labels were then checked with Debug/Release builds; no calculation or persistence behavior changed after the passing suite.

Workspace logs: `work/progress-verified-all.log`, `work/progress-pure.log`, `work/progress-ui-final.log`, `work/progress-debug-final.log`, `work/progress-release.log`. Successful result bundle: `work/DerivedData/Logs/Test/Run-PersonalFitness-2026.10.13_14-26-41--0700.xcresult`. [Weight-history fixture screenshot](Verification/progress-weight-fixture.png). Test coverage includes calendar week/month/current-day ranges, reverse/future/overlong ranges, DST/midnight boundaries, missing food versus logged zero, missing energy versus measured zero, matched-day historical balance, invalid macro/calorie totals, chart gaps, weight daily representatives/means/source separation, lookback, stale requests, explicit authorization, UUID workout deduplication, disk persistence and schema migration.

## Open, build and test

From `outputs/PersonalFitness`:

```sh
open PersonalFitness.xcodeproj
xcodebuild -project PersonalFitness.xcodeproj -scheme PersonalFitness \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project PersonalFitness.xcodeproj -scheme PersonalFitness \
  -configuration Release -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
SIMULATOR_ID='SIMULATOR_UUID'
xcodebuild -project PersonalFitness.xcodeproj -scheme PersonalFitness \
  -configuration Debug -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -parallel-testing-enabled NO -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO test
swift test
```

Use `xcrun simctl list devices available` to choose a simulator on another Mac. Command-R and Command-U work with the PersonalFitness scheme in Xcode. Select your developer team/unique bundle identifier for physical-device installation, as described in README.

## Physical-device and scope limitations

`xcrun devicectl list devices` reported only simulated devices. No physical iPhone or Apple Watch was available, so device installation, real Health authorization, source overlap/reconciliation and actual Watch data remain unverified. An automated accessibility-label audit does not replace hands-on VoiceOver focus/navigation testing. Full physical-device and Dynamic Type size coverage still requires manual validation.

Reports can only use manually recorded local data and readable Apple Health samples. Missing Health reads cannot establish denied access or zero activity. Historical energy estimates may change after sync and do not establish full-day coverage. No estimate claims exact fat gain/loss. Custom reports are capped at 90 days to bound per-day Health queries; multi-year exports, recovery reports, automatic forecasting and combined-source weight trends are not implemented.
