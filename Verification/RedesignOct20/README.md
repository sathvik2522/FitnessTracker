# Actual simulator captures — October 20, 2026

These images come from the successful 170-test full scheme on iPhone 18 Pro Max / iOS 27. They show the implemented SwiftUI app, not generated mockups.

- Today-empty-dark.png: isolated empty test store; no Health permission requested, no goals and no fabricated measurements.
- Food-goal-fixture-light.png: isolated UI-test preference of 2,000 kcal, selected explicitly by the test. This is not the owner's target or a recommendation. The diary is empty and intake/balance remain unavailable.

The tests use independent temporary disk stores and preference suites. These captures do not establish real-device Health access, Apple Watch reconciliation or manual VoiceOver validation. See [the redesign report](../../UI_REDESIGN.md) for exact verification and limits.
