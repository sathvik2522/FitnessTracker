# Architecture

## Composition and data flow

`PersonalFitnessApp` opens the local `AppPersistence` container and attaches it to `AppNavigation`. The five tabs are Today, Food, Training, Progress and More. AppNavigation owns root-level food/weight composition requests so a tab subtree cannot discard a modal food draft. If storage cannot open, the app displays an error and preserves the original store.

```text
SwiftUI screens / value drafts
    -> DashboardModel, WorkoutSessionModel, ProgressModel (state/coordination)
    -> FoodEntryStore, NutritionStore, WorkoutStore, ProgressStore (local data)
    -> SwiftData ModelContext -> on-device store

Explicit Connect action -> HealthKitService -> authorized HealthKit queries
    -> in-memory HealthDaySnapshot -> pure energy/report logic -> UI
```

Stores validate before save, update existing records by stable ID and publish local change notifications after successful saves. Editors use value drafts; a failed save rolls the context back. There is no backend repository layer or network client.

## Source map

```text
PersonalFitness.xcodeproj/       App, widget, hosted unit and UI-test targets
Configuration/                  Shared defaults, example and ignored local signing
PersonalFitness/
  App/                          Entry point and isolated DEBUG UI-test store setup
  Navigation/                   Five-tab composition, root composers and More preferences
  Components/                   Design system, states, cards and labels
  Dashboard/                    Presentation and selected-day refresh coordination
  Food/                         Diary, library, food/meal/portion editors
  Models/                       Eight persisted SwiftData model types
  Persistence/                  Container, daily food reads and validated writes
  Nutrition/                    Pure portions, units, dates, balance and reconciliation
  Health/                       Read-only adapter, protocols and explicit result states
  Workouts/Core/                Pure validation, snapshots, progression and matching
  Workouts/                     Session/routine/cardio UI and session coordination
  Progress/Core/                Pure report ranges, aggregates and trend series
  Progress/                     Local queries, report coordinator and Swift Charts
  Resources/                    Assets, Info.plist and HealthKit entitlement
  Widgets/                      App-side widget snapshot writer
PersonalFitnessWidgets/         WidgetKit extension and group entitlement
PersonalFitnessTests/           Calculation, dashboard, persistence and Health tests
PersonalFitnessUITests/         Nutrition, workout and progress flows
Tools/                          Optional Ruby project generation/validation
Verification/                   Development UI screenshots
```

## Widget boundary

The app writes a versioned, privacy-controlled snapshot to a shared App Group; the WidgetKit extension reads the snapshot rather than SwiftData or HealthKit directly. Values default to hidden. Group identifiers are currently owner-specific and appear in both entitlement files and both source targets; see [setup](GETTING_STARTED.md) before configuring a different team.

## Boundaries worth preserving

- Pure code in Nutrition, Workouts/Core and Progress/Core is compiled by both the iOS app and the standalone Swift package. It must not depend on SwiftUI, SwiftData or HealthKit.
- `HealthDataReading` / `HealthHistoryReading` allow fake services in tests. The production service owns unit conversion and query error mapping.
- Dashboard and Progress capture a calendar and cutoff per request. Request tokens reject stale async results after changing date/range.
- Health samples stay in memory; manual workout models remain independent. Matching affects display, never destructive merging or expenditure.
- Session/routine/food definitions use Codable snapshots inside SwiftData. Their serialized compatibility needs explicit care alongside schema migration.
- Views present states and gather inputs. Keep calculation and reconciliation policy in the existing pure types instead of copying it into chart or card views.

## Optional sleep boundary

`SleepDataReading` is independent of the existing activity read protocol. `SleepModel` coordinates its explicit permission flow and range query; `SleepAnalysis` in Nutrition contains pure noon-window and interval-union logic. `SleepOverview` presents those states and training context. Sleep samples remain in memory. Optional exercise snapshot metadata lives in existing JSON blobs, without adding SwiftData model fields or tables. See [UX implementation](../UX_IMPROVEMENTS.md).

## Offline catalogs

Optional food/exercise JSON metadata holds provenance, previous source baselines and archive flags. A background ModelActor imports bundled resources into the existing SavedFood/ExerciseRecord models, updating only untouched source fields. Nutrition and serving basis merge atomically. Historical diary/recipe/routine/session snapshots remain independent. The SwiftData schema/store URL is unchanged. See [catalog design and source licenses](../OFFLINE_CATALOGS.md).

## Final daily-use audit additions

The final audit adds one optional persisted column, `FoodEntry.mealCategoryRaw`, with predecessor-store migration tests. It leaves the model container, eight entity types and store URL intact. `LocalDataExport` captures those eight tables without mutating them; `DataExportView` uses the native Files exporter, with encoding off the main actor. No in-app restore exists. See [the final audit](../FINAL_DAILY_USE_AUDIT.md).

## Dashboard and nutrition redesign

`FitnessTheme` contains adaptive surfaces and reusable goal bars/rings. `NutritionPresentation` contains pure goal validation, safe drawing fractions, ring display states and search ranking. `GoalPreferences` persists only explicit goals/appearance in local UserDefaults; DEBUG UI tests use independent preference suites. Goals are display preferences, not expenditure inputs. `DashboardWeightModel` coordinates the source-separated 14-day weight section with injected Health reads and stale-response guards. Sleep timelines reuse the unioned asleep intervals from `SleepAnalysis`.

The existing eight-entity SwiftData schema is unchanged. `LocalDataExport` v3 includes goal/appearance and explicitly saved scoring preferences; it still decodes v1/v2 files. No in-app restore is implemented. [Detailed redesign and verification](../UI_REDESIGN.md).

## Scoring addition

`WellnessScoring` contains pure value configuration and deterministic load/recovery/energy policy. `ScoringHealthReading` isolates new optional heart consent and authorized historical queries; `ScoringDashboardModel` adapts completed local snapshots and coordinates token-protected, five-minute cached Health history. `EnergyExpenditureService` chooses compatible measured/predicted components and returns provenance-rich records. `ScoringPreferences` stores explicit settings and immutable first closed-day expenditure predictions separately from the unchanged SwiftData schema. Refresh boundaries perform snapshot writes; views only read estimates. Presentation is in the ring/detail and settings views. Raw heart samples/scores stay in memory. See [the review report](../IMPLEMENTATION_REVIEW_REPORT.md) for formulas, source consistency, export compatibility and the physical-install approval gate.
