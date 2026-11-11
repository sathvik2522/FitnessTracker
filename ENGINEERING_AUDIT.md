# PersonalFitness engineering audit — 2026-10-13

## Scope and focused fixes

Inspected the existing project, three targets, shared scheme, app entry point, assets, configuration, SwiftData models/stores, HealthKit service, pure calculation engine, navigation, editors, reports and existing tests. Preserved the project and working features; no dependencies, networking or cloud synchronization were added.

Reproduced these defects with failing regression tests before fixing them:

1. **Recent food excluded by an integer-second cutoff.** A food at 3600.25 seconds was missing from a report refreshed at 3600.75 seconds. `LocalDayWindow` now preserves the exact cutoff. HealthKit uses a single `HKStatisticsQueryDescriptor` with `.cumulativeSum` and the same window predicate rather than requiring an integer-second collection bucket. Removed the report screen's one-second workaround. Day intervals still come from Calendar, including DST; a zero-length exact-midnight window does not execute a statistics query.
2. **Historical dates reinterpreted in a different calendar.** Switching Gregorian to Buddhist interpreted 2026 as a Buddhist year and moved Dashboard/report selections centuries backward. Calendar-identifier changes now preserve the selected instant's local day. Time-zone-only changes preserve civil components, including era/leap-month metadata. Custom report endpoints follow the same rule.
3. **Unrelated workouts labeled possible duplicates.** Two disjoint one-minute stair sessions within five minutes were labeled matches. Matching now requires actual temporal overlap and a known activity; the generic “Other cardio” category cannot establish an activity match. Exact UUID deduplication, separate records and all energy calculations remain unchanged.

Additional simulator checks exposed **dashboard text contrast/wrapping issues** and **report navigation links disappearing from the accessibility hierarchy after a fast date-range update**. Shared headings/cards and dashboard supporting text now use primary text contrast; metric labels and unavailable values wrap, and the grid switches to one column at larger standard Dynamic Type sizes. The report uses an eager stack within its existing 90-day limit; the previously failing weight-history navigation/edit/relaunch flow passed a focused retest. A 375×667-point SE screenshot also exposed a truncated preparation selection at accessibility XXXL. Food preparation/unit pickers now use wrapping inline choices at accessibility sizes. The small-screen editor test was corrected to reveal lazy form rows by scrolling; both the full preparation label and input fields were then verified reachable.

Added regression coverage for these cases, a dashboard accessible-description audit over overlapping scroll positions, and a disk lifecycle test verifying edited routine/cardio data, historical completed sets and persisted deletions after reopening. Existing HealthKit descriptor tests were adapted to the single aggregate query. Energy and HealthKit documentation now describes the precise cutoff.

## Project, persistence and privacy findings

- Native app `PersonalFitness`, hosted XCTest target `PersonalFitnessTests`, UI target `PersonalFitnessUITests`, shared `PersonalFitness` scheme; Debug/Release; iOS 17.0 deployment target; Swift 5 language mode. Installed compiler is Apple Swift 6.4 with Xcode 27.0 (27A266a).
- HealthKit and Charts are SDK frameworks. No runtime third-party packages. The Ruby xcodeproj tooling is development-only.
- App entry point and source/resource membership validate. Info.plist and entitlement files parse. HealthKit capability and entitlement are present, with an accurate `NSHealthShareUsageDescription`; no write authorization or background delivery.
- Authorization occurs only in explicit Connect/Review actions. Completing a request is not treated as proof of read access. Missing samples remain unavailable, genuine numeric zero is retained, and failed queries have explicit states.
- Energy is a cumulative HealthKit statistic for each metric. No manual raw/per-source sums, no workout energy additions, and no persisted HealthKit imports. Distinct Health workout UUIDs remain separate; similarity is only a display hint. Real source priority, duplicate third-party samples and cross-boundary sample behavior still require comparison with Apple Health on an iPhone.
- All eight SwiftData model definitions and container initialization are unchanged by this audit. CloudKit is explicitly disabled. Container failure preserves the store; there is no destructive reset fallback. Editors use value drafts, validated stable-ID upserts, save/rollback boundaries and historical snapshots.
- Tests exercise food/recipe edits and deletion, historical nutrition snapshots, routine/exercise snapshot isolation, active-session relaunch and timer deadlines, set edits/completion/cancellation, cardio edits, manual-weight edits/deletion, disk reopen and representative earlier-schema migrations. This is fixture evidence, not validation of the user's personal database or every old schema/runtime combination.
- Current schema migration is implicit/lightweight, with JSON snapshots for recipes/training. Before any future rename, type change, mandatory-field addition, or JSON format change, preserve representative old stores and introduce/test a deliberate versioned migration and compatible JSON decoding. Do not delete an unreadable store. No schema migration was introduced here.
- Source/configuration/package scan found no HTTP client, remote endpoint, analytics, telemetry, API credentials, backend or paid API. XML plist DTD URLs and documentation/development gem links are not runtime network operations. Signing team is intentionally blank; no signing secrets were introduced. This is static inspection, not a runtime packet capture.
- App icon catalog exists but has no artwork. No safely removable runtime dependency or obsolete source file was identified.

## Verification

| Check | Actual result | Evidence |
| --- | --- | --- |
| Project validator and project/Info/entitlement plist lint | Exit 0; passed | `work/audit-project-final.log` |
| Standalone SwiftPM calculations | Exit 0; 61 XCTest cases, zero failures | `work/audit-pure-verified.log` |
| Final unsigned Release device compilation | Exit 0; BUILD SUCCEEDED | `work/audit-release-verified.log` |
| Final Debug simulator build + complete unit/UI suite | Exit 0; BUILD/TEST SUCCEEDED; 109 unit + 6 UI cases, zero failures/skips | `work/audit-final.log`, `work/AuditFinal.xcresult` |
| SE default-text dashboard accessible descriptions | Case passed; combined initial command exited 65 because its old editor test failed | `work/audit-small-screen.log` |
| SE final accessibility-XXXL editor reachability and inline preparation | Exit 0; selected test passed | `work/audit-small-editor-final.log` |

The 61 standalone calculation tests overlap the hosted unit suite; they are not extra distinct cases. Simulator destinations: iPhone 17e, iOS 27.0, `SIMULATOR_UUID`; temporary iPhone SE (3rd generation), iOS 27.0, `SIMULATOR_UUID`. The temporary SE was removed after verification. Its initial cold boot/automation setup was slow; checks began after initialization, not at creation time.

Saved and visually inspected fixture/empty-state evidence: `Verification/audit-small-dashboard.png`, `Verification/audit-small-food-preparation.png`, `Verification/audit-small-food-fields.png`. These contain no real Apple Watch or personal Health measurements.

The saved final result summary (`work/audit-final-summary.json`) confirms 115 passed tests, zero failed, zero skipped and zero expected failures. No Swift source compiler warnings or errors were found in successful final compilation. Xcode emits the nonblocking **AppIntents metadata extraction skipped: no AppIntents.framework dependency** warning. UI runs also emit simulator/framework diagnostics about missing debugger-version metadata and duplicate Apple `UIAccessibilityLoaderWebShared` classes in WebKit/WebCore accessibility bundles; these are not app-defined duplicate classes. They were not “fixed” by changing SDK files or adding an unused framework.

**Unresolved runtime layout warnings:** The final result bundle records three “Invalid frame dimension (negative or non-finite)” warnings immediately after keyboard focus in manual-weight, exercise-name and cardio-duration fields. The same warnings are present in pre-audit `work/progress-verified-all.log` and `work/workout-verified-all.log`. Tests still typed, edited, saved and relaunched successfully. Frame uses were inspected: explicit width/height values are positive constants, and flexible/min/max frames use supported values; no negative or calculated explicit frame dimensions were found. The root cause is not established. This is an outstanding debugger/device investigation, not a resolved warning or a proven SDK bug.

**Contrast/clipping audit limitation:** Also ran XCTest's `.contrast` audit. It found low-contrast secondary supporting text, which was strengthened. Subsequent probes still flagged some primary black-on-white labels/values, including content near floating system-bar fades. Screenshots were inspected; the expanded probe also reported a clipping issue without an associated element. These automated contrast/clipping checks remain inconclusive/failed, not clean passes. The committed regression checks accessible descriptions only and does not assert passing contrast or clipping audits. Overlapping scroll passes inspect accessible content in the viewport. Manual contrast/increased-contrast and VoiceOver verification remain required. Probe logs are `work/audit-full-final.log`, `work/audit-ui-focused.log`, `work/audit-dashboard-retest.log`, `work/audit-dashboard-visible.log` and `work/audit-verified-all.log` (the latter exited 65 only on its expanded dashboard clipping probe).

Initial regression runs deliberately failed before the calculation/date/matching fixes (`audit-regressions-before.log`, `audit-pure-before.log`). The first sandboxed SwiftPM command failed because the compiler cache was not writable (`audit-pure-baseline.log`); the approved retry ran normally. The initial full UI run failed on dashboard accessibility and report navigation; the report navigation subsequently passed. These failures are retained, not counted as successful verification.

## Prioritized remaining work

1. **Before trusting personal Health reports:** sign with your Apple team and run on a physical iPhone with a paired Watch. Check selective denial/revocation, no samples versus zero, device lock, sync delays, overlapping iPhone/Watch/third-party energy, workouts across midnight, historical/DST days, and manual-session match hints against Apple Health. No physical iPhone or Watch was available to this audit.
2. **Before changing storage schema:** add deliberate versioned migration/JSON compatibility fixtures and test a backed-up real store. Also validate on iOS 17: only the installed iOS 27 simulator runtime was available.
3. **Accessibility and keyboard layout:** investigate the three pre-existing keyboard-focus frame warnings with a runtime stack trace; validate keyboard/scroll behavior on device. Resolve or explain the remaining contrast/clipping probe results, then perform spoken VoiceOver navigation, chart exploration, Switch Control and full large-text/light/dark checks across screens. Automated descriptions and selected SE/17e flows cannot establish complete accessibility compliance.
4. **Performance:** profile a full 90-day Health report on a phone. The current implementation queries each day separately; actual latency and cancellation with a large Health store are unverified.
5. **Project hygiene/distribution:** initialize Git if desired (this workspace has no Git repository); assign app icon artwork. App Store submission/privacy manifests and signed archives are outside this personal simulator audit.

## Commands to reproduce

Run from the workspace root:

```sh
cd "<workspace>"
open outputs/PersonalFitness/PersonalFitness.xcodeproj
```

Complete final simulator build and tests, as executed (choose a new result-bundle path for another run):

```sh
xcodebuild -project outputs/PersonalFitness/PersonalFitness.xcodeproj -scheme PersonalFitness \
  -configuration Debug -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -derivedDataPath work/DerivedData -resultBundlePath work/AuditFinal.xcresult \
  -parallel-testing-enabled NO -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO \
  build test > work/audit-final.log 2>&1
```

Unsigned device compilation and standalone calculations, as executed:

```sh
xcodebuild -project outputs/PersonalFitness/PersonalFitness.xcodeproj -scheme PersonalFitness \
  -configuration Release -destination 'generic/platform=iOS' -derivedDataPath work/DeviceBuild \
  CODE_SIGNING_ALLOWED=NO build > work/audit-release-verified.log 2>&1
swift test --package-path outputs/PersonalFitness --scratch-path work/WorkoutPackage \
  > work/audit-pure-verified.log 2>&1
GEM_HOME="$PWD/work/gems" GEM_PATH="$PWD/work/gems" ruby outputs/PersonalFitness/Tools/validate_project.rb
plutil -lint outputs/PersonalFitness/PersonalFitness.xcodeproj/project.pbxproj \
  outputs/PersonalFitness/PersonalFitness/Resources/Info.plist \
  outputs/PersonalFitness/PersonalFitness/Resources/PersonalFitness.entitlements
```

Small-screen checks used the same Debug test command with the SE destination UUID and these selectors:

```sh
-only-testing:PersonalFitnessUITests/ProgressFlowTests/testDashboardAccessibilityAtDefaultTextSize
-only-testing:PersonalFitnessUITests/NutritionFlowTests/testAccessibilitySizeFoodEditor
```

The SE was created with `xcrun simctl create PersonalFitness-Audit-Small com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation com.apple.CoreSimulator.SimRuntime.iOS-27-0`, then booted with `simctl boot` and `simctl bootstatus -b`. It was shut down and deleted after the checks. Recreate it and use the newly returned UUID to repeat them.

In Xcode select the PersonalFitness scheme and an iPhone simulator, then Run (⌘R) or Test (⌘U). For a physical phone, select an eligible Apple developer team and unique bundle identifier, verify HealthKit provisioning and the read purpose string, then Run with normal signing enabled. Do not add write permission or background delivery to complete this audit. Tap Connect Apple Health yourself; compare the readings with Health after Watch sync. Unsigned compilation does not verify signing, installation, authorization or real samples.

## File review

There is no Git repository at either the workspace root or app project (`git status` exits 128). No Git diff could be produced. Existing sources/tests were copied to `work/audit-before` before editing; a unified before/after patch is saved at `work/audit-changes.patch`. It was reviewed for unrelated edits. Models, model container, project/target definitions, assets and signing/privacy configuration were preserved. No runtime dependencies or obsolete files were removed.

New deliverables: this report and the three `Verification/audit-small-*.png` screenshots. Existing files changed: 23. The exact list follows:

```text
ENERGY_ENGINE.md
HEALTHKIT_UPDATE.md
PersonalFitness/Components/DesignSystem.swift
PersonalFitness/Components/MetricRow.swift
PersonalFitness/Dashboard/DashboardModel.swift
PersonalFitness/Dashboard/DashboardView.swift
PersonalFitness/Food/FoodEditor.swift
PersonalFitness/Health/HealthKitService.swift
PersonalFitness/Nutrition/LocalDayWindow.swift
PersonalFitness/Progress/ProgressModel.swift
PersonalFitness/Progress/ProgressView.swift
PersonalFitness/Workouts/Core/WorkoutLogic.swift
PersonalFitness/Workouts/WorkoutDaySummary.swift
PersonalFitnessTests/Calculations/LocalDayWindowTests.swift
PersonalFitnessTests/Calculations/ProgressLogicTests.swift
PersonalFitnessTests/Calculations/WorkoutLogicTests.swift
PersonalFitnessTests/Dashboard/DashboardModelTests.swift
PersonalFitnessTests/Health/HealthKitConversionTests.swift
PersonalFitnessTests/Health/ProgressModelTests.swift
PersonalFitnessTests/Persistence/FoodEntryStoreTests.swift
PersonalFitnessTests/Persistence/WorkoutStoreTests.swift
PersonalFitnessUITests/NutritionFlowTests.swift
PersonalFitnessUITests/ProgressFlowTests.swift
```
