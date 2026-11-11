# Testing

Use Xcode 27.0 and an installed iPhone simulator runtime. `PersonalFitnessTests` contains hosted calculation, persistence and Health-adapter tests; `PersonalFitnessUITests` drives isolated synthetic stores. `swift test` exercises the standalone pure-calculation package and overlaps hosted coverage; do not add counts together.

```sh
xcrun simctl list devices available
xcodebuild -project PersonalFitness.xcodeproj -scheme PersonalFitness -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' -only-testing:PersonalFitnessTests CODE_SIGNING_ALLOWED=NO test
xcodebuild -project PersonalFitness.xcodeproj -scheme PersonalFitness -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO test
swift test
```

Replace the simulator UUID. UI tests can take considerable time and have shown intermittent keyboard focus issues and test-manager stalls. A November 2026 full run finished 227 passed/12 failed/0 skipped after prolonged stalls; all 12 failed UI tests passed in a separate rerun. That does not make the full run green. See [current state](CURRENT_STATE.md) and [verification](../Verification/README.md). Never run synthetic fixture setup against a real user store.

The proposed GitHub Actions workflow builds the simulator app and runs hosted unit tests only. Its hosted-runner execution is not yet verified; it does not sign or deploy, exercise UI tests, or validate real HealthKit behavior. GitHub Actions usage may be billed according to the repository/account plan.
