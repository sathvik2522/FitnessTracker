# Data and calculation contracts

## Persisted models

| SwiftData type | Purpose / historical behavior |
| --- | --- |
| FoodEntry | Timestamp, logged quantity/unit, portion calorie/macro totals and optional reference snapshot/source identity and explicit meal category (older records are Unassigned). Totals belong to the whole logged portion. |
| SavedFood | Searchable name, serialized FoodDefinition, usage count and recency. Editing it does not rewrite diary history. |
| SavedMeal | Meal/recipe kind, ingredient snapshots, serving count, usage and recency. Ingredients survive library deletion. |
| ExerciseRecord | Searchable exercise name and validated metadata snapshot. |
| WorkoutRoutine | Name and ordered exercise/set templates; sessions get independent snapshots. |
| StrengthSession | Stable ID, name/start/status indexes and authoritative StrengthDraft containing exercises, sets and timer end. |
| CardioSession | Stable ID, start/activity indexes and CardioDraft with optional manually entered machine metrics. |
| ManualWeight | Stable ID, date and kg; stored only in this app, separate from Health samples. |

There are no persisted imported Health sample tables. IDs support edits without inserting copies. Scalar indexes and serialized draft fields must be updated together through stores. Do not add relationships that cascade library deletion into historical logs.

`AppPersistence` declares the complete schema and explicitly disables CloudKit. Default app storage is persistent; injected disk URLs/in-memory configuration support isolated tests. Current migration uses defaults/optional fields, not a VersionedSchema migration plan. Test older stores and Codable blobs before changing formats. Never delete a store or silently fall back to an empty one after an opening error.

## Nutrition

- Calories use kcal; protein/carbohydrate/fat use grams. Inputs must be finite and nonnegative. Quantities and recipe serving counts must be strictly positive.
- A FoodDefinition describes one reference portion. Additional unit equivalents describe that same portion. Scaling factor = logged quantity / reference quantity for the selected supported unit.
- Grams, ml, servings and pieces convert only when explicit equivalents exist. There is no assumed density or universal piece size. Raw/cooked is descriptive metadata, not an automatic cooking conversion.
- Recipe total = sum of scaled ingredient snapshots. Per serving = total / serving count. Logging stores a new portion snapshot.
- Historical entry edits retain their selected timestamp unless explicitly changed. Saved-definition edits/deletion must not retroactively change diary totals.

## Energy and local dates

```text
consumed = sum of logged food portions in the selected local window
expenditure = resting Health aggregate + active Health aggregate
balance = consumed - expenditure
negative balance -> estimated deficit; positive -> estimated surplus
```

Both energy inputs must exist and cover the same window. Missing/failed/incomplete inputs are explicit enum cases; they are not zero. An empty diary means intake is unknown, so it cannot establish a deficit. A genuine recorded zero remains valid. Full precision is kept through calculations; `EnergyDisplay` handles presentation rounding.

`LocalDayWindow` uses calendar midnights, never 86,400-second arithmetic. Windows are half-open `[start, end)`; today's end is the captured current time. DST can produce 23/25-hour days. Future days are invalid. A closed historical window does not prove the diary or Health samples are complete; coverage remains unverified unless established by a caller.

The Health service uses a cumulative statistics query for each energy/step type, not raw per-source sums. The pure reconciliation engine accepts only matching Health aggregate representations, collapses identical copies and rejects conflicting copies. Workout calories/source subtotals cannot become extra expenditure. HealthKit source behavior must still be checked against Health on real devices; the app does not invent a preferred source or repair real measurements.

## Training and reports

- Strength load is **external kilograms**, including bodyweight exercises; body mass is not inferred into volume. Completed-set volume uses reps × external kg. Active/cancelled sessions must not be represented as completed training.
- One active strength session is allowed. Valid edits save before UI draft publication. Timer end is a timestamp; no background alarm/continuous execution guarantee exists.
- Imported workout UUIDs are deduplicated. Conservative manual/Health time/activity matches are display hints, not proof of identical activity and not data merges.
- Report ranges use local calendar days, with at most 90 days. Food totals cover logged days; matched balances use the same eligible closed-day subset on both sides.
- Weight trends use the latest sample per source/day and a trailing seven-calendar-day mean over recorded days (at least two). Missing days are not interpolated. Manual and Health sources remain separate; gaps break chart segments.
- Short-term weight changes are not direct measurements of fat change. Energy values are estimates, especially during the current day.

See [ENERGY_ENGINE.md](../ENERGY_ENGINE.md) and the calculation tests for edge-case policy and unresolved coverage assumptions.

## Export contract

`LocalDataExport` version 3 captures all eight local tables without saving or mutating the context. Dates are JSON numbers in seconds since 1970, including fractional seconds; serialized snapshots are Base64 byte arrays encoded as JSON strings. Units, IDs, raw enum strings, catalog provenance, usage metadata and archived records are retained. Raw Health samples and permissions are excluded. Saved expenditure predictions may contain derived Health component totals. Version 2 added explicit personal goal/appearance preferences; version 3 adds explicitly saved scoring configuration, any manually entered equation profile, and preserved closed-day expenditure predictions with component values/source metadata for reproducibility. Raw Health samples and permission flags are excluded. The decoder still accepts v1/v2, including v1 without preferences. No SwiftData schema change is needed. Capture runs on the context actor and encoding runs off the main actor. Nonfinite numbers or fetch/encoding errors fail visibly; no records are deliberately skipped. The system Files saver chooses the location. There is no in-app restore.

## Activity, Recovery and source-aware energy fallback

The [current scoring review](../IMPLEMENTATION_REVIEW_REPORT.md#c-exact-algorithms-and-data-policy) is the canonical specification for the added activity-load and wellness formulas, centralized defaults, source/window eligibility and synthetic examples. These indicators do not modify persisted nutrition, imported Health records or the canonical Health-only energy reconciliation. Optional session RPE is stored inside existing workout snapshots; version 3 exports preserve it and explicitly saved configuration. Existing older exports remain readable.

Today/Food use `EnergyExpenditureService`: valid Health resting/active components win individually; a complete explicit Mifflin profile can predict missing resting or active energy. Missing active is predicted REE × (explicit multiplier − 1), never a multiplier applied to Health resting. An independent explicit total is used only without a usable profile. Sources, current-day uniform time proration and uncertainty are visible. No missing profile value or energy quantity becomes zero; no intake goal or workout calories augment expenditure. First calculated closed-day predictions are retained in a separate local preference ledger with their exact profile/component values. Current-day predictions recalculate; unviewed historical days have no retrospective profile. Complete live Health pairs retain priority. Progress charts keep their Health-only series. Energy-ring progress is logged intake / estimated expenditure; the center remains signed kcal balance.
