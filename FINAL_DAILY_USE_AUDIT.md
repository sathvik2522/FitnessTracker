# PersonalFitness — final daily-use engineering audit


## Scope and environment

Inspected the existing SwiftUI app, eight SwiftData models/container, nutrition and workout stores/editors, dashboard/report models, pure calculation engines, HealthKit adapter, optional sleep, bundled catalogs, project, scheme and tests. Project remains `PersonalFitness.xcodeproj`; targets are `PersonalFitness`, `PersonalFitnessTests`, and `PersonalFitnessUITests`; deployment is iOS 17.0. No project recreation or runtime dependency was added.

Actual tools: macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), Apple Swift 6.4, iOS Simulator 27.0 on iPhone 18 Pro Max (`SIMULATOR_UUID`). Simulator service access required the tool sandbox exception. Signing configuration/team/bundle identifier were preserved; unsigned generic iOS compilation does not establish successful provisioning or installation.

## Focused fixes

| Files | Behavior |
| --- | --- |
| `Models/FoodEntry.swift`, `Nutrition/DiaryMeal.swift`, `Persistence/NutritionStore.swift`, `Food/EntryEditor.swift`, `Food/FoodDiaryView.swift` | Explicit Breakfast/Lunch/Dinner/Snacks/Unassigned attribution; edits retain dates and categories; stable-ID upserts remain. Old entries/quick-add portions are Unassigned, never guessed from time. An empty diary no longer presents its mathematical empty sum as measured zero intake. |
| `Health/SleepModel.swift`, `Dashboard/DashboardModel.swift`, `Progress/ProgressModel.swift` | Cancelled current requests release loading state; obsolete responses cannot dismiss a newer request's spinner or replace selected-date results. Sleep availability is refreshed rather than permanently cached. |
| `Nutrition/SleepAnalysis.swift`, `Health/HealthKitService.swift`, `Dashboard/SleepOverview.swift` | Display source names and the actual local sleep query window. Overlap union, separate in-bed time and conflict handling remain unchanged. Document HealthKit aggregate provenance limitations accurately. |
| `Resources/PersonalFitness.entitlements` | Retain HealthKit; remove unused clinical-record and background-delivery entitlements. No write access, clinical queries, observer registration or background delivery is requested. |
| `Persistence/LocalDataExport.swift`, `Progress/DataExportView.swift`, `Progress/ProgressView.swift` | User-initiated native Files export of every local table. Off-main JSON encoding, explicit errors and file-save result, no automatic network or database mutation. Clear no-restore wording. |
| Tests, existing project source membership, `Package.swift`, current user/development/privacy/install guides | Regression coverage and accurate instructions. Earlier UX/catalog work remains in the diff and is documented in its own milestone notes. |

## Data safety and migration

The eight local types remain FoodEntry, SavedFood, SavedMeal, ExerciseRecord, WorkoutRoutine, StrengthSession, CardioSession and ManualWeight. CloudKit is explicitly disabled. Opening a failed store shows an error; it never silently creates a replacement empty database.

Only one persisted column is added: optional `FoodEntry.mealCategoryRaw = nil`. Older rows stay Unassigned. Tests create separate disk stores using both the original diary schema and the immediate eight-entity pre-category schema, migrate using the actual app container, verify IDs/nutrition/snapshot bytes and existing training/weight records, save a category and reopen. This is additive automatic migration, not a complete versioned migration plan. The October 19 installation additionally verified preservation of the records then present in the owner’s actual database; it does not establish every possible real-device migration or editing scenario. Retain this fixture before any future required field, relationship or JSON-format change.

Saved foods/recipes and sessions contain independent historical snapshots. Deleting/editing a library item does not cascade into past diary nutrition or sets. Catalog deletion archives it; custom deletion removes its definition only. Valid strength edits persist before the observable draft changes; active workouts and rest deadlines survive reopening. Invalid text is blocked rather than turned into measurements. Temporary fixture tests cover save/edit/delete/reopen and stable-ID duplicate prevention. Existing meal/recipe/routine/set unsaved-change guards were preserved.

### Export format and use

Open **Progress → Export local data → Export local data**, then choose **Files → On My iPhone** and Save. The app does not choose a permanent export directory. Verify the JSON exists and copy it to your Mac or another location you control before changing phones or deleting the app.

Version 1 includes all eight tables: diary calories/macros/quantity/unit/date/meal/source IDs/reference bytes, saved foods and recipes (including archived catalog records, provenance and usage metadata), exercises, routines, active/completed/cancelled strength sessions with every set, cardio/machine estimates, and manual weights. Outer record dates use numeric Unix seconds including fractions; serialized snapshots remain Base64-encoded original bytes with their existing Codable schema/date conventions. Future schema changes must update export coverage and version/compatibility tests. Health readings, sleep records, permissions and system Health history are not exported. The file contains personal data and is not encrypted by PersonalFitness.

**This is a data export, not a tested one-tap restorable backup. There is no in-app restore yet.** Tests write/read a JSON file using an isolated disk fixture, verify all tables and snapshot bytes, reject corrupt/unsupported formats and verify export does not mutate the store. They do not import or overwrite the current database. Keep the installed app and original identifier; signing renewal should update it in place. GitHub is source code, not a backup of the live database.

## Food and exercise provenance

Rechecked actual bundled notices/licenses against the publishers and actual downloaded inputs:

- **799 selected USDA SR Legacy April 2018 foods**. USDA publishes FoodData Central as public domain/CC0 and requests source acknowledgement: [publisher licensing](https://fdc.nal.usda.gov/). All four nutrients for all selected records match the downloaded source CSV exactly. Values are per **100 g**, not automatically per serving. This is historical composition data, not a laboratory measurement of the user's food or a verified brand match.
- Source portions retain quantity/description/gram weight. Only explicit equivalents permit unit conversion; no universal ml-to-g density, piece weight or raw-to-cooked transformation is inferred. Raw/cooked foods remain distinct. Recipe scaling uses stored ingredient snapshots. User edits retain source provenance and are marked as personal edits, not newly USDA-verified values.
- **876 text-only Free Exercise DB records**, pinned to commit `f00c92c7dcf1216a928a52c3706c7ce8e2f71ed5`. The publisher's [Unlicense dedication](https://raw.githubusercontent.com/yuhonas/free-exercise-db/f00c92c7dcf1216a928a52c3706c7ce8e2f71ed5/LICENSE.md) permits copying/distribution; the full notice and attribution are bundled. Actual source text/metadata comparisons pass; two empty instruction steps are omitted. No images/video, commercial ExerciseDB.io dataset or runtime API is included. Community instructions are not personalized coaching or independently certified safety guidance.

These publisher licenses support redistribution of the selected bundled content; this is not a legal certification or independent audit of every contributor's authorship. There is no identified license blocker for the included material. Full source URLs, SHA-256, selection/release policy and limitations are in [OFFLINE_CATALOGS.md](OFFLINE_CATALOGS.md).

Stable UUIDs, preflight validation, same-release skip and three-way field merging prevent repeat-import duplicates while preserving custom records, user edits and historical blobs. A changed selection must bump its release. Disk tests cover partial/repeated/update imports and catalog archiving. The app reads bundled resources offline; generation downloads are development tools only.

## Calorie, Health and sleep methodology

```text
consumed kcal = sum of recorded portions in the selected local window
estimated expenditure kcal = Health resting kcal + Health active kcal
estimated balance kcal = consumed - estimated expenditure
negative = estimated deficit; positive = estimated surplus
```

Both energy values are required. Missing/failed/nonfinite values do not become zero; an empty food diary does not establish zero intake. Genuine supplied zero is valid. Calculations retain precision; display rounds consistently. Source subtotals and workout representations cannot enter expenditure. Identical aggregate copies collapse; conflicting copies are rejected. Manual machine/user workout calories are display-only and are never added to Health active energy.


Energy/steps use kcal/count, weight kg. Calendar-midnight boundaries include DST's 23/25-hour days; today's cutoff is captured now. Half-open app filtering excludes the next day. Food/Health assessments require the same cutoff/time zone. HealthKit cumulative overlap behavior, delayed sync and source reconciliation still need device comparison. Absolute timestamps are grouped using the current local calendar/time zone; the original logging zone is not separately stored, so travel can regroup records near midnight. Workout records are attributed to their start day. Weight is the latest selected-day sample, not a carried-forward value.

Health authorization is only explicit Connect/Review, with an empty `toShare` set. Sleep has its own separate opt-in. Request completion is not interpreted as granted read access. Missing data can mean no samples, denied access or late sync; the app cannot reliably distinguish these. Query errors/locked data are visible; refresh/foreground load never requests authorization. No guaranteed instant/background refresh exists.

Sleep uses previous-local-noon to selected-day-noon (clipped now), includes midnight-crossing records, clips intervals and unions overlapping asleep stages/sources. In-bed time stays separate. Conflicting awake/asleep intervals are flagged; comparisons are withheld when invalid/conflicting, and require three prior valid nights. The window can split shift-worker daytime sleep/naps; there is no clinical recovery score or source-priority inference. Source names and window bounds are shown; actual Watch data remains unverified.

Reports show missing-day gaps; today's incomplete expenditure is explicitly provisional. Matched balances use only the same closed-day subset with both food and energy. Weight trends use latest sample per source/day, separate Health/manual series and a trailing seven-calendar-day recorded-day mean with at least two days. Short-term weight changes are not exact fat change. Strength progression uses completed sets, external kg, reps and external-load volume; bodyweight is never inferred into load.

## Privacy and UX inspection

Source searches found no runtime URLSession/URLRequest/socket/WebKit calls, analytics/telemetry SDK, backend, paid service, API key or private key in app source/resources. App data remains in SwiftData and in-memory Health queries, except explicit user export via Files (the user may choose a system cloud destination). No custom cloud synchronization was introduced. No personal measurements are printed by app code. This is source inspection, not privacy/security certification.

Views use native system colors, Dynamic Type adaptations, explicit labels, 44-point numeric/action targets, keyboard dismissal, native search and validation. Existing test journeys cover food create-and-log, recipe/quantity/history edits, cancel/discard, active-workout relaunch, completion/progression, stairs and manual weights. Actual VoiceOver reading order, outdoor/gym contrast, small-screen usability and all real-device keyboard conditions still require hands-on checks. Nonfailing frame warnings are tracked below; a compile is not treated as end-to-end validation.

## Current verification

Build artifacts and raw logs remain under the workspace `work/` directory and are not committed with personal data.

| Check | Actual result |
| --- | --- |
| Full `PersonalFitness` scheme, Debug, iPhone 18 Pro Max / iOS 27 simulator | **Exit 0, TEST SUCCEEDED: 153 passed (142 hosted unit + 11 UI), 0 failed, 0 skipped.** `FinalAuditFull.xcresult`; 611.591 seconds command test phase. |
| Compact iPhone SE (3rd generation), iOS 27 | **Exit 0, TEST SUCCEEDED: 2 UI tests passed, 0 failed/skipped.** Historical food creation/meal assignment/relaunch/snapshot preservation and accessibility XXXL editor field reachability. These repeat cases from the full suite. |
| Pure Swift package / macOS | **Exit 0: 77 tests, 0 failures.** These overlap hosted calculation tests and are not 77 additional unique cases. |
| Physical iPhone follow-up, October 19 | **Signed Debug build, signature verification, in-place installation and normal launch succeeded.** Database integrity and preservation of pre-existing records verified. Health/Watch and hands-on acceptance remain open. |
| Actual `PersonalFitness` app target, Debug, generic iOS / arm64, signing disabled | **Exit 0, BUILD SUCCEEDED.** This is compilation, not signing/provisioning/installation. |
| Xcode project/resource/scheme validator, Info.plist + entitlements syntax, documentation links, final whitespace diff | Passed; targets/source membership and packaged resources checked. |
| Actual upstream-input comparisons | 799 food records/four nutrients exact; 876 exercise records/text exact; two blank instruction steps omitted. |
| Source inspection and credential-pattern scan | No runtime network/analytics/backend integration or credential patterns found in shared app/configuration source. Not a security certification. |


Logs: `work/final-audit-full.log`, `work/final-audit-full-summary.json`, `work/final-audit-core.log`, `work/final-audit-device.log`. Built app inspection confirms executable, minimum OS 17.0, Assets.car and both Catalogs JSON resources are packaged; `NSHealthShareUsageDescription` is present and `NSHealthUpdateUsageDescription` absent.

The final full run emitted **seven nonfailing Invalid frame dimension warnings** during form/keyboard journeys. No Swift compiler warning/error remains in the final iPhone build; the build emits one tooling warning, **AppIntents metadata extraction skipped because no AppIntents dependency exists**. Simulator logs also contain debugger-version lookup, duplicate UIAccessibilityLoaderWebShared and PointerUI diagnostics. None is represented as fixed merely because tests passed.

Earlier attempts are not counted as successful: the first audit unit attempt failed to compile a new export assertion missing `try` (fixed). A focused run then passed all 142 units and meal/relaunch UI but failed the new export test's nonexistent Cancel-button selector. Inspection of the actual system sheet showed swipe dismissal; the corrected export-only rerun passed (exit 0), followed by the complete 153-test pass above. No product save failure was inferred from that test-selector error.

Build/test commands used, from the repository root (the first command is provided for opening Xcode):

```sh
open PersonalFitness.xcodeproj

xcodebuild -project PersonalFitness.xcodeproj -scheme PersonalFitness \
  -configuration Debug -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -derivedDataPath ../../work/FinalAuditBuild -resultBundlePath ../../work/FinalAuditFull.xcresult \
  -parallel-testing-enabled NO -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO test

xcodebuild -project PersonalFitness.xcodeproj -scheme PersonalFitness \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath ../../work/CatalogDevice CODE_SIGNING_ALLOWED=NO build

swift test --scratch-path ../../work/FinalAuditCore
python3 Tools/verify_catalog_sources.py --sources ../../work/catalog-sources
GEM_HOME="$PWD/../../work/gems" GEM_PATH="$PWD/../../work/gems" /usr/bin/ruby Tools/validate_project.rb
plutil -lint PersonalFitness/Resources/Info.plist PersonalFitness/Resources/PersonalFitness.entitlements
git diff --check
```

The extra compact run used the same `xcodebuild test` arguments with destination `platform=iOS Simulator,id=SIMULATOR_UUID`, result bundle `../../work/FinalAuditCompact.xcresult`, and:

```sh
-only-testing:PersonalFitnessUITests/NutritionFlowTests/testCreateAndLogFromDiary \
-only-testing:PersonalFitnessUITests/NutritionFlowTests/testAccessibilitySizeFoodEditor
```

That temporary ID no longer exists. For a repeat, create/select an iPhone SE (3rd generation) simulator and substitute its ID. The original large simulator data was retained; it was shut down after its completed run.

Use a new result-bundle path on repeat runs; Xcode refuses to overwrite one. `work/gems` and downloaded catalog sources are workspace development artifacts, not required to build/run the app. A fresh checkout can follow the Tools README for optional Ruby validation tooling. No signing is needed for these simulator checks; choose your existing real team/phone in Xcode for an actual installation.

| Required area | Automated evidence |
| --- | --- |
| Nutrition scaling, units, invalid quantities, recipes | FoodScalingTests, OfflineCatalogTests |
| Diary add/edit/delete calories/macros, date and meal | NutritionStoreTests, FoodEntryStoreTests, NutritionFlowTests |
| Historical snapshots and library deletion | NutritionStoreTests, WorkoutStoreTests, CatalogImporterTests |
| Disk persistence, duplicate IDs and repeat imports | AppPersistenceTests, NutritionStoreTests, WorkoutStoreTests, ProgressStoreTests, CatalogImporterTests |
| Calorie balance, missing/partial inputs and duplicate representations | EnergyBalanceTests, EnergyReconciliationTests, HealthDashboardTests, WorkoutRecordTests |
| DST/midnight/time zones/historical reports | LocalDayWindowTests, FoodScalingTests, DashboardModelTests, ProgressLogicTests, ProgressModelTests |
| Sleep overlap, midnight, source labels, cancelled/stale queries | SleepAnalysisTests, SleepModelTests |
| Workout resume/completion/progression/cardio/sets | WorkoutLogicTests, WorkoutStoreTests, WorkoutFlowTests |
| Weight trends and manual weights | ProgressLogicTests, ProgressStoreTests, ProgressFlowTests |
| Migration and export | NutritionMigrationTests, ProgressStoreTests, LocalDataExportTests, DataExportFlowTests |

Unit tests use in-memory/unique temporary disk fixtures. UI journeys use UUID-isolated temporary SQLite stores; catalog UI explicitly enables the real bundled resources in that isolated store. UI fixture launches disable UIKit animations for deterministic automation; normal app launches retain animations. UI tests do not write export files to a user's Files locations: they open/dismiss the native saver. Actual fixture export bytes and temporary-file existence are tested separately.

## Remaining issues and release decision

No reproducible critical/high-severity defect has been found in the inspected and tested flows. This is not a claim that untested physical-device behavior is correct.

| Priority | Outstanding issue or limitation | Impact / next action |
| --- | --- | --- |
| Acceptance gate | Installation, launch and existing-record preservation passed on October 19; hands-on validation remains incomplete | Verify actual Watch/Health source totals and midnight overlap, permission switches, new logging/editing, offline relaunch, VoiceOver and saved Files export using the checklist below. Installation success does not close these checks. |
| Medium | No in-app restore, cross-device transfer or automatic backup | JSON export preserves records but cannot yet be imported through the app. Keep the installed app/original ID; copy exports off-device. Next recommended engineering milestone: validated restore into a separate store with preview and explicit conflict handling. |
| Medium | Reproducible nonfailing SwiftUI “Invalid frame dimension (negative or non-finite)” diagnostics around food form/keyboard interactions | The automated flows complete, but the root cause is not established. Source inspection found no computed negative frame dimensions to safely clamp. Check real-device keyboard/clipping before treating these as harmless; avoid masking warnings with an unrelated layout rewrite. |
| Low | App icon has no finished artwork | Cosmetic; project resource references build. |
| Explicit product limits | Reports limited to 90 local days; original logging time zone not separately retained; diary keeps the visible selected date; quick-add meal is Unassigned | Choose the intended date/meal explicitly. These limits do not silently substitute measured values. |
| Health/sleep estimates | Read denial vs missing data cannot be distinguished, source duplication/coverage cannot be certified, and noon-to-noon sleep can split daytime sleep/naps | UI discloses provisional/unavailable data. No manual workout calories are added; no clinical recovery score is inferred. Real-device reconciliation remains required. |

No schema reset, data deletion, signing identity change, network service or new paid capability was introduced. **Release verdict: READY WITH LIMITATIONS.** Core simulator workflows and calculations pass. Real-device acceptance, a tested restore flow and the nonfailing layout diagnostics remain open; this is not unconditional daily-use certification.

## Physical-iPhone acceptance checklist — remaining hands-on checks

The October 19 update is already installed. Future signing renewals must update the existing app using its **same bundle identifier**; do not delete it. Existing-record preservation was checked against the database, but the owner’s visual checks and new logging flows below remain open.

1. Verify old diary entries, foods/recipes, routines, completed workouts and manual weights still exist before entering new data.
2. Connect/review Health reads explicitly; enable resting/active energy, steps, workouts and weight. Enable sleep separately. Confirm no write request. Unlock, allow Watch sync, foreground and refresh; compare a closed day and today against Health, including overlapping manual/Watch workouts without extra calories and samples spanning midnight. Compare source totals in Health rather than assuming boundary proration is proven.
3. Add a custom food to Breakfast on a previous day, change quantity, assign Lunch, confirm calories/macros and date, cancel an edit, delete a test portion and check totals. Relaunch and confirm saved history stays.
4. Start a routine, record valid reps/kg/completion, force-close, reopen/resume, finish and check history/progression. Create/edit a stair-climber test log and verify its machine calories do not increase dashboard energy.
5. Inspect sleep source/window, overnight duration and weight history. Missing/denied data should say unavailable; late Watch sync may change estimates. Check today is marked partial.
6. In airplane mode, repeat local food/workout logging, search both catalogs and relaunch. Health only shows samples available locally.
7. Export from Progress to **On My iPhone**. Open Files, verify a nonempty JSON file with the chosen name exists, then copy it off the phone. Do not assume in-app restore exists.
8. With larger text and VoiceOver, check Save/Cancel/Meal/date/units, number fields, scroll/reachability and chart labels. Report clipping, unreachable controls or misleading reading order.

No item above is marked passed merely because simulator tests or unsigned compilation succeeded.

## Physical-install follow-up — October 19, 2026



Logs/receipts remain in workspace `work/phone-update-oct19-build.log`, `work/phone-update-oct19-install.json` and `work/phone-update-oct19-launch.json`. The private safety-copy directory is `work/private-phone-safety-oct19/`; it is outside this Git repository and is not an implemented in-app restore feature.

Still unverified: actual Health/Watch values and permissions, sleep reconciliation, VoiceOver, new on-phone food/workout editing, offline relaunch and user-selected Files export. The daily-use acceptance checklist above remains open for those items.
