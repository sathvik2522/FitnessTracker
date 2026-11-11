# Read-only Apple Health integration — October 13, 2026

Implemented in the existing project, keeping iOS 17.0, the existing targets, and the single FoodEntry SwiftData schema. No backend, analytics, external service, HealthKit writes, or new persistence model was introduced.

## Implementation

- `HealthKitService` implements injected `HealthDataReading`. It owns authorization, queries, unit conversion, error classification, and workout transformation. The dashboard never constructs HealthKit queries.
- Only tapping **Connect Apple Health** or **Review Apple Health access** requests authorization. The read set is exactly basal/resting energy, active energy, steps, workouts, and body mass. `toShare` is an empty set.
- A local UserDefaults Boolean records successful completion of the request flow only. It does **not** represent read authorization. No write-authorization status is consulted. An empty read can mean absent or hidden samples.
- Each metric has a value, unavailable, or failed state. Request-not-completed, requesting, unsupported device, request failure, refresh loading, and query-window failure are separate dashboard states. A failed metric does not discard readable metrics.
- Cumulative quantities use `HKStatisticsQueryDescriptor` with `.cumulativeSum`, without `.separateBySource` or manual per-source sums. The sample predicate covers local midnight to the precise selected-day cutoff, including fractional seconds and 23/25-hour days. Overlapping samples are selected for HealthKit's statistics engine to aggregate. This delegates source/boundary handling to HealthKit; agreement with the Health app for real overlapping sources remains a device check.
- Today ends at the precise read-start time; historical days end at the following local midnight. The same window is used for all five queries. Current-day values are explicitly provisional. No future-day values are queried.
- Units: resting/active energy in kcal, steps in count, body mass in kg. Missing sums remain unavailable; an actual measured zero remains zero. Invalid or incompatible quantities become errors, not invented values.
- Workouts are queried separately, sorted by start time, and assigned to the local day in which they started. Their titles, start times, and durations appear as records. Workout calories are never added to expenditure. Similar records from distinct sources are not automatically merged; record durations are not summed into expenditure.
- Weight uses a separate descending sample query limited to the latest sample **within the selected day**. Older measurements are not carried forward.
- Refresh: selected date, app foreground, significant time/time-zone changes, pull-to-refresh, and the toolbar Refresh action. Requests never happen during refresh. Request IDs prevent an older day or older refresh response from overwriting the current one. Time-zone changes preserve a historical civil-date selection and invalidate the old snapshot.
- No background delivery was added. Foreground/manual refresh is sufficient for this milestone; there are no observer queries, background tasks, or corresponding entitlements to provision.
- The UI explains unavailable reads, how to manage access, the refresh timestamp, and that Apple Watch estimates can change as activity is recorded and synced. Total expenditure is resting + active; logged balance stays unavailable when the food diary is empty.

Health measurements remain in memory; HealthKit owns their durable storage. Only request-flow bookkeeping is saved in UserDefaults. Existing food persistence is unchanged.

## Configuration inspected and retained

HealthKit framework linkage, the HealthKit target capability, `com.apple.developer.healthkit = true`, and app entitlement build settings already existed and were validated. The read-purpose description was updated to describe the data the user chooses to share. There is no write-purpose description, write request, or background-delivery entitlement. The bundle identifier remains `com.personal.PersonalFitness` and the development team is not set in shared configuration.

## Files changed

Added:

- `PersonalFitness/Health/HealthData.swift` — day windows, result types, and service protocol.
- `PersonalFitness/Health/HealthKitService.swift` — read-only HealthKit implementation.
- `PersonalFitness/Components/HealthMetricCard.swift` — per-metric failure presentation.
- `PersonalFitnessTests/Health/HealthDayWindowTests.swift`
- `PersonalFitnessTests/Health/HealthKitConversionTests.swift`
- `PersonalFitnessTests/Health/HealthDashboardTests.swift`
- `PersonalFitnessTests/Health/MockHealthService.swift`
- This report and `Verification/health-connect.png`.

Modified:

- `PersonalFitness/Dashboard/DashboardModel.swift` — connection/refresh state, injected service, stale-response protection, time-zone changes, and energy reconciliation.
- `PersonalFitness/Dashboard/DashboardView.swift` — Connect/review/refresh actions, readable Health metrics, records, failure states, and explanatory text.
- `PersonalFitness/Resources/Info.plist` — accurate read-purpose description.
- `PersonalFitnessTests/Dashboard/DashboardModelTests.swift` — explicit mock injection; no live Health queries in these tests.
- `PersonalFitness.xcodeproj/project.pbxproj` — membership for new sources/tests only.
- `README.md` — current implementation and verification information.

## Actual build and test results

Xcode 27.0 (27A266a), iPhone 17e simulator, iOS 27.0:

| Check | Result |
| --- | --- |
| Final Debug simulator build + hosted XCTest suite | Exit 0; BUILD SUCCEEDED / TEST SUCCEEDED; 36 tests, zero failures |
| Standalone calculation tests | Exit 0; 11 tests, zero failures (these are also included in the iOS suite) |
| Unsigned Release build for generic physical iPhone | Exit 0; BUILD SUCCEEDED |
| Project membership, framework linkage, plist/entitlements validation | Passed |
| Existing target/build-setting comparison | Preserved |
| Simulator launch before connection | Visually checked; explicit Connect action, no permission dialog at launch |
| Real permission sheet, granted reads, actual Apple Watch values | **Not verified** |

The 17 new tests cover five exact read types, quantity conversions, missing versus measured-zero values, error classification, discrete sample boundaries, latest-weight query ordering, cumulative aggregate options, DST, partial days, time zones, future windows, explicit request gating, unavailable devices, partial failures, absent/revoked data, no extra workout energy, and stale asynchronous results. They use injected services or in-memory HealthKit quantity/sample objects; they do not execute live HealthKit reads or write fixtures to Apple Health.

Only the nonblocking AppIntents metadata-extraction warning remains. Raw logs are in `work/health-tests-final.log`, `work/health-core-tests.log`, and `work/health-release.log`. The successful iOS result bundle is `work/DerivedData/Logs/Test/Run-PersonalFitness-2026.10.13_10-50-47--0700.xcresult`.

Commands, from the original workspace root:

```sh
xcodebuild -project outputs/PersonalFitness/PersonalFitness.xcodeproj \
  -scheme PersonalFitness -configuration Debug \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -derivedDataPath work/DerivedData -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO build test

swift test --package-path outputs/PersonalFitness --scratch-path work/swift-build-xcode

xcodebuild -project outputs/PersonalFitness/PersonalFitness.xcodeproj \
  -scheme PersonalFitness -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath work/DeviceBuild \
  CODE_SIGNING_ALLOWED=NO build
```

There is still no Git repository in this workspace. The project was updated through Xcodeproj rather than regenerated; original targets and build settings were compared with the pre-change copy.

## Required manual Xcode and iPhone checks

1. Open `PersonalFitness.xcodeproj`, select the app target's Signing & Capabilities, choose your developer team and an available bundle identifier, and confirm HealthKit provisioning. Do not enable write access or background delivery. The unsigned builds above do not prove provisioning.
2. Run on your supported personal iPhone. Confirm no authorization sheet appears on launch; tap Connect Apple Health yourself. Choose the data types you want to share. This is the first real authorization check.
3. Verify all-allowed, partially allowed, and all-refused choices. Missing values must remain unavailable, never be described as definitively denied, and never produce invented energy or deficits. Manage existing grants in Apple Health or Settings; requesting again may not show a new sheet for previously decided permissions.
4. Compare energy and steps with Apple Health for the same local day after Watch sync, including overlapping iPhone/Watch activity, a historical day, and a DST transition day. Validate the cumulative statistics results against actual store behavior; unit tests verify query construction, not Apple's execution of real queries.
5. Check latest weight on a measured day, an unmeasured day, multiple same-day weigh-ins, and workout records that cross midnight. Confirm no workout calories are added again.
6. Revoke read access, foreground the app, and refresh. Check locked-device errors where applicable, rapid day changes, a time-zone change, and partial current-day data. There is no automatic background refresh promise.

The service is implemented and compiled, but **successful device authorization and real Apple Watch data access are not claimed**.

[Pre-connection dashboard screenshot](Verification/health-connect.png)

## Primary references

- Apple: [Authorizing access to health data](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data) and [Protecting user privacy](https://developer.apple.com/documentation/healthkit/protecting-user-privacy).
- Apple: [Statistics collection queries](https://developer.apple.com/documentation/healthkit/hkstatisticscollectionquery) and [statistical queries](https://developer.apple.com/documentation/healthkit/executing-statistical-queries).
- Apple: [Sample predicates](https://developer.apple.com/documentation/healthkit/hkquery/predicateforsamples(withstart:end:options:)) and [strict end-date behavior](https://developer.apple.com/documentation/healthkit/hkqueryoptions/strictenddate).
