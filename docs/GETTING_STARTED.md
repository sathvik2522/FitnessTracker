# Getting started

Clone the repository, open `PersonalFitness.xcodeproj`, choose the `PersonalFitness` scheme and an iPhone simulator. The app requires iOS 17.0 or later. The verified environment is Xcode 27.0 with its iOS platform and simulator runtime; Swift language mode is 5, compiler Swift 6.4. No runtime package resolution, backend, API key or credentials are required for simulator builds.

From the repository root:

```sh
xcodebuild -list -project PersonalFitness.xcodeproj
xcrun simctl list devices available
xcodebuild -project PersonalFitness.xcodeproj -scheme PersonalFitness -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project PersonalFitness.xcodeproj -scheme PersonalFitness -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' -only-testing:PersonalFitnessTests CODE_SIGNING_ALLOWED=NO test
```

Replace `SIMULATOR_UUID` with an available simulator's UUID. UI tests use isolated fixtures; see [Testing](TESTING.md).

## Optional physical iPhone

Open Xcode Settings → Accounts and configure your own Apple ID/team. The project uses automatic signing. `Configuration/PersonalFitness.xcconfig` provides shared defaults and optionally includes ignored `Configuration/Local.xcconfig`; copy `Configuration/Local.xcconfig.example` and set your own team and unique `APP_BUNDLE_IDENTIFIER` locally. The widget identifier appends `.Widgets`. Do not commit that file.

The current App Group is hard-coded in **both entitlement files**, `PersonalFitness/Widgets/WidgetSnapshotStore.swift`, and `PersonalFitnessWidgets/PersonalFitnessWidgets.swift`. A different team must explicitly configure the same group in all four places and provision both targets; local bundle-ID overrides alone do not change it. The app additionally needs its existing HealthKit capability/profile. Capability availability varies by account; no device build is guaranteed for another team. Avoid committing personal identifiers.

With approval, select a compatible iPhone destination and build in Xcode, or build without installing using `xcodebuild -project PersonalFitness.xcodeproj -scheme PersonalFitness -configuration Debug -destination 'generic/platform=iOS' build`. Xcode may require profile/certificate setup. A signed build does not install or verify Health data. Before an update, preserve existing app data and use the same bundle identifier and team; do not uninstall to repair signing. See [troubleshooting](TROUBLESHOOTING.md).
