# Privacy and local data

PersonalFitness has no backend, login, telemetry, analytics, external nutrition requests or app-managed cloud synchronization. SwiftData is stored in the installed app's local container. Apple Health data belongs to the system Health store; the app reads authorized samples and keeps its query results in memory.

Health permission is requested only by an explicit Connect/Review action. The read set is resting energy, active energy, steps, workouts and body mass, with a separate optional sleep request. `toShare` is empty; no write access or background delivery is enabled. Request completion is saved in UserDefaults, but is not treated as proof of read access.

## Source code is not a data backup

GitHub contains the code, documentation and development test fixtures. It must never contain your real diary database, Health exports, device diagnostics, certificates, provisioning profiles, private keys or passwords. `.gitignore` excludes these artifacts and local signing settings. Development screenshots in Verification are historical simulator captures, not a personal Health backup.

Installing a new build with the **same bundle identifier** normally preserves its app container. Deleting the app can delete its local records. Changing the identifier creates a separate app/container; do not change it merely to renew signing.

## Moving to another iPhone

The new installation starts with a separate local store. **Progress → Export local data** creates a JSON copy of all eight local tables, including nutrition snapshots, meal categories, active/completed workouts, sets, custom library records and manual weights. Health readings and permissions are not exported. **There is no in-app restore or app-to-app transfer feature yet.** A Git clone or reinstall does not move your food diary or workout sessions. Do not erase the old phone or delete its app assuming records were uploaded somewhere.

Apple's device backup/restore and Health synchronization are separate system features; this app has not independently validated restoration of its local store, so do not promise recovery from them. Verify your chosen backup/transfer process before replacing the old phone. Save exports using Files → On My iPhone, then copy them to your Mac or another location you control. An export is not a tested one-tap restorable backup. Export encoding/decoding and file writes are tested on temporary fixtures; recovery into the app is not implemented. The JSON contains personal data and is not encrypted by PersonalFitness. A restore flow with isolated import/migration tests is the next data-safety milestone.

On the new phone, grant Health read access again. Only samples actually present and authorized there can appear. Apple/Watch Health sync settings are independent of PersonalFitness, and do not synchronize this app's food or manual workout records.

## Optional scoring inputs

HRV SDNN and resting heart rate are a separate, explicit read-only request from Recovery details. The original five-type connection and optional sleep request remain separate. Request completion never proves read permission. Heart readings and derived scores remain in memory and are not logged, exported or synchronized by the app.

Optional RPE remains in existing workout snapshots. Explicit scoring settings use local UserDefaults. A separate local preference ledger preserves first calculated closed-day expenditure predictions, including derived resting/active component totals, sources, timestamps and assumptions. Version 3 JSON export includes this ledger, explicitly saved configuration and any manually entered equation profile (age, height, weight, coefficient and multiplier), so estimates can be reproduced; the export screen discloses this. The JSON is personal and not app-encrypted. No backend, analytics, paid API or new runtime network dependency was added. [Current review and installation gate](../IMPLEMENTATION_REVIEW_REPORT.md).
