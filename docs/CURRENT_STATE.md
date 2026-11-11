# Current state

PersonalFitness is an iOS 17+ SwiftUI/SwiftData application with an embedded WidgetKit extension. It provides offline nutrition and workout logging, local reports, opt-in read-only HealthKit queries and transparent activity-load, Recovery and energy estimates. See [features](FEATURES.md), [architecture](ARCHITECTURE.md), and [scoring](SCORING.md).

The unsigned simulator build and 216 hosted unit tests passed locally on Xcode 27.0. A prior full simulator run had 227 passes and 12 failures after prolonged test-manager stalls; all 12 failed UI tests passed in a separate focused rerun. Do not treat the original full run as passing. Device Health, watch reconciliation and VoiceOver are not established by simulator tests. See [testing](TESTING.md).

The proposed GitHub Actions workflow has not been verified on a hosted runner. No in-app data restore exists. App Group identifiers must be configured consistently for a different development team; see [getting started](GETTING_STARTED.md).
