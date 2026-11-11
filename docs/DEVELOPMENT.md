# Development and maintenance

## Tooling

Use full Xcode with the iOS platform and an available simulator runtime. The app's minimum iOS version is 17.0; this checkout has been verified with Xcode 27.0. The Swift package uses tools version 5.9 and tests pure code on macOS; it is not the iPhone app.

Open `PersonalFitness.xcodeproj`, choose the PersonalFitness scheme and an iPhone simulator. Command-R runs; Command-U runs the hosted unit and UI suites. No package manager setup or backend is required for the app.

## Commands (repository root)

```sh
xcodebuild -list -project PersonalFitness.xcodeproj
xcrun simctl list devices available

# Compile for simulator without device signing.
xcodebuild -project PersonalFitness.xcodeproj -scheme PersonalFitness   -configuration Debug -destination 'generic/platform=iOS Simulator'   -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build

# Replace this placeholder with an actually available simulator UUID.
SIMULATOR_ID='YOUR_AVAILABLE_SIMULATOR_UUID'
xcodebuild -project PersonalFitness.xcodeproj -scheme PersonalFitness   -configuration Debug -destination "platform=iOS Simulator,id=$SIMULATOR_ID"   -derivedDataPath DerivedData -collect-test-diagnostics never   CODE_SIGNING_ALLOWED=NO test

# Pure calculations; does not test SwiftData, HealthKit or the UI.
swift test

# Compile iPhone architecture; this alone does not sign/install.
xcodebuild -project PersonalFitness.xcodeproj -scheme PersonalFitness   -configuration Debug -destination 'generic/platform=iOS'   -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

For signed builds, configure a real team/unique identifier and select the paired physical phone. See [installation](../IPHONE_INSTALLATION.md). Never run fixture arguments on the daily-use installation; DEBUG UI tests pass a unique temporary store UUID to keep tests isolated.

## Signing portability

Copy `Configuration/Local.xcconfig.example` to `Configuration/Local.xcconfig` and enter your actual team/identifier, or use Xcode's Signing editor. The shared xcconfig optionally includes that ignored file. Existing local installations retain their original values there. Verify resolved DEVELOPMENT_TEAM and PRODUCT_BUNDLE_IDENTIFIER with Xcode Build Settings or `xcodebuild -showBuildSettings` before signing.

The repository has blank shared team settings. Signing identity, certificate private key and provisioning are managed by Xcode/Keychain, not Git. Xcode may add a target-level team override if selected in the UI; review it before committing settings intended for others.

## Project membership and optional generation

The checked-in Xcode project is authoritative. When adding Swift files, add them to the appropriate target in Xcode; adding files on disk alone does not guarantee compilation. Pure calculation files also need Swift package membership. Existing targets are PersonalFitness, PersonalFitnessTests and PersonalFitnessUITests.

`Tools/generate_project.rb` uses pinned Ruby `xcodeproj` 1.27.0 and refuses to overwrite an existing project. Ordinary development does not need Ruby. If reconstruction is necessary, use Bundler with `Tools/Gemfile` in a separate checkout and review the resulting project. `Tools/validate_project.rb` checks structural references, not compilation. Do not regenerate the working project for routine edits.

## Tests and safe changes

- Calculations: energy/missing values, duplicate representations, local/DST dates, food/recipe scaling, workout volume/progression and report trends.
- Persistence: stable-ID edits/deletes, snapshots, session restoration, disk reopen and migration behavior.
- Health/dashboard: injected services, authorization/load/error states, conversion, stale results and selected-day handling.
- UI: isolated diary, large-text editing, strength/cardio and Progress flows.

Document reasoning at boundaries (units, coverage, snapshots, cancellation, migration); avoid comments that merely repeat a Swift statement. Before schema or Codable format changes, add compatibility tests. Preserve stores on errors. Review staged files for personal data and generated output before publishing.

## Verification of this documentation update

Fresh checks on October 16, 2026 with Xcode 27.0:

| Check | Actual result |
| --- | --- |
| Full simulator build/test, iPhone 18 Pro Max simulator (iOS 27.0) | Exit 0, TEST SUCCEEDED; 109 hosted unit + 6 UI tests passed, zero failures |
| Standalone Swift package | Exit 0; 61 XCTest cases passed (overlap the hosted suite) |
| Generic physical-iPhone Debug compilation, signing disabled | Exit 0, BUILD SUCCEEDED; does not install or authorize Health |
| Resolved local signing | Original team and `com.gbssathvik.PersonalFitness` retained through ignored Local.xcconfig |
| Project, Info.plist and entitlement lint | All passed |
| Current documentation links and Git whitespace checks | Passed |
| Tracked artifact scan | No checked private-key/token/local-device-identity patterns found; local config excluded |
| GitHub publishing check | Blocked: HTTPS credentials unavailable; remote was still empty at inspection |

Original workspace command logs: `work/documentation-ios-tests.log`, `work/documentation-swift-tests.log`, `work/documentation-device-build.log` and `work/documentation-build-settings.log`. Logs/result bundles are intentionally not committed. Commands were run against `outputs/PersonalFitness/PersonalFitness.xcodeproj` from its enclosing workspace, with derived data under `work/`; the repository-root commands above reproduce the same checks with local paths.


## Known limitations

No app icon artwork, paid nutrition API, barcode scanner, Android app, Health writes, background-delivery guarantee, cloud sync or in-app data restore. Local JSON export is available from More and Progress. Real-device Health reconciliation and full accessibility validation remain manual work. Earlier audits record keyboard/frame warnings; the October 20 report documents the focused layout fix and the actual redesigned-run diagnostics.

## October 20 redesign


## Scoring milestone review gate

[IMPLEMENTATION_REVIEW_REPORT.md](../IMPLEMENTATION_REVIEW_REPORT.md) records the unchanged baseline, final checks, exact methods and review-ready build path. Do not infer physical validation from generic-iPhone compilation. The user explicitly requires report review and approval before installing this combined build. RPE is additive optional Codable data, not a SwiftData schema migration; configuration/export version changes need legacy-decoding tests. Keep all UI fixtures in the existing isolated temporary store/preferences path.
