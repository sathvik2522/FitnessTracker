# Widget snapshot contract v1

## Purpose and boundary

`PersonalFitnessWidgetSnapshot` is a versioned, read-only `Codable` boundary
between the app and a future WidgetKit extension. It is intentionally kept in
the Foundation-only scoring module so it can be independently tested and so an
extension does not open the app's SwiftData store or call HealthKit.

The main app remains the only process that queries SwiftData and reads the
already-authorized Health data. It writes a complete encoded snapshot only after
it has produced the existing dashboard values. The widget decodes that snapshot,
then renders it without calculating a new score or substituting absent inputs.

## Schema

Schema version `1` contains:

| Field | Meaning |
| --- | --- |
| `generatedAt`, `localDayStart`, `timeZoneIdentifier` | Honest local-day context and freshness timestamp. |
| `recovery`, `strain` | Existing 0–100 score only when available, plus current/partial/unavailable state and provenance label. |
| `nutrition` | Logged calories and the explicit calorie goal only when available. |
| `activeWorkout` | A validated in-progress session summary. It is omitted when no independently durable active-session state exists. |
| `privacy` | `showValues` or `hideValues`; the latter redacts score, calorie, set-count and workout-name values. |

Numbers are rejected when non-finite or outside their display domain. A missing
score becomes `unavailable`; it never becomes zero. A partial-day snapshot stays
partial. Unsupported schema versions and snapshots generated more than five
minutes in the future are rejected.

Fresh partial snapshots expire after two hours. Closed-day snapshots expire
after 24 hours. A future timeline provider should use the contract's two-hour
partial or six-hour closed-day fallback refresh date and call `WidgetCenter`
only after a newly saved snapshot, respecting WidgetKit's coalesced/budgeted
refresh model.

## Intended widget matrix

After the approved extension target exists, render only values present in this
contract:

| Family | Content | Tap destination |
| --- | --- | --- |
| Home small | Recovery or Strain score, state and updated time | Recovery or Strain |
| Home medium | Compact daily overview: Recovery, Strain and calorie progress | Today |
| Home medium | Nutrition progress; active workout only when its durable snapshot is present | Nutrition or Workout |
| Lock Screen accessory circular / rectangular | A single score or compact overview label with timestamp/state | Matching destination |

Every layout must make `partial`, `unavailable`, or stale data visible, use
system Dynamic Type-compatible text styles, and include accessibility labels
that state the score/state/timestamp. Lock Screen privacy must use the system
redacted placeholder and the contract's `hideValues` form when configured.

`personalfitness://widget/{today|recovery|strain|nutrition|workout}` is the
documented deep-link contract. App URL registration and navigation handling
will be added alongside the extension after approval, so these URLs are not yet
claimed as operational links.

## Approval gate

The project currently has no WidgetKit target and its sole entitlement is
`com.apple.developer.healthkit`. A functional extension needs a new WidgetKit
extension target and the app plus extension must share an App Group container
such as `group.com.gbssathvik.PersonalFitness` to exchange this snapshot.

Adding that target changes the Xcode build configuration and creates a distinct
extension bundle identifier; enabling the shared container changes both
entitlement files and provisioning profiles. Those are signing/provisioning
changes, so they require explicit owner approval before any project or
entitlement modification. No entitlement, provisioning, signing, bundle
identifier, HealthKit permission, app store, or device operation was changed
while preparing v1.

## Verification completed

`swift test --scratch-path /private/tmp/personalfitness-widgets-contract`
completed with **129 tests passed, 0 failures**. New synthetic tests cover
encoding/decoding, unsupported versions, current/partial/stale/unavailable
freshness, privacy redaction, missing metrics, and deep-link parsing.

There is no widget target to render or build yet, so no WidgetKit gallery
screenshots, extension build, simulator rendering, or physical-device checks
have been performed.
