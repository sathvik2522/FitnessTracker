# Strength and cardio — October 13, 2026

## Using Workouts

The existing Workouts tab now supports local strength sessions, saved routines, an exercise library and manually logged cardio. No dependency, backend, cloud store, network service or additional Health permission was added.

1. Open **Workouts → Exercise library & progression → New exercise**. Enter a name, bodyweight setting and optional category, muscle group and notes. Library rows open exercise-level progression; Edit changes the library definition. Swipe to delete a library item.
2. Choose **New routine**, name it, add library exercises and choose the starting set counts. Edit mode allows reordering/removing exercises. A routine keeps exercise snapshots; remove/re-add an exercise to adopt a later library change.
3. Choose **Start routine** or **Start empty workout**. Only one active strength workout is allowed. Start creates a persistent record immediately.
4. Add exercises, edit reps and external load in kilograms, mark completed sets and add/remove sets. The **Exercises** toolbar button opens a dedicated list for dragging/reordering and removing exercises, then Save applies the change. Earlier completed performance for that exercise ID appears above its sets. Repeated appearances of the same exercise in one session combine for progression.
5. Valid set edits save immediately. **Done editing** dismisses the keyboard, including decimal pads with no Return key. Invalid or temporarily blank numeric text shows an inline error and prevents finishing. Invalid text is not persisted; the last valid values remain stored. **Close & keep active** leaves the session resumable, including after app termination/relaunch.
6. While logging, use the 60/90/120-second rest controls or Stop. The countdown uses a saved deadline, so leaving/reopening does not restart it. It runs visually while the screen is open; no background notification, audio or Live Activity is scheduled.
7. **Finish workout** requires at least one completed set. Unchecked sets remain recorded but do not contribute to progression. **Cancel workout** asks for confirmation and retains the draft as cancelled, excluded from progression. Neither action silently deletes sets.
8. Tap a history row to edit past sets, exercise order, name or dates. Name/date edits are explicit; set edits preserve the original timestamp. Completed/cancelled states stay distinct. Swipe a history row to delete it intentionally.
9. Use **Log cardio** for running, walking, cycling, elliptical, swimming, stairs or other cardio. Enter start and duration; distance is optional, incline appears for running/walking, and resistance appears for supported machine activities. These are completed sessions: start plus duration cannot be in the future.
10. **Log stair climber** is a dedicated flow with duration, optional distance, level/resistance, floors and reported calories. Optional calories have a Machine estimate/User estimate label and are always identified as user-entered. History rows reopen for editing; blank optional fields mean unavailable, not zero.

Native lists/forms, large controls, visible numeric labels, Dynamic Type layouts and explicit accessibility labels are used. Weights use kilograms and distance uses kilometers in this milestone; bodyweight sets store only extra external load. Body mass and machine calibration are never inferred.

## Data and energy rules

Four SwiftData models were added: `ExerciseRecord`, `WorkoutRoutine`, `StrengthSession`, `CardioSession`. The existing three nutrition models and their fields were preserved. Library/routine/session IDs are stable. Validated saves upsert by ID and roll back failures; cancellation is a state change, not deletion.

Exercise definitions and ordered set arrays are Codable value snapshots. Routine edits or exercise edits/deletion cannot rewrite an existing session. Each routine start regenerates session/exercise-row/set IDs while preserving the library exercise ID for progression. Raw persistence models and calculation types have no SwiftUI dependency.

Progression uses completed sessions and completed sets only, sorted by original start date. It shows recorded sets/reps, best external load and external volume (`reps × kg`). Body mass is excluded. Pending and cancelled work are excluded. Finite/nonnegative loads, integer rep ranges, unique row/set IDs, finite volume and valid timestamps are checked.

Manual strength/cardio records are separate from HealthKit records. Nothing is written to Apple Health. Machine/user calorie estimates never enter resting energy, active energy, total expenditure or balance. The existing calorie engine and energy aggregate queries are unchanged.

Health workout UUID repetitions are deduplicated in the read adapter and display; distinct IDs remain separate. The dashboard labels possible manual/Health and Health/Health matches when activity agrees and both start/end differ by at most five minutes. These are review hints only: imported source data may not prove identity. No manual records or distinct Health records are merged/deleted, and no combined workout count/calorie total is produced. Active/cancelled strength sessions are not match candidates. All records are assigned to the selected local day by their start time, consistent with the existing Health policy.

## Changed files

New production files:

- `PersonalFitness/Workouts/Core/WorkoutLogic.swift`: value snapshots, set/session/cardio validation, progression, rest countdown, conservative display reconciliation.
- `PersonalFitness/Models/TrainingModels.swift`: four local SwiftData models.
- `PersonalFitness/Persistence/WorkoutStore.swift`: transactional validated writes, active-session guard, stable-ID upserts.
- `PersonalFitness/Workouts/WorkoutSessionModel.swift`: presentation state, persist/finish/cancel operations.
- `PersonalFitness/Workouts/WorkoutsView.swift`: start/resume, routine actions, strength/cardio history.
- `PersonalFitness/Workouts/ExerciseLibraryView.swift`: search, library editing, exercise picker and progression.
- `PersonalFitness/Workouts/RoutineEditor.swift`: ordered routine exercise snapshots.
- `PersonalFitness/Workouts/StrengthSessionView.swift`: gym logging, set editing, last performance, date editor and timer.
- `PersonalFitness/Workouts/CardioEditor.swift`: cardio and dedicated stair-climber forms.
- `PersonalFitness/Workouts/WorkoutKeyboard.swift`: shared native keyboard dismissal for gym forms.
- `PersonalFitness/Workouts/WorkoutDaySummary.swift`: date-scoped dashboard manual/Health summaries and match labels.

Updated: `Persistence/AppPersistence.swift`, `Navigation/AppNavigation.swift`, `Dashboard/DashboardView.swift`, `Health/HealthData.swift`, `Health/HealthKitService.swift`, `Package.swift`, project source membership, README, and nutrition UI-test typing helper. Existing signing, HealthKit entitlements, privacy strings, deployment target and target build settings were preserved. The project was extended with Xcodeproj rather than recreated. The existing generator/validator discover new Swift files automatically and remain applicable.

New tests: `Calculations/WorkoutLogicTests.swift`, `Persistence/WorkoutStoreTests.swift`, `Health/WorkoutRecordTests.swift`, `PersonalFitnessUITests/WorkoutFlowTests.swift`.

## Verification

Environment: Xcode 27.0 (27A266a), iOS 27 simulator on iPhone 17e, unchanged iOS 17.0 deployment target.

| Check | Actual result |
| --- | --- |
| Final Debug simulator `build test` | Build succeeded; XCTest reported 87 unit + 4 UI cases passed, zero failures. Xcode then stalled and was stopped (exit 143); no clean final command success is claimed |
| Standalone `swift test` | 51 passed, exit 0; these overlap the hosted unit suite |
| Final unsigned Release generic-iPhone build | Passed; signing and physical-device installation are not verified |
| SwiftData disk reopen and schema migration | Passed; active sets/order/deadline and existing food records retained |
| Dashboard/manual-calorie isolation | Passed; changing machine estimates from 900 to 9,999 kcal leaves Health active energy, expenditure and balance unchanged |
| Project membership and plist lint | Passed; all existing target identities/build settings retained |
| Visual review | Gym logging and cardio history screenshots reviewed |
| Git diff/status | Unavailable: workspace has no Git repository |

The complete final Xcode run executed all existing nutrition/Health/energy tests, both nutrition UI tests, and both new workout UI tests. All XCTest suites reported passing. The command then remained idle for several minutes after the test runner had exited, without writing its final completion/result bundle; only that owned command was terminated. Its final exit was 143, not a successful CLI test exit. The separate full hosted-unit run (`work/workout-unit-final.log`) and targeted strength/manager/keyboard UI run (`work/workout-keyboard-ui.log`) completed with exit 0. A previous combined regression also completed with exit 0 before the final UI usability adjustments. Re-run Command-U in Xcode to confirm clean result finalization on this environment. Earlier UI attempts exposed text-entry timing and native-switch interactions with an open keyboard. The test helper now paces input and verifies switch state; workout forms also expose a native Done editing keyboard control. Those earlier failures are not counted as successful runs.

Workspace command logs: `work/workout-verified-all.log`, `work/workout-pure-verified.log`, `work/workout-release-final-verified.log`. Result bundles are under `work/DerivedData/Logs/Test/`. Tests use isolated fixtures and do not demonstrate real HealthKit authorization or Apple Watch data access.

Screenshots contain isolated test fixtures, not personal measurements: [strength logger](Verification/workout-strength-fixture.png), [cardio history](Verification/workout-cardio-fixture.png).

Unit coverage includes set validation/editing, finish/cancel, historical timestamps, independent routine/session IDs, active-session disk reopen, immutable exercise/routine history, nutrition-to-workout schema migration, cardio upserts/validation, external volume, completed-only progression, deadline expiration, local DST days and duplicate/match rules. Simulator UI tests use isolated temporary disk stores; their fixture measurements are not personal health data.

## Run and test

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
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
swift test
```

Use an available simulator ID from `xcrun simctl list devices available` on another Mac. In Xcode select the PersonalFitness scheme and simulator, then Command-R/Command-U. Choose your team and bundle identifier for a physical iPhone; existing setup instructions remain in README.

## Remaining checks and scope

The final combined Xcode result-finalization stall remains an environment limitation; its console records passing assertions, not a clean command completion. Physical-device signing/install, VoiceOver interaction, a full compact-device/Dynamic Type matrix, and actual Apple Watch reconciliation still need device testing. Similarity labels cannot confirm duplicate identity or source precedence. This milestone adds no Health writes/background delivery and makes no claim of successful real-device Health authorization. Progress is still a placeholder tab; exercise progression is available inside the exercise library. Graphs, per-equipment comparisons, pounds/miles, background timer alerts and automatic calorie estimates are outside this implementation.
