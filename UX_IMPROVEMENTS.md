# Daily-use UX audit and implementation — October 17, 2026

## Evidence and priority


| Daily journey | Finding and implemented response |
| --- | --- |
| Understand today's status | Connected-Health explanation occupied the top of the dashboard; collapsed it into a disclosure. Empty diary metrics now show unavailable rather than implying measured zero intake. |
| Reach logging | Added Dashboard Food/Workout shortcuts; Food transfers the selected historical day through a binding rather than recreating the tab. Added a direct Sleep destination. |
| Create unknown food | Original picker creation saved only to the library, with no explicit continuation. A baseline simulator regression failed on the missing Save & log action. Added save-only versus save-and-log and a post-sheet-dismiss handoff into quantity/date editing. |
| Retain form information | Several new-record IDs were generated as plain view properties, creating an identity risk on parent reevaluation. Moved editor IDs into State. Added dirty-draft dismissal protection and explicit discard alerts, including manual-weight editing. The confirmed missing handoff is distinct from the identity risk; no claim is made that an existing saved record was reproduced disappearing. |
| Find/log a saved food | Existing local search and scaling retained. Library labels now include macros; added explicit Log actions for the selected diary date, saved feedback and safe library deletion. Creating/renaming an item now clears a stale search filter so a successful save cannot appear missing; the regression also checks that historical diary names/calories stay unchanged. |
| Build a meal | Existing ingredient snapshot logic retained. Added meal/recipe creation inside Add food, save-and-log for meals, and discard protection for meal/ingredient drafts. |
| Edit/delete a diary entry | Existing edit flow retained; added clear date context, stable identity, editor deletion and confirmation for diary deletion. Explicit saves and rollback remain in NutritionStore. |
| Add exercises | Existing creation required manual re-selection. Picker creation now returns the saved exercise directly into its parent routine/session. Added optional equipment/movement metadata, starter/custom labels, safe deletion and explicit installation of ten editable starter definitions. |
| Build a routine | Existing name/order/set-count controls retained. Added target reps, external kg and exercise notes; stable routine identity and unsaved protection. |
| Log a workout | Existing valid-set autosave, rest deadline and interrupted-session recovery retained. Added saved completion summary, protected invalid-text closure and saved-record deletion confirmation. New starts are disabled while another workout is active. |
| Review history/progression | Existing completed-set progression and source-separated reports retained. Tests cover historical snapshots, disk reopen, completed/cancelled/active status and external-load volume. |
| Sleep and context | Added separately authorized sleep reads, seven-night history, overlap-aware duration, explicit in-bed/missing/conflicting states, and descriptive local-training counts. No clinical readiness/recovery score is computed. |
| Accessibility/errors | Existing system colors/Dynamic Type components retained. Forms use 44-point numeric input touch areas, keyboard controls, explicit Cancel/Save choices and accessible labels; larger-text and dashboard description probes are rerun. Full real-device VoiceOver/contrast checks remain manual. |

## Data protection

No SwiftData model, schema/container membership or store URL changed. Existing eight persisted types remain. Equipment, movementType and builtInKey are optional Codable ExerciseSnapshot fields in existing JSON blobs; old snapshots decode without them. Tests explicitly remove those keys from legacy-format JSON and verify decoding. Starter installation is user-initiated, uses stable IDs, skips existing IDs and does not overwrite custom edits. Library edits/deletions never rewrite historical snapshots.


## Sleep policy

- Existing activity/energy/weight read types remain unchanged. **Enable sleep insights** requests only sleepAnalysis, read-only; no automatic authorization or writes.
- Nights use a local noon-to-noon interval attributed to the waking day. This is a documented display policy, not inferred sleep schedules. Sessions crossing the interval are clipped; noon splits very long/daytime sleep and shift workers should interpret the window label accordingly. The app uses the union of available asleep intervals, not Apple Health's private source-priority or sleep-episode grouping; displayed totals can therefore differ from Health.
- Overlap queries include samples starting before the interval. Durations union asleep intervals (unspecified/Core/Deep/REM), never add in-bed time and never add stages/sources again. Unknown categories are ignored.
- Awake/asleep overlaps are flagged as conflicting; the UI labels duration provisional and suppresses comparisons rather than guessing a preferred source. Missing sleep/in-bed values stay unavailable. Recorded sleep does not prove complete coverage.
- Comparisons require three valid prior recorded nights; the current noon window must have closed. The comparison uses recorded nights, not interpolated missing days. Local completed training counts remain separate from Health workouts and energy.
- No HRV, VO2, clinical advice or recovery score is inferred. Sleep may arrive late, change or be hidden by read permissions. The existing entitlement file is unchanged, including its pre-existing health-records and background-delivery keys. This update neither requests clinical records nor registers HealthKit background delivery; those extra capabilities are not needed for sleep reads.

Apple documents overlapping in-bed and stage samples in [HKCategoryValueSleepAnalysis](https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis) and query predicates in [sample queries](https://developer.apple.com/documentation/healthkit/executing-sample-queries).

## Verification

| Check | Actual result |
| --- | --- |
| Standalone pure Swift tests | Exit 0: **70 passed**, no failures (`work/ux-pure-final.log`). These overlap the hosted unit suite. |
| Complete simulator run | Exit 65: **123 unit + 8 UI passed**, one outdated exercise-row selector failed after workout completion (`work/UXVerifiedFinal2.xcresult`, `work/ux-final-verified2.log`). The row now includes “Custom exercise”; the selector was corrected and its full workout class passed below. No skips. |
| Final unit/workout retest | Exit 0: **123 unit + all 3 workout UI tests passed**, no failures/skips (`work/UXWorkoutRetest.xcresult`, `work/ux-workout-retest.log`). Together with the six unchanged food/progress UI cases in the complete run, all nine distinct UI journeys passed. The complete suite was not rerun after this test-only selector correction. |
| iPhone arm64 Debug compilation | Exit 0: **BUILD SUCCEEDED**, signing disabled (`work/ux-device-final2.log`). This does not verify installation, signing or device authorization. |
| Smaller simulator | iPhone SE (3rd generation), normal app animations: the complete historical food/recipe/edit/snapshot-cancel/relaunch/delete/quick-add journey passed in a focused run (`work/ux-small-editor-delete.log`, exit 0). Accessibility XXXL editor and sleep/date transfer cases passed individually in the earlier mixed run whose diary case failed before the helper correction (`work/ux-small-final.log`, exit 65 overall). |
| Project/data checks | Structural project validation, plist/entitlement lint, documentation links and `git diff --check` passed. SwiftData models/container diff is empty. Isolated reconstruction with the existing project-generation utility validated; the working project was not regenerated. |

 Intermediate test failures were used to fix the missing create/log action, scope sheet-specific selectors, replace an ambiguous discard popover with an explicit two-choice alert, and verify numeric keyboard focus. The first final-suite attempt was stopped after a test mistook the native search Close button for navigation Back; its saved-rename visibility assertion had passed. The helper now explicitly closes search before navigating, and the complete historical-snapshot regression subsequently passed. Overlapping simulator runs were stopped and subsequent UI checks run serially. They are not reported as passing runs. UI automation uses a unique temporary SwiftData store. For the complete run and final focused rerun, UIKit animations are disabled only inside the DEBUG test-store launch branch to avoid repeated simulator animation-quiescence waits; ordinary app launches retain animations. Focused food/recipe/edit/delete/relaunch, manual-weight and small-screen accessibility checks also passed with normal app animations. Compact diary swipe-to-delete was unreliable under simulator automation; the visible editor Delete action was exercised instead. The direct meal save-and-log shortcut still needs a manual UI pass (recipe creation/scaling/persistence are tested).

### Reproduce the checks

From the repository root (`outputs/PersonalFitness` in this workspace):

```sh
swift test --scratch-path ../../work/UXPureFinal
xcodebuild -project PersonalFitness.xcodeproj -scheme PersonalFitness \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -derivedDataPath ../../work/UXAuditBuild \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  CODE_SIGNING_ALLOWED=NO test
# After the exercise-row test selector correction, all hosted units and all
# workout UI journeys are rerun (the other six UI cases passed above):
xcodebuild -project PersonalFitness.xcodeproj -scheme PersonalFitness \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -derivedDataPath ../../work/UXAuditBuild -parallel-testing-enabled NO \
  -collect-test-diagnostics never -only-testing:PersonalFitnessTests \
  -only-testing:PersonalFitnessUITests/WorkoutFlowTests CODE_SIGNING_ALLOWED=NO test
xcodebuild -project PersonalFitness.xcodeproj -scheme PersonalFitness \
  -destination 'generic/platform=iOS' -derivedDataPath ../../work/UXDeviceBuild \
  CODE_SIGNING_ALLOWED=NO build
```

The simulator UUID is specific to this Mac; use `xcrun simctl list devices available` to choose a local replacement. The complete test run additionally saves `work/UXVerifiedFinal2.xcresult`, and the final focused retest saves `work/UXWorkoutRetest.xcresult` from the workspace root. To structurally validate with the installed development gem, run `GEM_HOME="$PWD/../../work/gems" GEM_PATH="$PWD/../../work/gems" /usr/bin/ruby Tools/validate_project.rb`. Other Macs can install the pinned development gems using `Tools/Gemfile` as documented in [Tools](Tools/README.md).

## Physical-phone checks after updating


## Remaining validation and limitations, in priority order

2. Recheck real-device VoiceOver, normal animations, keyboards and compact swipe actions. Automated tests cover accessible descriptions and large-text reachability, not a complete VoiceOver or contrast assessment. The visible diary editor Delete flow is automated; direct meal save-and-log needs its manual pass.
3. The previously observed non-failing SwiftUI “Invalid frame dimension” runtime warning still occurs during simulator keyboard/form interactions. No failing calculation or layout assertion has been traced to it; its source remains unresolved. Xcode also emits skipped AppIntents metadata and simulator accessibility/debugger diagnostics. No Swift compiler warning was found in the final iPhone build. The complete simulator result bundle records six non-failing frame runtime warnings; the final focused rerun records three.
4. Unsaved ordinary form drafts are not a process-termination backup. No app-data export/import or sync was added. The existing app-icon catalog still lacks finished artwork; this pass concentrated on data safety and daily logging.

## Changed files

- `IPHONE_INSTALLATION.md`
- `PersonalFitness.xcodeproj/project.pbxproj`
- `PersonalFitness/App/PersonalFitnessApp.swift`
- `PersonalFitness/Components/DesignSystem.swift`
- `PersonalFitness/Dashboard/DashboardView.swift`
- `PersonalFitness/Dashboard/SleepOverview.swift`
- `PersonalFitness/Food/EntryEditor.swift`
- `PersonalFitness/Food/FoodComponents.swift`
- `PersonalFitness/Food/FoodDiaryView.swift`
- `PersonalFitness/Food/FoodEditor.swift`
- `PersonalFitness/Food/FoodLibraryView.swift`
- `PersonalFitness/Food/MealEditor.swift`
- `PersonalFitness/Health/HealthData.swift`
- `PersonalFitness/Health/HealthKitService.swift`
- `PersonalFitness/Health/SleepModel.swift`
- `PersonalFitness/Navigation/AppNavigation.swift`
- `PersonalFitness/Nutrition/SleepAnalysis.swift`
- `PersonalFitness/Persistence/NutritionStore.swift`
- `PersonalFitness/Persistence/WorkoutStore.swift`
- `PersonalFitness/Progress/WeightHistoryView.swift`
- `PersonalFitness/Workouts/CardioEditor.swift`
- `PersonalFitness/Workouts/Core/WorkoutLogic.swift`
- `PersonalFitness/Workouts/ExerciseLibraryView.swift`
- `PersonalFitness/Workouts/RoutineEditor.swift`
- `PersonalFitness/Workouts/StrengthSessionView.swift`
- `PersonalFitness/Workouts/WorkoutsView.swift`
- `PersonalFitnessTests/Calculations/SleepAnalysisTests.swift`
- `PersonalFitnessTests/Calculations/WorkoutLogicTests.swift`
- `PersonalFitnessTests/Health/SleepModelTests.swift`
- `PersonalFitnessTests/Persistence/WorkoutStoreTests.swift`
- `PersonalFitnessUITests/NutritionFlowTests.swift`
- `PersonalFitnessUITests/ProgressFlowTests.swift`
- `PersonalFitnessUITests/WorkoutFlowTests.swift`
- `README.md`
- `Tools/generate_project.rb`
- `UX_IMPROVEMENTS.md`
- `docs/ARCHITECTURE.md`
- `docs/README.md`
- `docs/USER_GUIDE.md`
