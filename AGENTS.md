# PersonalFitness session instructions

## Start here

Read [current state](docs/CURRENT_STATE.md), then [next task](docs/NEXT_TASK.md). Inspect actual files and `git status` before editing. Read the full linked technical report only when the task needs its details. These summaries do not replace source inspection or authorize work.

## Approval and data safety

- Obtain explicit owner approval before physical-device installation, app removal, database reset, signing changes or destructive operations.
- Preserve working code, ignored local signing configuration, user data and verification evidence. Never uninstall/reset to repair signing or storage. Before an approved deployment, make a coherent private container backup (app stopped; SQLite/WAL/SHM and preferences), and verify preservation afterward.
- Keep credentials, device containers, personal exports and raw device/signing receipts out of Git. Never request secrets in chat. GitHub publication was deferred by the owner; do not restart authentication or push without a new request.
- Do not regenerate the working Xcode project or change schema/store paths casually. Preserve stable IDs and historical Codable snapshots; review compatibility before schema/format changes. JSON export is **not** an implemented restore feature.
- Inspect relevant files before editing. Do not make unrelated refactors, fabricate health data, perform destructive migrations, or automatically change signing, capabilities or entitlements.

## Engineering boundaries

Native SwiftUI/SwiftData, read-only HealthKit, Swift Charts and XCTest; local-first, no backend/analytics/paid API/cloud sync. Keep pure calculations in `Nutrition`, `Workouts/Core` and `Progress/Core`; keep queries/state outside views. Health authorization requires an explicit tap; no write requests. Missing data is not zero. Use local calendar boundaries, keep current-day values provisional, and never add workout calories to Health active energy.

Report actual command outcomes, overlapping test counts and unverified device behavior. Reuse existing evidence for documentation-only work; run relevant checks for code changes. A build is not proof of installation or real Health access.
