# Local nutrition module — October 13, 2026

## Implemented

The existing project now has a working local food diary, saved-food library, saved meals and recipes. It uses SwiftUI, SwiftData and XCTest; no app dependency, account, backend, nutrition API or network fetch was added. Workouts and Progress remain outside this milestone. Existing HealthKit and energy-reconciliation logic are retained.

### Using the module

1. Open **Food**. Choose the diary day before adding a portion. The date picker and previous/next controls use the local calendar; future days are disabled.
2. Open **Food library** (books icon), then **+ → New food**. Enter a name, optional raw/cooked preparation, reference quantity/unit and calories/protein/carbohydrates/fat for that entire reference portion. Enter zero only when a nutrient is known to be zero.
3. Optionally supply explicit equivalents for that same portion. For example, a reference of 100 g may explicitly equal 2 pieces or 1 serving. Milliliters are supported only when the definition supplies them; density is never inferred.
4. Use **Add food**, search the local library, select an item, then choose quantity and one of its supported units. A preview shows the scaled nutrients. The saved portion remains on the selected day.
5. Tap a diary row to edit quantity, supported unit or logging date/time. **Change food or meal** explicitly replaces its reference snapshot while retaining the entry ID and date. Swipe a row to delete it.
6. In the library, tap an item to edit it; swipe to delete. Library edits and deletion do not rewrite diary history.
7. Use **New meal** or **New recipe** to name a collection, add saved-food ingredients and enter the total servings produced. Ingredient quantities can be edited or removed. Total and per-serving nutrition are calculated from the ingredient snapshots. Both saved meals and recipes are logged in servings; nested recipes and automatic cooked-yield/weight conversions are not implemented.
8. The Add food picker offers the five most frequently used foods and five recently used meals/recipes. The plus button logs one food reference portion or one meal/recipe serving. Tapping the item instead opens the quantity editor.

Search is local and name-based. Frequency counts successful log/replace actions, without counting repeated saves of the same entry/source. Deleting a diary portion does not decrement that lifetime usage count. Meal recency uses the time of the logging action, including when logging a historical day.

The dashboard reloads persisted portion totals after successful nutrition writes. It sums the already-scaled calories and macros once. Its existing rules for missing Health data, incomplete days and empty food logs are unchanged.

## Persistence and integrity

- SwiftData now contains `FoodEntry`, `SavedFood` and `SavedMeal`, with CloudKit disabled. Stable UUIDs and validated upserts avoid duplicate records during editing or repeated saves.
- Food definitions contain reference nutrients and explicit equivalent quantities. Recipe ingredients store food-definition snapshots. Diary entries store their own immutable reference snapshot plus the scaled whole-portion nutrients, quantity, unit, date and optional source metadata.
- Source IDs are metadata, not cascading relationships. Food/meal deletion therefore cannot delete diary portions or change their nutrition. Recipe ingredients also remain stable after food edits/deletion. Remove and re-add an ingredient to explicitly adopt updated library values.
- Existing `FoodEntry` fields were preserved. New properties use defaults or optionals for lightweight migration. A disk-backed test creates the original schema, opens it through the new schema and verifies the old nutrition is retained. Older entries without reference information are treated as one original serving; grams or density are never guessed.
- Editors hold value drafts. Validation precedes model mutation; failed persistence saves roll back the context and display an error. Corrupt definitions cannot silently overwrite valid history.
- Quantities and yields must be finite and strictly positive; calories and macros must be finite and nonnegative. Overflow is rejected. Numeric input must be a complete localized decimal number; trailing junk, NaN and infinity are rejected. Grouping separators are not accepted.
- Stored calculations retain full Double precision. Shared calorie formatting and one-decimal macro display round only for presentation. Calories are entered independently; the app does not infer them from a 4/4/9 macro formula.
- Local-day windows are calendar-based and exclusive at the next midnight. Historical additions default to local noon; today's additions use the current time. Editing an existing entry preserves its timestamp unless changed explicitly.

## Files changed

New production files:

- `PersonalFitness/Nutrition/FoodDefinition.swift`: pure validation, units, food scaling, recipe calculations and date helpers.
- `PersonalFitness/Models/SavedFood.swift`, `SavedMeal.swift`: library models and snapshots.
- `PersonalFitness/Persistence/NutritionStore.swift`: validated write boundary and update notifications.
- `PersonalFitness/Food/FoodComponents.swift`, `FoodDiaryView.swift`, `FoodLibraryView.swift`, `FoodEditor.swift`, `EntryEditor.swift`, `MealEditor.swift`: shared presentation, diary, search, library and editors.

Updated existing files:

- `PersonalFitness/Models/FoodEntry.swift`: historical snapshot and portion metadata, preserving original fields.
- `PersonalFitness/Persistence/AppPersistence.swift`: three-model schema and injectable disk URL for tests.
- `PersonalFitness/Navigation/AppNavigation.swift`: real Food tab.
- `PersonalFitness/Dashboard/DashboardView.swift`: persisted nutrition refresh and food-diary guidance.
- `PersonalFitness/App/PersonalFitnessApp.swift`: DEBUG-only UI-test launch option using a unique temporary disk store. Release and normal launches use the existing personal store.
- `PersonalFitness.xcodeproj/project.pbxproj` and shared scheme: new source membership and `PersonalFitnessUITests` target. Existing app/unit targets and their build configurations were preserved; the project was modified using Xcodeproj, not recreated.
- `Tools/generate_project.rb`, `Tools/validate_project.rb`: UI-target support and membership validation. The generator still refuses to overwrite an existing project.
- `README.md`, this report and three nutrition screenshots under `Verification/`.

New tests:

- `PersonalFitnessTests/Calculations/FoodScalingTests.swift` (7): scaling, explicit units, macro totals, recipe yields, invalid numbers/overflow, snapshots and local/DST dates.
- `PersonalFitnessTests/Persistence/NutritionStoreTests.swift` (5): stable IDs, failed saves, snapshot history, library deletion, recipe history, disk reopen and usage counts.
- `PersonalFitnessTests/Persistence/NutritionMigrationTests.swift` (1): migration from the original on-disk FoodEntry schema.
- `PersonalFitnessUITests/NutritionFlowTests.swift` (2): complete food/recipe/historical/relaunch flow and largest-accessibility-text editor check.

## Actual verification

Environment: Xcode 27.0 (27A266a), iOS 27 simulator, iPhone 17e (`SIMULATOR_UUID`), deployment target unchanged at iOS 17.0.

| Check | Result |
| --- | --- |
| Debug simulator app build | Passed, `BUILD SUCCEEDED` |
| Unsigned Release build for generic iOS device | Passed, exit 0; does not verify signing/install on a phone |
| Complete hosted unit suite | 72 passed, zero failures |
| Simulator end-to-end nutrition UI test | Passed, exit 0; 1 test, zero failures |
| Largest accessibility text editor UI test | Passed, exit 0; 1 test, zero failures |
| Standalone pure Swift suite | Passed, exit 0; 43 tests, zero failures (overlap hosted cases) |
| Project structure/source membership | Passed, exit 0 |
| Visual review | Saved-food editor, historical diary and largest-text editor screenshots reviewed |
| Original target/configuration preservation | App and unit-target build settings compared against pre-change project; preserved |
| Git diff/status | Unavailable: workspace has no Git repository |

The two UI tests and full unit suite were run separately. An earlier combined run exposed a UI-test text-caret issue after the numeric fields became right-aligned; its automation was corrected and the end-to-end test reran successfully. No production calculation was changed to accommodate the fixture.

The end-to-end test creates clearly labeled fixture food/recipe data in an isolated temporary disk store, verifies old nutrition after library editing, edits a historical portion without moving its date, logs a recipe, quick-adds recent/frequent items, checks dashboard calories/protein, terminates/relaunches the app, verifies persisted totals, and deletes a portion. Fixtures never enter the personal store or Apple Health.

Screenshots are test fixtures, not personal measurements:

- [Historical diary](Verification/nutrition-diary-fixture.png)
- [Food editor](Verification/nutrition-food-editor.png)
- [Largest accessibility text editor](Verification/nutrition-accessibility-editor.png)

Full command logs are in the workspace's `work/`: `nutrition-complete.log` (Debug build and unit assertions), `nutrition-unit-final.log`, `nutrition-ui-final.log`, `nutrition-accessibility.log`, `nutrition-release-complete.log`, `nutrition-core-tests-final.log`. Xcode result bundles are under `work/DerivedData/Logs/Test/`.

## Open, build and test

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
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
swift test
```

Choose an installed simulator from `xcrun simctl list devices available` when using another Mac. In Xcode, choose the PersonalFitness scheme and iPhone simulator, Command-R to run or Command-U to test. To reproduce final checks separately, append `-only-testing:PersonalFitnessTests` or `-only-testing:PersonalFitnessUITests`; the largest-text test can be selected by its full XCTest identifier.

## Remaining device checks

No known failing automated tests remain. The simulated largest-text review covers the editor, not a complete device-size/accessibility matrix. VoiceOver interaction, physical-device signing/install, all compact-device layouts and migration of the user's actual store remain manual checks. Choose your team and unique bundle identifier in Xcode as described in README. Existing HealthKit read authorization and real Apple Watch measurements remain unverified on a physical iPhone; this milestone does not claim otherwise.

Next recommended milestone: validate the food flows with your own labels on the iPhone, then implement the strength-workout logger without changing the energy engine's rule against adding workout calories twice.
