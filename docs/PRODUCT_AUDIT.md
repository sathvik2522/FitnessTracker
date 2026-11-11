# Product audit — 28 October 2026


## Baseline and architecture

- `HEAD` was `1996e5c` on `main` when this pass began. Numerous product files and documents were already modified or untracked; all were preserved. No commit or push was made.
- Native iOS 17+ SwiftUI app with five-tab navigation. `AppPersistence` opens an eight-model SwiftData container and propagates open errors; it does not reset a failed store. Workout and food persistence are handled by dedicated stores and value snapshots.
- HealthKit is read-only. Core activity/energy reads are separate from optional sleep and optional HRV SDNN/resting-heart-rate reads. New signal permissions are outside this pass.
- Pure nutrition, expenditure, recovery/strain, workout and progress logic is in `Nutrition`, `Workouts/Core` and `Progress/Core`. `GoalPreferences` and `ScoringPreferences` hold versioned local preferences. Legacy and advanced scores coexist; advanced scores are not silently substituted into Today.
- Dashboard configuration, accent/appearance, compact rings, insights, quick actions, routine execution, local food catalog, saved meals, custom foods, Progress ranges and JSON export already exist. A widget snapshot contract exists, but there is no WidgetKit extension or App Group entitlement.

## Prioritized findings

| Priority | Finding and evidence | Current disposition |
| --- | --- | --- |
| P1 | `InsightEngine.daily` returned a generic partial-day message before considering observed Recovery/load inputs. A missing Recovery score was also treated as zero when selecting coaching. | Fixed in this pass: observed partial-day values can produce explicitly provisional summaries; coaching requires an observed, nonprovisional Recovery and load. Pure regression tests pass. Hosted UI verification pending. |
| P1 | The app may have been removed from the physical iPhone, so prior local-container preservation evidence cannot establish current phone data. JSON export has no in-app restore. | Device recovery/deployment is outside authorized scope. No device action taken. |
| P1 | The first hosted Xcode baseline stalled before test execution in the build service. | Not counted as a pass. After a simulator-service restart, the final unsigned hosted targets passed 212/212 unit/integration and 18/18 UI tests. |
| P1 | On iPhone 17e, the food picker's floating bottom meal menu covered its empty-state Create food button. | Fixed by moving meal/recipe creation into the list and providing one always-visible Create food toolbar action. Verified by the focused energy flow and final UI target. |
| P1 | Export's action was below long explanatory text and not materialized in the first viewport. | Fixed by moving the action and concise restore/privacy note to the first section. Final export UI flow passed. |
| P1 | A manual weight history row was positioned under the floating tab bar in the failure hierarchy. | Fixed with bottom clearance and visible-row handling. Focused and final historical-weight UI flows passed. |
| P2 | Routine duplication was missing from the Training workflow despite existing snapshot-safe routine storage. | Added through `WorkoutStore` with new routine, exercise-row and set IDs; original routine and exercise identity remain intact. Hosted persistence test passed in the final 212-test target. |
| P2 | The two primary Training buttons were fixed in a horizontal row, risking compression on small screens or large text. | Changed to an adaptive horizontal/vertical layout. Simulator accessibility XXXL reachability passed; physical-device visual review remains pending. |
| P2 | Training exposed two identically named Log cardio actions; a UI flow could not choose one. | Removed the duplicate section action and kept the primary action. Focused and final quick-action UI flows passed. |
| P2 | Routine row action layout and detailed workout forms need a large-text / small-screen visual pass. | Open. No claim of visual acceptance. |
| P2 | Current theme surface reads appearance directly from standard defaults while UI-test settings can use an isolated suite; this limits deterministic theme fixture validation. | Open. Avoid changing preference behavior until hosted UI tests are reliable. |
| P2 | Rest timer offered only fixed 60/90/120-second actions. | A validated, versioned preferred duration now persists and joins the quick choices; saved deadline behavior remains intact. Background notifications remain outside scope and no permission was requested. |
| P2 | No routine organization, copy-previous-meal action, nutrition favorites, or active widget extension is present. | Open; see feature matrix and approval gates. |
| P3 | Existing primary views still contain some long instructional text and repeated setup language. | Simplify after screenshot review, without obscuring missing-data/provenance details. |

No source evidence in this pass established a P0 store reset or destructive migration. This is not a claim that every workflow is free of defects.

## Verification actually performed

- `swift test --scratch-path /private/tmp/personalfitness-recovery-baseline -q`: 129/129 pure tests passed before new edits.
- `swift test --scratch-path /private/tmp/personalfitness-product-recovery-fixed -q`: 129/129 pure tests passed after the insight change. These overlap and are not 258 distinct tests.
- Fresh unsigned `xcodebuild ... build-for-testing`: **TEST BUILD SUCCEEDED**.
- Focused hosted WellnessScoring/WorkoutStore run: **42/42 passed**, including routine duplication.
- The first complete hosted run passed 212/212 unit/integration tests and 11/18 UI tests. Its seven UI failures were used as defect evidence and are not counted as a passing suite.
- After corrections, four unresolved UI flows passed in clean focused runs: energy progress/food creation, historical manual weight, historical draft/meal copy/relaunch, and dashboard quick actions/active-workout reuse.
- Final hosted unit/integration target on iPhone 17e iOS 27.0 simulator: **212/212 passed**, 0 failed or skipped. Result: `/private/tmp/personalfitness-unit-final.xcresult`.
- Final hosted UI target on the same simulator: **18/18 passed**, 0 failed or skipped, with no xcresult runtime warnings. Result: `/private/tmp/personalfitness-ui-final.xcresult`.
- Final `git diff --check`: passed.
- Selected screenshots from the passing UI bundle were visually inspected and copied to `Verification/ProductRecoveryOct28/`. They use isolated synthetic stores.

## Safety review

The changes in this pass do not alter SwiftData models, store paths, bundle identity, Health authorization, entitlements, deployment target, signing or historical records. Routine duplication creates a new routine only when the user invokes it. The insight change reads existing calculated inputs and changes only presentation/selection. No physical-device operation, authentication, commit, push or cloud service was performed.
