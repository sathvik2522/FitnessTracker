# PersonalFitness — scoring and dashboard implementation review

**Historical review-stage report.** The owner subsequently approved installation and repository publication. The signed build, in-place iPhone installation, launch and preservation checks completed; see the [approved deployment record](APPROVED_IPHONE_UPDATE.md). The NO-installation gate below describes the earlier review stage.

Review date: October 20, 2026. Existing SwiftUI/SwiftData app; iOS 17 minimum. This report covers the scoring milestone, separately from earlier audits.

## A. Executive summary

Implemented a transparent activity-load Strain indicator, eligible-signal Recovery estimate, optional session RPE, inspectable scoring settings, and explicit energy fallbacks. The existing premium navy dashboard/food redesign was already present in source before this task. Its five tabs, meal diary, offline catalogs, portion editing, snapshots, workout/progress workflows and export were retained.


The new numerical indicators are deterministic engineering estimates. They are not equivalent to WHOOP/Bevel, clinically validated scores, medical advice, injury predictions or direct measurements of readiness. No meaningful input means an actionable setup state, never a default physiological value.

Validation complete: the unchanged baseline passed **170/170**. The final complete simulator scheme passed **221/221 (203 unit + 18 UI), zero failures/skips**; the pure package passed **123/123** (overlapping hosted tests). Generic iPhone architecture compiled successfully with signing disabled. A signed-build attempt stalled in macOS signature generation and was interrupted; signing and all physical-device behavior remain unverified. See section E for exact commands and unsuccessful attempts.

## B. Files, architecture and compatibility

Important additions:

| File | Purpose |
| --- | --- |
| `PersonalFitness/Nutrition/WellnessScoring.swift` | Pure configuration, activity-load reconciliation, normalization, recovery eligibility/mappings/weighting, energy fallback and ring presentation. No SwiftUI or HealthKit queries. |
| `PersonalFitness/Nutrition/EnergyExpenditure.swift` | Dedicated pure component selection, prediction, provenance and historical expenditure record. |
| `PersonalFitness/Health/ScoringHealth.swift` | Separate optional HRV SDNN/resting-HR consent; unit conversion, bounded date queries and historical daily active-energy/workout reads. |
| `PersonalFitness/Dashboard/ScoringDashboardModel.swift` | Adapts persisted completed sessions; coordinates/caches authorized reads with request tokens; derives scores from shared pure engines. |
| `PersonalFitness/Dashboard/ScoringRingViews.swift` | Interactive numerical/setup/loading rings and detailed input, source, contribution, confidence and formula screens. |
| `PersonalFitness/Persistence/ScoringPreferences.swift` | Validated local settings in an isolated UserDefaults key. UI tests use their separate existing preference suites. |
| `PersonalFitness/Navigation/ScoringSettingsView.swift` | Target, weight and mapping editors; optional explicit daily expenditure or equation setup. Save/cancel/error drafts. |
| `PersonalFitness/Workouts/SessionRPEField.swift` | Optional whole-session effort control, including existing fractional ratings. |
| `PersonalFitnessTests/Calculations/WellnessScoringTests.swift` | Pure score, missing-input, outlier, duplicate, date/DST, profile, normalization and weighted-average regressions. |
| `PersonalFitnessTests/Calculations/EnergyExpenditureTests.swift` | Both equations, source priority, optional activity assumption, zero/missing values, DST, historical preservation and actual ring ratios. |
| `PersonalFitnessTests/Health/ScoringModelTests.swift` | Consent isolation, conversions, local-only scoring, late reads, persistence/export and consistent-history fallback. |
| `PersonalFitnessUITests/ScoringFlowTests.swift` | Actual isolated cardio/RPE logging → calculated ring → relaunch; settings validation and persistence. |

Existing files changed at integration boundaries:

- `Workouts/Core/WorkoutLogic.swift`: optional `sessionRPE` in strength/cardio value snapshots; shared 0–10 validation. Workout activity gains Sendable conformance. No SwiftData entity changes.
- `Workouts/StrengthSessionView.swift`: optional post-finish “Rate effort” action and editable effort in session details. Done remains available without a rating.
- `Workouts/CardioEditor.swift`: optional effort section and draft fingerprint; existing metrics and machine-calorie labeling retained.
- `Health/HealthKitService.swift`: existing read-only helpers are module-visible for its scoring extension; original five-type consent, aggregation and sleep consent remain separate.
- `Dashboard/DashboardView.swift`, `DashboardModel.swift`, `DashboardDetails.swift`: integrate score state, manual/foreground refresh, workout-change refresh, settings and truthful sleep context; old permanent-unavailable ring implementation replaced.
- `Navigation/AppNavigation.swift`, `MoreView.swift`: inject scoring preferences and expose settings/methodology while retaining all five tabs.
- `Food/FoodDiaryView.swift`: same independent configured energy fallback as Today, with source labeling. Food totals/snapshots remain canonical.
- `Nutrition/NutritionPresentation.swift`: unscored activity/recovery states offer setup actions. Existing balance sign/rounding retained.
- `Persistence/LocalDataExport.swift`, `Progress/DataExportView.swift`: export format 3 adds explicitly saved configuration; warns about any manually entered equation profile. Versions 1 and 2 still decode.
- `Package.swift`: excludes the iOS-only RPE view from the pure target, removing the introduced unhandled-file warning.
- Project source membership and privacy description updated in `PersonalFitness.xcodeproj/project.pbxproj`; matching description maintained in `Tools/generate_project.rb`. The working project was not regenerated.
- Existing tests change only intended setup labels, export version, or visibility/caret interaction needed for the new UI. Historical snapshot, save-error, duplicate, date and persistence assertions remain.

The complete milestone-relative file list is in `Verification/ScoringReview/CHANGED_FILES.txt`. Comparison uses a private pre-task source archive, not just Git HEAD: the repository already contained substantial uncommitted prior work. No files were removed and no reset/clean/discard was performed.

### Persistence and migration

All eight `@Model` entities and `AppPersistence.makeContainer` remain unchanged. Production store URL, bundle identifier, local signing configuration and entitlements are preserved. No destructive migration, database replacement, row deletion, catalog reseeding or new cloud configuration was introduced.

RPE is an **optional Codable field inside existing `draftData`**, not a new column/table. Older payloads with the field absent decode as nil. Reading old records does not rewrite them. Editing one record persists its updated snapshot through the existing stable-ID store. No mandatory rating or invented historical RPE is assigned. Disk-reopen and legacy-payload tests cover this boundary.

Scoring preferences are separately versioned local configuration. Strain/Recovery are calculated on demand, not persisted; their settings apply to every selected date. Closed-day expenditure predictions now retain their exact first-recorded components/profile in a separate historical ledger, described below. Future changes to this Codable format require compatibility tests; SwiftData migration alone cannot migrate JSON.

## C. Exact algorithms and data policy

### 1. Strain / activity load

The session-RPE method multiplies session duration by a global perceived-effort rating. This method is research-informed; our normalization and fallback policies are product choices. [Foster et al., 2001](https://pubmed.ncbi.nlm.nih.gov/11708692/).

A completed, valid session contributes:

`sessionLoad = completed durationMinutes × explicit sessionRPE`, with RPE finite in **0...10**.

Strength uses elapsed start/end duration, including rests; cardio uses its recorded duration. Active/cancelled sessions, future-ended records and invalid dates/durations are excluded. A session belongs to its **local start day**, including its full completed duration if it crosses midnight. This policy matches existing workout history; energy remains independently aggregated by its calendar window.

For each selected day choose **one mode**, never add unlike units:

1. If usable workouts exist and all have valid RPE: sum session-RPE load.
2. If any usable workout lacks/has invalid RPE: use the sum of workout minutes for the whole day. Explicitly label this duration-only activity fallback; do not invent effort or exercise-type coefficients.
3. If no usable workouts exist: use valid Health active-energy kcal.
4. Otherwise use valid Health step count.
5. Otherwise show **Start / Log activity**. No records does not establish zero activity.

A recorded RPE of zero or actual aggregate quantity of zero is an observed zero; absent quantities are not. No heart-rate-derived workout-intensity model or type-based RPE is invented. The existing service did not provide a defensible session-intensity input.

Normalize: `score = 100 × min(1, dailyLoad / target)`; display whole points, **0...100**, with no intermediate rounding. At 100 the scale saturates, not a physiological safety threshold.

Personalized target: the median of positive, nonpartial, distinct-day loads in the **same unit**, from the prior 28 local days, requiring **7 eligible days**, multiplied by `targetScale`. Duplicate/conflicting day representations do not increase eligibility; old/future days and other units are excluded. Observed zero days are not positive training-target examples. With insufficient history, use the configured provisional target.

Initial targets, all adjustable: **300 session-RPE units, 60 workout minutes, 500 active kcal, 10,000 steps**; scale **1.0**; personalization enabled. These are provisional display denominators, not recommended exercise amounts. Steps have a current-day fallback but no separately queried step-history personalization in this version.

Reconciliation occurs only in calculation memory. Repeated UUIDs count once; conflicting copies of one UUID are rejected. Manual data wins over a possible Health representation. A same-activity Health record is considered a possible duplicate when overlap is at least **80% of the shorter interval** and start/end are each within **5 minutes**. Distinct overlapping manual logs are retained. Health-vs-Health possible duplicates are also excluded deterministically. Excluded counts and uncertainty are disclosed; no saved records are merged or deleted. This heuristic cannot prove identity and may exclude genuinely distinct near-identical Health workouts.

Strain is provisional with a provisional target, partial day/inputs, a non-RPE fallback or possible duplicate exclusions. Even personalized load is not validated physiological strain or an injury-risk measure.

### 2. Recovery

Initial configurable weights: **sleep 40, HRV 30, resting HR 20, recent load 10**. These and mappings below are **product engineering heuristics, not clinically validated constants**. Zero-weight components do not contribute. No Low/Moderate/High clinical-looking thresholds are added.

`recovery = Σ(componentScore × configuredWeight) / Σ(eligible positive weights)`.

Only finite eligible scores in 0...100 participate. Missing, invalid, stale or insufficient-baseline signals have no numerical substitute. Identical components are not added twice; conflicting copies are rejected. With no eligible input, show **Build / Build baseline**. With fewer than all four contributing signals or partial/error inputs, show **Provisional**. All four eligible on a closed day says “4 signals · estimate”, not “validated” or “fully recovered”. A single valid component may determine the renormalized result; details disclose this prominently.

#### Sleep duration

Reuse `SleepModel`, `SleepWindow` and `SleepAnalysis`. Waking-day window is previous local noon to selected-day noon, clipped to now. Actual asleep intervals are unioned; in-bed time is separate; conflicting awake/asleep or invalid records make sleep ineligible. No stages, awake gaps or sleep-quality metric is invented.

`sleepScore = clamp(100 × asleepMinutes / sleepTargetMinutes, 0, 100)`.

Initial configurable target: **480 minutes**; supported settings guard **180...900** minutes. A still-open window can contribute actual valid recorded duration but makes the estimate provisional. No sleep samples means missing, not zero.

#### HRV SDNN and resting heart rate

New reads require the explicit **Enable HRV & resting heart rate** action in Recovery details. They are not added to the original five-type connection or sleep request. Refresh never requests permission. HealthKit completion does not establish that reading was allowed. [Apple authorization documentation](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data).

Use HealthKit **HRV SDNN**, converted to milliseconds; do not substitute RMSSD. [Apple SDNN definition](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilitysdnn). Resting heart rate uses beats/minute.

Collect from selected local midnight minus **28 calendar days** through the selected-day cutoff. Recent window starts **2 calendar days before selected midnight** (3 local dates including selected day). The nonoverlapping baseline ends at that recent start: **26 prior local dates at default settings**, drawn from the 28-day lookback. No measurements after the selected cutoff are used for historical scores.

Quality rules, centralized in `ScoringConfiguration` / `ScoringQualityRules`:

- Require at least **14 distinct baseline days** after filtering, **2 recent days**, and **3 recent HRV samples / 2 recent resting-HR samples**. Latest eligible recent measurement must be within **36 hours of the selected cutoff**.
- Select one source with the most eligible baseline days, with deterministic source-ID tie handling. Source key includes bundle identifier plus device model/hardware where supplied. Require recent samples from that same key. This cannot certify consistent timing, measurement conditions, or distinguish every device change when metadata is absent/identical.
- Deduplicate UUIDs and identical source/timestamp/value events. Conflicting values at one UUID or one source/timestamp are excluded. Out-of-order input does not change the result.
- Engineering range gates: SDNN **5...300 ms**, resting HR **30...120 bpm**. These are quality-filter bounds, not diagnostic/reference ranges; legitimate observations outside them may be omitted.
- Summarize each local date with its median to avoid sampling-frequency bias. Baseline initial center is the median of daily medians; MAD is median absolute deviation.
- Keep baseline daily medians within `max(3 × 1.4826 × MAD, floor)` of that center. Floor is **50% of the initial HRV center**, or **10 bpm** for resting HR. Final baseline is their median.
- Keep recent samples within `max(4 × 1.4826 × MAD, floor)` of baseline. Recent floor is **baseline HRV**, or **25 bpm** for resting HR. Recent summary is the median of recent daily medians. Recheck sample/day counts after filtering.

HRV: `ratio = recentSDNN / baselineSDNN`; `score = clamp(50 + slope × (ratio − 1), 0, 100)`. Default adjustable slope **100**. Ratios 1.0/0.8/1.2 map to 50/30/70. Baseline must be positive. “50” at baseline does not mean 50% recovered. Timing, illness, alcohol, sleep and measurement context can influence readings; this mapping does not diagnose their cause.

Resting HR: `delta = recentBPM − baselineBPM`; `score = clamp(100 − penalty × max(0, delta), 0, 100)`. Default adjustable penalty **5 points/bpm**. Lower readings cannot generate a bonus over 100. A lone elevated value is not enough for eligibility or a diagnosis.

#### Recent load

Use the same `ActivityLoad.day` engine. Compare observed-day mean over the **prior 7 closed days** with observed-day mean over the **prior 28 closed days**; the windows overlap. Exclude the selected day so a partial current day does not look like low training. Require **5/7 recent** and **21/28 baseline** observed days, one unit throughout, and a positive finite usual-load mean. Do not infer rest days from no logs.

`loadScore = clamp(100 − 50 × max(0, recentMean / usualMean − 1), 0, 100)`.

If daily primary modes differ or coverage is insufficient, attempt an **all-days Health active-energy projection** through the same load engine. It includes workout days' active aggregates as well as other days; it does not omit known training days merely because they used RPE in the Strain display. It never mixes units or adds workout calories. Details explicitly identify this fallback and explain that the current Strain ring may use rated workouts instead. If that consistent history is also insufficient, omit the component. This is a descriptive activity-load comparison, not a validated acute/chronic safety or injury-risk model.

### 3. Estimated calorie balance

Preferred calculation remains the existing `EnergyReconciliation` over one matching local day, timezone and cutoff:

`expenditure = restingEnergy + activeEnergy`; `balance = recordedIntake − expenditure`.

Negative = estimated deficit; positive = surplus; zero = balanced recorded estimate. Both Health inputs must be valid and from the same scope. Never add workout records, machine calories or source subtotals. Empty diary is unknown intake. The existing food/macro totals and historical snapshots are unchanged.

Fallback is **opt-in**: no expenditure default, age, height, weight, equation parameter or multiplier is inferred. `EnergyExpenditureService` first consumes the existing canonical reconciled aggregates; it accepts no workout calories. Source priority is per component:

1. Valid Health resting + active → their sum, including genuinely observed zero values.
2. Missing resting + valid Health active + explicit valid profile → predicted resting + Health active (**mixed-source**).
3. Health resting + missing active + explicit valid profile → Health resting + predicted active. Predicted active is `predicted REE × (explicit multiplier − 1)`. **Health resting is never multiplied.**
4. Both missing + profile → predicted REE + predicted active, algebraically REE × multiplier.
5. Without a usable profile, an explicitly configured daily total is an independent fallback. Partial Health components remain separately inspectable and are **not added**. No defensible inputs → setup state; missing is never zero.

The common rounded Mifflin–St Jeor resting prediction is `10 × kg + 6.25 × cm − 5 × age + coefficient`, coefficient **+5 male / −161 female**, explicitly selected equation parameters. This is a prediction, not measured BMR or Apple Watch output. Multipliers are additional user assumptions, not part of the original resting equation. Individual energy needs can differ substantially. [Original Mifflin–St Jeor study](https://pubmed.ncbi.nlm.nih.gov/2305711/).

Supported profile guards: finite age **19...78 years**, height **100...250 cm**, weight **30...350 kg**, optional activity multiplier **1...2.5**. Resting prediction alone needs no multiplier; a blank multiplier leaves missing active energy unavailable unless an independent total is explicitly configured. These input guards do not establish suitability. Missing equation parameters cannot decode as a default. Explicit independent daily-estimate guard is **500...10,000 kcal**. Profile weight is explicitly selected in settings; editing it recalculates the current prediction. Health/manual weight is not silently carried forward into a profile, and age does not silently increment. Update these inputs deliberately.

Each prediction component is prorated by `elapsedSeconds / actualLocalDaySeconds`; closed-day predictions use 1. DST days use the actual 23/25-hour interval. This is a uniform elapsed-time assumption, not a model of when exercise occurred or a final-day forecast. Valid Health components use their actual shared query cutoff without further proration. Food is logged intake through that cutoff, not extrapolated intake. Empty food logs remain unknown, and nonempty logs may still omit meals.

The record captures start/end, timezone, calculation timestamp, partial/closed status, kcal, component source, measured-aggregate versus predicted status, validity/missing-input reasons, exact profile/multiplier or independent-total assumption. Dashboard values use whole kcal with no intermediate rounding. Health energy itself is an estimate with unverified coverage; a closed window does not prove complete data.

**Historical preservation:** after a successful Today/Food refresh, the first closed-day expenditure containing a prediction is saved in a separate local UserDefaults ledger (`personalFitness.energyHistory.v1`), with the exact component values and assumptions. Saving profile changes does not overwrite it. Food edits still update the numerator/balance. A subsequent complete live Health pair takes display priority; the archived prediction remains retained and identifiable by its calculation time. Current-day predictions are never frozen. A past day never previously calculated uses the profile available at its first calculation—there is no invented retrospective profile or unattended midnight snapshot. A snapshot from another day, cutoff or timezone cannot be reused. Corrupt saved records produce an explicit review error. The ledger is included in the explicit version-3 JSON export, including any derived Health component totals; raw Health samples and HRV/RHR are excluded. No SwiftData entity or migration changes were needed.


Neither expenditure nor balance directly measures fat gain/loss. Progress energy charts retain their Health-only series; preserved Today/Food predictions are not backfilled into those charts.

### Synthetic worked examples — not the owner's data

- Two rated sessions: 60 min × RPE 5 + 20 min × RPE 3 = **360 units**. Provisional 300-unit target → **100/100**, saturated; double target scale → 60/100.
- An unrated 40-minute workout plus rated 20-minute workout uses **60 workout minutes**, not an invented effort or 60+RPE mixture. Default minute target → 100/100 provisional.
- Valid sleep 360/480 min → **75**. HRV 50/50 ms → **50**. Resting HR 55/55 bpm → **100**. Eligible recent-load component 50 → weighted Recovery **70**. Sleep alone → **75 provisional**, not a penalized 30 or invented other components.
- Intake 2,000 kcal, resting 1,500 and active 600 → **−100 kcal estimated deficit**. Missing active and no configured fallback → setup state. Explicit 2,500 full-day expenditure → **−500 kcal configured estimate** for a historical day, with no extra workout calories.
- Explicit age 30, 180 cm, 80 kg, male coefficient and multiplier 1.5 → resting 1,780, predicted active 890, full-day estimate **2,670 kcal**. Female coefficient with those same inputs → resting **1,614 kcal/day**. With valid Health active 600 but missing resting → **2,380 kcal mixed-source**. With Health resting 1,500 and missing active → **2,390 kcal**, not 1,500 × 1.5 plus activity.
- Intake 1,500 / expenditure 2,000 → energy arc **75%**, center **−500 kcal**. Intake 2,500 → capped arc 100%, caption **125%**, center **+500 kcal**. Empty intake or expenditure zero → no ratio.
- A saved closed-day 2,670 prediction retains the original 80 kg profile after a later edit to 100 kg; new current-day predictions use the changed input. A historical food edit to 2,200 changes that saved-day balance to **−470 kcal**.

## D. Dashboard, food and accessibility

Today retains date selection, previous/next/return-to-today, the three navy rings, goal-aware calories/macros, expandable Health/activity, actual sleep timeline/source, recent training, weight trend and deterministic daily context. All three rings are circular progress indicators, not decorative circles. Strain/Recovery arcs are score / 100. The energy arc is logged intake / estimated expenditure for the same window, capped at 100%; its signed kcal center still shows deficits/surpluses and a caption explains the ratio (including values above 100%). It is not a percent deficit. Missing or zero-denominator data leaves an empty track, without invented progress. Loading replaces scores while inputs refresh. Ring labels describe value, availability/setup and action for VoiceOver; at accessibility sizes rings stack vertically.

Tap each ring to inspect methodology, selected scope, inputs, targets/baselines, contributing weights, missing signals and limitations. More → **Scoring & expenditure settings** edits targets, scale, sleep target, weights/mappings and optional energy setup. Settings errors retain the draft; Cancel confirms discarding edits. Original calorie/macro goals remain optional and independent of expenditure.

Food retains Breakfast/Lunch/Dinner/Snacks and legacy Unassigned, offline search scopes, verified source portions, custom foods/recipes, edit/move/copy/delete and independent snapshots. The existing composer belongs to the stable navigation root. It is a **native modal session that blocks tab switching**, rather than an autosaved cross-tab editor: navigating within it, Home/activation, validation failure and Cancel → Keep editing retain values. It does not promise unsaved drafts across force quit/process termination. This is an explicit remaining UX limitation, not a claim of implemented cross-tab draft autosave.

Shared dark/light/system colors, native controls, minimum 44-point actions and keyboard dismissal are retained. Sufficient-description and large-type tests run in the complete scheme; these do not establish real VoiceOver order, all contrast cases or physical-phone keyboard comfort. No fake production scores, nutrition quantities, sleep stages or charts were introduced. UI test fixtures are explicitly isolated from personal stores.

Actual reviewed captures and synthetic fixture disclosures: [verification images](Verification/ScoringReview/README.md). The 75% arc is visibly drawn from entered values, not a decorative full circle.

## E. Validation evidence

Environment: macOS with Xcode 27.0, iOS 27 simulator runtime; Swift 6.4 compiler in the project's Swift 5 mode; deployment iOS 17.0. Primary destination: **iPhone 18 Pro Max simulator**, `SIMULATOR_UUID`.

| Check | Actual outcome |
| --- | --- |
| Unchanged full baseline | **Exit 0, TEST SUCCEEDED; 170 passed (155 unit + 15 UI), zero failures/skips.** `work/scoring-review/Baseline.xcresult`, `baseline.log`. |
| Integrated simulator app build | **Exit 0, BUILD SUCCEEDED.** `compile.log`. |
| Final pure package | **Exit 0, 123 tests passed, zero failures.** `energy-core-release.log`; overlaps hosted calculations and must not be added again to the app suite count. |
| First hosted/focused attempt | Interrupted, **not a successful run**. New async fixture released its temporary SwiftData container, causing a SwiftData trap before the stub callback; retained container and bounded wait added. `Focused.xcresult`, `focused.log`. |
| Focused retry | **188 hosted unit tests passed**. Both new UI cases failed due caret-placement automation; retained assertions exposed `1030` instead of `10`, and invalid-setting entry did not match intended text. Helpers now check visibility/focus and end-caret before clearing. `FocusedRetry.xcresult`, `focused-retry.log`. |
| Intermediate full attempts | `FinalFull.xcresult` was interrupted after a new exact-float assertion received 99.99999999999997 instead of 100; the assertion now uses 1e−8 tolerance and aggregations use stable ordering. `FinalVerified.xcresult` passed 190 unit tests but its export UI case timed out waiting for Files; this attempt was also interrupted, not passed. |
| Focused verification | `ScoringVerified.xcresult`: 189 unit tests and real RPE-score UI passed; settings retry needed per-character input. `SettingsRetry.xcresult`: **1/1 passed, exit 0**, including failed-save correction and relaunch. `ExportDiagnostic.xcresult`: **1/1 passed, exit 0**, same export app logic; system picker appeared near the old 10-second bound. |
| Scoring checkpoint before energy addendum | **Exit 0, TEST SUCCEEDED; 207/207 passed (190 unit + 17 UI), zero failures/skips and no xcresult runtime warnings.** `CleanFull.xcresult`, `clean-full.log`. |
| Initial energy-addendum full attempt | Interrupted **exit 75** after 203 hosted tests found one new snapshot/export fixture failure. The fixture used wall-clock fractional timestamps and exact equality across different JSON date epochs. It now injects fixed synthetic whole-second times; no app calculation/export logic was relaxed. `EnergyFinal.xcresult`, `energy-full.log`. |
| Focused energy verification | **Exit 0, TEST SUCCEEDED; 204/204 passed (203 unit + 1 UI), zero failures/skips/runtime warnings.** `EnergyFocused.xcresult`, `energy-focused.log`: actual 75% energy-ring UI journey, preserved source detail and relaunch. |
| Final complete scheme including energy addendum | **Exit 0, TEST SUCCEEDED; 221/221 passed (203 unit + 18 UI), zero failures/skips and no xcresult runtime warnings.** `EnergyComplete.xcresult`, `energy-complete.log`, on the unchanged verified app source. Includes every legacy UI journey, corrected new tests, cached-cutoff regression and bounded 30-second system-Files wait. Export now shows opening feedback; Save/cancel assertions are retained. |
| iPhone architecture review build | **Exit 0, BUILD SUCCEEDED with signing disabled.** `energy-device-final.log`, generic iOS arm64 destination, completed source. No install. The compiled app has the existing bundle ID, minimum iOS 17.0, a Health read description and no Health write description. |
| Signing attempt | Interrupted with **exit 75**, not passed. `energy-signed-build.log` reached codesign, which waited over two minutes. A bounded process sample shows a wait in macOS SecurityServer signature generation; this does not prove the cause was a visible keychain prompt. No credentials or keychain-access policy were changed. The review artifact is unsigned and cannot be installed as-is. Resolve signing in Xcode after review/approval. |
| Structural/resource validation | `Tools/validate_project.rb` passed: app/unit/UI targets, source membership, catalogs/assets/frameworks and scheme. |
| Info.plist/entitlements | `plutil -lint` passed. HealthKit capability entitlement unchanged; request code is read-only and the generated privacy description includes optional heart signals. No Health write usage description is present. |
| Whitespace | `git diff --check` passed at integration; repeated before handoff. |
| Physical iPhone / Watch / real Health consent / manual VoiceOver | **Not performed in this milestone.** Explicit user approval is required before installation. |

The initial restricted SwiftPM invocation could not write its local compiler cache and failed; the permitted retry succeeded. This was an environment restriction, not a passing test or app compiler defect. The introduced SwiftPM unhandled-file warning was corrected by excluding the iOS-only RPE view; the latest package run no longer emits it. The nonfatal AppIntents metadata-skipped warning is expected because no AppIntents framework is used. Simulator tooling can emit duplicate Apple accessibility-class and debugger-version diagnostics. The final full log contains an Apple simulator `UIAccessibilityLoaderWebShared` duplicate-class diagnostic and debugger-version lookup diagnostics; these paths belong to Apple runtime/tooling. No Swift compiler errors or warnings, invalid-frame diagnostics or xcresult runtime warnings were found in that final run. The unsigned device build emitted the nonfatal AppIntents metadata-skipped warning. No warning-free toolchain run is claimed. The compact simulator was confirmed available but not executed during this milestone; large-text UI tests ran on iPhone 18 Pro Max, not every phone size.

Reproduction from repository root (use a fresh result path for repeats):

```sh
open PersonalFitness.xcodeproj
swift test --jobs 1
xcodebuild -project PersonalFitness.xcodeproj -scheme PersonalFitness -configuration Debug \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -derivedDataPath ../../work/FinalAuditBuild \
  -resultBundlePath ../../work/scoring-review/EnergyComplete.xcresult \
  -parallel-testing-enabled NO -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO test
# Verified unsigned iPhone-architecture build; does not install or launch on a phone.
xcodebuild -project PersonalFitness.xcodeproj -scheme PersonalFitness -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath ../../work/scoring-review/ReviewPhoneBuild CODE_SIGNING_ALLOWED=NO build
```

Simulator UI tests pass `--nutrition-ui-test-store <unique UUID>` to independent temporary disk stores/preferences. Never use those fixture arguments for a personal-phone launch. On another Mac choose an actually installed simulator using `xcodebuild -showdestinations`.

## F. Data safety and privacy

No database reset, record deletion, app uninstall, physical install/launch, production path change, signing-configuration change, backend, runtime network dependency, analytics, paid service, synchronization or Health write was performed/added. Source comparison against the private pre-task archive confirms no existing source files were removed, no SwiftData models/container changed, and bundle/team/signing/deployment/compiler settings are unchanged. The generic signing attempt reached macOS SecurityServer but did not finish. Existing SwiftData CloudKit configuration remains `.none`. No credentials or private keys were stored. A repository verification manifest records hashes of 124 app/test/build inputs (`Verification/ScoringReview/SOURCE_HASHES.txt`). The pre-task source/diff archive and build logs live outside the repository in workspace `work/scoring-review/`; the archive excludes ignored local signing configuration.

Health HRV/RHR samples and calculated scores stay in memory and are not printed or persisted. The model uses a **five-minute, same-day/same-timezone** Health-history cache; explicit pull/button refresh bypasses it. Cached heart details retain the actual query cutoff, not a falsely advanced refresh time; a regression tests this boundary. Derived ring values are computed once per render rather than repeatedly for each label. Local logs are refetched on workout changes; dates/foreground refresh use existing dashboard behavior. No background delivery is introduced, and iOS/Watch/Health synchronization is not instantaneous.

Export version **3** retains all eight tables, stable IDs and raw historical snapshots, including active workouts. It adds explicitly saved calculation configuration, closed-day expenditure snapshots with source metadata/derived aggregate values, and optional RPE already inside workout snapshots; no raw Health samples or permissions. If a manually entered equation profile exists, age/height/weight/parameter/multiplier are included to reproduce the estimate; the export screen discloses this. The JSON is personal and not app-encrypted. Versions 1/2 still decode, but older app binaries do not understand version 3 exports.

In-app restore is still not implemented. Export is not a tested one-tap restoration system. Deleting the app or losing/replacing a phone can lose local records. Unsaved modal food drafts can be lost on process termination; saved records and active workouts use the existing persistence boundary. Future schema/configuration changes need explicit compatibility tests.

## G. Limitations and unresolved checks

1. No real HRV/RHR or Apple Watch data was read or reconciled. Permission refusal cannot reliably be distinguished from absent samples. Per-source energy duplication inside HealthKit cannot be certified by this app.
2. Scores, quality gates, weights, targets and mappings are provisional product choices. Range/outlier/source rules can exclude legitimate readings or fail to detect systematic measurement bias. Heart source grouping uses bundle ID plus device model/hardware version; it is not a guaranteed unique physical-device identifier. No medical/readiness/injury claims are supported.
3. Recovery may be sleep-only or another limited subset while baselines build; all contributing weights/details are shown. Consistent training-load history may be unavailable. An all-days active-energy fallback is explicitly different from rated workouts on the current Strain ring, although both use the same load engine.
4. Strain/Recovery remain calculated on demand and can change with settings or old RPE edits. Closed-day expenditure predictions now preserve their first recorded values/assumptions separately; unviewed days have no retrospective profile. Explicit age and selected weight require deliberate updating. No unattended midnight prediction capture is implemented.
5. Configured expenditure is not a validated personal TDEE measurement; the uniform current-day proration does not model workout timing. Progress charts intentionally remain Health-only.
6. Food drafts are modal-session protected, not a persistent cross-tab/process-restart draft system. Favorites/barcode scanning and in-app restore remain out of scope/not implemented.
7. An export UI run exceeded the original 10-second system-picker wait; the same code passed in isolation. The final suite uses a bounded 30-second wait and preserves failure screenshots. Real-device export responsiveness remains a manual check.
8. Actual VoiceOver navigation, physical keyboard/touch behavior, Health/Watch reconciliation, sync latency, query performance with a large real history, and device layout remain unverified. The history adapter can query 28 daily active/workout windows; cache/manual refresh avoid promising instant updates.
9. Device signing is still unresolved for this review artifact: the attempted signature generation waited in macOS SecurityServer and was interrupted, not passed. After explicit installation approval, check Xcode/keychain state personally; no password or broader key access was requested here.
10. Existing final custom app-icon artwork is still absent. No generated asset or sample physiological reading was added to fill a gap.

## H. Proposed iPhone installation and rollback plan — only after approval

1. Review this report, actual simulator captures and the final test/build receipts. Explicitly approve the **new combined scoring build** before any device command.
2. Verify Xcode's existing **PersonalFitness app target / PersonalFitness scheme / Debug configuration**, original bundle identifier and actual local developer team. Do not create a new identity or change signing. Ensure provisioning is still valid at that time; unlock/trust the paired phone and enable Developer Mode if required.
3. Before updating, if the currently installed version offers JSON export, save an explicit export and a private Mac copy. If it does not, do not assume that feature is installed: require a coherent full-container backup using Xcode/authorized device tools before updating. Keep the current binary/source snapshot. Stop app writes, then download/copy its full container using Xcode/authorized device tools; include SQLite store/WAL/SHM and preferences. Check copied-store integrity and capture logical row/snapshot hashes. A live multfile copy without stopping writes is not an atomic database backup.
4. Install **in place** with the same bundle identifier, using Xcode Run or the approved signed artifact. Never uninstall/reset to fix provisioning or app errors. Launch normally, with no test-store arguments.
5. Read back/compare all pre-update stable IDs, logical records and raw snapshots. Confirm food/recipes/routines/sets, active workout and settings; relaunch and test offline. Verify old dates and DST boundaries with appropriate records.
6. Only then use explicit Health actions. Compare resting/active energy, steps, workouts, weight and sleep against the same Apple Health windows. Separately opt into HRV/RHR if wanted; inspect source keys, baseline/recent counts, filters and contributions. Confirm no consent prompt appears automatically at launch and no writes are requested.
7. Test optional RPE before/after finish, later editing, cardio/stairs and score changes; verify no workout calories augment expenditure. Review fallback setup, current-day provisional labels, unavailable energy and empty diaries. Use actual VoiceOver, preferred text size and physical keyboard interactions.
8. If the new build misbehaves, stop making edits and preserve the updated container too. Reinstall the preserved prior compatible binary **in place** if signing permits, without deleting the database. No SwiftData schema changed; older decoders ignore the optional RPE key but could drop it when rewriting a session, so retain the new backup. Any full-container restoration must be a separate reviewed operation with coherent backups; no automatic delete/recreate recovery is provided.

## I. Review gate

Implementation, source review, full simulator validation and the report are ready for user review. Signing must still be resolved in Xcode before any approved future device installation. No device deployment is implied by a successful generic-iPhone build.

- READY FOR USER REVIEW: YES
- PHYSICAL IPHONE INSTALLATION PERFORMED: NO
- USER APPROVAL REQUIRED BEFORE INSTALLATION: YES
