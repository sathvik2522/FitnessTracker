# Calorie calculation and reconciliation — October 13, 2026

The existing EnergyBalance arithmetic and HealthKit aggregate queries were reused. This milestone adds a pure assessment policy, shared read scopes, and display formatting; it does not add another calorie formula, persistence schema, or HealthKit data source.

## Definitions and scope

- Logged calories are the unrounded sum of food portions in the selected local-day window. Queries include the start and exclude the end. For today, future-timestamped portions are excluded until the shared cutoff; historical windows include the complete local day.
- Resting and active energy come from the corresponding merged HealthKit cumulative statistics in kcal.
- Estimated expenditure = resting + active, only when both accepted inputs exist.
- Estimated balance = logged intake − expenditure. Negative means estimated deficit; positive means estimated surplus; zero means balance for the supplied values.
- An empty diary has a logged sum of zero, but does not establish zero actual intake. Balance stays unavailable until intake is recorded. Explicitly supplied measured/confirmed zero values remain valid.
- These are calorie estimates, not an exact measurement or conversion of fat gain/loss. There is no calorie-to-body-fat conversion, BMR fallback, daily extrapolation, or exercise multiplier.

## Pure Swift engine

`Nutrition/EnergyReconciliation.swift` depends only on Foundation and the existing EnergyBalance type. It accepts:

- A required immutable `LocalDayWindow`.
- Food energy with explicit value/missing/failed/known-incomplete state, window, and coverage metadata.
- Energy aggregates with a resting/active kind, value state, window, representation, and coverage metadata.

The result includes the existing numeric EnergyBalance plus separate expenditure and balance quality (`available`, `partial`, `unavailable`) and explanatory reasons. Missing food does not hide known expenditure. Missing, failed, invalid, conflicting, or known-incomplete required energy suppresses expenditure and balance rather than becoming zero. A known-incomplete intake suppresses balance while preserving known expenditure.

Available numbers with unverified collection coverage remain visibly qualified as partial estimates. Current-day windows always add a day-in-progress reason. A closed historical window is a temporal fact, not proof that all meals or energy samples were recorded. The live Health adapter always marks coverage unverified; it never upgrades coverage based on the date or permission-request completion. The complete-coverage input option exists for explicitly established inputs, not an inference the current app makes.

## Reconciliation rules

1. Only a merged HealthKit aggregate with an **exact matching window** is eligible for each energy kind. Matching includes start, cutoff, time-zone identifier, and partial/full-day scope.
2. Identical aggregate copies are used once. Conflicting copies are rejected; the engine does not sum them, choose the largest, or guess a source priority.
3. If an exact canonical aggregate exists, different-window representations contribute nothing. If only mismatched or overlapping windows exist, the required energy is unavailable. Subintervals are not combined into a guessed full-day total.
4. Per-source subtotals and workout representations are excluded, even when their numbers or intervals resemble the aggregate. The live adapter supplies only resting and active aggregates; actual workout records remain separate and contain no expenditure input.
5. The existing HealthKit query uses `.cumulativeSum` without `.separateBySource` or app-side raw-sample/per-source addition. Source overlap inside the merged result is delegated to HealthKit's statistics engine.

This engine reconciles **aggregate representations**, not raw samples. Equal values are considered duplicate aggregate copies only when their kind and complete scope match; this rule must not be reused to deduplicate two legitimate raw energy samples with equal quantities.

## Shared boundaries and refresh

`LocalDayWindow` now owns the existing calendar-based boundary logic in the pure module. `HealthDayWindow` is an alias rather than a duplicate implementation. The existing boundary tests were moved into the standalone calculation suite.

- Calendar day intervals handle 23-, 24-, and 25-hour days. No production path assumes 86,400 seconds per day.
- Today ends at the precise read cutoff. A single HealthKit statistics query uses the same predicate window without an integer-second bucket. Past days end at the following local midnight.
- At the exact first instant of a new day, a zero-duration scope is valid and empty. Food reads return no entries; Health reads return unavailable without constructing a zero-second statistics query. Future days remain invalid.
- `FoodEntryStore.snapshot(in:)` returns a typed `DailyNutrition` containing totals and their window. The dashboard's food and Health queries use that exact same scope.
- A manual/foreground load creates a fresh shared cutoff. A permission request can reuse an already loaded scope, preserving consistency; the UI shows the actual cutoff independently of the last query refresh timestamp.
- Date and time-zone changes invalidate old Health snapshots. Historical civil-date selections follow the selected/current device time zone; original travel-time-zone attribution is not stored. The UI displays the time-zone identifier.
- Existing request IDs still prevent older asynchronous results from replacing a newer selection.

## Rounding and presentation

`EnergyDisplay` is a shared, pure Foundation formatter. All kcal cards use nearest-whole-kcal rounding, with ties away from zero, only for display. Intermediate sums and subtraction retain Double precision. Locale-specific grouping is preserved.

Negative zero displays as zero. A small nonzero balance that rounds to zero is labeled **Approximately balanced**, rather than an exact zero or a zero-kcal deficit/surplus. Individual rounded cards may not add up visually to the separately rounded total; the underlying calculation uses the unrounded values.

The dashboard displays the window/cutoff, closed historical versus in-progress scope, partial/unavailable reasons, and the limitation of calorie estimates. Food completeness and Health coverage are not silently asserted.

## Assumptions that cannot be resolved definitively

- HealthKit does not reveal definitive read-denial status for every type. Missing data can mean no samples or hidden samples; neither becomes zero.
- A numeric cumulative sum does not establish continuous sensor coverage, full Watch synchronization, or complete permission coverage. Historical values may change after delayed sync, edits, or deletions.
- The app cannot determine from an already merged number whether two third-party sources described the same underlying event. It does not subtract suspected duplicates or arbitrarily prefer a source. Compare actual totals with Apple Health on the personal iPhone, including overlapping iPhone/Watch activity and third-party writers.
- SDK aggregation and interval-boundary behavior are delegated to HealthKit, not recreated through guessed prorating. Unit tests verify query construction and app policy; they do not prove Apple's execution against real overlapping samples.
- Food entries are summed as intentional portions. Matching meal names or quantities are not deduplicated because they can represent legitimate repeated portions. No feature currently confirms that a diary includes every meal.
- Resting + active is the requested expenditure model. It is not independently measured complete metabolism, and a calorie balance alone cannot establish exact fat-mass change.

## Changed files

Added:

- `PersonalFitness/Nutrition/LocalDayWindow.swift` — shared scope and DailyNutrition.
- `PersonalFitness/Nutrition/EnergyReconciliation.swift` — pure assessment and aggregate policy.
- `PersonalFitness/Nutrition/EnergyDisplay.swift` — common kcal formatting and labels.
- `PersonalFitnessTests/Calculations/EnergyReconciliationTests.swift` — 18 cases.
- `PersonalFitnessTests/Calculations/EnergyDisplayTests.swift` — 3 cases.
- This document.

Moved/refactored:

- `PersonalFitnessTests/Health/HealthDayWindowTests.swift` → `PersonalFitnessTests/Calculations/LocalDayWindowTests.swift`, retaining four boundary tests and updating the midnight-empty-window expectation.

Updated:

- `PersonalFitness/Health/HealthData.swift` — alias and adaptation of Health readings into pure inputs.
- `PersonalFitness/Health/HealthKitService.swift` — zero-length read/query guards; existing aggregate query strategy retained.
- `PersonalFitness/Persistence/FoodEntryStore.swift` — scoped reads sharing the existing query/aggregation path.
- `PersonalFitness/Dashboard/DashboardModel.swift` — typed nutrition scope, shared cutoff, injected clock for loading, assessment composition.
- `PersonalFitness/Dashboard/DashboardView.swift` — assessment state, scope/cutoff, balance labels, and explanatory copy.
- `PersonalFitness/Components/MetricRow.swift` — shared kcal formatting.
- Existing dashboard/Health conversion and state tests — explicit scoped inputs and cutoff/midnight regression checks.
- Xcode project membership and README.

EnergyBalance and NutritionTotals arithmetic, the FoodEntry model, signing settings, Health read permissions, and entitlements were preserved. The project was not regenerated.

## Verification

Xcode 27.0 (27A266a), iPhone 17e simulator, iOS 27.0:

| Check | Actual result |
| --- | --- |
| Final Debug simulator build and hosted suite | Exit 0; BUILD SUCCEEDED / TEST SUCCEEDED; 59 tests, zero failures |
| Pure Swift standalone suite | Exit 0; 36 tests, zero failures (also included in the iOS suite) |
| Final unsigned Release iPhone build | Exit 0; BUILD SUCCEEDED |
| Structural project and plist validation | Passed |
| Existing target/build-configuration comparison | Preserved |
| Real HealthKit authorization and real source-overlap reconciliation | Not verified on a physical iPhone |

Tests cover deficit, surplus, exact and near-zero balance, missing food/resting/active data, empty and known-incomplete inputs, partial days, identical/conflicting/overlapping representations, excluded workout/source totals, unverified historical coverage, historical DST calculations, midnight, invalid values and overflow, formatting, and actual SwiftData/Health-model cutoff alignment. The first-second-at-midnight regression was fixed and the suites rerun successfully.

The only build warning is the existing nonblocking AppIntents metadata-extraction warning. No new visual or spoken VoiceOver audit was performed for this calculation milestone. The workspace has no Git repository; original project targets and build configurations were compared with a pre-change copy.

Commands from the original workspace root:

```sh
xcodebuild -project outputs/PersonalFitness/PersonalFitness.xcodeproj \
  -scheme PersonalFitness -configuration Debug \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -derivedDataPath work/DerivedData -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO build test

swift test --package-path outputs/PersonalFitness --scratch-path work/swift-build-xcode

xcodebuild -project outputs/PersonalFitness/PersonalFitness.xcodeproj \
  -scheme PersonalFitness -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath work/DeviceBuild \
  CODE_SIGNING_ALLOWED=NO build
```

Logs: `work/energy-tests-final.log`, `work/energy-core-tests-final.log`, `work/energy-release-final.log`. Successful iOS result bundle: `work/DerivedData/Logs/Test/Run-PersonalFitness-2026.10.13_11-12-26--0700.xcresult`.

Before relying on personal results, complete the signing/authorization and real-data comparison steps in [HEALTHKIT_UPDATE.md](HEALTHKIT_UPDATE.md), including source overlap, DST days, missing data, and delayed sync.

Primary references: Apple's [statistics options](https://developer.apple.com/documentation/healthkit/hkstatisticsoptions), [statistics collection queries](https://developer.apple.com/documentation/healthkit/hkstatisticscollectionquery), and [read-authorization privacy model](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data).
