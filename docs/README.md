# Documentation index

The main guides describe the current code. Dated milestone notes preserve what was verified at each checkpoint; older counts, paths and setup limitations are historical, not the current project status.

| Guide | Purpose |
| --- | --- |
| [iPhone installation](../IPHONE_INSTALLATION.md) | New phone, new Mac, trust, signing renewal and troubleshooting |
| [User guide](USER_GUIDE.md) | Daily flows and physical-device acceptance checks |
| [Architecture](ARCHITECTURE.md) | Composition, boundaries, modules and source tree |
| [Data and calculations](DATA_AND_CALCULATIONS.md) | Eight models, units, snapshots, calendar boundaries and reconciliation |
| [GitHub](GITHUB.md) | Authenticate, publish, clone and review future changes |
| [Development](DEVELOPMENT.md) | Build/test commands, source membership and maintenance |
| [Privacy and data](PRIVACY_AND_DATA.md) | Local storage, JSON export, restore limitations and phone migration |
| [Android](ANDROID.md) | Current unsupported platform and requirements for a future app |

## Dashboard and nutrition redesign

[October 20 implementation and verification](../UI_REDESIGN.md) covers five tabs, truthful rings, meal logging, offline search, goals, appearance and draft safety. Earlier test counts below remain historical.

## Final daily-use audit

[October 18 final audit](../FINAL_DAILY_USE_AUDIT.md) documents current fixes, migration/export behavior, test results and the physical-iPhone acceptance gate.

## Offline catalog implementation

[October 18 offline libraries](../OFFLINE_CATALOGS.md) documents the actual downloads, licenses, bundled counts, update/archiving policy and verification.

## Current UX implementation

[October 17 UX audit and fixes](../UX_IMPROVEMENTS.md) covers create-and-log, safe drafts, routines, starter/custom exercises, optional sleep and final verification. It supersedes older descriptions of these flows.

## Detailed engineering records

- [Foundation](../FOUNDATION_UPDATE.md)
- [Health integration](../HEALTHKIT_UPDATE.md)
- [Energy reconciliation](../ENERGY_ENGINE.md)
- [Nutrition](../NUTRITION_UPDATE.md)
- [Workouts](../WORKOUTS_UPDATE.md)
- [Progress](../PROGRESS_UPDATE.md)
- [Engineering audit and remaining issues](../ENGINEERING_AUDIT.md)
- [Earlier environment validation](../VALIDATION.md)


Historical `work/` log/result paths refer to the original development workspace; those generated artifacts are not published. Reproduce checks using the current development guide. Optional project tools have their own [README](../Tools/README.md).

- [Scoring implementation review and explicit installation gate](../IMPLEMENTATION_REVIEW_REPORT.md) — formulas, inputs, defaults, tests, limitations and proposed device validation.

- [October 20 approved iPhone deployment](../APPROVED_IPHONE_UPDATE.md) — general device verification guidance.
