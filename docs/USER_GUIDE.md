# Use and validate PersonalFitness

## Daily use

**Today:** choose a date, review logged food/macros and available Health readings, and refresh. Connect Apple Health only when ready; no permission prompt should appear automatically at launch. Today remains partial. Missing data and query failures are displayed explicitly.

**Food:** create saved foods from your actual label/reference, enter nutrition per reference portion and explicit equivalents when needed, then select the quantity to log. Search your local library, reuse frequent foods or meals, and create meals/recipes from ingredients with a serving count. Select the intended diary day before logging. Edit or delete diary entries from that day's list.

**Training:** create exercises and routines or start a session directly. Add/reorder exercises, enter reps/external kg and mark completed sets. Resume an unfinished session after relaunch, or explicitly finish/cancel it. Use cardio or stair-climber logging for duration, optional distance/incline/resistance and optional machine calories. Machine estimates do not increase dashboard active energy.

**Progress:** choose Day, Week, Month or a custom range. Review energy/macros, weight trends, training and daily calculation details. Manual weight is labeled as local and is not written to Apple Health. Days without readings remain gaps.

## Physical-phone acceptance checks

- Compare Health resting/active energy and steps on the same local date and units after refresh. Repeat with a historical day and a current partial day.
- Confirm expenditure = resting + active, and balance = food − expenditure only when required data exists. Workout or machine calories must not be added again.
- Compare Health workout types/start times/durations and selected-day weight. Missing read access and no samples may look identical; don't assume denial or zero.
- Add/edit a real diary entry, relaunch and verify persistence. Change a saved food and confirm old portion snapshots stay stable.
- Save a routine, start a workout, enter sets, relaunch, resume and finish; verify history. Check cardio/stair entries similarly.
- Edit yesterday and confirm the entry remains on yesterday. Check time-zone/date changes with appropriate existing records.
- Stop Xcode, unplug the Mac and launch from Home Screen. Test offline logging/relaunch; new Watch data may sync later.
- Try VoiceOver, larger text, light/dark appearance and keyboard interactions on the actual phone.

These are manual checks to perform, not claims of completed validation. Do not create fabricated Health measurements to make checks pass. See [the audit](../ENGINEERING_AUDIT.md) for previously verified simulator tests and remaining issues.

## Optional sleep and training context

Open **Sleep** on Today and choose **Enable sleep insights**. This requests only sleep read access and does not change the existing five-type Health connection. Review recorded asleep and in-bed time separately, expand the seven-night history, and refresh after Watch sync.

The labeled window is local noon the previous day through noon on the selected waking day, clipped to now when still open. Overlapping sleep/stage/source intervals count once. Conflicts or invalid intervals make the reading provisional and suppress comparative observations. No samples means unavailable, not zero hours. Comparisons use your recorded prior nights only; this is not a clinical recovery or readiness score.

**Log food** on Today carries its selected date into Food. In Add food, **Save & log** creates a library definition and continues to the quantity/date step; **Save to library only** does not create a diary entry. Use **Keep editing** when cancelling a draft to retain its values. Saved records require explicit confirmation before deletion.

## Offline foods and exercises

After updating, wait for the bundled libraries to prepare. Food search includes generic USDA reference foods and aliases such as moong, rajma and dahi. Check the exact source description and raw/cooked state, then choose grams or the explicitly described source serving. Actual brand labels/recipes can differ; create a personal food when needed. Cottage cheese is not assumed to be paneer.

Search uses all records, even beyond the first page. Use **Show more foods/exercises** to browse more rows. Library edits preserve personal fields across catalog updates and never alter old diary/workout snapshots. Removing a bundled record hides it across future launches; no restore browser is provided yet. Custom records keep their normal delete flow.

Exercise search also includes aliases; source instructions and attribution appear on the exercise detail page, separate from personal notes. Use the existing cardio/stair forms for timed activities. All library searches and normal logging work without internet. [Dataset and import details](../OFFLINE_CATALOGS.md).

## Meal categories and local export

In the portion editor, choose **Meal → Breakfast, Lunch, Dinner or Snacks**. Legacy entries remain **Unassigned** until you explicitly assign a meal. A meal’s plus button preselects that meal; the general Add Food action starts Unassigned. Quick add uses the currently selected meal. Editing a quantity keeps its date and meal. An empty diary shows no recorded intake rather than implying you ate zero calories.

Open **More → Export local data → Export local data** (also available in Progress), choose **On My iPhone**, and Save. Verify the JSON exists in Files and copy it to your Mac before deleting the app or replacing the phone. This exports all local food/workout/manual-weight records; Apple Health data remains in Health. In-app restore is not yet available.

## Goals, appearance and the redesigned diary

Use **More → Nutrition & activity goals** to enter your own optional calorie, macro and step targets. Blank means no target; zero/negative values are rejected. Targets apply to all dates you view and are not historical goal snapshots. They do not change expenditure. More also offers Dark, Light and System appearance.

Tap a Today ring for its methodology and available supporting observations. Strain shows an activity-load score when eligible workout or Health inputs exist. Recovery uses eligible sleep, personal HRV/resting-HR baselines and consistent recent load; missing signals are omitted and weights renormalized. These are heuristic estimates, not readiness percentages. Without inputs, use the rings’ Log activity / Build baseline actions. Estimated balance is signed kcal, provisional today and coverage-unverified for older days.

In Food, use each meal’s plus button to log directly to it. Tap a logged food to edit. Long-press for **Move to meal**, **Copy portion** or confirmed deletion. Moving preserves date and nutrition; copying opens a separate draft with a new ID and the original snapshot/date. Change the date explicitly if needed.

The Add Food sheet offers All, Recent, Frequent, Custom and Meals filters. Exact names rank first; aliases and token searches work offline. Verified portion buttons use the source’s stated gram weight. There is no barcode scanner or guessed ml-to-gram conversion.

Food editing is a modal session: tab switching is unavailable while the draft is open. Returning from the Home Screen keeps the draft while the app remains alive. **Cancel → Keep editing** preserves input; **Discard changes** abandons it. Failed validation keeps the input for correction. An unsaved food draft is not promised to survive force-quit or OS process termination; saved records and active workouts are persisted.

## Scoring and optional effort ratings

Use **More → Scoring & expenditure settings** to inspect provisional load targets, normalization scale, sleep-duration target, recovery weights/mappings and optional independent expenditure setup. No calorie goal is used as expenditure. Age, height, selected weight and equation coefficient must be explicit. The activity multiplier is optional: leave it blank to estimate resting only and require Health active energy; no activity assumption is guessed. Strain/Recovery settings apply on demand. The first calculated closed-day expenditure prediction is preserved with its inputs; later profile edits do not replace it. Current-day predictions recalculate. Update the explicitly selected equation weight/age yourself; the app does not infer them.

After finishing strength training, **Rate effort (optional)** opens session details; Done remains available without a rating. You can edit Session RPE later through session details. Cardio/stair forms offer the same optional rating. Session load uses duration × RPE only when all usable workouts that day are rated; otherwise it shows a labeled duration-based activity fallback, or available Health active energy/steps. Do not compare different load units as if they were the same measurement.

Recovery’s **Enable HRV & resting heart rate** is a separate read-only opt-in. It is never requested automatically or added to the original Health/sleep request. Baselines require adequate same-source daily measurements. Tap the ring for eligible components, source/time windows, effective weights and reasons other signals are still building history. A provisional sleep-only or activity-only estimate is not a medical assessment.

The configured energy fallback is labeled in Today/Food and never adds machine/workout calories. Today’s fallback is uniformly prorated by elapsed local-day time; it is not measured activity or a final-day forecast. Progress energy charts keep Health-only series. Tap the energy ring for component sources and assumptions. Its arc tracks logged intake divided by expenditure, capped at 100%, while the signed center shows deficit/surplus; it is not a percent deficit. Explicit exports include scoring settings, the manually entered equation profile and saved expenditure predictions (possibly derived Health totals), but never raw Health heart samples. Keep such JSON private. See [exact methods and the current review gate](../IMPLEMENTATION_REVIEW_REPORT.md).
