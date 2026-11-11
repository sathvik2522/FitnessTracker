# Dashboard and nutrition redesign — October 20, 2026

## Delivered experience

The existing app now has five native tabs: Today, Food, Training, Progress and More. The shared visual system uses layered navy cards, accessible semantic accents and a light/system appearance option. There is no new runtime dependency or network service.

- **Today:** selected-date navigation, three interactive metric rings, optional-goal nutrition summary, expandable Health & Activity, actual sleep intervals and sources, recent local workouts/cardio, weight history and deterministic daily context. Quick actions open the existing food, strength, cardio, stair-climber and weight editors.
- **Food:** calorie and macro overview, meal groups, add/edit/move/copy/delete, offline ranked search with All/Recent/Frequent/Custom/Meals scopes, custom foods and recipes, source-aware portion shortcuts and a prominent diary action. Legacy entries remain Unassigned.
- **Draft safety:** the food composer belongs to the stable navigation root. Its native modal protects the editing session from tab changes. Home/activation, invalid saves and Cancel → Keep editing retain the draft. Only a successful store save dismisses it; stable IDs prevent duplicate upserts. Drafts are not crash/restart autosaved.
- **Training and Progress:** existing routines, sessions, sets, timer, cardio, stair-climber, weight, charts, history and export remain available with shared styling.
- **More:** explicitly configured nutrition/step goals, dark/light/system appearance, local export and calculation/privacy explanations. No personalized goal is assumed.

## Data definitions

Strain is unavailable: current activity counts/energy do not establish physiological strain. Recovery is unavailable: the app has no validated readiness model or HRV/resting-heart-rate baseline; sleep alone cannot establish a percentage. Detail views show actual supporting data and limitations. All three dashboard rings use neutral tracks when no meaningful target exists; the energy ring is never a percentage. Nutrition progress uses only explicitly configured goals, clamps drawing fractions to 0...1, keeps over-goal text separate, and never turns unknown intake into zero. Goals are preferences, not calorie-expenditure inputs or health prescriptions.

The pre-redesign diff and source archive were preserved privately in workspace `work/`. Existing uncommitted work was retained. No database reset, app deletion or signing-configuration change was performed.

## Baseline — before app modifications

The unchanged full scheme built and ran on iPhone 18 Pro Max / iOS 27: 142 hosted unit tests passed; 10/11 UI cases passed, with NutritionFlowTests.testFoodHistoricalEditingRecipeQuickAddAndRelaunch failing to type because Quantity did not receive keyboard focus. Overall xcodebuild exit 65 (not a successful baseline suite). The test assertions were retained. Raw log/result: workspace work/redesign-baseline.log and RedesignBaseline.xcresult. Existing frame warnings reproduced.

## Layout-warning investigation

Controlled tests ran the same unchanged stair-climber edit/relaunch UI journey before the redesign. Replacing the flexible keyboard toolbar group with a single ToolbarItem still passed but retained the frame warning (`RedesignKeyboardAB.xcresult`). Replacing the keyboard-toolbar host with a native safe-area “Done editing” strip passed the same assertions with no frame warning (`RedesignKeyboardSafeArea.xcresult`). The dismissal action still resigns the first responder, including decimal keyboards. This isolates the keyboard toolbar layout path in this environment; final full-flow warning results are recorded separately below.

## Implementation and data preservation

- Five native tabs: Today, Food, Training, Progress, More. Today quick actions use the existing food/workout/cardio/weight editors and stores.
- Adaptive navy surfaces, metric rings, macro bars, meal icons and optional configured goals. Explicit light/system appearance is available in More. Empty rings use neutral tracks; no default personal targets or illustrative health values are supplied.
- Today reuses `DashboardModel`, `EnergyAssessment`, authorized Health reads, sleep overlap union and weight trends. Date changes refresh health/sleep/weight, with request tokens preventing late responses replacing another day. Health & Activity expands to existing energy, activity and workout reconciliation. Sleep timeline draws only actual unioned asleep intervals, with query window, sources and conflicts; gaps are not labelled awake.
- Food has a goal-aware overview, explicit meal groups and snapshot-safe edit, move, copy and delete. Legacy entries stay Unassigned. Offline search offers ranked matches and All/Recent/Frequent/Custom/Meals scopes. Source portions use explicit gram weights only. Custom food and recipe creation continue into logging.
- The food composer is owned by the stable tab root. Its native modal prevents tab switching from destroying an unsaved editing session. Each editor holds value drafts; validation failures retain input; Cancel asks before discarding; only a successful store save dismisses; stable IDs/upserts prevent repeated-save duplication.
- No SwiftData table/column changes. All eight models, bundle identifier, signing, entitlements and deployment target remain intact. Goal/appearance settings use local UserDefaults; no syncing. Export format **v2** adds these preferences while retaining all eight tables and historical raw snapshots; decoder accepts v1 without preferences. Export is not an in-app restore system.
- Training/Progress retain their existing workflows, with shared surfaces/actions/navigation styling. Manual workout calories remain separate from Health energy.

## Verification results

| Check | Actual result | Evidence in workspace `work/` |
| --- | --- | --- |
| First complete redesigned scheme, iPhone 18 Pro Max / iOS 27 | **170 passed: 155 hosted unit + 15 UI; 0 failed, 0 skipped; exit 0** | `RedesignFull.xcresult`, `redesign-full.log` |
| Final standalone calculations, `swift test --jobs 1` | **85 passed, 0 failed; exit 0** | `redesign-core-final.log` |
| Compact iPhone SE (3rd generation) / iOS 27 | **Four distinct UI journeys passed across retries**; not one four-case successful run | `RedesignCompactRetry.xcresult` (3 passed/1 failed), `RedesignCompactFood3.xcresult` (remaining case passed) |
| Signed generic iPhone Debug build | **BUILD SUCCEEDED** using the existing local signing configuration | `redesign-phone-build.log`, `RedesignPhoneBuild/` |
| Signed app integrity | `codesign --verify --deep --strict` **exit 0** with macOS trust-store access | Checked against the signed iPhone build |
| Project/source/resource membership | **Passed** | `Tools/validate_project.rb` |
| Info.plist and HealthKit entitlements | **plutil passed** | Existing configuration retained |
| Whitespace | **git diff --check passed** | Includes prior uncommitted work |

The complete rerun after the final full-width 44-point food-button refinement finished with **169/170 passed: 155/155 unit and 14/15 UI; exit 65** (`RedesignFullFinal.xcresult`, `redesign-full-final.log`). Its sole failure was the new historical-draft test tapping the meal picker after Quantity editing scrolled that row above the navigation bar. The test now explicitly scrolls it into view and asserts visibility/menu existence; no date, quantity, snapshot, cancel or persistence assertions were removed. The corrected focused retest **passed 1/1, exit 0** (`RedesignDraftFinal.xcresult`, `redesign-draft-final.log`), including Home/activation, failed validation, cancel recovery, the actual full-width Add to Diary button with minimum 44-point height, meal move/copy, snapshot totals and relaunch. Only test scrolling changed after the complete rerun; the app sources stayed unchanged. All 170 distinct cases passed across the final complete run plus focused retest; a second complete run after the test-helper correction was not performed. The first successful 170-test run predates the final button refinement; these are separate runs.

The compact runs exposed automation assumptions: an offscreen Create food action, a Quantity field behind the fixed footer that accessibility incorrectly reported hittable, and an offscreen meal picker. The helpers now bring the entire field/action into view and require keyboard focus before typing. Original quantity, meal, date, persistence and snapshot assertions were retained. An initial cold compact launch also failed before cases started with an accessibility-load timeout; subsequent launches ran normally.

Focused regressions fixed a real name-field focus loss by keeping its form section identity stable, and fixed ring navigation semantics after the accessibility hierarchy exposed generic elements instead of links/buttons. Failed save and cancel tests still assert that entered values remain intact. Sleep tests cover real interval union and descriptive comparisons across at least three valid prior nights; invalid/conflicting or partial windows suppress comparisons. No recovery score is derived.

The first full redesigned run contained no invalid-frame diagnostics and no Swift compiler warnings/errors. Xcode emitted the nonfatal AppIntents metadata-skipped message because the app does not use AppIntents, plus simulator/debugger diagnostics. These do not establish a warning-free physical-device runtime. The final complete rerun also recorded **no invalid-frame diagnostics**, no Swift compiler warnings/errors and an empty result-bundle runtime-warning list.

## Files changed in this milestone

Compared with the pre-redesign source snapshot (not the older Git HEAD):

```text
PersonalFitness.xcodeproj/project.pbxproj
PersonalFitness/App/CatalogLoadingView.swift
PersonalFitness/Components/DesignSystem.swift
PersonalFitness/Components/FitnessTheme.swift
PersonalFitness/Dashboard/DashboardDetails.swift
PersonalFitness/Dashboard/DashboardView.swift
PersonalFitness/Dashboard/DashboardWeightModel.swift
PersonalFitness/Food/EntryEditor.swift
PersonalFitness/Food/FoodComponents.swift
PersonalFitness/Food/FoodDiaryView.swift
PersonalFitness/Food/FoodEditor.swift
PersonalFitness/Food/FoodLibraryView.swift
PersonalFitness/Food/MealEditor.swift
PersonalFitness/Navigation/AppNavigation.swift
PersonalFitness/Navigation/MoreView.swift
PersonalFitness/Nutrition/FoodSearchScopes.swift
PersonalFitness/Nutrition/NutritionPresentation.swift
PersonalFitness/Nutrition/SleepAnalysis.swift
PersonalFitness/Persistence/GoalPreferences.swift
PersonalFitness/Persistence/LocalDataExport.swift
PersonalFitness/Persistence/NutritionStore.swift
PersonalFitness/Progress/DataExportView.swift
PersonalFitness/Progress/ProgressCharts.swift
PersonalFitness/Progress/ProgressView.swift
PersonalFitness/Progress/ReportDetailView.swift
PersonalFitness/Progress/TrainingReportView.swift
PersonalFitness/Progress/WeightHistoryView.swift
PersonalFitness/Workouts/CardioEditor.swift
PersonalFitness/Workouts/ExerciseLibraryView.swift
PersonalFitness/Workouts/RoutineEditor.swift
PersonalFitness/Workouts/StrengthSessionView.swift
PersonalFitness/Workouts/WorkoutKeyboard.swift
PersonalFitness/Workouts/WorkoutsView.swift
PersonalFitnessTests/Calculations/NutritionPresentationTests.swift
PersonalFitnessTests/Calculations/SleepAnalysisTests.swift
PersonalFitnessTests/Health/RedesignStateTests.swift
PersonalFitnessTests/Persistence/GoalPreferencesTests.swift
PersonalFitnessUITests/CatalogFlowTests.swift
PersonalFitnessUITests/NutritionFlowTests.swift
PersonalFitnessUITests/RedesignFlowTests.swift
PersonalFitnessUITests/WorkoutFlowTests.swift
README.md
UI_REDESIGN.md
Verification/RedesignOct20/Food-goal-fixture-light.png
Verification/RedesignOct20/README.md
Verification/RedesignOct20/Today-empty-dark.png
docs/ARCHITECTURE.md
docs/DATA_AND_CALCULATIONS.md
docs/DEVELOPMENT.md
docs/README.md
docs/USER_GUIDE.md
```

## Accessibility and appearance checks


## Reproduction commands

From the existing repository directory:

```sh
open PersonalFitness.xcodeproj
swift test --jobs 1
xcodebuild -project PersonalFitness.xcodeproj -scheme PersonalFitness -configuration Debug \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -derivedDataPath ../../work/FinalAuditBuild -resultBundlePath ../../work/RedesignFullFinal.xcresult \
  -parallel-testing-enabled NO -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO test
```

The focused historical-draft retest used the same simulator/build settings and:

```sh
xcodebuild -project PersonalFitness.xcodeproj -scheme PersonalFitness -configuration Debug \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -derivedDataPath ../../work/FinalAuditBuild -resultBundlePath ../../work/RedesignDraftFinal.xcresult \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:PersonalFitnessUITests/RedesignFlowTests/testHistoricalDraftSurvivesActivationErrorsCancelAndMealCopy \
  CODE_SIGNING_ALLOWED=NO test

# Uses the existing ignored local signing configuration.
xcodebuild -project PersonalFitness.xcodeproj -scheme PersonalFitness -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath ../../work/RedesignPhoneBuild build
codesign --verify --deep --strict ../../work/RedesignPhoneBuild/Build/Products/Debug-iphoneos/PersonalFitness.app
```

Use a fresh result-bundle path for a repeated run. On another Mac, choose an installed simulator from `xcodebuild -showdestinations -project PersonalFitness.xcodeproj -scheme PersonalFitness`. Local signing remains in ignored Configuration/Local.xcconfig; preserve the existing installed bundle identifier when updating the phone. No app deletion or database reset is needed.

## Physical iPhone status and remaining checks

After Mac verification, the connection retry and private pre-update safety copy **succeeded**. The copied store passed SQLite integrity checks with all eight expected tables and unique stable identifiers. The signed update was **installed in place successfully** using the existing bundle identifier; no app deletion or database reset was performed. Evidence: workspace `work/redesign-phone-install.json` / `.log`. The post-update container copy also succeeded. Read-only comparison verified identical table columns and **every pre-update stable ID, logical field and raw snapshot** across all eight tables; SQLite integrity checks passed. Private evidence is under workspace `work/private-phone-safety-oct20/` and is not committed.


Remaining owner/device checks:

1. **Unlock the iPhone and tap PersonalFitness.** The in-place installation is complete. Confirm existing food/workout history and any active workout, then relaunch and test offline logging.
2. Use the explicit Connect Apple Health and separate sleep action where needed. Compare the same local day against Apple Health for resting/active energy, steps, workouts, weight and sleep. No authorization is requested automatically.
3. Check Today versus historical dates; current-day energy is provisional and historical coverage remains unverified. Manual workout calories must not augment Health active energy.
5. Keep the installed bundle identifier when renewing development signing. Use Xcode Run to update without deleting the app. The existing export is a safety artifact, not an in-app restore feature.

The app icon still lacks final custom artwork; no app-icon or physiological-score asset was fabricated for this milestone. No barcode scanning, favorites schema, in-app restore, validated strain/recovery model, Health writes, backend or cloud synchronization was added.
