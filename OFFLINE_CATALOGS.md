# Offline catalog import — intended strategy (October 18, 2026)

Before implementation: inspect and retain the existing eight-model SwiftData schema, local stores, diary/recipe nutrition snapshots and routine/session exercise snapshots. Existing uncommitted UX improvements are the baseline and will be preserved.

## Planned import boundary

- Obtain official USDA bulk nutrition data during development, evaluate size/coverage, and generate a compact generic-food subset with complete calorie/protein/carbohydrate/fat values. Verify public-domain terms and retain source IDs, release, aliases, preparation, serving descriptions and quality information. No runtime network/API keys.
- Evaluate ExerciseDB's actual redistribution terms. Prefer a genuinely redistributable text dataset if its terms are unsuitable. Exclude all images/videos. Keep source/license notices in the bundle.
- Use deterministic namespaced UUIDs, independent of display names. Decode/validate versioned JSON before importing through a background SwiftData ModelActor with bounded saves. Surface loading, completion and retryable failures while leaving personal logging accessible.
- Add only optional Codable metadata to existing food/exercise JSON blobs, avoiding new SwiftData tables or columns. Store each imported record's prior catalog baseline alongside its provenance; update only fields that the user has not edited. Preserve user-owned usage counts/notes and all historical snapshots. Keep archived imported records as hidden tombstones so a subsequent launch cannot recreate them. Custom records remain untouched, including the existing ten starter exercises.
- Merge the imported records into existing search, recipe, routine and active-session pickers; search aliases offline. Label source and user-modified definitions. Version changes never rewrite diary, recipe, routine or completed-session snapshots.
- Add decoding, metadata, identity, merge, alias/unit/preparation, idempotency, archive, disk-reopen and historical-preservation tests; run actual build/test commands and report their results.

Dataset selection, exact counts/sizes, implementation details and verification will be recorded after obtaining and validating the source files. No dataset or license claim is implied by this plan.

## Implemented dataset selection and redistribution assessment

### USDA nutrition

Selected **USDA FoodData Central SR Legacy, April 2018**, from the [official downloadable dataset](https://fdc.nal.usda.gov/download-datasets/). The actual downloaded CSV ZIP is **6,074,592 bytes**, expanding to **39,791,883 bytes**, with **7,793** source foods. Evaluated the much larger branded/all-data downloads and newer Foundation downloads; SR Legacy supplies the required generic families, including unbranded whey powders, in one manageable historical release. It is deliberately not presented as current branded-product label data.

The [official USDA licensing statement](https://fdc.nal.usda.gov/) identifies FDC data as public domain / **CC0 1.0**, with no permission required and a request for source acknowledgement. The bundled NOTICE and per-record provenance retain that acknowledgement. No communication was sent to USDA and no API key was obtained. [USDA documentation](https://fdc.nal.usda.gov/Foundation_Foods_Documentation/) describes portion gram weights and per-100-g nutrient calculations; the supplied SR Legacy CSV dictionaries were also inspected.

Generated a selected **799-food** generic catalog. All four required nutrients must be explicitly present, finite and nonnegative. Nutrient IDs **1008 (kcal), 1003 (protein g), 1005 (carbohydrate g), 1004 (fat g)** retain their source values per **100 g**; source nutrient units are asserted during generation. No macro-derived calorie replacement is performed. None of the selected 799 records needed exclusion for missing required macros; the generator and tests still reject missing values.

Coverage includes eggs, chicken breast, raw/cooked rice and mung beans, plain and Greek yogurt, cottage cheese, sweet potatoes, apples, grapes, watermelon, generic whey protein powders, legumes, soybeans, peanuts, coconut, grains, vegetables and spices. Curated search aliases include moong, urad, masoor, chana, rajma, dahi, jeera, haldi and others. Aliases aid discovery; they do not assert that different recipes, cultivars or brands have identical nutrition. Mung and mungo remain distinct. **Cottage cheese is not aliased to paneer; generic rice is not relabeled basmati.** Named branded SR records such as Uncle Ben's/KAMUT are omitted. Other unselected foods, restaurant/packaged collections and micronutrients are outside this subset.

Source preparation is retained separately: explicit raw/uncooked and cooking terms produce raw/cooked metadata; otherwise preparation stays unspecified. No raw-to-cooked transformation is calculated. Source portions retain amount, original description and gram weight. One explicitly labeled source portion maps to the existing **serving** unit; grams always remain available. There is **no inferred ml↔g density or arbitrary piece size**. Other source portion descriptions remain readable in the food editor; custom definitions can still provide their own validated unit equivalents. Source evidence includes nutrient derivation IDs and reported data-point counts, without implying that every value was analytically measured.

### Exercise text

Selected [Free Exercise DB](https://github.com/yuhonas/free-exercise-db), pinned to commit **f00c92c7dcf1216a928a52c3706c7ce8e2f71ed5**. Its actual downloadable `dist/exercises.json` contains **876 exercises** and the publisher supplies an [Unlicense/public-domain dedication](https://github.com/yuhonas/free-exercise-db/blob/f00c92c7dcf1216a928a52c3706c7ce8e2f71ed5/LICENSE.md), allowing copying, modification and distribution. Attribution is voluntarily retained and the complete license is bundled. This assessment relies on the source publisher's stated license; no media is imported.

ExerciseDB was investigated: the [commercial EDB package terms](https://exercisedb.io/terms) restrict raw redistribution, and an API code license alone would not establish unrestricted rights to all associated media/content. No ExerciseDB package or paid/runtime API is used.

Imported names, equipment, primary/secondary muscles, category, force/mechanic and instructions from the source. Search aliases cover chest fly/lateral raise and Bulgarian split squat where source movement descriptions support the synonym. **Two empty instruction steps** were removed; no instruction text or safety guidance was invented. All source images/GIFs/videos and website code are omitted. These are community instructions, explicitly labeled as not individually safety-reviewed. Cardio references are included; duration/distance and stair metrics continue through the existing cardio/stair logging flows, rather than deriving calories or intensity from the catalog.

## Reproducible resources and measured size

| Bundled resource | Record count | Bytes |
| --- | ---: | ---: |
| `foods-v1.json` | 799 | 498,580 |
| `exercises-v1.json` | 876 | 1,019,761 |
| `NOTICE.txt` | — | 1,555 |
| `EXERCISE_LICENSE.txt` | — | 1,211 |
| `generation-report.json` | — | 495 |
| Total | 1,675 definitions | **1,521,602** (~1.45 MiB) |

These are uncompressed resource bytes, not an invented installed-app or App Store compressed size. Full source downloads remain outside the app/repository under workspace `work/catalog-sources`. Each resource records the original download SHA-256; the generation manifest records generated file hashes. The development validator verifies those bytes. Both food and exercise JSON reproduced byte-for-byte into a separate output directory. `verify_catalog_sources.py` independently compared all **799 × 4** nutrition values and all **876** exercise names/equipment/muscle/instruction records with the actual downloaded source rows.

From the repository root, obtain the pinned files (development only):

```sh
mkdir -p ../../work/catalog-sources
curl -L --fail 'https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2018-04.zip' -o ../../work/catalog-sources/usda-sr-legacy.zip
curl -L --fail 'https://raw.githubusercontent.com/yuhonas/free-exercise-db/f00c92c7dcf1216a928a52c3706c7ce8e2f71ed5/dist/exercises.json' -o ../../work/catalog-sources/exercises.json
curl -L --fail 'https://raw.githubusercontent.com/yuhonas/free-exercise-db/f00c92c7dcf1216a928a52c3706c7ce8e2f71ed5/LICENSE.md' -o ../../work/catalog-sources/EXERCISE_LICENSE.md
python3 Tools/generate_catalogs.py --sources ../../work/catalog-sources
python3 Tools/verify_catalog_sources.py --sources ../../work/catalog-sources
```

The generator checks pinned input hashes. To change source bytes, selection, aliases or conversions, deliberately review the source/rights and **bump the affected JSON release string**; a same-release import intentionally does not overwrite an existing row. Keep source identity stable. Rebuild the app to ship a catalog update. No download command is executed by the app.

## Import architecture and data compatibility

- `OfflineCatalog.swift`: pure schema validation, source/license metadata, UUIDv5 identities, alias matching and three-way merges. FoodDefinition and ExerciseSnapshot gain only optional Codable fields; legacy definitions without them still decode.
- `CatalogImporter.swift`: a ModelActor created off the main actor, validating the complete resource set before writes and preflighting identifier collisions. Dedicated context, explicit saves in batches of 100, rollback of only the current unsaved batch. Interrupted imports safely resume by source identity/release. An import failure never resets the store.
- `CatalogLoadingView`: responsive initial loading, a retry action and a way to use existing records if import fails. Normal launches import from bundled files only. Existing XCTest fixtures retain their empty isolated stores; a separate `--with-offline-catalog` test path imports the real packaged resources.
- Existing SavedFood/ExerciseRecord rows store catalog provenance, previous source baseline, edit state and archive tombstones in their existing JSON data. There are **no new SwiftData types, columns, container/schema changes or store URL changes**. No destructive or lightweight schema migration is required.
- A catalog update adopts fields only if they still match the previous source baseline. User fields that differ are preserved. Nutrition, reference quantity/unit, equivalents and source portions are one atomic merge group. New source evidence is labeled as reference metadata, never verification of personal edits. Names are not deduplication keys: similarly named personal foods/exercises are retained deliberately.
- Deleting an imported library item archives it as a hidden tombstone, so launches/releases cannot recreate it. Personal records retain ordinary confirmed deletion. There is no archive browser/unarchive UI in this milestone. Source entries removed from a future release are retained rather than silently deleted. Existing ten starter exercises remain intact with their original IDs.
- Import touches only SavedFood/ExerciseRecord. Usage counts, diary nutrition snapshots, meal/recipe ingredients, routine definitions and active/completed sessions are preserved. HealthKit authorization/query/energy reconciliation code is unchanged.
- Existing library/picker flows now search aliases across all stored definitions offline, with explicit top search placement and 50-result pages. New/renamed food definitions are revealed even if they would otherwise lie beyond the first catalog page. Source labels, personal-edit labels, portions, instructions and source notices are presented in the existing flows.

## Validation

Final verification completed October 18, 2026:

| Command/check | Actual result |
| --- | --- |
| Complete simulator `xcodebuild test` | **Exit 0, TEST SUCCEEDED: 133 unit + 10 UI tests passed**, zero failures/skips; `work/CatalogFull.xcresult`. |
| Standalone `swift test` | **Exit 0: 76 tests passed**, zero failures (overlap the hosted unit suite); `work/catalog-core-final.log`. |
| iPhone arm64 Debug `xcodebuild build`, signing disabled | **Exit 0, BUILD SUCCEEDED**; `work/catalog-device.log`. No installation/signing claim. |
| Original-source value/text comparison | **799 foods × 4 nutrient values and 876 exercises verified**, with exactly two empty instruction steps omitted. |
| Reproduction, schema/resources, documentation and final diff | Both catalogs reproduced byte-for-byte. Project membership/resource/hash validator, Python parsing, documentation-link checks and `git diff --check` passed. Existing SwiftData model/container/configuration diff is empty. |

The full UI suite includes the real bundled-resource food alias → portion → relaunch → exercise-alias journey, existing custom food/exercise creation, recipes, edits/deletes, workout resume/completion/progression, stairs, historical weights and accessibility-description checks. It uses isolated temporary stores; UIKit animations are disabled in the existing DEBUG UI-test path, so normal device animations remain a manual check. The disk-backed import test measured about **0.162 seconds for the remaining 1,575 rows after an initial 100-row partial import** on this Mac/simulator setup; this is not a physical-iPhone benchmark. Repeat imports inserted/updated zero rows. Disk-reopen release-update tests preserve usage, personal edits, diary snapshots and byte-identical recipes/routines/completed-session blobs.

An initial compiler exclusivity error was fixed. Dataset validation caught two empty instruction steps, which were omitted without inventing text. An early simulator test identified automatic search placement disappearing alongside the picker toolbar; explicit placement fixed it. These initial/aborted/failing runs are not reported as successful final runs.

Physical iPhone cold-launch responsiveness, memory/storage behavior on older devices, VoiceOver and real personal-data validation remain manual. Install the update **over the existing app with the same identifier**, never delete the app to import catalogs. No new signing, HealthKit permission, backend or network setup is required. The complete run records **seven non-failing SwiftUI “Invalid frame dimension” runtime warnings** during simulator keyboard/form interactions, an existing unresolved diagnostic category. The build also reports skipped AppIntents metadata extraction; no Swift compiler warning was found in the final iPhone build. This change does not claim physical-device validation.

### Build and test commands used

From `outputs/PersonalFitness` in this workspace:

```sh
swift test --scratch-path ../../work/CatalogCore
xcodebuild -project PersonalFitness.xcodeproj -scheme PersonalFitness \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -derivedDataPath ../../work/CatalogBuild -resultBundlePath ../../work/CatalogFull.xcresult \
  -parallel-testing-enabled NO -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO test
xcodebuild -project PersonalFitness.xcodeproj -scheme PersonalFitness \
  -destination 'generic/platform=iOS' -derivedDataPath ../../work/CatalogDevice \
  CODE_SIGNING_ALLOWED=NO build
GEM_HOME="$PWD/../../work/gems" GEM_PATH="$PWD/../../work/gems" /usr/bin/ruby Tools/validate_project.rb
```

Use a fresh result-bundle path when repeating the command; choose an available local simulator UUID on another Mac. The actual logs are workspace `work/catalog-core-final.log`, `work/catalog-full.log`, `work/catalog-device.log`; source validation is `work/catalog-source-verification.json`. Tests use isolated containers; no physical iPhone was installed, authorized or exercised for this task. Xcode 27.0 / iOS 27 simulator were available; deployment remains iOS 17, whose runtime was not separately executed.

### Files for this milestone

New: `Nutrition/OfflineCatalog.swift`, `Persistence/CatalogImporter.swift`, `App/CatalogLoadingView.swift`, the five `Resources/Catalogs` files, `OfflineCatalogTests.swift`, `CatalogImporterTests.swift`, `CatalogFlowTests.swift`, `Tools/generate_catalogs.py`, `Tools/verify_catalog_sources.py`, and this report.

Integrated through existing `FoodDefinition.swift`, `WorkoutLogic.swift`, `NutritionStore.swift`, `WorkoutStore.swift`, `PersonalFitnessApp.swift`, `FoodLibraryView.swift`, `FoodEditor.swift`, `ExerciseLibraryView.swift`, project resource/source membership, the project generator/validator, README and architecture/user guides. The uncommitted October 17 UX improvements were retained; the working diff also includes that earlier work.
