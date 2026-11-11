# Navigation and dashboard foundation — October 13, 2026

Implemented in the existing Xcode project; it was not recreated. The SwiftData schema remains the single existing FoodEntry model, with local storage and CloudKit disabled.

## Behavior

- Native Dashboard, Food, Workouts, and Progress tabs with independent navigation stacks. The latter three are explicit placeholders.
- Dashboard shows logged calories and protein/carbohydrate/fat totals, resting/active energy, estimated total expenditure, deficit/surplus, steps, workout summary, and body weight. Health values remain unavailable; no authorization, query, or sample personal data was added.
- Date picker, previous/next-day buttons, return-to-today button, and future-date prevention. The day follows midnight when viewing today and preserves a historical selection otherwise. Queries use half-open local calendar day intervals rather than fixed 24-hour windows.
- FoodEntryStore owns daily SwiftData reads; DashboardModel owns selection, refresh and loading/error state; NutritionTotals owns aggregation. Views present those results. Refresh occurs on selection, foreground activation, and pull-to-refresh.
- Reusable MetricCard / MetricRow, SectionHeading, EmptyState, LoadingState, ErrorMessage and ActionButton. System colors, semantic fonts, wrapping labels, VoiceOver groups and labels, and 44-point date controls. Cards switch to one column at accessibility text sizes; date controls stack vertically.
- Invalid or overflowing nutrient totals remain unavailable, with valid other nutrients preserved. Empty-day totals explicitly mean zero logged portions.

## Files changed

Modified:

- `PersonalFitness/App/PersonalFitnessApp.swift` — tab root and shared storage-error presentation.
- `PersonalFitness/Dashboard/DashboardView.swift` — presentation, cards, date controls, refresh and state views.
- `PersonalFitness/Components/MetricRow.swift` — fractional gram/weight display.
- `PersonalFitness.xcodeproj/project.pbxproj` — source membership and navigator groups, retaining existing targets and build settings.
- `Tools/validate_project.rb` — validates actual on-disk source membership as the project grows.
- `README.md` — current architecture, test counts, and verification links.

Added:

- `PersonalFitness/Navigation/AppNavigation.swift`
- `PersonalFitness/Components/DesignSystem.swift`
- `PersonalFitness/Dashboard/DashboardModel.swift`
- `PersonalFitness/Persistence/FoodEntryStore.swift`
- `PersonalFitness/Nutrition/NutritionTotals.swift`
- `PersonalFitnessTests/Calculations/NutritionTotalsTests.swift`
- `PersonalFitnessTests/Dashboard/DashboardModelTests.swift`
- `PersonalFitnessTests/Persistence/FoodEntryStoreTests.swift`
- This report and `Verification/foundation-light.png`, `Verification/foundation-accessibility-dark.png`.

## Actual verification

Xcode 27.0 (27A266a), iPhone 17e simulator with iOS 27.0.

| Check | Result |
| --- | --- |
| Debug simulator build and hosted XCTest suite | Exit 0; BUILD SUCCEEDED / TEST SUCCEEDED; 19 tests, 0 failures |
| Standalone macOS calculation suite | Exit 0; 11 tests, 0 failures (included in the 19 above) |
| Unsigned Release build for physical iPhone | Exit 0; BUILD SUCCEEDED |
| Structural project validation and plist validation | Passed |
| Initial visible dashboard at standard text size, light appearance | Visually checked on iPhone 17e |
| Initial visible layout at largest accessibility text size, dark appearance | Visually checked; date controls wrap and stack without horizontal clipping |
| Simulator settings | Restored to their original large text size and light appearance |

The first Debug attempt exposed an initialization-order error in DashboardModel; it was fixed before the successful final run. Builds retain only the nonblocking AppIntents metadata-extraction warning for an app that does not use AppIntents.

New tests cover whole-portion totals, empty days, invalid values and overflow; future-date clamping, DST-aware navigation, midnight behavior, same-date reselection, loaded summaries with missing health energy; and persistence query boundaries including a 23-hour DST day.

Commands run from the original workspace root:

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

Logs are in `work/foundation-tests-fixed.log`, `work/foundation-core-tests.log`, and `work/foundation-release.log`. The simulator result bundle is `work/DerivedData/Logs/Test/Run-PersonalFitness-2026.10.13_08-03-07--0700.xcresult`.

The workspace still has no Git repository. The project-file diff was inspected against a pre-change copy; project generation was not rerun. No HealthKit read implementation, full food diary, or workout logging was introduced.

Remaining verification: physical iPhone signing and execution, actual authorized HealthKit data, spoken VoiceOver traversal, interactions across all four tabs, and a broader device/OS layout matrix. Visual checks cover the initial visible viewport, not every scrolled card or every state. The persistence tests use in-memory stores; disk durability across relaunch is not newly verified.

[Light dashboard](Verification/foundation-light.png) · [Largest accessibility text, dark appearance](Verification/foundation-accessibility-dark.png)
