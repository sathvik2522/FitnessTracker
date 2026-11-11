# Troubleshooting

- **Signing/profile:** verify Xcode account, team, app and widget identifiers and profile expiry. Preserve the existing app identifier and container. Do not uninstall or reset data to fix signing.
- **App Group/widget:** the app, widget, both entitlements and both snapshot source constants must use an authorized shared group. See [setup](GETTING_STARTED.md) and [widget audit](WIDGET_CONFIGURATION_AUDIT.md). A local bundle override does not change that group. Widget values are hidden by default and snapshots can be stale.
- **Health data missing:** Health reads require explicit Connect actions and may have no samples or permissions. HealthKit does not disclose every read denial; check Apple Health sharing and device synchronization. Simulator results are not proof of watch data.
- **Build/simulator unavailable:** select full Xcode and install an iOS runtime. Use `xcodebuild -list` and `xcrun simctl list devices available`; use an actual simulator UUID. The verified Xcode version is 27.0.
- **UI test stalls/keyboard:** inspect the xcresult and test log, preserve receipts, and rerun only affected tests when appropriate. Do not disable failures or treat a retry as a passing original run.
- **Lost data:** do not uninstall or reset. JSON export currently has no in-app restore. Contact the owner before any potentially destructive intervention.
