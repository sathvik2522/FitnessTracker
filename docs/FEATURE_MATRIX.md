# Feature matrix — source-audited, 27 October 2026

`Implemented` means source exists; it does not imply a fresh end-to-end UI pass. `Partial` means material gaps remain. `Gate` requires owner approval before work that changes entitlements, permissions or schema.

| Area | Status | Evidence / gap |
| --- | --- | --- |
| Today status, rings, nutrition, sleep, training, historical day | Implemented | Dashboard/ScoringDashboardModel; score provenance in detail views. Partial-day insight defect fixed in this pass. |
| Today ordering, hiding, compact rings | Implemented | Versioned `DashboardConfiguration`; persistence tests existed. |
| Appearance and accent palettes | Implemented | Dark/light/system/black and four accent choices. Large-text/contrast visual checks pending. |
| Active strength session, saved routine start, set edit/complete, history | Implemented | `WorkoutStore`, session snapshot, progress calculations; existing disk-reopen tests. |
| Routine create/edit/duplicate/reorder exercises | Implemented | Duplicate added in this pass; hosted test pending. Routine folders/organization remain absent. |
| Configurable rest timer / background alert | Partial | Versioned validated 30–300-second preferred duration added and used by the saved deadline timer; no background alert or notification. Full hosted preference test passed; visual check pending. |
| Cardio and stair sessions, optional RPE | Implemented | Separate manual records; no automatic calorie addition. |
| Food diary, meals, catalog, recent/frequent, quick add, saved meals/recipes | Implemented | Existing snapshots and source IDs preserved. |
| Favorites and copy previous meal | Missing | Do not reinterpret a frequent-food scope as favorites. |
| Calorie/macro goals and nutrition history | Implemented | Versioned goals; missing goals shown explicitly. |
| Legacy Recovery/Strain and transparent advanced comparison | Implemented | Advanced model is versioned/opt-in preview; additional Health signals gated by authorization. |
| Explainable local insights | Partial | Deterministic rules and visibility toggle; current-day and missing-score rule fixed; visual/hosted checks pending. No notification delivery. |
| Progress 7/30/90/custom, interactive charts, workout and nutrition trends | Implemented | Source-level implementation exists; visual and VoiceOver audit pending. |
| JSON export | Implemented | Versioned export; no in-app restore. |
| Home/Lock widgets | Gate | Read-only snapshot contract only. Extension/App Group needs entitlement approval and reliable shared state. |
