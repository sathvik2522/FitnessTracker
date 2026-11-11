# UX direction and interaction audit

PersonalFitness should present an immediate daily status and one useful next action, then disclose sources, formulas and editing controls on demand. The current navy surfaces, semantic text, accent palettes and score rings form the starting design system. Keep score provenance inspectable without placing technical paragraphs in the first screenful.

| Journey | Current route and friction | Target / evidence needed |
| --- | --- | --- |
| Today → food | Today quick action switches to Food composer; the diary also has meal-specific add actions. | Verify first-screen discoverability and an existing-food quick add in at most a few actions using a synthetic fixture. Confirm keyboard and floating-tab clearance. |
| Today → training | Today routes to Training; Training can start/resume, then the session sheet opens. | Show active workout prominently; verify saved sets and timer after simulated relaunch. |
| Routine → session | Training lists routines with Start/Edit; this pass adds Duplicate in More. | Keep routine name readable at accessibility text sizes; capture narrow and large-text screens. |
| Set logging | Each row edits weight/reps and completes a set; previous performance is shown per exercise. | Count taps on a synthetic session; inspect keyboard focus and one-tap completion before changing storage behavior. |
| Food logging | Meal cards, recent/frequent/custom/saved-meal scopes and quick add exist. | Verify source/portion labels and edit/move/copy flows; then add any missing favorites/copy-previous-meal behavior without altering snapshots. |
| Progress | 7/30/90/custom ranges and charts exist. | Visually check selection, missing-day semantics and VoiceOver chart descriptions on synthetic histories. |

The first implementation checkpoint fixes insight selection for a partial day and avoids treating missing Recovery as low Recovery. The second adds safe routine duplication and adaptive Training actions. Neither checkpoint is considered visually complete until simulator screenshots and accessibility checks pass.

For future visual review, capture Today, Food, Training, Progress and More in dark/light, then narrow and large-text variants of primary tasks. Inspect clipped names, contrast, card density, tab/safe-area clearance, keyboard occlusion and VoiceOver labels. Use only synthetic simulator data. Do not relabel older images as new verification.
